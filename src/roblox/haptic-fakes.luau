--!strict

local Environment = require "./environment-types"
local Datatypes = require "./datatypes"
local Enum = require "./datatypes/enum"

local function requireEnum(value: unknown, family: string)
	assert(Enum.isItem(value) and Enum.enumType(value) == family, "expected Enum." .. family)
end

local function attach(environment: Environment.Environment)
	environment.fake("HapticEffect.Play", function() end)
	environment.fake("HapticEffect.Stop", function() end)
	environment.fake("HapticEffect.SetWaveformKeys", function(effect: Environment.Instance, keys: { unknown })
		assert(tostring(effect.Type) == "Enum.HapticEffectType.Custom", "Cannot modify non-custom haptic effect!")
		assert(type(keys) == "table", "HapticEffect:SetWaveformKeys expects an array")
		for _, key in keys do
			assert(Datatypes.typeof(key) == "FloatCurveKey", "Variant cast failed")
		end
	end)
	environment.fake(
		"HapticService.IsVibrationSupported",
		function(_service: Environment.Instance, input: unknown): boolean
			requireEnum(input, "UserInputType")
			return false
		end
	)
	environment.fake(
		"HapticService.IsMotorSupported",
		function(_service: Environment.Instance, input: unknown, motor: unknown): boolean
			requireEnum(input, "UserInputType")
			requireEnum(motor, "VibrationMotor")
			return false
		end
	)
end

return { attach = attach }
