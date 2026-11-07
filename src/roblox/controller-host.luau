--!strict

local Types = require "./place-types"
local Frames = require "./datatypes/cframe"
local Vectors = require "./datatypes/vector"
local Environment = require "./environment"

local function number(value: unknown): number
	assert(type(value) == "number" and math.abs(value) < math.huge, "controller requires a finite number")
	return value
end

local function simulated(engine: Types.Engine): Environment.Connection
	local environment = engine.environment
	local managers: { Types.Instance } = {}
	local function added(object: Environment.Object)
		if object:IsA "ControllerManager" then
			table.insert(managers, environment.assertInstance(object))
		end
	end
	for _, object in engine.service("Workspace"):GetDescendants() do
		added(object)
	end
	local created = environment.onCreate(added)
	local connection = environment.event(engine.service "RunService", "PreSimulation"):Connect(function(raw: unknown)
		local seconds = number(raw)
		for _, manager in table.clone(managers) do
			if not environment.isAlive(manager) then
				local index = table.find(managers, manager)
				if index then
					table.remove(managers, index)
				end
				continue
			end
			if not manager:IsDescendantOf(engine.service "Workspace") then
				continue
			end
			local rootValue, activeValue = manager.RootPart, manager.ActiveController
			if rootValue == nil or activeValue == nil then
				continue
			end
			local root, active = environment.assertInstance(rootValue), environment.assertInstance(activeValue)
			if root.Anchored == true then
				continue
			end
			assert(active:IsA "GroundController" or active:IsA "AirController", "unsupported kinematic controller")
			local frame = Frames.expect(root.CFrame, 1)
			local direction = Vectors.expect3(manager.MovingDirection, 1)
			local speed = number(manager.BaseMoveSpeed) * number(active.MoveSpeedFactor)
			local velocity = engine.datatypes.Vector3.new(direction.X, 0, direction.Z) * speed
			local destination = frame.Position + velocity * seconds
			local sensorValue = manager.GroundSensor
			if sensorValue ~= nil then
				local sensor = environment.assertInstance(sensorValue)
				if sensor.UpdateType == engine.datatypes.Enum.SensorUpdateType.OnRead then
					local params = engine.datatypes.RaycastParams.new()
					params.FilterType = engine.datatypes.Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = { assert(manager.Parent) }
					params.RespectCanCollide = true
					local hit = environment.method(engine.service "Workspace", "Raycast")(
						engine.service "Workspace",
						destination + engine.datatypes.Vector3.new(0, 32, 0),
						engine.datatypes.Vector3.new(0, -512, 0),
						params
					)
					if hit ~= nil then
						local part = Environment.read(hit, "Instance")
						local position = Vectors.expect3(Environment.read(hit, "Position"), 1)
						environment.poke(sensor, "SensedPart", part)
						environment.poke(sensor, "HitNormal", Environment.read(hit, "Normal"))
						environment.poke(sensor, "HitFrame", engine.datatypes.CFrame.new(position))
						if active:IsA "GroundController" then
							destination = engine.datatypes.Vector3.new(
								destination.X,
								position.Y + number(active.GroundOffset),
								destination.Z
							)
						end
					else
						environment.poke(sensor, "SensedPart", nil)
					end
				end
			end
			environment.poke(root, "AssemblyLinearVelocity", velocity)
			local model = manager.Parent
			assert(model ~= nil and model:IsA "Model", "controller requires a model")
			local pivot = Frames.expect(environment.method(model, "GetPivot")(model), 1)
			environment.method(model, "PivotTo")(model, pivot + (destination - frame.Position))
		end
	end)
	return {
		Connected = true,
		Disconnect = function(self: Environment.Connection)
			self.Connected = false
			connection:Disconnect()
			created:Disconnect()
			table.clear(managers)
		end,
	}
end

return { simulated = simulated }
