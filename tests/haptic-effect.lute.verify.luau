--!strict

local Test = require "./harness"
local it, expect = Test.it, Test.expect
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"

it("haptic effects accept native waveform keys and reject non-custom edits", function(own)
	local snapshot = Lute.fixture.load()
	local bridge = Lute.fixture.bridge(snapshot)
	own(bridge.close)
	local engine = bridge.placeEngine()
	local library = Roblox.reflectionSnapshot.library(snapshot)
	local globals: { [string]: unknown } = {
		Enum = library.Enum,
		FloatCurveKey = library.FloatCurveKey,
		Instance = { new = bridge.environment.createInstance },
		workspace = engine.service "Workspace",
	}
	expect(Lute.chunk.load(require "./fixtures/haptic-effect", { environment = globals })()):toBe(true)
end)

it("a host without haptic hardware reports no motors and emits no completion", function(own)
	local snapshot = Lute.fixture.load()
	local library = Roblox.reflectionSnapshot.library(snapshot)
	local bridge = Lute.fixture.bridge(snapshot)
	own(bridge.close)
	local engine = bridge.placeEngine()
	local service = engine.service "HapticService"
	local vibration = service.IsVibrationSupported :: (Roblox.Instance, unknown) -> boolean
	local motor = service.IsMotorSupported :: (Roblox.Instance, unknown, unknown) -> boolean
	for _, input in { library.Enum.UserInputType.Gamepad1, library.Enum.UserInputType.Touch } do
		expect(vibration(service, input)):toBe(false)
		expect(motor(service, input, library.Enum.VibrationMotor.Large)):toBe(false)
	end
	local effect = bridge.environment.createInstance "HapticEffect"
	effect.Parent = engine.service "Workspace"
	local play = effect.Play :: (Roblox.Instance) -> ()
	local stop = effect.Stop :: (Roblox.Instance) -> ()
	play(effect)
	bridge.environment.step(1)
	stop(effect)
	expect(bridge.environment.signalOf(effect, "Ended").fires()):toBe(0)
end)

return nil
