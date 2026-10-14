--!strict

local Enum = require "./enum"
local Float = require "./float"
local Names = require "./names"

local f32 = Float.f32

export type Vector2Value = typeof(setmetatable(
	{} :: {
		X: number,
		Y: number,
		Magnitude: number,
		Unit: Vector2Value,
		Lerp: (self: Vector2Value, goal: Vector2Value, alpha: number) -> Vector2Value,
		Dot: (self: Vector2Value, other: Vector2Value) -> number,
		Cross: (self: Vector2Value, other: Vector2Value) -> number,
		Abs: (self: Vector2Value) -> Vector2Value,
		Ceil: (self: Vector2Value) -> Vector2Value,
		Floor: (self: Vector2Value) -> Vector2Value,
		Sign: (self: Vector2Value) -> Vector2Value,
		Max: (self: Vector2Value, ...Vector2Value) -> Vector2Value,
		Min: (self: Vector2Value, ...Vector2Value) -> Vector2Value,
		Angle: (self: Vector2Value, other: Vector2Value, isSigned: boolean?) -> number,
		FuzzyEq: (self: Vector2Value, other: Vector2Value, epsilon: number?) -> boolean,
	},
	{} :: {
		__add: (Vector2Value, Vector2Value) -> Vector2Value,
		__sub: (Vector2Value, Vector2Value) -> Vector2Value,
		__mul: (Vector2Value | number, Vector2Value | number) -> Vector2Value,
		__div: (Vector2Value | number, Vector2Value | number) -> Vector2Value,
		__idiv: (Vector2Value, Vector2Value | number) -> Vector2Value,
		__unm: (Vector2Value) -> Vector2Value,
		__eq: (Vector2Value, Vector2Value) -> boolean,
		__tostring: (Vector2Value) -> string,
	}
))

export type Vector3Value = typeof(setmetatable(
	{} :: {
		X: number,
		Y: number,
		Z: number,
		Magnitude: number,
		Unit: Vector3Value,
		Lerp: (self: Vector3Value, goal: Vector3Value, alpha: number) -> Vector3Value,
		Dot: (self: Vector3Value, other: Vector3Value) -> number,
		Cross: (self: Vector3Value, other: Vector3Value) -> Vector3Value,
		Abs: (self: Vector3Value) -> Vector3Value,
		Ceil: (self: Vector3Value) -> Vector3Value,
		Floor: (self: Vector3Value) -> Vector3Value,
		Sign: (self: Vector3Value) -> Vector3Value,
		Max: (self: Vector3Value, ...Vector3Value) -> Vector3Value,
		Min: (self: Vector3Value, ...Vector3Value) -> Vector3Value,
		Angle: (self: Vector3Value, other: Vector3Value, axis: Vector3Value?) -> number,
		FuzzyEq: (self: Vector3Value, other: Vector3Value, epsilon: number?) -> boolean,
	},
	{} :: {
		__add: (Vector3Value, Vector3Value) -> Vector3Value,
		__sub: (Vector3Value, Vector3Value) -> Vector3Value,
		__mul: (Vector3Value | number, Vector3Value | number) -> Vector3Value,
		__div: (Vector3Value | number, Vector3Value | number) -> Vector3Value,
		__idiv: (Vector3Value, Vector3Value | number) -> Vector3Value,
		__unm: (Vector3Value) -> Vector3Value,
		__eq: (Vector3Value, Vector3Value) -> boolean,
		__tostring: (Vector3Value) -> string,
	}
))

export type Vector2int16Value = typeof(setmetatable(
	{} :: { X: number, Y: number },
	{} :: {
		__add: (Vector2int16Value, Vector2int16Value) -> Vector2int16Value,
		__sub: (Vector2int16Value, Vector2int16Value) -> Vector2int16Value,
		__mul: (Vector2int16Value, Vector2int16Value | number) -> Vector2int16Value,
		__div: (Vector2int16Value, Vector2int16Value | number) -> Vector2int16Value,
		__unm: (Vector2int16Value) -> Vector2int16Value,
		__eq: (Vector2int16Value, Vector2int16Value) -> boolean,
		__tostring: (Vector2int16Value) -> string,
	}
))

export type Vector3int16Value = typeof(setmetatable(
	{} :: { X: number, Y: number, Z: number },
	{} :: {
		__add: (Vector3int16Value, Vector3int16Value) -> Vector3int16Value,
		__sub: (Vector3int16Value, Vector3int16Value) -> Vector3int16Value,
		__mul: (Vector3int16Value, Vector3int16Value | number) -> Vector3int16Value,
		__div: (Vector3int16Value, Vector3int16Value | number) -> Vector3int16Value,
		__unm: (Vector3int16Value) -> Vector3int16Value,
		__eq: (Vector3int16Value, Vector3int16Value) -> boolean,
		__tostring: (Vector3int16Value) -> string,
	}
))

