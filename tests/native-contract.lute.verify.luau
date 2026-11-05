--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Core = require "../src/core"
local Roblox = require "../src/roblox"
local Wire = require "../src/lute/wire"
local NativeCode = require "../tools/lib/native-code"
local Engine = require "./studio-engine"
local luau = require "@std/luau"

describe("native execution contract", function()
	it("narrows only unsandboxed verification modules before Assistant requires them", function()
		local factory = luau.load(
			luau.compile [[
local capabilities, removed = {}, false
local modules = {
 {Sandboxed = false, IsA = function(_, class) return class == 'ModuleScript' end},
 {Sandboxed = true, Capabilities = 'authored', IsA = function() return true end},
 {Sandboxed = false, IsA = function() return false end},
}
return {
 game = {GetService = function(_, name)
  assert(name == 'ReplicatedStorage')
  return {WaitForChild = function(_, root)
   assert(root == 'Mounted')
   return {GetDescendants = function() return modules end}
  end}
 end},
 SecurityCapabilities = {fromCurrent = function() return {Remove = function(_, value)
  assert(value == 'Unassigned'); removed = true; return capabilities
 end} end},
 Enum = {SecurityCapability = {Unassigned = 'Unassigned'}},
 verify = function()
  return removed and modules[1].Sandboxed and modules[1].Capabilities == capabilities
   and modules[2].Capabilities == 'authored' and not modules[3].Sandboxed
 end,
}
]],
			"=native-capabilities",
			{ assert = assert }
		)
		local engine = Engine.new(factory())
		expect(engine.run("Client", NativeCode("Mounted", "return verify()"))):toBe "true"
	end)

	it("one engine report survives chunking and refuses stale or duplicate runs", function()
		local harness = Core.createHarness { now = os.clock }
		harness:case("observed", function(context)
			context:expect(true):toBe(true)
		end)
		local report = harness:run { executor = "fixture", capabilities = {}, environment = {} }
		local lines: { string } = {}
		Roblox.reportChannel.publish("run-a", report, function(value)
			return Wire.encode(value)
		end, function(line)
			table.insert(lines, line)
		end)
		local bytes = table.concat(lines, "\n")
		expect(Roblox.reportChannel.collect(bytes, "run-a", Wire.parse).passed):toBe(1)
		expect(function()
			Roblox.reportChannel.collect(bytes, "run-b", Wire.parse)
		end):toThrow()
		expect(function()
			Roblox.reportChannel.receive({ runId = "run-a", report = {} }, "run-a")
		end):toThrow()
		local one = Wire.encode(Roblox.reportChannel.envelope("run-a", report))
		expect(function()
			Roblox.reportChannel.collect("VERIFY_REPORT|" .. one .. "\nVERIFY_REPORT|" .. one, "run-a", Wire.parse)
		end):toThrow()
	end)
	it("runtime unsupported preserves cleanup and an observed defect still fails", function()
		local cleaned = 0
		local harness = Core.createHarness { now = os.clock }
		harness:case("unsupported review", function(context)
			context:defer(function()
				cleaned += 1
			end)
			context:unsupported "native-renderer"
		end)
		local report = harness:run { executor = "fixture", capabilities = {}, environment = {} }
		expect(report.unsupported):toBe(1)
		expect(Core.decode(report).results[1].missingCapabilities):toEqual { "native-renderer" }
		expect(cleaned):toBe(1)
	end)
	it("player operations validate both sides without claiming simulated physics", function()
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
				context:expect(context:perform("client", Roblox.playerHost.inspect, nil).equipped):toBe "FixtureTool"
			end,
		}, host)
		expect(report.passed):toBe(1)
		expect(jumped):toBe(true)
		local nativeCase = require "../examples/player-case"
		expect(Core.runCase(nativeCase, host).unsupported):toBe(1)
	end)
end)

return nil
