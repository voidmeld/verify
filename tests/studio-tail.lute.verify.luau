--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local fs = require "@std/fs"
local Core = require "../src/core"
local Tail = require "../src/lute/studio-tail"
local temporary = require "./temporary"

local REPLIES = {
	'{"jsonrpc":"2.0","id":1,"result":{"text":"first"}}',
	'{"jsonrpc":"2.0","id":2,"result":{"text":"second \\u00e9 \\u20ac"}}',
	'{"jsonrpc":"2.0","id":3,"result":{"text":"third"}}',
}

local function transcript(): string
	return table.concat(REPLIES, "\n") .. "\n"
end

local function collect(path: string, tail: Tail.Tail, into: { string })
	for _, text in Tail.lines(path, tail) do
		table.insert(into, text)
	end
end

describe("studio reply tail", function()
	it("returns nothing for a file that does not exist or has no new bytes", function()
		local tail = Tail.create()
		expect(Tail.lines("/nonexistent/verify-tail-output", tail)):toEqual {}
		expect(tail.consumed):toBe(0)
	end)

	it("reads a reply split across two writes only once it is complete", function()
		local report = Core.runCases({
			{
				id = "split",
				name = "split",
				run = function(context)
					local path = temporary(context, "verify-tail") .. "/output"
					local whole = transcript()
					local cut = #REPLIES[1] + 1 + 20
					local tail = Tail.create()
					local seen: { string } = {}
					fs.writeStringToFile(path, string.sub(whole, 1, cut))
					collect(path, tail, seen)
					expect(seen):toEqual { REPLIES[1] }
					expect(tail.consumed):toBe(#REPLIES[1] + 1)
					fs.writeStringToFile(path, whole)
					collect(path, tail, seen)
					expect(seen):toEqual { REPLIES[1], REPLIES[2], REPLIES[3] }
					expect(tail.consumed):toBe(#whole)
				end,
			},
		}, { executor = "tail" }, os.clock)
		expect(report.passed):toBe(1)
	end)

	it("never loses or repeats a reply wherever the writes are split", function()
		local report = Core.runCases({
			{
				id = "every-split",
				name = "every split",
				run = function(context)
					local path = temporary(context, "verify-tail-every") .. "/output"
					local whole = transcript()
					for count = 1, #whole + 1 do
						local cut = count - 1
						fs.writeStringToFile(path, string.sub(whole, 1, cut))
						local tail = Tail.create()
						local seen: { string } = {}
						collect(path, tail, seen)
						fs.writeStringToFile(path, whole)
						collect(path, tail, seen)
						collect(path, tail, seen)
						expect(seen):toEqual(REPLIES)
					end
				end,
			},
		}, { executor = "tail" }, os.clock)
		expect(report.passed):toBe(1)
	end)

	it("reads only the bytes after the consumed offset of a large file", function()
		local report = Core.runCases({
			{
				id = "large",
				name = "large",
				run = function(context)
					local path = temporary(context, "verify-tail-large") .. "/output"
					local big = string.rep(string.rep("x", 79999) .. "\n", 140)
					local tail = Tail.create()
					fs.writeStringToFile(path, big)
					local first = Tail.lines(path, tail)
					expect(#first):toBe(140)
					expect(tail.consumed):toBe(#big)
					fs.writeStringToFile(path, big .. REPLIES[1] .. "\n")
					expect(Tail.lines(path, tail)):toEqual { REPLIES[1] }
					expect(tail.consumed):toBe(#big + #REPLIES[1] + 1)
				end,
			},
		}, { executor = "tail" }, os.clock)
		expect(report.passed):toBe(1)
	end)
end)

return nil
