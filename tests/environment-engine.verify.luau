--!strict
local Core = require "../src/core"
local Environment = require "../src/roblox/environment"
local Adapter = require "../src/roblox/environment-engine"
local Datatypes = require "../src/roblox/datatypes"
return function(suite: Core.Harness)
	suite:suite("environment engine adapter", function()
		suite:case("preserves instance and signal identity with live mutations", function(check)
			local env = Environment.create()
			local engine = Adapter.create(env)
			local object = engine.new "Part"
			check:expect(Environment.isInstance(object)):toEqual(true)
			check:expect(engine.heartbeat == (env.heartbeat :: unknown)):toEqual(true)
			local changed = engine.propertyChanged(object, "Name")
			check:expect(changed == (object:GetPropertyChangedSignal "Name" :: unknown)):toEqual(true)
			local calls = 0
			local connection = changed:Connect(function()
				calls += 1
			end)
			object.Name = "renamed"
			check:expect(calls):toEqual(1)
			env.step(0.5)
			check:expect(engine.clock()):toEqual(0.5)
			connection:Disconnect()
			engine.destroy(object)
			check:expect(env.liveObjects()):toEqual(0)
			check:expect(env.liveConnections()):toEqual(0)
		end)
		suite:case("normalizes default and supplied datatype libraries", function(check)
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
			check:expect({ x, y, z }):toEqual { 2, 3, 4 }
			check:expect(rotation):toEqual { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
			check:expect(engine.typeName(value)):toEqual "CFrame"
			check:expect((pcall(frame, vector(0, 0, 0), {}))):toEqual(false)
		end)
	end)
end
