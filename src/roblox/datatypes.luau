--!strict

type Vec3 = { X: number, Y: number, Z: number }
type Vec2 = { X: number, Y: number }
type CF = { X: number, Y: number, Z: number, _cframe: boolean, r: { number } }
type C3 = { R: number, G: number, B: number }

export type Vector3Value = typeof(setmetatable(
	{} :: {
		X: number,
		Y: number,
		Z: number,
		Magnitude: number,
		Unit: Vector3Value,
		Dot: (Vector3Value, Vec3 | Vector3Value) -> number,
		Cross: (Vector3Value, Vec3 | Vector3Value) -> Vector3Value,
	},
	{} :: {
		__add: (Vector3Value, Vec3 | Vector3Value) -> Vector3Value,
		__sub: (Vector3Value, Vec3 | Vector3Value) -> Vector3Value,
		__mul: (Vector3Value, number | Vec3 | Vector3Value) -> Vector3Value,
		__div: (Vector3Value, number | Vec3 | Vector3Value) -> Vector3Value,
		__unm: (Vector3Value) -> Vector3Value,
		__eq: (Vector3Value, Vector3Value) -> boolean,
		__tostring: (Vec3) -> string,
		__index: (Vec3, string) -> unknown,
	}
))

export type Vector2Value = typeof(setmetatable(
	{} :: {
		X: number,
		Y: number,
		Magnitude: number,
		Unit: Vector2Value,
		Dot: (Vector2Value, Vec2 | Vector2Value) -> number,
	},
	{} :: {
		__add: (Vector2Value, Vec2 | Vector2Value) -> Vector2Value,
		__sub: (Vector2Value, Vec2 | Vector2Value) -> Vector2Value,
		__mul: (Vector2Value, number | Vec2 | Vector2Value) -> Vector2Value,
		__div: (Vector2Value, number | Vec2 | Vector2Value) -> Vector2Value,
		__unm: (Vector2Value) -> Vector2Value,
		__eq: (Vector2Value, Vector2Value) -> boolean,
		__tostring: (Vec2) -> string,
		__index: (Vec2, string) -> unknown,
	}
))

export type CFrameValue = typeof(setmetatable(
	{} :: {
		X: number,
		Y: number,
		Z: number,
		_cframe: boolean,
		r: { number },
		Position: Vector3Value,
		RightVector: Vector3Value,
		XVector: Vector3Value,
		UpVector: Vector3Value,
		YVector: Vector3Value,
		ZVector: Vector3Value,
		LookVector: Vector3Value,
		GetComponents: (
			CFrameValue
		) -> (number, number, number, number, number, number, number, number, number, number, number, number),
		Inverse: (CFrameValue) -> CFrameValue,
	},
	{} :: {
		__mul: ((CFrameValue, CFrameValue) -> CFrameValue) & ((CFrameValue, Vec3 | Vector3Value) -> Vector3Value),
		__sub: (CFrameValue, Vec3 | Vector3Value) -> CFrameValue,
		__eq: (CFrameValue, CFrameValue) -> boolean,
		__index: (CF, string) -> unknown,
	}
))

export type Color3Value = typeof(setmetatable(
	{} :: C3,
	{} :: {
		__index: { Lerp: (Color3Value, C3 | Color3Value, number) -> Color3Value },
		__eq: (Color3Value, Color3Value) -> boolean,
		__tostring: (C3) -> string,
	}
))

export type UDimValue = typeof(setmetatable(
	{} :: { Scale: number, Offset: number },
	{} :: {
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
	},
	{} :: {
		__eq: (UDim2Value, UDim2Value) -> boolean,
		__tostring: (UDim2Value) -> string,
	}
))

export type Vector3Constructor = { new: (number?, number?, number?) -> Vector3Value }
export type CFrameConstructor = {
	new: ((number?, number?, number?, ...number) -> CFrameValue)
		& ((Vec3) -> CFrameValue)
		& ((Vector3Value, Vector3Value?) -> CFrameValue),
	Angles: (number, number, number) -> CFrameValue,
	fromEulerAnglesXYZ: (number, number, number) -> CFrameValue,
	lookAt: (Vector3Value, Vector3Value, Vector3Value?) -> CFrameValue,
}

