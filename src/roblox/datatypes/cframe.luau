--!strict

local Float = require "./float"
local Names = require "./names"
local Vector = require "./vector"

local f32 = Float.f32
local Vector3 = Vector.Vector3

type Vector3Value = Vector.Vector3Value
type Rotation = { number }

local CFrameValueFields: {
	X: number,
	Y: number,
	Z: number,
	Position: Vector3Value,
	Rotation: CFrameValue,
	RightVector: Vector3Value,
	UpVector: Vector3Value,
	LookVector: Vector3Value,
	XVector: Vector3Value,
	YVector: Vector3Value,
	ZVector: Vector3Value,
	GetComponents: (
		self: CFrameValue
	) -> (number, number, number, number, number, number, number, number, number, number, number, number),
	Inverse: (self: CFrameValue) -> CFrameValue,
	Lerp: (self: CFrameValue, goal: CFrameValue, alpha: number) -> CFrameValue,
	Orthonormalize: (self: CFrameValue) -> CFrameValue,
	ToWorldSpace: (self: CFrameValue, ...CFrameValue) -> ...CFrameValue,
	ToObjectSpace: (self: CFrameValue, ...CFrameValue) -> ...CFrameValue,
	PointToWorldSpace: (self: CFrameValue, ...Vector3Value) -> ...Vector3Value,
	PointToObjectSpace: (self: CFrameValue, ...Vector3Value) -> ...Vector3Value,
	VectorToWorldSpace: (self: CFrameValue, ...Vector3Value) -> ...Vector3Value,
	VectorToObjectSpace: (self: CFrameValue, ...Vector3Value) -> ...Vector3Value,
	ToEulerAnglesXYZ: (self: CFrameValue) -> (number, number, number),
	ToEulerAnglesYXZ: (self: CFrameValue) -> (number, number, number),
	ToOrientation: (self: CFrameValue) -> (number, number, number),
	ToAxisAngle: (self: CFrameValue) -> (Vector3Value, number),
	FuzzyEq: (self: CFrameValue, other: CFrameValue, epsilon: number?) -> boolean,
}
local CFrameValueMeta: {
	__mul: ((CFrameValue, CFrameValue) -> CFrameValue) & ((CFrameValue, Vector3Value) -> Vector3Value),
	__add: (CFrameValue, Vector3Value) -> CFrameValue,
	__sub: (CFrameValue, Vector3Value) -> CFrameValue,
	__eq: (CFrameValue, CFrameValue) -> boolean,
	__tostring: (CFrameValue) -> string,
}

export type CFrameValue = typeof(setmetatable(CFrameValueFields, CFrameValueMeta))

type Methods = { [unknown]: unknown }

local ROTATION = {}
local UNIT_TOLERANCE = 1e-5
local IDENTITY = table.freeze { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

local CFrameKind = Names.behavior "CFrame"

local frames: { [unknown]: CFrameValue? } = {}
local rotations: { [unknown]: Rotation } = {}
Names.weak(frames)
Names.weak(rotations)

local function make(x: number, y: number, z: number, rotation: Rotation): CFrameValue
	local r = table.create(9, 0)
	for index = 1, 9 do
		r[index] = f32(rotation[index])
	end
	local fields: Names.Fields = { X = f32(x), Y = f32(y), Z = f32(z), [ROTATION] = table.freeze(r) }
	local made: CFrameValue = Names.make(CFrameKind, fields)
	frames[made], frames[fields] = made, made
	rotations[made], rotations[fields] = r, r
	return made
end

local function rotationOf(frame: CFrameValue): Rotation
	return rotations[frame]
end

local function expectFrame(value: unknown, position: number): CFrameValue
	local found = frames[value]
	if not found then
		return Names.argument(position, "CFrame", value)
	end
	return found
end

local function expectVector(value: unknown, position: number): Vector3Value
	return Vector.expect3(value, position)
end

local function dot(a1: number, b1: number, a2: number, b2: number, a3: number, b3: number): number
	return f32(f32(f32(a1 * b1) + f32(a2 * b2)) + f32(a3 * b3))
end

local function multiply(ar: Rotation, br: Rotation): Rotation
	local r = table.create(9, 0)
	for row = 0, 2 do
		for column = 1, 3 do
			r[row * 3 + column] =
				dot(ar[row * 3 + 1], br[column], ar[row * 3 + 2], br[column + 3], ar[row * 3 + 3], br[column + 6])
		end
	end
	return r
end

local function rotate(r: Rotation, x: number, y: number, z: number): (number, number, number)
	return dot(r[1], x, r[2], y, r[3], z), dot(r[4], x, r[5], y, r[6], z), dot(r[7], x, r[8], y, r[9], z)
end

local function unrotate(r: Rotation, x: number, y: number, z: number): (number, number, number)
	return dot(r[1], x, r[4], y, r[7], z), dot(r[2], x, r[5], y, r[8], z), dot(r[3], x, r[6], y, r[9], z)
end

local function compose(a: CFrameValue, b: CFrameValue): CFrameValue
	local ar = rotationOf(a)
	local x, y, z = rotate(ar, b.X, b.Y, b.Z)
	return make(a.X + x, a.Y + y, a.Z + z, multiply(ar, rotationOf(b)))
end

local function inverse(frame: CFrameValue): CFrameValue
	local r = rotationOf(frame)
	local x, y, z = unrotate(r, frame.X, frame.Y, frame.Z)
	return make(-x, -y, -z, { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] })
