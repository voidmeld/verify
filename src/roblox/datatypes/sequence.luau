--!strict

local Color = require "./color"
local Float = require "./float"
local Names = require "./names"

local f32 = Float.f32

type Color3Value = Color.Color3Value

export type NumberRangeValue = typeof(setmetatable(
	{} :: { Min: number, Max: number },
	{} :: { __eq: (NumberRangeValue, NumberRangeValue) -> boolean, __tostring: (NumberRangeValue) -> string }
))

export type NumberSequenceKeypointValue = typeof(setmetatable(
	{} :: { Time: number, Value: number, Envelope: number },
	{} :: {
		__eq: (NumberSequenceKeypointValue, NumberSequenceKeypointValue) -> boolean,
		__tostring: (NumberSequenceKeypointValue) -> string,
	}
))

export type ColorSequenceKeypointValue = typeof(setmetatable(
	{} :: { Time: number, Value: Color3Value },
	{} :: {
		__eq: (ColorSequenceKeypointValue, ColorSequenceKeypointValue) -> boolean,
		__tostring: (ColorSequenceKeypointValue) -> string,
	}
))

export type NumberSequenceValue = typeof(setmetatable(
	{} :: { Keypoints: { NumberSequenceKeypointValue } },
	{} :: { __eq: (NumberSequenceValue, NumberSequenceValue) -> boolean, __tostring: (NumberSequenceValue) -> string }
))

export type ColorSequenceValue = typeof(setmetatable(
	{} :: { Keypoints: { ColorSequenceKeypointValue } },
	{} :: { __eq: (ColorSequenceValue, ColorSequenceValue) -> boolean, __tostring: (ColorSequenceValue) -> string }
))

type Keypoint = { Time: number }

local KEYPOINTS = {}

local NumberRangeKind = Names.behavior("NumberRange", { quoted = true })
local NumberKeypointKind = Names.behavior("NumberSequenceKeypoint", { quoted = true })
local ColorKeypointKind = Names.behavior("ColorSequenceKeypoint", { quoted = true })
local NumberSequenceKind = Names.behavior("NumberSequence", { quoted = true })
local ColorSequenceKind = Names.behavior("ColorSequence", { quoted = true })

local function general(value: number): string
	return Float.general(value, 6)
end

NumberRangeKind.meta.__eq = function(a: NumberRangeValue, b: NumberRangeValue): boolean
	return a.Min == b.Min and a.Max == b.Max
end
NumberRangeKind.meta.__tostring = function(a: NumberRangeValue): string
	return general(a.Min) .. " " .. general(a.Max) .. " "
end

local NumberRange = {
	new = function(min: unknown, max: unknown?): NumberRangeValue
		local low = f32(Float.coerce(min, 1))
		local high = if max == nil then low else f32(Float.coerce(max, 2))
		if high < low then
			error("NumberRange: invalid range", 2)
		end
		return Names.make(NumberRangeKind, { Min = low, Max = high })
	end,
}

NumberKeypointKind.meta.__eq = function(a: NumberSequenceKeypointValue, b: NumberSequenceKeypointValue): boolean
	return a.Time == b.Time and a.Value == b.Value and a.Envelope == b.Envelope
end
NumberKeypointKind.meta.__tostring = function(a: NumberSequenceKeypointValue): string
	return general(a.Time) .. " " .. general(a.Value) .. " " .. general(a.Envelope) .. " "
end

local function numberKeypoint(time: number, value: number, envelope: number): NumberSequenceKeypointValue
	return Names.make(NumberKeypointKind, { Time = f32(time), Value = f32(value), Envelope = f32(envelope) })
end

local NumberSequenceKeypoint = {
	new = function(time: unknown, value: unknown, envelope: unknown?): NumberSequenceKeypointValue
		return numberKeypoint(Float.coerce(time, 1), Float.coerce(value, 2), Float.coerce(envelope, 3))
	end,
}

ColorKeypointKind.meta.__eq = function(a: ColorSequenceKeypointValue, b: ColorSequenceKeypointValue): boolean
	return a.Time == b.Time and a.Value == b.Value
end
ColorKeypointKind.meta.__tostring = function(a: ColorSequenceKeypointValue): string
	return ("%s %s %s %s 0 "):format(general(a.Time), general(a.Value.R), general(a.Value.G), general(a.Value.B))
end

