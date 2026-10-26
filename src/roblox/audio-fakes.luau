--!strict

local Environment = require "./environment-types"

type Instance = Environment.Instance
type Curve = { [number]: number }

local function attach(environment: Environment.Environment)
	local seeks: { [Instance]: number } = {}
	setmetatable(seeks, { __mode = "k" })
	local active: { [Instance]: number } = {}
	local heartbeat: Environment.Connection? = nil
	local function idle()
		if next(active) == nil and heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end
	end
	local function playing(sound: Instance, value: boolean)
		environment.poke(sound, "Playing", value)
		environment.poke(sound, "IsPlaying", value)
		environment.poke(sound, "IsPaused", not value)
	end
	local function start(sound: Instance)
		playing(sound, true)
		active[sound] = active[sound] or 0
		if heartbeat then
			return
		end
		heartbeat = environment.heartbeat:Connect(function(seconds: number)
			for object, loops in table.clone(active) do
				if not environment.isAlive(object) or object.Playing ~= true then
					active[object] = nil
					continue
				end
				local position = (object.TimePosition :: number) + seconds * (object.PlaybackSpeed :: number)
				local length = object.TimeLength :: number
				if length > 0 and position >= length then
					if object.Looped == true then
						local count = math.floor(position / length)
						position %= length
						active[object] = loops + count
						for index = 1, count do
							environment.fire(object, "DidLoop", object.SoundId, loops + index)
						end
					else
						active[object] = nil
						playing(object, false)
						environment.poke(object, "TimePosition", 0)
						environment.fire(object, "Ended", object.SoundId)
						continue
					end
				end
				environment.poke(object, "TimePosition", position)
			end
			idle()
		end)
	end
	environment.observe(function(event)
		local object = event.object
		if not object:IsA "Sound" then
			return
		end
		if
			event.operation == "setProperty"
			and event.member == "TimePosition"
			and type(event.value) == "number"
			and not event.injected
		then
			seeks[object] = event.value
		elseif event.operation == "destroy" then
			active[object] = nil
			idle()
		end
	end)
	environment.fake("Sound.Play", function(sound: Instance)
		environment.poke(sound, "TimePosition", seeks[sound] or 0)
		start(sound)
		environment.fire(sound, "Played", sound.SoundId)
	end)
	environment.fake("Sound.Pause", function(sound: Instance)
		playing(sound, false)
		active[sound] = nil
		idle()
		environment.fire(sound, "Paused", sound.SoundId)
	end)
	environment.fake("Sound.Resume", function(sound: Instance)
		start(sound)
		environment.fire(sound, "Resumed", sound.SoundId)
	end)
	environment.fake("Sound.Stop", function(sound: Instance)
		playing(sound, false)
		environment.poke(sound, "TimePosition", 0)
		active[sound] = nil
		idle()
		environment.fire(sound, "Stopped", sound.SoundId)
	end)
	local curves: { [Instance]: Curve } = {}
	setmetatable(curves, { __mode = "k" })
	environment.fake("AudioEmitter.SetDistanceAttenuation", function(object: Instance, curve: { [unknown]: unknown }?)
		local nextCurve: Curve = {}
		local count = 0
		local points: { [unknown]: unknown } = curve or {}
		for distance, volume in points do
			assert(type(distance) == "number", "AudioEmitter:SetDistanceAttenuation: numeric key expected.")
			assert(type(volume) == "number", "AudioEmitter:SetDistanceAttenuation: numeric volume expected.")
			assert(distance == distance and math.abs(distance) < math.huge, "distance must be finite")
			assert(volume == volume and math.abs(volume) < math.huge, "volume must be finite")
			count += 1
			assert(count <= 400, "distance attenuation supports at most 400 points")
			nextCurve[math.max(0, distance)] = math.clamp(volume, 0, 1)
		end
		curves[object] = nextCurve
	end)
	environment.fake("AudioEmitter.GetDistanceAttenuation", function(object: Instance): Curve
		return table.clone(curves[object] or {})
	end)
	environment.onClone(function(source: Instance, copy: Instance)
		local curve = curves[source]
		if curve ~= nil then
			curves[copy] = table.clone(curve)
		end
	end)
end

return { attach = attach }
