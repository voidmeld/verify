--!strict

local Float = require "./float"
local Names = require "./names"

local f32 = Float.f32

local Color3ValueFields: {
	R: number,
	G: number,
	B: number,
	Lerp: (self: Color3Value, goal: Color3Value, alpha: number) -> Color3Value,
	ToHSV: (self: Color3Value) -> (number, number, number),
	ToHex: (self: Color3Value) -> string,
}
local Color3ValueMeta: {
	__eq: (Color3Value, Color3Value) -> boolean,
	__tostring: (Color3Value) -> string,
}

export type Color3Value = typeof(setmetatable(Color3ValueFields, Color3ValueMeta))

local BrickColorValueFields: {
	Number: number,
	Name: string,
	Color: Color3Value,
	r: number,
	g: number,
	b: number,
}
local BrickColorValueMeta: {
	__eq: (BrickColorValue, BrickColorValue) -> boolean,
	__tostring: (BrickColorValue) -> string,
}

export type BrickColorValue = typeof(setmetatable(BrickColorValueFields, BrickColorValueMeta))

export type BrickColorEntry = { number: number, name: string, color: { number } }
export type BrickColorCatalog = { colors: { BrickColorEntry }, palette: { number } }

export type BrickColorConstructor = {
	new: (...unknown) -> BrickColorValue,
	palette: (index: number) -> BrickColorValue,
	random: () -> BrickColorValue,
	White: () -> BrickColorValue,
	Gray: () -> BrickColorValue,
	DarkGray: () -> BrickColorValue,
	Black: () -> BrickColorValue,
	Red: () -> BrickColorValue,
	Yellow: () -> BrickColorValue,
	Green: () -> BrickColorValue,
	Blue: () -> BrickColorValue,
}

local Color3Kind = Names.behavior "Color3"
local BrickColorKind = Names.behavior("BrickColor", { quoted = true })

local values: { [unknown]: Color3Value? } = {}
Names.weak(values)

local function make(r: number, g: number, b: number): Color3Value
	local made: Color3Value = Names.make(Color3Kind, { R = f32(r), G = f32(g), B = f32(b) })
	values[made] = made
	return made
end

local function expect(value: unknown, position: number): Color3Value
	local found = values[value]
	if found == nil then
		return Names.argument(position, "Color3", value)
	end
	return found
end

local function fromHSV(hue: number, saturation: number, value: number): Color3Value
	local h, s, v = f32(hue), f32(saturation), f32(value)
	local scaled = f32(h * 6)
	local sector = math.floor(scaled)
	if sector > 5 then
		sector = 5
	end
	if sector < 0 then
		return make(0, 0, 0)
	end
	local fraction = f32(scaled - sector)
	local p = f32(v * f32(1 - s))
	local q = f32(v * f32(1 - f32(s * fraction)))
	local t = f32(v * f32(1 - f32(s * f32(1 - fraction))))
	if sector == 0 then
		return make(v, t, p)
	elseif sector == 1 then
		return make(q, v, p)
	elseif sector == 2 then
		return make(p, v, t)
	elseif sector == 3 then
		return make(p, q, v)
	elseif sector == 4 then
		return make(t, p, v)
	end
	return make(v, p, q)
end

local function toHSV(color: Color3Value): (number, number, number)
	local r, g, b = math.clamp(color.R, 0, 1), math.clamp(color.G, 0, 1), math.clamp(color.B, 0, 1)
	local high, low = math.max(r, g, b), math.min(r, g, b)
	local delta = f32(high - low)
	local saturation = if high > 0 then f32(delta / high) else 0
	if delta <= 0 then
		return 0, saturation, high
	end
	local hue
	if high == r then
		hue = f32(f32(g - b) / delta)
	elseif high == g then
		hue = f32(2 + f32(f32(b - r) / delta))
	else
		hue = f32(4 + f32(f32(r - g) / delta))
	end
	hue = f32(hue / 6)
	if hue < 0 then
		hue = f32(hue + 1)
	end
	return hue, saturation, high
end

local function byte(component: number): number
	return math.clamp(math.floor(component * 255 + 0.5), 0, 255)
end

local function toHex(color: Color3Value): string
	return string.format("%02x%02x%02x", byte(color.R), byte(color.G), byte(color.B))
end

local function fromHex(text: string): Color3Value
	local digits = string.gsub(text, "^#", "")
	if #digits == 3 then
		digits = string.gsub(digits, ".", "%0%0")
	end
	if #digits ~= 6 or string.find(digits, "%X") ~= nil then
		error("Unable to convert characters to hex value", 2)
	end
	local value = tonumber(digits, 16)
	assert(value ~= nil)
	return make(
		bit32.rshift(value, 16) / 255,
		bit32.band(bit32.rshift(value, 8), 255) / 255,
		bit32.band(value, 255) / 255
	)
end

local methods: { [unknown]: unknown } = {
	Lerp = function(self: Color3Value, goal: unknown, alpha: number): Color3Value
		local target = expect(goal, 1)
		local t = f32(alpha)
		return make(
			self.R + f32(f32(target.R - self.R) * t),
			self.G + f32(f32(target.G - self.G) * t),
			self.B + f32(f32(target.B - self.B) * t)
		)
	end,
	ToHSV = toHSV,
	ToHex = toHex,
}

