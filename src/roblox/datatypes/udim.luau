--!strict

local Float = require "./float"
local Names = require "./names"
local Vector = require "./vector"

local f32 = Float.f32

type Vector2Value = Vector.Vector2Value

export type UDimValue = typeof(setmetatable(
	{} :: { Scale: number, Offset: number },
	{} :: {
		__add: (UDimValue, UDimValue) -> UDimValue,
		__sub: (UDimValue, UDimValue) -> UDimValue,
		__unm: (UDimValue) -> UDimValue,
		__eq: (UDimValue, UDimValue) -> boolean,
		__tostring: (UDimValue) -> string,
	}
))

export type UDim2Value = typeof(setmetatable(
	{} :: {
		X: UDimValue,
		Y: UDimValue,
		Width: UDimValue,
		Height: UDimValue,
		Lerp: (self: UDim2Value, goal: UDim2Value, alpha: number) -> UDim2Value,
	},
	{} :: {
		__add: (UDim2Value, UDim2Value) -> UDim2Value,
		__sub: (UDim2Value, UDim2Value) -> UDim2Value,
		__unm: (UDim2Value) -> UDim2Value,
		__eq: (UDim2Value, UDim2Value) -> boolean,
		__tostring: (UDim2Value) -> string,
	}
))

export type RectValue = typeof(setmetatable(
	{} :: { Min: Vector2Value, Max: Vector2Value, Width: number, Height: number },
	{} :: {
		__eq: (RectValue, RectValue) -> boolean,
		__tostring: (RectValue) -> string,
	}
))

local UDimKind = Names.behavior("UDim", { quoted = true })
local UDim2Kind = Names.behavior "UDim2"
local RectKind = Names.behavior("Rect", { quoted = true })

local function udim(scale: number, offset: number): UDimValue
	return Names.make(UDimKind, { Scale = f32(scale), Offset = Float.int32(offset) })
end

local function udim2(x: UDimValue, y: UDimValue): UDim2Value
	return Names.make(UDim2Kind, { X = x, Y = y })
end

local function expect(value: unknown, kind: Names.Behavior, owner: string, position: number)
	if not Names.is(value, kind) then
		Names.argument(position, owner, value)
	end
end

local function scale(value: number): string
	return Float.general(value, 9)
end

UDimKind.meta.__add = function(a: UDimValue, b: UDimValue): UDimValue
	expect(b, UDimKind, "UDim", 2)
	return udim(a.Scale + b.Scale, a.Offset + b.Offset)
end
UDimKind.meta.__sub = function(a: UDimValue, b: UDimValue): UDimValue
	expect(b, UDimKind, "UDim", 2)
	return udim(a.Scale - b.Scale, a.Offset - b.Offset)
end
UDimKind.meta.__unm = function(a: UDimValue): UDimValue
	return udim(-a.Scale, -a.Offset)
end
UDimKind.meta.__eq = function(a: UDimValue, b: UDimValue): boolean
	return a.Scale == b.Scale and a.Offset == b.Offset
end
UDimKind.meta.__tostring = function(a: UDimValue): string
	return scale(a.Scale) .. ", " .. string.format("%d", a.Offset)
end

local function lerpOffset(a: number, b: number, t: number): number
	return math.round(a + (b - a) * t)
end

local udim2Methods: { [string]: unknown } = {
	Lerp = function(self: UDim2Value, goal: unknown, alpha: number): UDim2Value
		expect(goal, UDim2Kind, "UDim2", 1)
		local target = goal :: UDim2Value
		local t = f32(alpha)
		return udim2(
			udim(
				self.X.Scale + f32(f32(target.X.Scale - self.X.Scale) * t),
				lerpOffset(self.X.Offset, target.X.Offset, t)
			),
			udim(
				self.Y.Scale + f32(f32(target.Y.Scale - self.Y.Scale) * t),
				lerpOffset(self.Y.Offset, target.Y.Offset, t)
			)
		)
	end,
}

UDim2Kind.fields.__index = function(value: UDim2Value, key: unknown): unknown
	local method = udim2Methods[key :: string]
	if method ~= nil then
		return method
	elseif key == "Width" then
		return value.X
	elseif key == "Height" then
		return value.Y
	end
	return Names.invalid(key, "UDim2")
