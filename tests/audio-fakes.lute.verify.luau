--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Lute = require "../src/lute"
local Environment = require "../src/roblox/environment"

type Instance = Environment.Instance

local function field(value: unknown, key: unknown): unknown
	assert(type(value) == "table")
	for name, item in value do
		if name == key then
			return item
		end
	end

	return nil
end

it("sound methods preserve seeks and pauses and emit playback transitions", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local env = engine.environment
	local sound = engine.newInstance "Sound"
	sound.SoundId = "fixture-sound"
	local play = env.method(sound, "Play")
	local pause = env.method(sound, "Pause")
	local resume = env.method(sound, "Resume")
	local stop = env.method(sound, "Stop")
	local received: { string } = {}
	local connections: { Environment.Connection } = {}
	for _, event in { "Played", "Paused", "Resumed", "Stopped", "Ended" } do
		local signal = env.event(sound, event)
		local connection = signal:Connect(function(id: unknown)
			expect(id):toBe "fixture-sound"
			table.insert(received, event)
		end)
		table.insert(connections, connection)
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
	local play = env.method(sound, "Play")
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
	local signal = env.event(sound, "DidLoop")
	signal:Connect(function(_, count)
		assert(type(count) == "number")
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
	local set = engine.environment.method(emitter, "SetDistanceAttenuation")
	local get = engine.environment.method(emitter, "GetDistanceAttenuation")
	expect(get(emitter)):toEqual {}
	local curve = { [0] = 1, [10] = 0.5, [20] = 0 }
	set(emitter, curve)
	curve[10] = 0.1
	local returned = get(emitter)
	assert(type(returned) == "table")
	table.clear(returned)
	local copy = assert(emitter:Clone())
	local getCopy = engine.environment.method(copy, "GetDistanceAttenuation")
	expect(field(getCopy(copy), 10)):toBe(0.5)
	set(emitter, nil)
	expect(get(emitter)):toEqual {}
	expect(field(getCopy(copy), 10)):toBe(0.5)
end)
it("attenuation clamps numeric bounds and retains the curve on invalid keys", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local emitter = engine.newInstance "AudioEmitter"
	local set = engine.environment.method(emitter, "SetDistanceAttenuation")
	local get = engine.environment.method(emitter, "GetDistanceAttenuation")
	set(emitter, { [-1] = 2, [10] = -1 })
	expect(get(emitter)):toEqual { [0] = 1, [10] = 0 }
	expect((pcall(set, emitter, { bad = 1 }))):toBe(false)
	expect(get(emitter)):toEqual { [0] = 1, [10] = 0 }
end)

it("modern audio controls preserve position and expose readiness separately", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local env = engine.environment
	for _, className in { "AudioPlayer", "AudioTextToSpeech" } do
		local player = engine.newInstance(className)
		local play = env.method(player, "Play")
		local halt = env.method(player, if className == "AudioPlayer" then "Stop" else "Pause")
		local ready = if className == "AudioPlayer" then "IsReady" else "IsLoaded"
		env.poke(player, ready, false)
		player.TimePosition = 2
		play(player)
		expect(player.IsPlaying):toBe(className == "AudioPlayer")
		expect(player.TimePosition):toBe(2)
		halt(player)
		expect(player.IsPlaying):toBe(false)
		expect(player.TimePosition):toBe(2)
		env.poke(player, ready, true)
		play(player)
		expect(player.IsPlaying):toBe(true)
		expect(pcall(halt, player, 1)):toBe(false)
		expect(player.IsPlaying):toBe(true)
		halt(player)
		expect(pcall(play, player, 1)):toBe(false)
		expect(player.IsPlaying):toBe(false)
	end
end)

return nil