end

local function quaternion(r: Rotation): (number, number, number, number)
	local trace = r[1] + r[5] + r[9]
	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		return (r[8] - r[6]) / s, (r[3] - r[7]) / s, (r[4] - r[2]) / s, s / 4
	elseif r[1] > r[5] and r[1] > r[9] then
		local s = math.sqrt(1 + r[1] - r[5] - r[9]) * 2
		return s / 4, (r[2] + r[4]) / s, (r[3] + r[7]) / s, (r[8] - r[6]) / s
	elseif r[5] > r[9] then
		local s = math.sqrt(1 + r[5] - r[1] - r[9]) * 2
		return (r[2] + r[4]) / s, s / 4, (r[6] + r[8]) / s, (r[3] - r[7]) / s
	end
	local s = math.sqrt(1 + r[9] - r[1] - r[5]) * 2
	return (r[3] + r[7]) / s, (r[6] + r[8]) / s, s / 4, (r[4] - r[2]) / s
end

local function fromQuaternion(qx: number, qy: number, qz: number, qw: number): Rotation
	local x, y, z, w = f32(qx), f32(qy), f32(qz), f32(qw)
	local norm = f32(f32(f32(f32(x * x) + f32(y * y)) + f32(z * z)) + f32(w * w))
	local scale = if math.abs(norm - 1) <= UNIT_TOLERANCE then 2 elseif norm > 0 then f32(2 / norm) else 0
	local xs, ys, zs = f32(x * scale), f32(y * scale), f32(z * scale)
	local wx, wy, wz = f32(w * xs), f32(w * ys), f32(w * zs)
	local xx, xy, xz = f32(x * xs), f32(x * ys), f32(x * zs)
	local yy, yz, zz = f32(y * ys), f32(y * zs), f32(z * zs)
	return {
		1 - f32(yy + zz),
		xy - wz,
		xz + wy,
		xy + wz,
		1 - f32(xx + zz),
		yz - wx,
		xz - wy,
		yz + wx,
		1 - f32(xx + yy),
	}
end

local function axisAngle(axis: Vector3Value, angle: number): Rotation
	local length = math.sqrt(axis.X * axis.X + axis.Y * axis.Y + axis.Z * axis.Z)
	local half = f32(angle) / 2
	local s = math.sin(half) / length
	return fromQuaternion(axis.X * s, axis.Y * s, axis.Z * s, math.cos(half))
end

local function trig(angle: number): (number, number)
	local value = f32(angle)
	return f32(math.cos(value)), f32(math.sin(value))
end

