--!strict

local Environment = require "./environment-types"

type Instance = Environment.Instance
type Curve = { [number]: number }

local function attach(environment: Environment.Environment)
	local curves = setmetatable({} :: { [Instance]: Curve }, { __mode = "k" })
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