local function colorKeypoint(time: number, color: unknown): ColorSequenceKeypointValue
	if not Color.isColor3(color) then
		Names.argument(2, "Color3", color)
	end
	return Names.make(ColorKeypointKind, { Time = f32(time), Value = color })
end

local ColorSequenceKeypoint = {
	new = function(time: unknown, color: unknown): ColorSequenceKeypointValue
		return colorKeypoint(Float.coerce(time, 1), color)
	end,
}

local function validate(owner: string, keypoints: { Keypoint })
	if #keypoints < 2 then
		error(owner .. ": requires at least 2 keypoints", 3)
	elseif #keypoints > 20 then
		error(owner .. ": table is too long.", 3)
	end
	if keypoints[1].Time ~= 0 then
		error(owner .. " must start at time=0.0", 3)
	end
	if keypoints[#keypoints].Time ~= 1 then
		error(owner .. " must end at time=1.0", 3)
	end
	for index = 2, #keypoints do
		if keypoints[index].Time < keypoints[index - 1].Time then
			error(owner .. ": all keypoints must be ordered by time", 3)
		end
	end
end

local function keypointsOf(value: unknown): { unknown }
	return Names.fields(value)[KEYPOINTS] :: { unknown }
end

local function sequenceKind(kind: Names.Behavior, owner: string)
	kind.fields.__index = function(fields: { [unknown]: unknown }, key: unknown): unknown
		if key == "Keypoints" then
			return table.clone(fields[KEYPOINTS] :: { unknown })
		end
		return Names.missing(kind, key)
	end
	local meta = kind.meta
	meta.__eq = function(a: unknown, b: unknown): boolean
		local left = keypointsOf(a)
		local right = keypointsOf(b)
		if #left ~= #right then
			return false
		end
		for index, keypoint in left do
			if keypoint ~= right[index] then
				return false
			end
		end
		return true
	end
	meta.__tostring = function(value: unknown): string
		local parts: { string } = {}
		for _, keypoint in keypointsOf(value) do
			table.insert(parts, tostring(keypoint))
		end
		return table.concat(parts)
	end
end

sequenceKind(NumberSequenceKind, "NumberSequence")
sequenceKind(ColorSequenceKind, "ColorSequence")

local function keypointList(value: unknown, kind: Names.Behavior, owner: string): { unknown }
	local list: { unknown } = {}
	for index, keypoint in value :: { unknown } do
		if not Names.is(keypoint, kind) then
			error(("%s: expected keypoint at index %d"):format(owner, index), 3)
		end
		list[index] = keypoint
	end
	return list
end

local NumberSequence = {
	new = function(...: unknown): NumberSequenceValue
		local first, second = ...
		local keypoints: { unknown }
		if type(first) == "table" and not Names.is(first, NumberKeypointKind) then
			keypoints = keypointList(first, NumberKeypointKind, "NumberSequence")
		elseif second ~= nil then
			keypoints = { numberKeypoint(0, Float.coerce(first, 1), 0), numberKeypoint(1, Float.coerce(second, 2), 0) }
		else
			local value = Float.coerce(first, 1)
			keypoints = { numberKeypoint(0, value, 0), numberKeypoint(1, value, 0) }
		end
		validate("NumberSequence", (keypoints :: unknown) :: { Keypoint })
		return Names.make(NumberSequenceKind, { [KEYPOINTS] = table.freeze(keypoints) })
	end,
}

local ColorSequence = {
	new = function(...: unknown): ColorSequenceValue
		local first, second = ...
		local keypoints: { unknown }
		if type(first) == "table" and not Color.isColor3(first) then
			keypoints = keypointList(first, ColorKeypointKind, "ColorSequence")
		elseif second ~= nil then
			keypoints = { colorKeypoint(0, first), colorKeypoint(1, second) }
		else
			keypoints = { colorKeypoint(0, first), colorKeypoint(1, first) }
		end
		validate("ColorSequence", (keypoints :: unknown) :: { Keypoint })
		return Names.make(ColorSequenceKind, { [KEYPOINTS] = table.freeze(keypoints) })
	end,
}

return {
	NumberRange = NumberRange,
	NumberSequenceKeypoint = NumberSequenceKeypoint,
	NumberSequence = NumberSequence,
	ColorSequenceKeypoint = ColorSequenceKeypoint,
	ColorSequence = ColorSequence,
}