type Components = { X: number, Y: number, Z: number? }
type Methods = { [string]: unknown }

local DEFAULT_EPSILON = 1e-5

local function sign(value: number): number
	return if value > 0 then 1 elseif value < 0 then -1 else 0
end

local function fuzzy(left: number, right: number, epsilon: number): boolean
	return math.abs(left - right) <= epsilon * math.max(1, math.abs(left), math.abs(right))
end

local function checkEpsilon(epsilon: number?): number
	local value = epsilon or DEFAULT_EPSILON
	if not (value >= 0 and value <= 0.1) then
		error("The eps value provided to FuzzyEq should be a small positive value <= 0.1", 3)
	end
	return value
end

local Vector2Kind = Names.behavior "Vector2"
local Vector3Kind = Names.behavior "Vector3"
local Vector2int16Kind = Names.behavior("Vector2int16", { quoted = true })
local Vector3int16Kind = Names.behavior("Vector3int16", { quoted = true })

local function make2(x: number, y: number): Vector2Value
	return Names.make(Vector2Kind, { X = f32(x), Y = f32(y) })
end

local function make3(x: number, y: number, z: number): Vector3Value
	return Names.make(Vector3Kind, { X = f32(x), Y = f32(y), Z = f32(z) })
end

local function expect2(value: unknown, position: number): Vector2Value
	if not Names.is(value, Vector2Kind) then
		Names.argument(position, "Vector2", value)
	end
	return value :: Vector2Value
end

local function expect3(value: unknown, position: number): Vector3Value
	if not Names.is(value, Vector3Kind) then
		Names.argument(position, "Vector3", value)
	end
	return value :: Vector3Value
end

local methods2: Methods = {}
local methods3: Methods = {}

local function magnitude2(v: Vector2Value): number
	return f32(math.sqrt(v.X * v.X + v.Y * v.Y))
end

local function magnitude3(v: Vector3Value): number
	return f32(math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z))
end

local function lerp(a: number, b: number, alpha: number): number
	return a + f32(f32(b - a) * alpha)
end

local function each2(v: Vector2Value, map: (number) -> number): Vector2Value
	return make2(map(v.X), map(v.Y))
end

local function each3(v: Vector3Value, map: (number) -> number): Vector3Value
	return make3(map(v.X), map(v.Y), map(v.Z))
end

local function fold2(v: Vector2Value, others: { unknown }, pick: (number, number) -> number): Vector2Value
	local x, y = v.X, v.Y
	for index, other in others do
		local vector = expect2(other, index + 1)
		x, y = pick(x, vector.X), pick(y, vector.Y)
	end
	return make2(x, y)
end

local function fold3(v: Vector3Value, others: { unknown }, pick: (number, number) -> number): Vector3Value
	local x, y, z = v.X, v.Y, v.Z
	for index, other in others do
		local vector = expect3(other, index + 1)
		x, y, z = pick(x, vector.X), pick(y, vector.Y), pick(z, vector.Z)
	end
	return make3(x, y, z)
end

function methods2.Lerp(self: Vector2Value, goal: unknown, alpha: number): Vector2Value
	local target = expect2(goal, 1)
	local t = f32(alpha)
	return make2(lerp(self.X, target.X, t), lerp(self.Y, target.Y, t))
end

function methods2.Dot(self: Vector2Value, other: unknown): number
	local vector = expect2(other, 1)
	return f32(self.X * vector.X + self.Y * vector.Y)
end

function methods2.Cross(self: Vector2Value, other: unknown): number
	local vector = expect2(other, 1)
	return f32(self.X * vector.Y - self.Y * vector.X)
end

function methods2.Abs(self: Vector2Value): Vector2Value
	return each2(self, math.abs)
end

function methods2.Ceil(self: Vector2Value): Vector2Value
	return each2(self, math.ceil)
end

function methods2.Floor(self: Vector2Value): Vector2Value
	return each2(self, math.floor)
end

function methods2.Sign(self: Vector2Value): Vector2Value
	return each2(self, sign)
end

function methods2.Max(self: Vector2Value, ...: unknown): Vector2Value
	return fold2(self, { ... }, math.max)
end

function methods2.Min(self: Vector2Value, ...: unknown): Vector2Value
	return fold2(self, { ... }, math.min)