local Vector3: Vector3Constructor
local CFrame: CFrameConstructor

local v3Mt = {}
v3Mt.__add = function(a: Vector3Value, b: Vec3): Vector3Value
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
v3Mt.__sub = function(a: Vector3Value, b: Vec3): Vector3Value
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
v3Mt.__mul = function(a: Vector3Value, b: number | Vec3 | Vector3Value): Vector3Value
	if type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
v3Mt.__div = function(a: Vector3Value, b: number | Vec3 | Vector3Value): Vector3Value
	if type(b) == "number" then
		return Vector3.new(a.X / b, a.Y / b, a.Z / b)
	end
	return Vector3.new(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
v3Mt.__unm = function(a: Vector3Value): Vector3Value
	return Vector3.new(-a.X, -a.Y, -a.Z)
end
v3Mt.__eq = function(a: Vector3Value, b: Vector3Value): boolean
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
v3Mt.__tostring = function(a: Vec3): string
	return ("Vector3(%g, %g, %g)"):format(a.X, a.Y, a.Z)
end
v3Mt.__index = function(v: Vec3, key: string): unknown
	if key == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif key == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return Vector3.new(v.X / m, v.Y / m, v.Z / m)
	end
	return rawget(v3Mt, key)
end

function v3Mt.Dot(a: Vector3Value, b: Vec3): number
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

function v3Mt.Cross(a: Vector3Value, b: Vec3): Vector3Value
	return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end

Vector3 = {
	new = function(x: number?, y: number?, z: number?): Vector3Value
		local v: Vec3 = { X = x or 0, Y = y or 0, Z = z or 0 }
		setmetatable(v, v3Mt)
		return (v :: unknown) :: Vector3Value
	end,
}

local cfMt = {}

local function makeCFrame(x: number, y: number, z: number, r: { number }): CFrameValue
	local cf: CF = { _cframe = true, X = x, Y = y, Z = z, r = r }
	setmetatable(cf, cfMt)
	return (cf :: unknown) :: CFrameValue
end

local IDENTITY_R = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

cfMt.__index = function(cf: CF, key: string): unknown
	local r = rawget(cf, "r") :: { number }
	if key == "Position" then
		return Vector3.new(cf.X, cf.Y, cf.Z)
	elseif key == "RightVector" or key == "XVector" then
		return Vector3.new(r[1], r[4], r[7])
	elseif key == "UpVector" or key == "YVector" then
		return Vector3.new(r[2], r[5], r[8])
	elseif key == "ZVector" then
		return Vector3.new(r[3], r[6], r[9])
	elseif key == "LookVector" then
		return Vector3.new(-r[3], -r[6], -r[9])
	end
	return rawget(cfMt, key)
end

cfMt.__mul = function(a: CF, b: CF | Vec3): CFrameValue | Vector3Value
	local ar = rawget((a :: unknown) :: CF, "r") :: { number }
	if b ~= nil and rawget(b, "_cframe") ~= nil then
		local br = rawget((b :: unknown) :: CF, "r") :: { number }
		local r = table.create(9, 0)
		for row = 0, 2 do
			for col = 1, 3 do
				r[row * 3 + col] = ar[row * 3 + 1] * br[col]
					+ ar[row * 3 + 2] * br[col + 3]
					+ ar[row * 3 + 3] * br[col + 6]
			end
		end
		return makeCFrame(
			a.X + ar[1] * b.X + ar[2] * b.Y + ar[3] * b.Z,
			a.Y + ar[4] * b.X + ar[5] * b.Y + ar[6] * b.Z,
			a.Z + ar[7] * b.X + ar[8] * b.Y + ar[9] * b.Z,
			r
		)
	end
	return Vector3.new(
		a.X + ar[1] * b.X + ar[2] * b.Y + ar[3] * b.Z,
		a.Y + ar[4] * b.X + ar[5] * b.Y + ar[6] * b.Z,
		a.Z + ar[7] * b.X + ar[8] * b.Y + ar[9] * b.Z
	)
end

cfMt.__eq = function(a: CFrameValue, b: CFrameValue): boolean
	if a.X ~= b.X or a.Y ~= b.Y or a.Z ~= b.Z then
		return false
	end
	local ar = rawget((a :: unknown) :: CF, "r") :: { number }
	local br = rawget((b :: unknown) :: CF, "r") :: { number }
	for index = 1, 9 do
		if ar[index] ~= br[index] then
			return false
		end
	end
	return true
end

cfMt.__sub = function(a: CF, b: Vec3): CFrameValue
	return makeCFrame(a.X - b.X, a.Y - b.Y, a.Z - b.Z, rawget((a :: unknown) :: CF, "r") :: { number })
end

function cfMt.GetComponents(cf: CF): (
	number,
	number,
	number,
	number,
	number,
	number,
	number,
	number,
	number,
	number,
	number,
	number
)
	local r = rawget(cf, "r") :: { number }
	return cf.X, cf.Y, cf.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
end

function cfMt.Inverse(cf: CF): CFrameValue
	local r = rawget(cf, "r") :: { number }
	return makeCFrame(
		-(r[1] * cf.X + r[4] * cf.Y + r[7] * cf.Z),
		-(r[2] * cf.X + r[5] * cf.Y + r[8] * cf.Z),
		-(r[3] * cf.X + r[6] * cf.Y + r[9] * cf.Z),
		{ r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
	)
end

local function fromEulerAnglesXYZ(rx: number, ry: number, rz: number): CFrameValue
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	return makeCFrame(0, 0, 0, {
		cy * cz,
		-cy * sz,
		sy,
		sx * sy * cz + cx * sz,
		-sx * sy * sz + cx * cz,
		-sx * cy,
		-cx * sy * cz + sx * sz,
		cx * sy * sz + sx * cz,
		cx * cy,
	})
end

local cframeConstructor = {
	new = function(
		x: number | Vec3 | Vector3Value?,
		y: number | Vec3 | Vector3Value?,
		z: number?,
		...: number
	): CFrameValue
		if type(x) == "table" then
			if type(y) == "table" then
				return CFrame.lookAt((x :: unknown) :: Vector3Value, (y :: unknown) :: Vector3Value)
			end
			return makeCFrame(x.X, x.Y, x.Z, IDENTITY_R)
		end
		if select("#", ...) == 9 then
			return makeCFrame((x :: number?) or 0, (y :: number?) or 0, z or 0, { ... })
		end
		return makeCFrame((x :: number?) or 0, (y :: number?) or 0, z or 0, IDENTITY_R)
	end,
	Angles = fromEulerAnglesXYZ,
	fromEulerAnglesXYZ = fromEulerAnglesXYZ,
	lookAt = function(from: Vector3Value, to: Vector3Value, up: Vector3Value?): CFrameValue
		local worldUp = up or Vector3.new(0, 1, 0)
		local look = (to - from).Unit
		local right = look:Cross(worldUp)
		if right.Magnitude < 1e-6 then
			right = look:Cross(Vector3.new(1, 0, 0))
			if right.Magnitude < 1e-6 then
				right = look:Cross(Vector3.new(0, 0, 1))
			end
		end
		right = right.Unit
		local newUp = right:Cross(look)
		return makeCFrame(from.X, from.Y, from.Z, {
			right.X,
			newUp.X,
			-look.X,
			right.Y,
			newUp.Y,
			-look.Y,
			right.Z,
			newUp.Z,
			-look.Z,
		})
	end,
}

CFrame = cframeConstructor :: CFrameConstructor

local color3Mt = {}
color3Mt.__index = color3Mt
local makeColor3: (number, number, number) -> Color3Value
function color3Mt.Lerp(self: C3, other: C3 | Color3Value, alpha: number): Color3Value
	return makeColor3(
		self.R + (other.R - self.R) * alpha,
		self.G + (other.G - self.G) * alpha,
		self.B + (other.B - self.B) * alpha
	)
end
color3Mt.__eq = function(a: Color3Value, b: Color3Value): boolean
	return a.R == b.R and a.G == b.G and a.B == b.B
end
color3Mt.__tostring = function(a: C3): string
	return ("%g, %g, %g"):format(a.R, a.G, a.B)
end

makeColor3 = function(r: number, g: number, b: number): Color3Value
	local color: C3 = { R = r, G = g, B = b }
	setmetatable(color, color3Mt)
	return (color :: unknown) :: Color3Value
end

local Color3 = {
	fromRGB = function(r: number, g: number, b: number): Color3Value
		return makeColor3(r / 255, g / 255, b / 255)
	end,
	new = function(r: number?, g: number?, b: number?): Color3Value
		return makeColor3(r or 0, g or 0, b or 0)
	end,
}

local v2Mt = {}
local makeVector2: (number, number) -> Vector2Value
v2Mt.__index = function(v: Vec2, key: string): unknown
	if key == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	elseif key == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y)
		return makeVector2(v.X / m, v.Y / m)
	end
	return rawget(v2Mt, key)
end
v2Mt.__add = function(a: Vector2Value, b: Vec2): Vector2Value
	return makeVector2(a.X + b.X, a.Y + b.Y)
end
v2Mt.__sub = function(a: Vector2Value, b: Vec2): Vector2Value
	return makeVector2(a.X - b.X, a.Y - b.Y)
end
v2Mt.__mul = function(a: Vector2Value, b: number | Vec2 | Vector2Value): Vector2Value
	if type(b) == "number" then
		return makeVector2(a.X * b, a.Y * b)
	end
	return makeVector2(a.X * b.X, a.Y * b.Y)
end
v2Mt.__div = function(a: Vector2Value, b: number | Vec2 | Vector2Value): Vector2Value
	if type(b) == "number" then
		return makeVector2(a.X / b, a.Y / b)
	end
	return makeVector2(a.X / b.X, a.Y / b.Y)
end
v2Mt.__unm = function(a: Vector2Value): Vector2Value
	return makeVector2(-a.X, -a.Y)
end
v2Mt.__eq = function(a: Vector2Value, b: Vector2Value): boolean
	return a.X == b.X and a.Y == b.Y
end
v2Mt.__tostring = function(a: Vec2): string
	return ("%g, %g"):format(a.X, a.Y)
end
function v2Mt.Dot(a: Vector2Value, b: Vec2): number
	return a.X * b.X + a.Y * b.Y
end
makeVector2 = function(x: number, y: number): Vector2Value
	return (setmetatable({ X = x, Y = y }, v2Mt) :: unknown) :: Vector2Value
end
local Vector2 = {
	new = function(x: number?, y: number?): Vector2Value
		return makeVector2(x or 0, y or 0)
	end,
}

local udimMt = {}
udimMt.__eq = function(a: UDimValue, b: UDimValue): boolean
	return a.Scale == b.Scale and a.Offset == b.Offset
end
udimMt.__tostring = function(a: UDimValue): string
	return ("%g, %g"):format(a.Scale, a.Offset)
end
local UDim = {
	new = function(scale: number?, offset: number?): UDimValue
		return setmetatable({ Scale = scale or 0, Offset = offset or 0 }, udimMt)
	end,
}

local udim2Mt = {}
udim2Mt.__eq = function(a: UDim2Value, b: UDim2Value): boolean
	return a.X == b.X and a.Y == b.Y
end
udim2Mt.__tostring = function(a: UDim2Value): string
	return ("{%g, %g}, {%g, %g}"):format(a.X.Scale, a.X.Offset, a.Y.Scale, a.Y.Offset)
end
local function makeUDim2(xs: number | UDimValue?, xo: number | UDimValue?, ys: number?, yo: number?): UDim2Value
	local x, y
	if type(xs) == "table" then
		x, y = xs, xo :: UDimValue
	else
		x, y = UDim.new(xs :: number?, xo :: number?), UDim.new(ys, yo)
	end
	return setmetatable({ X = x, Y = y, Width = x, Height = y }, udim2Mt) :: UDim2Value
end
local UDim2 = {
	new = makeUDim2 :: ((number?, number?, number?, number?) -> UDim2Value) & ((UDimValue, UDimValue) -> UDim2Value),
	fromScale = function(x: number?, y: number?): UDim2Value
		return makeUDim2(x or 0, 0, y or 0, 0)
	end,
	fromOffset = function(x: number?, y: number?): UDim2Value
		return makeUDim2(0, x or 0, 0, y or 0)
	end,
}

export type EnumMember = { _enum: string, _family: string }
export type EnumCategory = { [string]: EnumMember }
export type EnumValue = { [string]: EnumCategory }

local families = setmetatable({} :: { [unknown]: string }, { __mode = "k" })
local enumItemMt = {
	__tostring = function(item: EnumMember): string
		return ("Enum.%s.%s"):format(item._family, item._enum)
	end,
}
local memberMt = {}
memberMt.__index = function(category: EnumCategory, member: string): EnumMember
	local value = (setmetatable({ _enum = member, _family = families[category] }, enumItemMt) :: unknown) :: EnumMember
	rawset(category, member, value)
	return value
end
local enumMt = {}
enumMt.__index = function(enum: EnumValue, category: string): EnumCategory
	local members = (setmetatable({}, memberMt) :: unknown) :: EnumCategory
	families[members] = category
	rawset(enum, category, members)
	return members
end
local Enum = (setmetatable({}, enumMt) :: unknown) :: EnumValue

local shellMt: { [string]: { [string]: unknown } } = {
	NumberSequenceKeypoint = {},
	ColorSequenceKeypoint = {},
	NumberRange = {},
	NumberSequence = {},
	ColorSequence = {},
	Rect = {},
	TweenInfo = {},
	FloatCurveKey = {},
	Path2DControlPoint = {},
}

local function tag<T>(value: T, metatable: {}): T
	setmetatable((value :: unknown) :: {}, metatable)
	return value
end

local NumberSequenceKeypoint = {
	new = function(t: number, v: number, _envelope: number?): { Time: number, Value: number }
		return tag({ Time = t, Value = v }, shellMt.NumberSequenceKeypoint)
	end,
}

local ColorSequenceKeypoint = {
	new = function<T>(t: number, color: T): { Time: number, Value: T }
		return tag({ Time = t, Value = color }, shellMt.ColorSequenceKeypoint)
	end,
}

local NumberRange = {
	new = function(min: number, max: number?): { Min: number, Max: number }
		return tag({ Min = min, Max = max or min }, shellMt.NumberRange)
	end,
}

local NumberSequence = {
	new = function<T>(value: T): { _ns: T }
		return tag({ _ns = value }, shellMt.NumberSequence)
	end,
}

local ColorSequence = {
	new = function<T>(value: T): { _cs: T }
		return tag({ _cs = value }, shellMt.ColorSequence)
	end,
}

local Rect = {
	new = function(_x0: number?, _y0: number?, _x1: number?, _y1: number?): { _rect: boolean }
		return tag({ _rect = true }, shellMt.Rect)
	end,
}

export type TweenInfoValue = {
	Time: number,
	EasingStyle: EnumMember,
	EasingDirection: EnumMember,
	RepeatCount: number,
	Reverses: boolean,
	DelayTime: number,
}

shellMt.TweenInfo.__eq = function(a: TweenInfoValue, b: TweenInfoValue): boolean
	return a.Time == b.Time
		and a.EasingStyle == b.EasingStyle
		and a.EasingDirection == b.EasingDirection
		and a.RepeatCount == b.RepeatCount
		and a.Reverses == b.Reverses
		and a.DelayTime == b.DelayTime
end

local TweenInfo = {
	new = function(
		time: number?,
		style: EnumMember?,
		direction: EnumMember?,
		count: number?,
		reverses: boolean?,
		delayTime: number?
	): TweenInfoValue
		return tag({
			Time = time or 1,
			EasingStyle = style or Enum.EasingStyle.Quad,
			EasingDirection = direction or Enum.EasingDirection.Out,
			RepeatCount = count or 0,
			Reverses = reverses or false,
			DelayTime = delayTime or 0,
		}, shellMt.TweenInfo)
	end,
}

export type FloatCurveKeyValue = {
	Time: number,
	Value: number,
	Interpolation: EnumMember,
	LeftTangent: number?,
	RightTangent: number?,
}

shellMt.FloatCurveKey.__eq = function(a: FloatCurveKeyValue, b: FloatCurveKeyValue): boolean
	return a.Time == b.Time
		and a.Value == b.Value
		and a.Interpolation == b.Interpolation
		and a.LeftTangent == b.LeftTangent
		and a.RightTangent == b.RightTangent
end

local FloatCurveKey = {
	new = function(time: number, value: number, interpolation: EnumMember): FloatCurveKeyValue
		return tag({
			Time = time,
			Value = value,
			Interpolation = interpolation,
		}, shellMt.FloatCurveKey)
	end,
}

export type Path2DControlPointValue = {
	Position: UDim2Value,
	LeftTangent: UDim2Value,
	RightTangent: UDim2Value,
}

shellMt.Path2DControlPoint.__eq = function(a: Path2DControlPointValue, b: Path2DControlPointValue): boolean
	return a.Position == b.Position and a.LeftTangent == b.LeftTangent and a.RightTangent == b.RightTangent
end

local Path2DControlPoint = {
	new = function(position: UDim2Value, leftTangent: UDim2Value?, rightTangent: UDim2Value?): Path2DControlPointValue
		return tag({
			Position = position,
			LeftTangent = leftTangent or UDim2.new(0, 0, 0, 0),
			RightTangent = rightTangent or UDim2.new(0, 0, 0, 0),
		}, shellMt.Path2DControlPoint)
	end,
}

export type Vector2Constructor = typeof(Vector2)
export type Color3Constructor = typeof(Color3)
export type UDimConstructor = typeof(UDim)
export type UDim2Constructor = typeof(UDim2)

local names: { [unknown]: string } = {
	[v3Mt] = "Vector3",
	[cfMt] = "CFrame",
	[color3Mt] = "Color3",
	[v2Mt] = "Vector2",
	[udimMt] = "UDim",
	[udim2Mt] = "UDim2",
	[enumItemMt] = "EnumItem",
}
for name, metatable in shellMt do
	names[metatable] = name
end

local ATTRIBUTE_TYPES: { [string]: boolean } = {
	Vector2 = true,
	Vector3 = true,
	Color3 = true,
	UDim = true,
	UDim2 = true,
	CFrame = true,
	NumberRange = true,
	NumberSequence = true,
	ColorSequence = true,
	Rect = true,
	TweenInfo = true,
	EnumItem = true,
	BrickColor = true,
	Font = true,
	Instance = true,
}

local function enumType(value: unknown): string
	return (value :: EnumMember)._family
end

local function typeName(value: unknown): string?
	if type(value) ~= "table" then
		return nil
	end
	return names[((getmetatable :: unknown) :: (unknown) -> unknown)(value)]
end

local function isAttributeType(name: string): boolean
	return ATTRIBUTE_TYPES[name] == true
end

local function readCFrame(value: CFrameValue): (number, number, number, { number })
	local r = rawget((value :: unknown) :: CF, "r") :: { number }
	return value.X, value.Y, value.Z, table.clone(r)
end

return {
	Color3 = Color3,
	Vector2 = Vector2,
	Vector3 = Vector3,
	CFrame = CFrame,
	Enum = Enum,
	UDim2 = UDim2,
	UDim = UDim,
	NumberSequenceKeypoint = NumberSequenceKeypoint,
	ColorSequenceKeypoint = ColorSequenceKeypoint,
	NumberRange = NumberRange,
	NumberSequence = NumberSequence,
	ColorSequence = ColorSequence,
	Rect = Rect,
	TweenInfo = TweenInfo,
	FloatCurveKey = FloatCurveKey,
	Path2DControlPoint = Path2DControlPoint,
	typeName = typeName,
	isAttributeType = isAttributeType,
	enumType = enumType,
	readCFrame = readCFrame,
}
