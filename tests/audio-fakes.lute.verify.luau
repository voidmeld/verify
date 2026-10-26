--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Lute = require "../src/lute"
local Environment = require "../src/roblox/environment"

type Instance = Environment.Instance
type Method = (Instance) -> ()

it("sound methods preserve seeks and pauses and emit playback transitions", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local env = engine.environment
	local sound = engine.newInstance "Sound"
	sound.SoundId = "fixture-sound"
	local play = sound.Play :: Method
	local pause = sound.Pause :: Method
	local resume = sound.Resume :: Method
	local stop = sound.Stop :: Method
	local received: { string } = {}
	local connections: { Environment.Connection } = {}
	for _, event in { "Played", "Paused", "Resumed", "Stopped", "Ended" } do
		local signal = sound[event] :: Environment.Signal<string>
		table.insert(
			connections,
			signal:Connect(function(id)
				expect(id):toBe "fixture-sound"
				table.insert(received, event)
			end)
		)
	end
	env.poke(sound, "TimeLength", 10)
	sound.TimePosition = 2
	play(sound)
	expect(sound.TimePosition):toBe(2)
	expect(sound.Playing):toBe(true)
	expect(sound.IsPlaying):toBe(true)
	expect(sound.IsPaused):toBe(false)
	env.step(1)
	expect(sound.TimePosition):toBe(3)
	pause(sound)
	env.step(1)
	expect(sound.TimePosition):toBe(3)
	resume(sound)
	sound.PlaybackSpeed = 2
	env.step(1)
	expect(sound.TimePosition):toBe(5)
	play(sound)
	expect(sound.TimePosition):toBe(2)
	stop(sound)
	expect(sound.TimePosition):toBe(0)
	expect(sound.IsPaused):toBe(true)
	expect(received):toEqual { "Played", "Paused", "Resumed", "Played", "Stopped" }
	for _, connection in connections do
		connection:Disconnect()
	end
	expect(env.liveConnections()):toBe(0)
end)
it("sound completion loops and destruction release clock subscriptions", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local env = engine.environment
	local sound = engine.newInstance "Sound"
	local play = sound.Play :: Method
	env.poke(sound, "TimeLength", 2)
	play(sound)
	env.step(2)
	expect(sound.IsPlaying):toBe(false)
	expect(sound.TimePosition):toBe(0)
	expect(env.signalOf(sound, "Ended").fires()):toBe(1)
	expect(env.signalOf(sound, "Stopped").fires()):toBe(0)
	expect(env.liveConnections()):toBe(0)
	sound.Looped = true
	local loops: { number } = {}
	local signal = sound.DidLoop :: Environment.Signal<string, number>
	signal:Connect(function(_, count)
		table.insert(loops, count)
	end)
	play(sound)
	env.step(5)
	expect(sound.TimePosition):toBe(1)
	expect(loops):toEqual { 1, 2 }
	expect(sound.IsPlaying):toBe(true)
	sound:Destroy()
	expect(env.liveConnections()):toBe(0)
	env.step(5)
	expect(#env.errors):toBe(0)
end)
it("attenuation curves copy inputs, outputs and cloned emitters", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local emitter = engine.newInstance "AudioEmitter"
	local set = emitter.SetDistanceAttenuation :: (typeof(emitter), { [number]: number }?) -> ()
	local get = emitter.GetDistanceAttenuation :: (typeof(emitter)) -> { [number]: number }
	expect(get(emitter)):toEqual {}
	local curve = { [0] = 1, [10] = 0.5, [20] = 0 }
	set(emitter, curve)
	curve[10] = 0.1
	get(emitter)[10] = 0.2
	local copy = assert(emitter:Clone())
	local getCopy = copy.GetDistanceAttenuation :: (typeof(copy)) -> { [number]: number }
	expect(getCopy(copy)[10]):toBe(0.5)
	set(emitter, nil)
	expect(get(emitter)):toEqual {}
	expect(getCopy(copy)[10]):toBe(0.5)
end)
it("attenuation clamps numeric bounds and retains the curve on invalid keys", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local emitter = engine.newInstance "AudioEmitter"
	local set = emitter.SetDistanceAttenuation :: (typeof(emitter), { [unknown]: unknown }) -> ()
	local get = emitter.GetDistanceAttenuation :: (typeof(emitter)) -> { [number]: number }
	set(emitter, { [-1] = 2, [10] = -1 })
	expect(get(emitter)):toEqual { [0] = 1, [10] = 0 }
	expect((pcall(set, emitter, { bad = 1 }))):toBe(false)
	expect(get(emitter)):toEqual { [0] = 1, [10] = 0 }
end)

return nil
