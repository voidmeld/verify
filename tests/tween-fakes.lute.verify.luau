--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Lute = require "../src/lute"
local Environment = require "../src/roblox/environment"
local D = require "../src/roblox/datatypes"

type Instance = Environment.Instance

local function fixture()
	local bridge = Lute.fixture.bridge()
	local engine = bridge.engine
	local service = bridge.environment.createEngineInstance "TweenService"
	local create = bridge.environment.method(service, "Create")
	return bridge.environment,
		engine,
		function(target: Instance, info: unknown, goal: { [string]: unknown }): Instance
			return Environment.assertInstance(create(service, target, info, goal))
		end
end

it("tweens interpolate after the delay with the declared easing", function()
	local env, engine, create = fixture()
	local Enum, TweenInfo = D.Enum, D.TweenInfo
	local frame = env.createEngineInstance "Frame"
	frame.BackgroundTransparency = 1
	local tween = create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out, 0, false, 0.1), {
		BackgroundTransparency = 0,
	})
	expect(tween.ClassName):toBe "Tween"
	expect(tween.Instance):toBe(frame)
	expect(tween.PlaybackState):toBe(Enum.PlaybackState.Begin)
	local states: { unknown } = {}
	local completed = env.event(tween, "Completed")
	completed:Connect(function(state)
		table.insert(states, state)
	end)
	local writes = 0
	local watch = env.observe(function(event)
		if event.object == frame and event.member == "BackgroundTransparency" then
			writes += 1
		end
	end)
	local play = env.method(tween, "Play")
	play(tween)
	expect(tween.PlaybackState):toBe(Enum.PlaybackState.Delayed)
	local pause = env.method(tween, "Pause")
	pause(tween)
	expect(tween.PlaybackState):toBe(Enum.PlaybackState.Delayed)
	env.step(0.1)
	expect(tween.PlaybackState):toBe(Enum.PlaybackState.Playing)
	expect(frame.BackgroundTransparency):toBe(1)
	expect(writes):toBe(0)
	env.step(0.15)
	expect(frame.BackgroundTransparency):toBeCloseTo(0.125, 1e-6)
	expect(writes):toBe(1)
	env.step(0.15)
	expect(frame.BackgroundTransparency):toBe(0)
	expect(writes):toBe(2)
	expect(tween.PlaybackState):toBe(Enum.PlaybackState.Completed)
	expect(states):toEqual { Enum.PlaybackState.Completed }
	watch:Disconnect()
	tween:Destroy()
	expect(env.liveConnections()):toBe(0)
end)

it("pause holds progress and cancellation restarts from the held position", function()
	local env, engine, create = fixture()
	local Enum, TweenInfo = D.Enum, D.TweenInfo
	local frame = env.createEngineInstance "Frame"
	local tween = create(frame, TweenInfo.new(1, Enum.EasingStyle.Linear), { Position = D.UDim2.fromOffset(100, 200) })
	local play, pause, cancel = env.method(tween, "Play"), env.method(tween, "Pause"), env.method(tween, "Cancel")
	local states: { unknown } = {}
	local completed = env.event(tween, "Completed")
	completed:Connect(function(state)
		table.insert(states, state)
	end)
	play(tween)
	env.step(0.6)
	expect(frame.Position):toBe(D.UDim2.fromOffset(60, 120))
	pause(tween)
	expect(tween.PlaybackState):toBe(Enum.PlaybackState.Paused)
	env.step(5)
	expect(frame.Position):toBe(D.UDim2.fromOffset(60, 120))
	play(tween)
	env.step(0.4)
	expect(frame.Position):toBe(D.UDim2.fromOffset(100, 200))
	frame.Position = D.UDim2.fromOffset(0, 0)
	play(tween)
	env.step(0.5)
	expect(frame.Position):toBe(D.UDim2.fromOffset(50, 100))
	cancel(tween)
	expect(tween.PlaybackState):toBe(Enum.PlaybackState.Cancelled)
	env.step(1)
	expect(frame.Position):toBe(D.UDim2.fromOffset(50, 100))
	cancel(tween)
	expect(states):toEqual { Enum.PlaybackState.Completed, Enum.PlaybackState.Cancelled }
	play(tween)
	env.step(0.5)
	expect(frame.Position):toBe(D.UDim2.fromOffset(75, 150))
	env.step(0.5)
	expect(frame.Position):toBe(D.UDim2.fromOffset(100, 200))
	expect(env.liveConnections()):toBe(1)
	tween:Destroy()
	expect(env.liveConnections()):toBe(0)
end)

it("destroying a playing tween releases the clock and rejects unsupported tweens", function()
	local env, engine, create = fixture()
	local TweenInfo = D.TweenInfo
	local frame = env.createEngineInstance "Frame"
	local tween = create(frame, TweenInfo.new(1), { BackgroundTransparency = 0.5 })
	local play = env.method(tween, "Play")
	play(tween)
	tween:Destroy()
	env.step(2)
	expect(frame.BackgroundTransparency):toBe(0)
	expect(env.liveConnections()):toBe(0)
	local goal: { [string]: unknown } = { BackgroundTransparency = 1 }
	expect((pcall(create, frame, TweenInfo.new(1, nil, nil, 2), goal))):toBe(false)
	expect((pcall(create, frame, TweenInfo.new(1, nil, nil, 0, true), goal))):toBe(false)
	expect((pcall(create, frame, 1, goal))):toBe(false)
	expect(#env.errors):toBe(0)
end)

return nil
