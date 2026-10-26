--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local temporary = require "./temporary"

local fs = require "@std/fs"
local Core = require "../src/core"
local Published = require "../src/lute/published-source"
local function fixture(context: Core.Context): string
	local directory = temporary(context, "verify-published-source-tests")
	return directory
end
describe("published verification fixture", function()
	it("builds a caller-authorized server runner with run-correlated client output", function(_, caseContext)
		local directory = fixture(caseContext)
		Published.build {
			output = directory .. "/fixture.rbxlx",
			entry = "examples/multiplayer/entry.luau",
			roots = { "examples/multiplayer" },
			authorizedUserIds = { 123, 456 },
		}
		local source = fs.readFileToString(directory .. "/fixture.rbxlx")
		for _, token in
			{
				"[123]=true",
				"[456]=true",
				"player.UserId",
				"GetJoinData().LaunchData",
				"request.verifyEntry==expectedEntry",
				"not used[player]",
				"Channel.publish",
				"Channel.envelope",
				"Core.syntheticReport",
				"verifyCases",
				"VerifyPublishedRun",
			}
		do
			expect(source:find(token, 1, true) ~= nil):toBe(true)
		end
		expect(source:find("InvokeServer()", 1, true) ~= nil):toBe(true)
		expect(source:find("OnServerInvoke=function(player: Player)", 1, true) ~= nil):toBe(true)
	end)
	it("builds client execution only after server authorization", function(_, caseContext)
		local directory = fixture(caseContext)
		Published.build {
			output = directory .. "/fixture.rbxlx",
			entry = "examples/multiplayer/entry.luau",
			roots = { "examples/multiplayer" },
			authorizedUserIds = { 123 },
			context = "Client",
		}
		local source = fs.readFileToString(directory .. "/fixture.rbxlx")
		expect(source:find("return authorize(player)", 1, true) ~= nil):toBe(true)
		expect(source:find("local report=execute(request)", 1, true) ~= nil):toBe(true)
		expect(source:find("Channel.publish(request.runId", 1, true) ~= nil):toBe(true)
	end)
	it("rejects empty duplicate malformed or sparse authorization before writing", function(_, caseContext)
		local directory = fixture(caseContext)
		local cases: { { number } } =
			{ {}, { 1, 1 }, { 0 }, { -1 }, { 1.5 }, { math.huge }, { math.huge - math.huge }, { [2] = 123 } }
		for _, ids in cases do
			expect(pcall(function()
				Published.build {
					output = directory .. "/fixture.rbxlx",
					entry = "examples/multiplayer/entry.luau",
					authorizedUserIds = ids,
				}
			end)):toBe(false)
			expect(fs.exists(directory .. "/fixture.rbxlx")):toBe(false)
		end
		expect(pcall(function()
			Published.build {
				output = "",
				entry = "examples/multiplayer/entry.luau",
				authorizedUserIds = { 123 },
			}
		end)):toBe(false)
		expect(pcall(function()
			Published.build { output = directory .. "/fixture.rbxlx", entry = "", authorizedUserIds = { 123 } }
		end)):toBe(false)
		expect(pcall(function()
			Published.build {
				output = directory .. "/fixture.rbxlx",
				entry = "examples/multiplayer/entry.luau",
				authorizedUserIds = { 123 },
				frameworkDirectory = "",
			}
		end)):toBe(false)
	end)
end)

return nil
