--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect
local Environment = require "../src/roblox/environment"
local Adapter = require "../src/roblox/environment-engine"
local Datatypes = require "../src/roblox/datatypes"
describe("environment engine adapter", function()
	it("preserves instance and signal identity with live mutations", function()
		local env = Environment.create()
		local engine = Adapter.create(env)
		local object = engine.new "Part"
		expect(Environment.isInstance(object)):toEqual(true)
		expect(engine.heartbeat == env.heartbeat):toEqual(true)
		local changed = engine.propertyChanged(object, "Name")
		expect(changed == (object:GetPropertyChangedSignal "Name")):toEqual(true)
		local calls = 0
		local connection = changed:Connect(function()
			calls += 1
		end)
		object.Name = "renamed"
		expect(calls):toEqual(1)
		env.step(0.5)
		expect(engine.clock()):toEqual(0.5)
		connection:Disconnect()
		engine.destroy(object)
		expect(env.liveObjects()):toEqual(0)
		expect(env.liveConnections()):toEqual(0)
	end)
	it("normalizes default and supplied datatype libraries", function()
		local env = Environment.create()
		local engine = Adapter.create(env, {
			typeName = Environment.typeName,
			datatypes = {
				Vector2 = { new = Datatypes.Vector2.new },
				Vector3 = { new = Datatypes.Vector3.new },
				Color3 = { new = Datatypes.Color3.new },
				UDim = { new = Datatypes.UDim.new },
				UDim2 = { new = Datatypes.UDim2.new },
				CFrame = { new = Datatypes.CFrame.new },
			},
		})
		local vector = engine.datatypes.Vector3
		local frame = engine.datatypes.CFrame
		local read = engine.readCFrame
		assert(vector and frame and read)
		local value = frame(vector(2, 3, 4), { 1, 0, 0, 0, 1, 0, 0, 0, 1 })
		local x, y, z, rotation = read(value)
		expect({ x, y, z }):toEqual { 2, 3, 4 }
		expect(rotation):toEqual { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
		expect(engine.typeName(value)):toEqual "CFrame"
		expect((pcall(frame, vector(0, 0, 0), {}))):toEqual(false)
	end)
end)

return nil
