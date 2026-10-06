--!strict

local Core = require "../src/core"
local Roblox = require "../src/roblox"
local Wire = require "../src/lute/wire"
local json = require "@std/json"

return function(suite: Core.Harness)
	suite:suite("native execution contract", function()
		suite:case("one engine report survives chunking and refuses stale or duplicate runs", function(check)
			local harness = Core.createHarness { now = os.clock }
			harness:case("observed", function(context)
				context:expect(true):toBe(true)
			end)
			local report = harness:run { executor = "fixture", capabilities = {}, environment = {} }
			local lines: { string } = {}
			Roblox.reportChannel.publish("run-a", report, function(value)
				return json.serialize(value :: json.Value)
			end, function(line)
				table.insert(lines, line)
			end)
			local bytes = table.concat(lines, "\n")
			check:expect(Roblox.reportChannel.collect(bytes, "run-a", Wire.parse).passed):toBe(1)
			check
				:expect(function()
					Roblox.reportChannel.collect(bytes, "run-b", Wire.parse)
				end)
				:toThrow()
			check
				:expect(function()
					Roblox.reportChannel.receive({ runId = "run-a", report = {} }, "run-a")
				end)
				:toThrow()
			local one = json.serialize(Roblox.reportChannel.envelope("run-a", report))
			check
				:expect(function()
					Roblox.reportChannel.collect(
						"VERIFY_REPORT|" .. one .. "\nVERIFY_REPORT|" .. one,
						"run-a",
						Wire.parse
					)
				end)
				:toThrow()
		end)
		suite:case("runtime unsupported preserves cleanup and an observed defect still fails", function(check)
			local cleaned = 0
			local harness = Core.createHarness { now = os.clock }
			harness:case("unsupported review", function(context)
				context:defer(function()
					cleaned += 1
				end)
				context:unsupported "native-renderer"
			end)
			local report = harness:run { executor = "fixture", capabilities = {}, environment = {} }
			check:expect(report.unsupported):toBe(1)
			check:expect(Core.decode(report).results[1].missingCapabilities):toEqual { "native-renderer" }
			check:expect(cleaned):toBe(1)
		end)
		suite:case("player operations validate both sides without claiming simulated physics", function(check)
			local moved = { x = 0, y = 0, z = 0 }
			local jumped = false
			local equipped: string? = nil
			local bound = Roblox.playerHost.registry {
				move = function(value)
					moved = value
				end,
				jump = function()
					jumped = true
				end,
				equip = function(value)
					equipped = value
				end,
				state = function()
					return {
						position = moved,
						velocity = { x = 0, y = 0, z = 0 },
						health = 100,
						maximumHealth = 100,
						equipped = equipped,
					}
				end,
			}
			local host: Core.CaseHost = {
				name = "player-fixture",
				capabilities = {
					"action:player.move",
					"action:player.jump",
					"action:player.equip",
					"query:player.state",
				},
				environment = {},
				now = function()
					return 0
				end,
				invoke = function(request)
					local endpoints = if request.kind == "action" then bound.actions else bound.queries
					return endpoints[request.name].run(request.payload, request)
				end,
			}
			local report = Core.runCase({
				id = "player",
				name = "player vocabulary",
				run = function(context: Core.Context)
					context:perform("client", Roblox.playerHost.move, { x = 1, y = 0, z = 0 })
					context:perform("client", Roblox.playerHost.jump, nil)
					context:perform("client", Roblox.playerHost.equip, "FixtureTool")
					context
						:expect(context:perform("client", Roblox.playerHost.inspect, nil).equipped)
						:toBe "FixtureTool"
				end,
			}, host)
			check:expect(report.passed):toBe(1)
			check:expect(jumped):toBe(true)
			local nativeCase = require "../examples/player-case"
			check:expect(Core.runCase(nativeCase, host).unsupported):toBe(1)
		end)
	end)
end