end

function methods2.Angle(self: Vector2Value, other: unknown, isSigned: boolean?): number
	local vector = expect2(other, 1)
	local angle = math.atan2(self.X * vector.Y - self.Y * vector.X, self.X * vector.X + self.Y * vector.Y)
	return f32(if isSigned then angle else math.abs(angle))
end

function methods2.FuzzyEq(self: Vector2Value, other: unknown, epsilon: number?): boolean
	local vector = expect2(other, 1)
	local limit = checkEpsilon(epsilon)
	return fuzzy(self.X, vector.X, limit) and fuzzy(self.Y, vector.Y, limit)
end

function methods3.Lerp(self: Vector3Value, goal: unknown, alpha: number): Vector3Value
	local target = expect3(goal, 1)
	local t = f32(alpha)
	return make3(lerp(self.X, target.X, t), lerp(self.Y, target.Y, t), lerp(self.Z, target.Z, t))
end

function methods3.Dot(self: Vector3Value, other: unknown): number
	local vector = expect3(other, 1)
	return f32(self.X * vector.X + self.Y * vector.Y + self.Z * vector.Z)
end

function methods3.Cross(self: Vector3Value, other: unknown): Vector3Value
	local v = expect3(other, 1)
	return make3(self.Y * v.Z - self.Z * v.Y, self.Z * v.X - self.X * v.Z, self.X * v.Y - self.Y * v.X)
end

function methods3.Abs(self: Vector3Value): Vector3Value
	return each3(self, math.abs)
end

function methods3.Ceil(self: Vector3Value): Vector3Value
	return each3(self, math.ceil)
end

function methods3.Floor(self: Vector3Value): Vector3Value
	return each3(self, math.floor)
end

function methods3.Sign(self: Vector3Value): Vector3Value
	return each3(self, sign)
end

function methods3.Max(self: Vector3Value, ...: unknown): Vector3Value
	return fold3(self, { ... }, math.max)
end

function methods3.Min(self: Vector3Value, ...: unknown): Vector3Value
	return fold3(self, { ... }, math.min)
end

function methods3.Angle(self: Vector3Value, other: unknown, axis: unknown?): number
	local v = expect3(other, 1)
	local cx, cy, cz = self.Y * v.Z - self.Z * v.Y, self.Z * v.X - self.X * v.Z, self.X * v.Y - self.Y * v.X
	local angle = math.atan2(math.sqrt(cx * cx + cy * cy + cz * cz), self.X * v.X + self.Y * v.Y + self.Z * v.Z)
	if axis ~= nil then
		local reference = expect3(axis, 2)
		if cx * reference.X + cy * reference.Y + cz * reference.Z < 0 then
			angle = -angle
		end
	end
	return f32(angle)
end

function methods3.FuzzyEq(self: Vector3Value, other: unknown, epsilon: number?): boolean
	local v = expect3(other, 1)
	local limit = checkEpsilon(epsilon)
	return fuzzy(self.X, v.X, limit) and fuzzy(self.Y, v.Y, limit) and fuzzy(self.Z, v.Z, limit)
end

Vector2Kind.fields.__index = function(v: Vector2Value, key: unknown): unknown
	local method = methods2[key :: string]
	if method ~= nil then
		return method
	elseif key == "Magnitude" then
		return magnitude2(v)
	elseif key == "Unit" then
		local inverse = f32(1 / magnitude2(v))
		return make2(v.X * inverse, v.Y * inverse)
	elseif key == "x" then
		return v.X
	elseif key == "y" then
		return v.Y
	end
	return Names.invalid(key, "Vector2")
end

Vector3Kind.fields.__index = function(v: Vector3Value, key: unknown): unknown
	local method = methods3[key :: string]
	if method ~= nil then
		return method
	elseif key == "Magnitude" then
		return magnitude3(v)
	elseif key == "Unit" then
		local inverse = f32(1 / magnitude3(v))
		return make3(v.X * inverse, v.Y * inverse, v.Z * inverse)
	elseif key == "x" then
		return v.X
	elseif key == "y" then
		return v.Y
	elseif key == "z" then
		return v.Z
	end
	return Names.invalid(key, "Vector3")
end

type Combine = (number, number) -> number