end
UDim2Kind.meta.__add = function(a: UDim2Value, b: UDim2Value): UDim2Value
	expect(b, UDim2Kind, "UDim2", 2)
	return udim2(a.X + b.X, a.Y + b.Y)
end
UDim2Kind.meta.__sub = function(a: UDim2Value, b: UDim2Value): UDim2Value
	expect(b, UDim2Kind, "UDim2", 2)
	return udim2(a.X - b.X, a.Y - b.Y)
end
UDim2Kind.meta.__unm = function(a: UDim2Value): UDim2Value
	return udim2(-a.X, -a.Y)
end
UDim2Kind.meta.__eq = function(a: UDim2Value, b: UDim2Value): boolean
	return a.X == b.X and a.Y == b.Y
end
UDim2Kind.meta.__tostring = function(a: UDim2Value): string
	return ("{%s, %d}, {%s, %d}"):format(scale(a.X.Scale), a.X.Offset, scale(a.Y.Scale), a.Y.Offset)
end

RectKind.fields.__index = function(value: RectValue, key: unknown): unknown
	if key == "Width" then
		return f32(value.Max.X - value.Min.X)
	elseif key == "Height" then
		return f32(value.Max.Y - value.Min.Y)
	end
	return Names.missing(RectKind, key)
end
RectKind.meta.__eq = function(a: RectValue, b: RectValue): boolean
	return a.Min == b.Min and a.Max == b.Max
end
RectKind.meta.__tostring = function(a: RectValue): string
	return ("%s, %s, %s, %s"):format(scale(a.Min.X), scale(a.Min.Y), scale(a.Max.X), scale(a.Max.Y))
end

local UDim = {
	new = function(scaleValue: unknown?, offset: unknown?): UDimValue
		return udim(Float.coerce(scaleValue, 1), Float.coerce(offset, 2))
	end,
}

local function newUDim2(...: unknown): UDim2Value
	local first, second = ...
	if Names.is(first, UDimKind) or Names.is(second, UDimKind) then
		expect(first, UDimKind, "UDim", 1)
		expect(second, UDimKind, "UDim", 2)
		return udim2(first :: UDimValue, second :: UDimValue)
	end
	local _, _, third, fourth = ...
	return udim2(
		udim(Float.coerce(first, 1), Float.coerce(second, 2)),
		udim(Float.coerce(third, 3), Float.coerce(fourth, 4))
	)
end

local UDim2 = {
	new = newUDim2 :: ((number?, number?, number?, number?) -> UDim2Value) & ((UDimValue, UDimValue) -> UDim2Value),
	fromScale = function(x: unknown?, y: unknown?): UDim2Value
		return udim2(udim(Float.coerce(x, 1), 0), udim(Float.coerce(y, 2), 0))
	end,
	fromOffset = function(x: unknown?, y: unknown?): UDim2Value
		return udim2(udim(0, Float.coerce(x, 1)), udim(0, Float.coerce(y, 2)))
	end,
}

local function rect(x0: number, y0: number, x1: number, y1: number): RectValue
	local min = Vector.Vector2.new(math.min(x0, x1), math.min(y0, y1))
	local max = Vector.Vector2.new(math.max(x0, x1), math.max(y0, y1))
	return Names.make(RectKind, { Min = min, Max = max })
end

local Rect = {
	new = function(...: unknown): RectValue
		local first, second = ...
		if Vector.isVector2(first) or Vector.isVector2(second) then
			if not Vector.isVector2(first) then
				Names.argument(1, "Vector2", first)
			end
			if not Vector.isVector2(second) then
				Names.argument(2, "Vector2", second)
			end
			local a, b = first :: Vector2Value, second :: Vector2Value
			return rect(a.X, a.Y, b.X, b.Y)
		end
		local _, _, third, fourth = ...
		return rect(Float.coerce(first, 1), Float.coerce(second, 2), Float.coerce(third, 3), Float.coerce(fourth, 4))
	end,
}

return { UDim = UDim, UDim2 = UDim2, Rect = Rect }
