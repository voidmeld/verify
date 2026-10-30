--!strict

local Float = require "./float"
local Names = require "./names"
local Vector = require "./vector"

local f32 = Float.f32

type Vector2Value = Vector.Vector2Value

local UDimValueFields: { Scale: number, Offset: number }
local UDimValueMeta: {
	__add: (UDimValue, UDimValue) -> UDimValue,
	__sub: (UDimValue, UDimValue) -> UDimValue,
	__unm: (UDimValue) -> UDimValue,
	__eq: (UDimValue, UDimValue) -> boolean,
	__tostring: (UDimValue) -> string,
}

export type UDimValue = typeof(setmetatable(UDimValueFields, UDimValueMeta))

local UDim2ValueFields: {
	X: UDimValue,
	Y: UDimValue,
	Width: UDimValue,
	Height: UDimValue,
	Lerp: (self: UDim2Value, goal: UDim2Value, alpha: number) -> UDim2Value,
}
local UDim2ValueMeta: {
	__add: (UDim2Value, UDim2Value) -> UDim2Value,
	__sub: (UDim2Value, UDim2Value) -> UDim2Value,
	__unm: (UDim2Value) -> UDim2Value,
	__eq: (UDim2Value, UDim2Value) -> boolean,
	__tostring: (UDim2Value) -> string,
}

export type UDim2Value = typeof(setmetatable(UDim2ValueFields, UDim2ValueMeta))

local RectValueFields: { Min: Vector2Value, Max: Vector2Value, Width: number, Height: number }
local RectValueMeta: {
	__eq: (RectValue, RectValue) -> boolean,
	__tostring: (RectValue) -> string,
}

export type RectValue = typeof(setmetatable(RectValueFields, RectValueMeta))

local UDimKind = Names.behavior("UDim", { quoted = true })
local UDim2Kind = Names.behavior "UDim2"
local RectKind = Names.behavior("Rect", { quoted = true })

local udims: { [unknown]: UDimValue } = {}
local udim2s: { [unknown]: UDim2Value } = {}
Names.weak(udims)
Names.weak(udim2s)

local function udim(scale: number, offset: number): UDimValue
	local made: UDimValue = Names.make(UDimKind, { Scale = f32(scale), Offset = Float.int32(offset) })
	udims[made] = made
	return made
end

local XS, XO, YS, YO = {}, {}, {}, {}

local function parts(value: UDim2Value): (number, number, number, number)
	local fields = Names.fields(value)
	return fields[XS] :: number, fields[XO] :: number, fields[YS] :: number, fields[YO] :: number
end

local function compose(xs: number, xo: number, ys: number, yo: number): UDim2Value
	local made: UDim2Value =
		Names.make(UDim2Kind, { [XS] = f32(xs), [XO] = Float.int32(xo), [YS] = f32(ys), [YO] = Float.int32(yo) })
	udim2s[made] = made
	return made
end

local function udim2(x: UDimValue, y: UDimValue): UDim2Value
	return compose(x.Scale, x.Offset, y.Scale, y.Offset)
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

local udim2Methods: { [unknown]: unknown } = {
	Lerp = function(self: UDim2Value, goal: unknown, alpha: number): UDim2Value
		expect(goal, UDim2Kind, "UDim2", 1)
		local t = f32(alpha)
		local xs, xo, ys, yo = parts(self)
		local txs, txo, tys, tyo = parts(udim2s[goal])
		return compose(
			xs + f32(f32(txs - xs) * t),
			lerpOffset(xo, txo, t),
			ys + f32(f32(tys - ys) * t),
			lerpOffset(yo, tyo, t)
		)
	end,
}

UDim2Kind.fields.__index = function(value: UDim2Value, key: unknown): unknown
	local method = udim2Methods[key]
	if method ~= nil then
		return method
	elseif key == "X" or key == "Width" then
		local fields = (value :: unknown) :: Names.Fields
		local made = rawget(fields, "X") or udim(fields[XS] :: number, fields[XO] :: number)
		rawset(fields, "X", made)
		return made
	elseif key == "Y" or key == "Height" then
		local fields = (value :: unknown) :: Names.Fields
		local made = rawget(fields, "Y") or udim(fields[YS] :: number, fields[YO] :: number)
		rawset(fields, "Y", made)
		return made
	end
	return Names.invalid(key, "UDim2")
end
UDim2Kind.meta.__add = function(a: UDim2Value, b: UDim2Value): UDim2Value
	expect(b, UDim2Kind, "UDim2", 2)
	local axs, axo, ays, ayo = parts(a)
	local bxs, bxo, bys, byo = parts(b)
	return compose(axs + bxs, axo + bxo, ays + bys, ayo + byo)
end
UDim2Kind.meta.__sub = function(a: UDim2Value, b: UDim2Value): UDim2Value
	expect(b, UDim2Kind, "UDim2", 2)
	local axs, axo, ays, ayo = parts(a)
	local bxs, bxo, bys, byo = parts(b)
	return compose(axs - bxs, axo - bxo, ays - bys, ayo - byo)
end
UDim2Kind.meta.__unm = function(a: UDim2Value): UDim2Value
	local xs, xo, ys, yo = parts(a)
	return compose(-xs, -xo, -ys, -yo)
end
UDim2Kind.meta.__eq = function(a: UDim2Value, b: UDim2Value): boolean
	local axs, axo, ays, ayo = parts(a)
	local bxs, bxo, bys, byo = parts(b)
	return axs == bxs and axo == bxo and ays == bys and ayo == byo
end
UDim2Kind.meta.__tostring = function(a: UDim2Value): string
	local xs, xo, ys, yo = parts(a)
	return ("{%s, %d}, {%s, %d}"):format(scale(xs), xo, scale(ys), yo)
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
		return udim2(udims[first], udims[second])
	end
	local _, _, third, fourth = ...
	return compose(Float.coerce(first, 1), Float.coerce(second, 2), Float.coerce(third, 3), Float.coerce(fourth, 4))
end

local UDim2 = {
	new = newUDim2,
	fromScale = function(x: unknown?, y: unknown?): UDim2Value
		return compose(Float.coerce(x, 1), 0, Float.coerce(y, 2), 0)
	end,
	fromOffset = function(x: unknown?, y: unknown?): UDim2Value
		return compose(0, Float.coerce(x, 1), 0, Float.coerce(y, 2))
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
			local a, b = Vector.expect2(first, 1), Vector.expect2(second, 2)
			return rect(a.X, a.Y, b.X, b.Y)
		end
		local _, _, third, fourth = ...
		return rect(Float.coerce(first, 1), Float.coerce(second, 2), Float.coerce(third, 3), Float.coerce(fourth, 4))
	end,
}

return { UDim = UDim, UDim2 = UDim2, Rect = Rect }
