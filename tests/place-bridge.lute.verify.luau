--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local temporary = require "./temporary"

local fs = require "@std/fs"
local Bridge = require "../src/lute/place-bridge"
local Place = require "../src/lute/place"

type Response = { ok: boolean, count: number, parts: { string } }

local function fake(handler: (string) -> (boolean, string)): (Bridge.Execute, { string })
	local responses: { [string]: Response } = {}
	local contexts: { string } = {}
	local function execute(datamodel: string, source: string): Bridge.Reply
		table.insert(contexts, datamodel)
		local raw = string.match(source, "F:SetAttribute%('request', (%b\"\")%)")
		if raw ~= nil then
			local decoded = string.gsub(string.sub(raw, 2, -2), "\\\n", "\n")
			local id, text = string.match(decoded, "^(%w+)\n(.*)$")
			local ok, out = handler(assert(text))
			local parts: { string } = {}
			for index = 1, math.max(#out, 1), Bridge.SEGMENT_BYTES do
				table.insert(parts, string.sub(out, index, index + Bridge.SEGMENT_BYTES - 1))
			end
			responses[assert(id)] = { ok = ok, count = #parts, parts = parts }
			return { ok = true, text = "verify-bridge:sent" }
		end
		local acknowledged = string.match(source, "F:SetAttribute%('ack', \"(%w+)\"%)")
		if acknowledged ~= nil then
			responses[acknowledged] = nil
			return { ok = true, text = "verify-bridge:acknowledged" }
		end
		local id = assert(string.match(source, 'FindFirstChild%("(%w+)"%)'), "no request id")
		local response = responses[id]
		local part = string.match(source, "FindFirstChild%('p(%d+)'%)")
		if part ~= nil then
			return { ok = true, text = "verify-bridge:" .. response.parts[assert(tonumber(part))] }
		end
		return {
			ok = true,
			text = "verify-bridge:" .. (if response.ok then "ok " else "error ") .. tostring(response.count),
		}
	end
	return execute, contexts
end

describe("place bridge", function()
	it("sends a request to the chosen context and joins every segment of the reply", function()
		local long = string.rep("x", Bridge.SEGMENT_BYTES + 5)
		local execute, contexts = fake(function(text: string): (boolean, string)
			return true, text .. long
		end)
		local outcome = Bridge.call { execute = execute, context = "Client", text = "ping" }
		expect(outcome.ok):toBe(true)
		expect(outcome.text):toBe("ping" .. long)
		for _, context in contexts do
			expect(context):toBe "Client"
		end
	end)

	it("reports a module error with its message", function()
		local execute = fake(function(): (boolean, string)
			return false, "probe exploded"
		end)
		local outcome = Bridge.call { execute = execute, context = "Server", text = "{}" }
		expect(outcome.ok):toBe(false)
		expect(outcome.text):toBe "probe exploded"
	end)

	it("fails when the place has no bridge", function()
		local outcome = Bridge.call {
			execute = function(): Bridge.Reply
				return { ok = true, text = "verify-bridge:missing" }
			end,
			context = "Client",
			text = "{}",
		}
		expect(outcome.ok):toBe(false)
		expect(string.find(outcome.detail or "", "VerifyBridgeClient", 1, true) ~= nil):toBe(true)
	end)

	it("builds a bridge script for each requested context", function(_, context)
		local root = temporary(context, "verify-place-bridge")
		fs.writeStringToFile(root .. "/probe.luau", "return { call = function(text) return text end }")
		Place.build {
			output = root .. "/result.rbxlx",
			roots = {},
			modules = { root .. "/probe.luau" },
			bridges = { Client = root .. "/probe.luau" },
		}
		local output = fs.readFileToString(root .. "/result.rbxlx")
		local _, count = string.gsub(output, '<string name="Name">VerifyBridge</string>', "")
		expect(count):toBe(1)
		expect(string.find(output, ":WaitForChild(&quot;probe&quot;)", 1, true) ~= nil):toBe(true)
	end)
end)

return nil
