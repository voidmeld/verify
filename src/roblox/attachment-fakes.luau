--!strict

local Types = require "./environment-types"
local Frames = require "./datatypes/cframe"
local Vm = require "./value"

local worldFrame: (Types.Instance) -> Frames.CFrameValue
local function basis(object: Types.Instance): Frames.CFrameValue
	local parent = object.Parent
	while parent ~= nil do
		if parent:IsA "Attachment" then
			return worldFrame(parent)
		elseif parent:IsA "BasePart" then
			return Frames.expect(parent.CFrame, 1)
		elseif parent:IsA "PVInstance" then
			local getPivot = parent.GetPivot
			assert(type(getPivot) == "function", "attachment ancestor requires GetPivot")
			local value: unknown = Vm.invoke(Vm.value(getPivot), parent)
			return Frames.expect(value, 1)
		end
		parent = parent.Parent
	end
	return Frames.CFrame.identity
end

worldFrame = function(object: Types.Instance): Frames.CFrameValue
	return basis(object) * Frames.expect(object.CFrame, 1)
end

return { basis = basis, worldFrame = worldFrame }
