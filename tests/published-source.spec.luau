--!strict

local fs = require "@std/fs"
local Core = require "../src/core"
local Files = require "../src/lute/files"
local Published = require "../src/lute/published-source"
local function fixture(context: Core.Context): string
	local directory = Files.claimDirectory "/tmp/verify-published-source-tests"
	context:defer(function()
		fs.removeDirectory(directory, { recursive = true })
	end)
	return directory
end
return function(suite: Core.Harness)
	suite:suite("published verification fixture", function()
		suite:case("builds a caller-authorized server runner with run-correlated client output", function(check)
			local directory = fixture(check)
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
				check:expect(source:find(token, 1, true) ~= nil):toBe(true)
			end
			check:expect(source:find("InvokeServer()", 1, true) ~= nil):toBe(true)
			check:expect(source:find("OnServerInvoke=function(player: Player)", 1, true) ~= nil):toBe(true)
		end)
		suite:case("builds client execution only after server authorization", function(check)
			local directory = fixture(check)
			Published.build {
				output = directory .. "/fixture.rbxlx",
				entry = "examples/multiplayer/entry.luau",
				roots = { "examples/multiplayer" },
				authorizedUserIds = { 123 },
				context = "Client",
			}
			local source = fs.readFileToString(directory .. "/fixture.rbxlx")
			check:expect(source:find("return authorize(player)", 1, true) ~= nil):toBe(true)
			check:expect(source:find("local report=execute(request)", 1, true) ~= nil):toBe(true)
			check:expect(source:find("Channel.publish(request.runId", 1, true) ~= nil):toBe(true)
		end)
		suite:case("rejects empty duplicate malformed or sparse authorization before writing", function(check)
			local directory = fixture(check)
			local cases: { { number } } =
				{ {}, { 1, 1 }, { 0 }, { -1 }, { 1.5 }, { math.huge }, { math.huge - math.huge }, { [2] = 123 } }
			for _, ids in cases do
				check
					:expect(pcall(function()
						Published.build {
							output = directory .. "/fixture.rbxlx",
							entry = "examples/multiplayer/entry.luau",
							authorizedUserIds = ids,
						}
					end))
					:toBe(false)
				check:expect(fs.exists(directory .. "/fixture.rbxlx")):toBe(false)
			end
			check
				:expect(pcall(function()
					Published.build {
						output = "",
						entry = "examples/multiplayer/entry.luau",
						authorizedUserIds = { 123 },
					}
				end))
				:toBe(false)
			check
				:expect(pcall(function()
					Published.build { output = directory .. "/fixture.rbxlx", entry = "", authorizedUserIds = { 123 } }
				end))
				:toBe(false)
			check
				:expect(pcall(function()
					Published.build {
						output = directory .. "/fixture.rbxlx",
						entry = "examples/multiplayer/entry.luau",
						authorizedUserIds = { 123 },
						frameworkDirectory = "",
					}
				end))
				:toBe(false)
		end)
	end)
end