Color3Kind.fields.__index = function(color: Color3Value, key: unknown): unknown
	local method = methods[key]
	if method ~= nil then
		return method
	elseif key == "r" then
		return color.R
	elseif key == "g" then
		return color.G
	elseif key == "b" then
		return color.B
	end
	return Names.invalid(key, "Color3")
end
Color3Kind.meta.__eq = function(a: Color3Value, b: Color3Value): boolean
	return a.R == b.R and a.G == b.G and a.B == b.B
end
Color3Kind.meta.__tostring = function(color: Color3Value): string
	return Float.general(color.R, 6) .. ", " .. Float.general(color.G, 6) .. ", " .. Float.general(color.B, 6)
end

local Color3 = {
	new = function(r: unknown?, g: unknown?, b: unknown?): Color3Value
		return make(Float.coerce(r, 1), Float.coerce(g, 2), Float.coerce(b, 3))
	end,
	fromRGB = function(r: unknown?, g: unknown?, b: unknown?): Color3Value
		return make(Float.coerce(r, 1) / 255, Float.coerce(g, 2) / 255, Float.coerce(b, 3) / 255)
	end,
	fromHSV = fromHSV,
	fromHex = fromHex,
	toHSV = function(color: unknown): (number, number, number)
		return toHSV(expect(color, 1))
	end,
}

BrickColorKind.fields.__index = function(color: BrickColorValue, key: unknown): unknown
	if key == "r" then
		return color.Color.R
	elseif key == "g" then
		return color.Color.G
	elseif key == "b" then
		return color.Color.B
	end
	return Names.missing(BrickColorKind, key)
end
BrickColorKind.meta.__eq = function(a: BrickColorValue, b: BrickColorValue): boolean
	return a.Number == b.Number
end
BrickColorKind.meta.__tostring = function(color: BrickColorValue): string
	return color.Name
end

local DEFAULT_NUMBER = 194

local function brickColor(catalog: BrickColorCatalog?): BrickColorConstructor
	local byNumber: { [number]: BrickColorValue } = {}
	local byName: { [string]: BrickColorValue } = {}
	local ordered: { BrickColorValue } = {}
	local entries: { BrickColorEntry } = if catalog ~= nil then catalog.colors else {}
	for _, entry in entries do
		local value: BrickColorValue = Names.make(BrickColorKind, {
			Number = entry.number,
			Name = entry.name,
			Color = make(entry.color[1], entry.color[2], entry.color[3]),
		})
		byNumber[entry.number] = value
		table.insert(ordered, value)
	end
	table.sort(ordered, function(a: BrickColorValue, b: BrickColorValue): boolean
		return a.Number < b.Number
	end)
	for _, value in ordered do
		byName[value.Name] = value
	end
	local palette: { number } = if catalog ~= nil then catalog.palette else {}

	local function require_(): ()
		if #ordered == 0 then
			error("BrickColor requires a reflection snapshot with brickColors", 3)
		end
	end

	local function numbered(number: number): BrickColorValue
		require_()
		return byNumber[number] or byNumber[DEFAULT_NUMBER] or ordered[1]
	end

	local function closest(r: number, g: number, b: number): BrickColorValue
		require_()
		local best, distance = ordered[1], math.huge
		for _, candidate in ordered do
			local color = candidate.Color
			local measured = math.abs(color.R - r) + math.abs(color.G - g) + math.abs(color.B - b)
			if measured < distance then
				best, distance = candidate, measured
			end
		end
		return best
	end

	local function new(...: unknown): BrickColorValue
		local first = ...
		if select("#", ...) >= 3 then
			local _, g, b = ...
			return closest(Float.coerce(first, 1), Float.coerce(g, 2), Float.coerce(b, 3))
		elseif type(first) == "number" then
			return numbered(first)
		elseif type(first) == "string" then
			require_()
			return byName[first] or numbered(DEFAULT_NUMBER)
		elseif Names.is(first, Color3Kind) then
			local color = expect(first, 1)
			return closest(color.R, color.G, color.B)
		elseif first == nil then
			return closest(0, 0, 0)
		end
		return Names.argument(1, "number", first)
	end

	local function named(name: string): () -> BrickColorValue
		return function(): BrickColorValue
			return new(name)
		end
	end

	return {
		new = new,
		palette = function(index: number): BrickColorValue
			require_()
			local number = palette[index + 1]
			if index % 1 ~= 0 or number == nil then
				error(("palette index out of bounds (%s)"):format(tostring(index)), 2)
			end
			return numbered(number)
		end,
		random = function(): BrickColorValue
			require_()
			return numbered(palette[math.random(1, #palette)])
		end,
		White = named "White",
		Gray = named "Medium stone grey",
		DarkGray = named "Dark stone grey",
		Black = named "Black",
		Red = named "Bright red",
		Yellow = named "Bright yellow",
		Green = named "Dark green",
		Blue = named "Bright blue",
	}
end

return {
	Color3 = Color3,
	brickColor = brickColor,
	isColor3 = function(value: unknown): boolean
		return Names.is(value, Color3Kind)
	end,
}
