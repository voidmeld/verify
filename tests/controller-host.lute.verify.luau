--!strict

local Test = require "./harness"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"

Test.it("opt-in controller motion follows the configured direction and stops on disconnect", function(own)
	local bridge = Lute.fixture.bridge()
	own(function()
		bridge.close()
	end)
	local engine = bridge.placeEngine()
	local runtime = Roblox.createPlaceRuntime(engine, { root = engine.game, scripts = {}, sources = {} }, {
		aliases = {},
		cache = Roblox.createPlaceCache(Lute.fixture.host),
		host = Lute.fixture.host,
	})
	local motion = Roblox.controllerHost.simulated(engine)
	local model = engine.newInstance "Model"
	model.Parent = engine.service "Workspace"
	local root = engine.newInstance "Part"
	root.Name, root.Parent = "Root", model
	root.CFrame = engine.datatypes.CFrame.new(2, 3, 4)
	model.PrimaryPart = root
	local controller = engine.newInstance "GroundController"
	controller.MoveSpeedFactor = 0.5
	local manager = engine.newInstance "ControllerManager"
	manager.RootPart, manager.ActiveController, manager.Parent = root, controller, model
	manager.BaseMoveSpeed, manager.MovingDirection = 12, engine.datatypes.Vector3.new(0, 0, 1)
	runtime.step(0.5)
	Test.expect(root.Position):toEqual(engine.datatypes.Vector3.new(2, 3, 7))
	Test.expect(root.AssemblyLinearVelocity):toEqual(engine.datatypes.Vector3.new(0, 0, 6))
	root.Anchored = true
	runtime.step(0.5)
	Test.expect(root.Position):toEqual(engine.datatypes.Vector3.new(2, 3, 7))
	root.Anchored = false
	motion:Disconnect()
	runtime.step(0.5)
	Test.expect(root.Position):toEqual(engine.datatypes.Vector3.new(2, 3, 7))
	Test.expect(motion.Connected):toBe(false)
end)

Test.it("controller floor sensing uses the host raycast and preserves manual sensors", function(own)
	local bridge = Lute.fixture.bridge()
	own(function()
		bridge.close()
	end)
	local engine = bridge.placeEngine()
	local runtime = Roblox.createPlaceRuntime(engine, { root = engine.game, scripts = {}, sources = {} }, {
		aliases = {},
		cache = Roblox.createPlaceCache(Lute.fixture.host),
		host = Lute.fixture.host,
	})
	local motion = Roblox.controllerHost.simulated(engine)
	own(function()
		motion:Disconnect()
	end)
	local model = engine.newInstance "Model"
	model.Parent = engine.service "Workspace"
	local root = engine.newInstance "Part"
	root.Name, root.Parent, model.PrimaryPart = "Root", model, root
	local ground = engine.newInstance "Part"
	ground.Parent = engine.service "Workspace"
	local sensor = engine.newInstance "ControllerPartSensor"
	sensor.UpdateType = engine.datatypes.Enum.SensorUpdateType.OnRead
	local controller = engine.newInstance "GroundController"
	controller.GroundOffset, controller.MoveSpeedFactor = 3, 1
	local manager = engine.newInstance "ControllerManager"
	manager.Parent, manager.RootPart, manager.ActiveController, manager.GroundSensor = model, root, controller, sensor
	manager.BaseMoveSpeed, manager.MovingDirection = 10, engine.datatypes.Vector3.zero
	engine.environment.fake("Workspace.Raycast", function()
		return {
			Instance = ground,
			Position = engine.datatypes.Vector3.new(0, 8, 0),
			Normal = engine.datatypes.Vector3.yAxis,
		}
	end)
	runtime.step(0.1)
	Test.expect(root.Position):toEqual(engine.datatypes.Vector3.new(0, 11, 0))
	Test.expect(sensor.SensedPart):toBe(ground)
	sensor.UpdateType = engine.datatypes.Enum.SensorUpdateType.Manual
	engine.environment.poke(sensor, "SensedPart", nil)
	runtime.step(0.1)
	Test.expect(sensor.SensedPart):toBeNil()
end)

return nil