local function axes(rx: number, ry: number, rz: number): (Rotation, Rotation, Rotation)
	local cx, sx = trig(rx)
	local cy, sy = trig(ry)
	local cz, sz = trig(rz)
	return { 1, 0, 0, 0, cx, -sx, 0, sx, cx }, { cy, 0, sy, 0, 1, 0, -sy, 0, cy }, { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
end

local function angles(rx: number, ry: number, rz: number): Rotation
	local x, y, z = axes(rx, ry, rz)
	return multiply(multiply(x, y), z)
end

local function orientation(rx: number, ry: number, rz: number): Rotation
	local x, y, z = axes(rx, ry, rz)
	return multiply(multiply(y, x), z)
end

local function cross(ax: number, ay: number, az: number, bx: number, by: number, bz: number): (number, number, number)
	return f32(f32(ay * bz) - f32(az * by)), f32(f32(az * bx) - f32(ax * bz)), f32(f32(ax * by) - f32(ay * bx))
end

local function unit(x: number, y: number, z: number): (number, number, number)
	local inverse = f32(1 / f32(math.sqrt(x * x + y * y + z * z)))
	return f32(x * inverse), f32(y * inverse), f32(z * inverse)
end

local function lookAt(at: Vector3Value, target: Vector3Value, up: Vector3Value?): CFrameValue
	local lx, ly, lz = f32(target.X - at.X), f32(target.Y - at.Y), f32(target.Z - at.Z)
	if lx == 0 and ly == 0 and lz == 0 then
		return make(at.X, at.Y, at.Z, IDENTITY)
	end
	lx, ly, lz = unit(lx, ly, lz)
	local bx, by, bz = -lx, -ly, -lz
	local ux, uy, uz = 0, 1, 0
	if up ~= nil then
		ux, uy, uz = up.X, up.Y, up.Z
	end
	local rx, ry, rz = cross(ux, uy, uz, bx, by, bz)
	if rx * rx + ry * ry + rz * rz < 1e-12 then
		rx, ry, rz = cross(1, 0, 0, bx, by, bz)
		if rx * rx + ry * ry + rz * rz < 1e-12 then
			rx, ry, rz = cross(0, 0, 1, bx, by, bz)
		end
	end
	rx, ry, rz = unit(rx, ry, rz)
	local nx, ny, nz = cross(bx, by, bz, rx, ry, rz)
	return make(at.X, at.Y, at.Z, { rx, nx, bx, ry, ny, by, rz, nz, bz })
end

local function fromMatrix(
	position: Vector3Value,
	right: Vector3Value,
	up: Vector3Value,
	back: Vector3Value?
): CFrameValue
	local z = back or right:Cross(up).Unit
	return make(position.X, position.Y, position.Z, { right.X, up.X, z.X, right.Y, up.Y, z.Y, right.Z, up.Z, z.Z })
end

local function eulerXYZ(r: Rotation): (number, number, number)
	local y = math.asin(math.clamp(r[3], -1, 1))
	local x, z
	if math.abs(r[3]) < 0.9999999 then
		x = math.atan2(-r[6], r[9])
		z = math.atan2(-r[2], r[1])
	else
		x = math.atan2(r[8], r[5])
		z = 0
	end
	return f32(x), f32(y), f32(z)
end

local function eulerYXZ(r: Rotation): (number, number, number)
	local x = math.asin(math.clamp(-r[6], -1, 1))
	local y, z
	if math.abs(r[6]) < 0.9999999 then
		y = math.atan2(r[3], r[9])
		z = math.atan2(r[4], r[5])
	else
		y = math.atan2(-r[7], r[1])
		z = 0
	end
	return f32(x), f32(y), f32(z)
end

local methods: Methods = {}

local function components(self: CFrameValue): (
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
	local r = rotationOf(self)
	return self.X, self.Y, self.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
end
methods.GetComponents = components
methods.components = components

function methods.Inverse(self: CFrameValue): CFrameValue
	return inverse(self)
end

function methods.Lerp(self: CFrameValue, goal: unknown, alpha: number): CFrameValue
	local target = expectFrame(goal, 1)
	local ax, ay, az, aw = quaternion(rotationOf(self))
	local bx, by, bz, bw = quaternion(rotationOf(target))
	local dot = ax * bx + ay * by + az * bz + aw * bw
	if dot < 0 then
		bx, by, bz, bw, dot = -bx, -by, -bz, -bw, -dot
	end
	local t = f32(alpha)
	local wa, wb = 1 - t, t
	if dot < 0.9995 then
		local theta = math.acos(math.clamp(dot, -1, 1))
		local sine = math.sin(theta)
		wa, wb = math.sin((1 - t) * theta) / sine, math.sin(t * theta) / sine
	end
	return make(
		self.X + (target.X - self.X) * t,
		self.Y + (target.Y - self.Y) * t,
		self.Z + (target.Z - self.Z) * t,
		fromQuaternion(ax * wa + bx * wb, ay * wa + by * wb, az * wa + bz * wb, aw * wa + bw * wb)
	)
end

function methods.Orthonormalize(self: CFrameValue): CFrameValue
	return make(self.X, self.Y, self.Z, fromQuaternion(quaternion(rotationOf(self))))
end

local function mapped(transform: (CFrameValue, unknown, number) -> unknown)
	return function(self: CFrameValue, ...: unknown): ...unknown
		local results = table.pack(...)
		for index = 1, results.n do
			results[index] = transform(self, results[index], index)
		end
		return table.unpack(results, 1, results.n)
	end
end

methods.ToWorldSpace = mapped(function(self: CFrameValue, value: unknown, index: number): unknown
	return compose(self, expectFrame(value, index))
end)
methods.ToObjectSpace = mapped(function(self: CFrameValue, value: unknown, index: number): unknown
	return compose(inverse(self), expectFrame(value, index))
end)
methods.PointToWorldSpace = mapped(function(self: CFrameValue, value: unknown, index: number): unknown
	local v = expectVector(value, index)
	local x, y, z = rotate(rotationOf(self), v.X, v.Y, v.Z)
	return Vector3.new(self.X + x, self.Y + y, self.Z + z)
end)
methods.PointToObjectSpace = mapped(function(self: CFrameValue, value: unknown, index: number): unknown
	local v = expectVector(value, index)
	return Vector3.new(unrotate(rotationOf(self), f32(v.X - self.X), f32(v.Y - self.Y), f32(v.Z - self.Z)))
end)
methods.VectorToWorldSpace = mapped(function(self: CFrameValue, value: unknown, index: number): unknown
	local v = expectVector(value, index)
	return Vector3.new(rotate(rotationOf(self), v.X, v.Y, v.Z))
end)
methods.VectorToObjectSpace = mapped(function(self: CFrameValue, value: unknown, index: number): unknown
	local v = expectVector(value, index)
	return Vector3.new(unrotate(rotationOf(self), v.X, v.Y, v.Z))
end)

function methods.ToEulerAnglesXYZ(self: CFrameValue): (number, number, number)
	return eulerXYZ(rotationOf(self))
end
methods.toEulerAnglesXYZ = methods.ToEulerAnglesXYZ

function methods.ToEulerAnglesYXZ(self: CFrameValue): (number, number, number)
	return eulerYXZ(rotationOf(self))
end
methods.ToOrientation = methods.ToEulerAnglesYXZ

function methods.ToAxisAngle(self: CFrameValue): (Vector3Value, number)
	local x, y, z, w = quaternion(rotationOf(self))
	local angle = 2 * math.acos(math.clamp(w, -1, 1))
	local s = math.sqrt(math.max(0, 1 - w * w))
	if s < 1e-9 then
		return Vector3.new(1, 0, 0), 0
	end
	return Vector3.new(x / s, y / s, z / s), f32(angle)
end

function methods.FuzzyEq(self: CFrameValue, other: unknown, epsilon: number?): boolean
	local target = expectFrame(other, 1)
	local limit = epsilon or 1e-5
	local a, b = { components(self) }, { components(target) }
	for index = 1, 12 do
		local left, right = a[index], b[index]
		if math.abs(left - right) > limit * math.max(1, math.abs(left), math.abs(right)) then
			return false
		end
	end
	return true
end

CFrameKind.fields.__index = function(fields: Names.Fields, key: unknown): unknown
	local method = methods[key]
	if method ~= nil then
		return method
	end
	local frame = frames[fields]
	assert(frame ~= nil)
	local r = rotations[fields]
	if key == "Position" or key == "p" then
		return Vector3.new(frame.X, frame.Y, frame.Z)
	elseif key == "Rotation" then
		return make(0, 0, 0, r)
	elseif key == "RightVector" or key == "XVector" then
		return Vector3.new(r[1], r[4], r[7])
	elseif key == "UpVector" or key == "YVector" then
		return Vector3.new(r[2], r[5], r[8])
	elseif key == "ZVector" then
		return Vector3.new(r[3], r[6], r[9])
	elseif key == "LookVector" then
		return Vector3.new(-r[3], -r[6], -r[9])
	end
	return Names.invalid(key, "CFrame")
end

CFrameKind.meta.__mul = function(left: unknown, right: unknown): unknown
	local frame = expectFrame(left, 1)
	if Names.is(right, CFrameKind) then
		return compose(frame, expectFrame(right, 2))
	elseif Vector.isVector3(right) then
		local v = Vector.expect3(right, 2)
		local x, y, z = rotate(rotationOf(frame), v.X, v.Y, v.Z)
		return Vector3.new(frame.X + x, frame.Y + y, frame.Z + z)
	end
	return Names.arithmetic("mul", left, right)
end

CFrameKind.meta.__add = function(left: unknown, right: unknown): CFrameValue
	local frame = expectFrame(left, 1)
	local v = expectVector(right, 2)
	return make(frame.X + v.X, frame.Y + v.Y, frame.Z + v.Z, rotationOf(frame))
end

CFrameKind.meta.__sub = function(left: unknown, right: unknown): CFrameValue
	local frame = expectFrame(left, 1)
	local v = expectVector(right, 2)
	return make(frame.X - v.X, frame.Y - v.Y, frame.Z - v.Z, rotationOf(frame))
end

CFrameKind.meta.__eq = function(a: CFrameValue, b: CFrameValue): boolean
	if a.X ~= b.X or a.Y ~= b.Y or a.Z ~= b.Z then
		return false
	end
	local ar, br = rotationOf(a), rotationOf(b)
	for index = 1, 9 do
		if ar[index] ~= br[index] then
			return false
		end
	end
	return true
end

CFrameKind.meta.__tostring = function(frame: CFrameValue): string
	local parts: { string } = {}
	for _, component in { components(frame) } do
		table.insert(parts, Float.general(component, 9))
	end
	return table.concat(parts, ", ")
end

local function new(...: unknown): CFrameValue
	local count = select("#", ...)
	local first, second = ...
	if count == 0 then
		return make(0, 0, 0, IDENTITY)
	elseif Vector.isVector3(first) then
		local position = Vector.expect3(first, 1)
		if count >= 2 and second ~= nil then
			return lookAt(position, expectVector(second, 2))
		end
		return make(position.X, position.Y, position.Z, IDENTITY)
	end
	local values = table.create(count, 0)
	for index = 1, count do
		values[index] = Float.coerce((select(index, ...)), index)
	end
	if count == 12 then
		return make(values[1], values[2], values[3], table.move(values, 4, 12, 1, {}))
	elseif count == 7 then
		return make(values[1], values[2], values[3], fromQuaternion(values[4], values[5], values[6], values[7]))
	elseif count <= 3 then
		return make(values[1] or 0, values[2] or 0, values[3] or 0, IDENTITY)
	end
	error("Invalid number of arguments: " .. count, 2)
end

local CFrame = {
	new = new,
	identity = make(0, 0, 0, IDENTITY),
	Angles = function(rx: number, ry: number, rz: number): CFrameValue
		return make(0, 0, 0, angles(rx, ry, rz))
	end,
	fromEulerAnglesXYZ = function(rx: number, ry: number, rz: number): CFrameValue
		return make(0, 0, 0, angles(rx, ry, rz))
	end,
	fromEulerAnglesYXZ = function(rx: number, ry: number, rz: number): CFrameValue
		return make(0, 0, 0, orientation(rx, ry, rz))
	end,
	fromOrientation = function(rx: number, ry: number, rz: number): CFrameValue
		return make(0, 0, 0, orientation(rx, ry, rz))
	end,
	fromAxisAngle = function(axis: Vector3Value, angle: number): CFrameValue
		return make(0, 0, 0, axisAngle(expectVector(axis, 1), angle))
	end,
	fromMatrix = function(
		position: Vector3Value,
		right: Vector3Value,
		up: Vector3Value,
		back: Vector3Value?
	): CFrameValue
		return fromMatrix(expectVector(position, 1), expectVector(right, 2), expectVector(up, 3), back)
	end,
	lookAt = function(at: Vector3Value, target: Vector3Value, up: Vector3Value?): CFrameValue
		return lookAt(expectVector(at, 1), expectVector(target, 2), up)
	end,
	lookAlong = function(at: Vector3Value, direction: Vector3Value, up: Vector3Value?): CFrameValue
		local origin = expectVector(at, 1)
		return lookAt(origin, origin + expectVector(direction, 2), up)
	end,
}

local function read(value: CFrameValue): (number, number, number, { number })
	return value.X, value.Y, value.Z, table.clone(rotationOf(value))
end

return {
	expect = expectFrame,
	CFrame = CFrame,
	read = read,
	isCFrame = function(value: unknown): boolean
		return Names.is(value, CFrameKind)
	end,
}
