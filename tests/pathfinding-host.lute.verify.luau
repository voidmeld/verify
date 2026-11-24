--!strict

local Test = require "./harness"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"
local it, expect = Test.it, Test.expect

it("configured paths expose copied waypoints and clear successful results after a miss", function(own)
	local bridge = Lute.fixture.bridge()
	own(bridge.close)
	local engine = bridge.placeEngine()
	local env = engine.environment
	local vector = engine.datatypes.Vector3
	local origin, destination = vector.new(1, 2, 3), vector.new(9, 2, 8)
	local success = true
	local observed: unknown = nil
	Roblox.pathfindingHost.install(engine, function(from, to, parameters)
		observed = parameters
		return if success then { from, vector.new(4, 2, 3), to } else nil
	end)
	local parameters = { AgentRadius = 2 }
	local service = engine.service "PathfindingService"
	local created: unknown = env.method(service, "CreatePath")(service, parameters)
	local path = env.assertInstance(created)
	parameters.AgentRadius = 4
	env.method(path, "ComputeAsync")(path, origin, destination)
	expect(path.Status):toBe(engine.datatypes.Enum.PathStatus.Success)
	expect(observed):toEqual { AgentRadius = 2 }
	local first: unknown = env.method(path, "GetWaypoints")(path)
	expect(Roblox.value.read(Roblox.value.read(Roblox.value.value(first), 2), "Position")):toBe(vector.new(4, 2, 3))
	Roblox.value.write(Roblox.value.read(Roblox.value.value(first), 2), "Label", "edited")
	local again: unknown = env.method(path, "GetWaypoints")(path)
	expect(Roblox.value.read(Roblox.value.read(Roblox.value.value(again), 2), "Label")):toBe ""
	success = false
	env.method(path, "ComputeAsync")(path, origin, destination)
	expect(path.Status):toBe(engine.datatypes.Enum.PathStatus.NoPath)
	expect(env.method(path, "GetWaypoints")(path)):toEqual {}
end)

it("configured paths refuse invalid endpoints and nonfinite geometry without reporting success", function(own)
	local bridge = Lute.fixture.bridge()
	own(bridge.close)
	local engine = bridge.placeEngine()
	local env = engine.environment
	local vector = engine.datatypes.Vector3
	local service = engine.service "PathfindingService"
	for _, points in
		{ { vector.zero }, { vector.zero, vector.one }, { vector.zero, vector.new(math.nan, 0, 0), vector.zero } }
	do
		Roblox.pathfindingHost.install(engine, function()
			return points
		end)
		local created: unknown = env.method(service, "CreatePath")(service)
		local path = env.assertInstance(created)
		expect(function()
			env.method(path, "ComputeAsync")(path, vector.zero, vector.zero)
		end):toThrow()
		expect(path.Status):toBe(engine.datatypes.Enum.PathStatus.NoPath)
	end
end)

return nil