local function combine2(name: string, combine: Combine, scalars: boolean, leftScalars: boolean)
	return function(left: unknown, right: unknown): Vector2Value
		local leftVector, rightVector = Names.is(left, Vector2Kind), Names.is(right, Vector2Kind)
		if leftVector and rightVector then
			local a, b = left :: Vector2Value, right :: Vector2Value
			return make2(combine(a.X, b.X), combine(a.Y, b.Y))
		elseif leftVector and scalars and type(right) == "number" then
			local a, s = left :: Vector2Value, f32(right)
			return make2(combine(a.X, s), combine(a.Y, s))
		elseif rightVector and leftScalars and type(left) == "number" then
			local s, b = f32(left), right :: Vector2Value
			return make2(combine(s, b.X), combine(s, b.Y))
		elseif leftVector and not scalars then
			return Names.argument(2, "Vector2", right)
		end
		return Names.arithmetic(name, left, right)
	end
end

local function combine3(name: string, combine: Combine, scalars: boolean, leftScalars: boolean)
	return function(left: unknown, right: unknown): Vector3Value
		local leftVector, rightVector = Names.is(left, Vector3Kind), Names.is(right, Vector3Kind)
		if leftVector and rightVector then
			local a, b = left :: Vector3Value, right :: Vector3Value
			return make3(combine(a.X, b.X), combine(a.Y, b.Y), combine(a.Z, b.Z))
		elseif leftVector and scalars and type(right) == "number" then
			local a, s = left :: Vector3Value, f32(right)
			return make3(combine(a.X, s), combine(a.Y, s), combine(a.Z, s))
		elseif rightVector and leftScalars and type(left) == "number" then
			local s, b = f32(left), right :: Vector3Value
			return make3(combine(s, b.X), combine(s, b.Y), combine(s, b.Z))
		end
		return Names.arithmetic(name, left, right)
	end
end

local function add(a: number, b: number): number
	return a + b
end
local function subtract(a: number, b: number): number
	return a - b
end
local function multiply(a: number, b: number): number
	return a * b
end
local function divide(a: number, b: number): number
	return a / b
end
local function floorDivide(a: number, b: number): number
	return math.floor(f32(a / b))
end

Vector2Kind.meta.__add = combine2("add", add, false, false)
Vector2Kind.meta.__sub = combine2("sub", subtract, false, false)
Vector2Kind.meta.__mul = combine2("mul", multiply, true, true)
Vector2Kind.meta.__div = combine2("div", divide, true, true)
Vector2Kind.meta.__idiv = combine2("idiv", floorDivide, true, false)
Vector2Kind.meta.__unm = function(v: Vector2Value): Vector2Value
	return make2(-v.X, -v.Y)
end
Vector2Kind.meta.__eq = function(a: Vector2Value, b: Vector2Value): boolean
	return a.X == b.X and a.Y == b.Y
end
Vector2Kind.meta.__tostring = function(v: Vector2Value): string
	return Float.general(v.X, 9, true) .. ", " .. Float.general(v.Y, 9, true)
end

Vector3Kind.meta.__add = combine3("add", add, false, false)
Vector3Kind.meta.__sub = combine3("sub", subtract, false, false)
Vector3Kind.meta.__mul = combine3("mul", multiply, true, true)
Vector3Kind.meta.__div = combine3("div", divide, true, true)
Vector3Kind.meta.__idiv = combine3("idiv", floorDivide, true, false)
Vector3Kind.meta.__unm = function(v: Vector3Value): Vector3Value
	return make3(-v.X, -v.Y, -v.Z)
end
Vector3Kind.meta.__eq = function(a: Vector3Value, b: Vector3Value): boolean
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
Vector3Kind.meta.__tostring = function(v: Vector3Value): string
	return Float.shortest(v.X) .. ", " .. Float.shortest(v.Y) .. ", " .. Float.shortest(v.Z)
end

local function makeInt2(x: number, y: number): Vector2int16Value
	return Names.make(Vector2int16Kind, { X = Float.int16(x), Y = Float.int16(y) })
end

local function makeInt3(x: number, y: number, z: number): Vector3int16Value
	return Names.make(Vector3int16Kind, { X = Float.int16(x), Y = Float.int16(y), Z = Float.int16(z) })
end

local function components(value: unknown): Components
	local fields = Names.fields(value)
	return { X = rawget(fields, "X") :: number, Y = rawget(fields, "Y") :: number, Z = rawget(fields, "Z") :: number? }
end

