--!strict

local D = require "./datatypes"
local Environment = require "./environment-types"

type Instance = Environment.Instance

local destroyed: Environment.ObserveFilter = { operations = { "destroy" :: Environment.Operation } }
type Info = D.TweenInfoValue
type Entry = { target: Instance, goal: { [string]: unknown }, info: Info, elapsed: number }

local SETTLED = 1e-6

local function attach(environment: Environment.Environment)
	local State = D.Enum.PlaybackState
	local entries: { [Instance]: Entry } = {}
	setmetatable(entries, { __mode = "k" })
	local active: { [Instance]: boolean } = {}
	local heartbeat: Environment.Connection? = nil
	local function idle()
		if next(active) == nil and heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end
	end
	local function settle(tween: Instance, state: unknown)
		active[tween] = nil
		environment.poke(tween, "PlaybackState", state)
		environment.fire(tween, "Completed", state)
	end
	local function advance(seconds: number)
		for tween in table.clone(active) do
			local entry = entries[tween]
			if entry == nil or not environment.isAlive(tween) or not environment.isAlive(entry.target) then
				active[tween] = nil
				continue
			end
			entry.elapsed += seconds
			local delay, duration = entry.info.DelayTime, entry.info.Time
			if entry.elapsed + SETTLED >= delay + duration then
				for key, value in entry.goal do
					entry.target[key] = value
				end
				settle(tween, State.Completed)
			elseif entry.elapsed + SETTLED >= delay then
				environment.poke(tween, "PlaybackState", State.Playing)
			end
		end
		idle()
	end
	environment.fake(
		"TweenService.Create",
		function(_service: Instance, target: Instance, info: Info, goal: { [string]: unknown }): Instance
			assert(D.typeName(info) == "TweenInfo", "TweenService:Create requires TweenInfo")
			assert(type(goal) == "table", "TweenService:Create requires a goal table")
			assert(
				info.RepeatCount == 0 and not info.Reverses,
				"the double supports tweens without repeats or reversal"
			)
			for key in goal do
				assert(type(key) == "string", "TweenService:Create goal keys must be property names")
			end
			local tween = environment.createEngineInstance "Tween"
			environment.poke(tween, "Instance", target)
			environment.poke(tween, "TweenInfo", info)
			entries[tween] = { target = target, goal = table.clone(goal), info = info, elapsed = 0 }
			return tween
		end
	)
	environment.fake("TweenBase.Play", function(tween: Instance)
		local entry = assert(entries[tween], "the tween was not created by TweenService:Create")
		if active[tween] then
			return
		end
		if tween.PlaybackState == State.Completed or tween.PlaybackState == State.Cancelled then
			entry.elapsed = 0
		end
		active[tween] = true
		environment.poke(
			tween,
			"PlaybackState",
			if entry.elapsed + SETTLED < entry.info.DelayTime then State.Delayed else State.Playing
		)
		if heartbeat == nil then
			heartbeat = environment.heartbeat:Connect(advance)
		end
	end)
	environment.fake("TweenBase.Pause", function(tween: Instance)
		if active[tween] then
			active[tween] = nil
			environment.poke(tween, "PlaybackState", State.Paused)
			idle()
		end
	end)
	environment.fake("TweenBase.Cancel", function(tween: Instance)
		local entry = entries[tween]
		if entry == nil or not (active[tween] or tween.PlaybackState == State.Paused) then
			return
		end
		entry.elapsed = 0
		settle(tween, State.Cancelled)
		idle()
	end)
	environment.observe(function(event)
		if active[event.object] then
			active[event.object] = nil
			idle()
		end
	end, destroyed)
end

return { attach = attach }
