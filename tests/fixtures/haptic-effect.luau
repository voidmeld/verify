--!strict

return [==[
local effect = Instance.new("HapticEffect")
effect.Parent = workspace
for _, preset in { Enum.HapticEffectType.UIClick, Enum.HapticEffectType.UINotification, Enum.HapticEffectType.GameplayCollision } do
	effect.Type = preset
	assert(not pcall(function() effect:SetWaveformKeys({}) end))
	effect:Play()
	effect:Stop()
end
effect.Type = Enum.HapticEffectType.Custom
effect:SetWaveformKeys({})
assert(not pcall(function() effect:SetWaveformKeys({1}) end))
for _, keys in {
	{FloatCurveKey.new(-1, 0, Enum.KeyInterpolationMode.Linear)},
	{FloatCurveKey.new(0, 2, Enum.KeyInterpolationMode.Linear)},
	{FloatCurveKey.new(0, 0, Enum.KeyInterpolationMode.Linear), FloatCurveKey.new(0, 1, Enum.KeyInterpolationMode.Linear)},
	{FloatCurveKey.new(10, 0, Enum.KeyInterpolationMode.Linear), FloatCurveKey.new(0, 1, Enum.KeyInterpolationMode.Linear)},
} do
	effect:SetWaveformKeys(keys)
end
effect:SetWaveformKeys({
	FloatCurveKey.new(0, 0, Enum.KeyInterpolationMode.Linear),
	FloatCurveKey.new(20, 1, Enum.KeyInterpolationMode.Linear),
	FloatCurveKey.new(100, 0, Enum.KeyInterpolationMode.Linear),
})
effect.Looped = true
effect:Play()
effect:Stop()
local clone = effect:Clone()
clone.Parent = workspace
clone:Play()
clone:Stop()
clone:Destroy()
effect:Destroy()
return true
]==]