local function integer(
	owner: string,
	kind: Names.Behavior,
	build: (Components) -> unknown,
	operation: string,
	combine: Combine,
	scalars: boolean
)
	return function(left: unknown, right: unknown): unknown
		if not Names.is(left, kind) then
			return Names.arithmetic(operation, left, right)
		end
		local a = components(left)
		if Names.is(right, kind) then
			local b = components(right)
			return build {
				X = combine(a.X, b.X),
				Y = combine(a.Y, b.Y),
				Z = if a.Z ~= nil then combine(a.Z, b.Z :: number) else nil,
			}
		elseif scalars and type(right) == "number" then
			return build {
				X = combine(a.X, right),
				Y = combine(a.Y, right),
				Z = if a.Z ~= nil then combine(a.Z, right) else nil,
			}
		end
		return Names.argument(2, owner, right)
	end
end

local function build2(components: Components): unknown
	return makeInt2(components.X, components.Y)
end

local function build3(components: Components): unknown
	return makeInt3(components.X, components.Y, components.Z :: number)
end

for _, entry in
	{
		{ owner = "Vector2int16", kind = Vector2int16Kind, build = build2 },
		{ owner = "Vector3int16", kind = Vector3int16Kind, build = build3 },
	}
do
	local kind = entry.kind
	local metatable = kind.meta
	metatable.__add = integer(entry.owner, kind, entry.build, "add", add, false)
	metatable.__sub = integer(entry.owner, kind, entry.build, "sub", subtract, false)
	metatable.__mul = integer(entry.owner, kind, entry.build, "mul", multiply, true)
	metatable.__div = integer(entry.owner, kind, entry.build, "div", divide, true)
	metatable.__unm = function(value: unknown): unknown
		local v = components(value)
		return entry.build { X = -v.X, Y = -v.Y, Z = if v.Z ~= nil then -v.Z else nil }
	end
	metatable.__eq = function(left: unknown, right: unknown): boolean
		local a, b = components(left), components(right)
		return a.X == b.X and a.Y == b.Y and a.Z == b.Z
	end
	metatable.__tostring = function(value: unknown): string
		local v = components(value)
		return if v.Z ~= nil then ("%d, %d, %d"):format(v.X, v.Y, v.Z) else ("%d, %d"):format(v.X, v.Y)
	end
end

local Vector2 = {
	new = function(x: unknown?, y: unknown?): Vector2Value
		return make2(Float.coerce(x, 1), Float.coerce(y, 2))
	end,
	zero = make2(0, 0),
	one = make2(1, 1),
	xAxis = make2(1, 0),
	yAxis = make2(0, 1),
}

local NORMALS: { [string]: { number } } = {
	Right = { 1, 0, 0 },
	Top = { 0, 1, 0 },
	Back = { 0, 0, 1 },
	Left = { -1, 0, 0 },
	Bottom = { 0, -1, 0 },
	Front = { 0, 0, -1 },
}
local AXES: { [string]: { number } } = { X = { 1, 0, 0 }, Y = { 0, 1, 0 }, Z = { 0, 0, 1 } }

local function fromItem(table_: { [string]: { number } }, item: unknown, family: string): Vector3Value
	local components = if Enum.isItem(item) and Enum.enumType(item) == family
		then table_[(item :: Enum.EnumItem).Name]
		else nil
	if components == nil then
		Names.argument(1, "Enum." .. family, item)
	end
	local found = components :: { number }
	return make3(found[1], found[2], found[3])
end

local Vector3 = {
	new = function(x: unknown?, y: unknown?, z: unknown?): Vector3Value
		return make3(Float.coerce(x, 1), Float.coerce(y, 2), Float.coerce(z, 3))
	end,
	FromNormalId = function(normal: unknown): Vector3Value
		return fromItem(NORMALS, normal, "NormalId")
	end,
	FromAxis = function(axis: unknown): Vector3Value
		return fromItem(AXES, axis, "Axis")
	end,
	zero = make3(0, 0, 0),
	one = make3(1, 1, 1),
	xAxis = make3(1, 0, 0),
	yAxis = make3(0, 1, 0),
	zAxis = make3(0, 0, 1),
}

local Vector2int16 = {
	new = function(x: unknown?, y: unknown?): Vector2int16Value
		return makeInt2(Float.coerce(x, 1), Float.coerce(y, 2))
	end,
}

local Vector3int16 = {
	new = function(x: unknown?, y: unknown?, z: unknown?): Vector3int16Value
		return makeInt3(Float.coerce(x, 1), Float.coerce(y, 2), Float.coerce(z, 3))
	end,
}

return {
	Vector2 = Vector2,
	Vector3 = Vector3,
	Vector2int16 = Vector2int16,
	Vector3int16 = Vector3int16,
	isVector2 = function(value: unknown): boolean
		return Names.is(value, Vector2Kind)
	end,
	isVector3 = function(value: unknown): boolean
		return Names.is(value, Vector3Kind)
	end,
}
