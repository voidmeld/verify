--!strict

type CallableExpectation = { read actual: () -> ...unknown }

local function view(value: unknown): { [unknown]: unknown }
	assert(type(value) == "table")
	local result: { [unknown]: unknown } = {}
	setmetatable(result, { __index = value })
	return result
end

local function render(value: unknown, depth: number, seen: { [unknown]: boolean }): string
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) ~= "table" then
		return tostring(value)
	end
	if seen[value] then
		return "<cycle>"
	end
	if depth == 0 then
		return "<table>"
	end
	seen[value] = true
	local values = view(value)
	local keys: { unknown } = {}
	for key in value do
		table.insert(keys, key)
	end
	table.sort(keys, function(left, right)
		return tostring(left) < tostring(right)
	end)
	local pieces: { string } = {}
	for _, key in keys do
		table.insert(pieces, ("[%s] = %s"):format(render(key, depth - 1, seen), render(values[key], depth - 1, seen)))
	end
	seen[value] = nil
	return "{ " .. table.concat(pieces, ", ") .. " }"
end

local function describe(value: unknown): string
	return render(value, 4, {})
end

local function deepEqual(left: unknown, right: unknown, visited: { [unknown]: unknown }?): boolean
	if left == right then
		return true
	end
	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end
	local seen: { [unknown]: unknown } = visited or {}
	if seen[left] ~= nil then
		return seen[left] == right
	end
	seen[left] = right
	local leftTable = view(left)
	local rightTable = view(right)
	for key, value in left do
		if not deepEqual(value, rightTable[key], seen) then
			return false
		end
	end
	for key in right do
		if leftTable[key] == nil and rightTable[key] ~= nil then
			return false
		end
	end
	return true
end

local function fail(negated: boolean, verb: string, actual: unknown, expected: unknown?, detail: string?): never
	local message = if negated then "expected NOT " .. verb else "expected " .. verb
	if expected ~= nil then
		message ..= " " .. describe(expected)
	end
	message ..= "\n     actual: " .. describe(actual)
	if detail ~= nil then
		message ..= "\n     " .. detail
	end

	return error(message, 0)
end

local float32Slot = buffer.create(4)
local function float32(value: number): number
	buffer.writef32(float32Slot, 0, value)
	return buffer.readf32(float32Slot, 0)
end

local function caught(ok: boolean, thrown: unknown): string
	return if ok then "caught: (no error)" else "caught: " .. tostring(thrown)
end

local unknownMatcher = {
	__index = function(_: unknown, key: unknown)
		if key == "actual" then
			return nil
		end
		return error(("unknown matcher %q"):format(tostring(key)), 2)
	end,
}

local function numberValue(actual: unknown): number
	if type(actual) ~= "number" then
		return error("numeric expectation received " .. describe(actual), 3)
	end
	return actual
end

local function contain(actual: unknown, expected: unknown, identical: boolean): (boolean, string, unknown)
	if type(actual) == "string" then
		local needle = if type(expected) == "string" then expected else tostring(expected)
		return string.find(actual, needle, 1, true) ~= nil, "to contain substring", needle
	end
	local found = false
	assert(type(actual) == "table", "containment expectation requires a string or table")
	for _, item in actual do
		if if identical then item == expected else deepEqual(item, expected, nil) then
			found = true
			break
		end
	end
	return found, if identical then "to contain the identical member" else "to contain a deeply equal member", expected
end

type Value = { read actual: unknown }
local methods = {}
setmetatable(methods, unknownMatcher)
local positiveMeta = { __index = methods }
local negativeMeta = { __index = methods }

local function check(self: Value, condition: boolean, verb: string, expected: unknown?, detail: string?)
	local negated = getmetatable(self) == negativeMeta
	if condition == negated then
		fail(negated, verb, self.actual, expected, detail)
	end
end

function methods.toBe(self: Value, expected: unknown)
	check(self, self.actual == expected, "to be", expected)
end

function methods.toEqual(self: Value, expected: unknown)
	check(self, deepEqual(self.actual, expected, nil), "to deeply equal", expected)
end

function methods.toBeNil(self: Value)
	check(self, self.actual == nil, "to be nil")
end

function methods.toBeOk(self: Value)
	check(self, self.actual ~= nil, "to be non-nil")
end

function methods.toBeTruthy(self: Value)
	check(self, not not self.actual, "to be truthy")
end

function methods.toBeFalsy(self: Value)
	check(self, not self.actual, "to be falsy")
end

function methods.toBeCloseTo(self: Value, expected: number, tolerance: number?)
	local epsilon = tolerance or 1e-9
	check(self, math.abs(numberValue(self.actual) - expected) <= epsilon, "to be close to", expected)
end

function methods.toBeNear(self: Value, expected: number, tolerance: number)
	if type(expected) ~= "number" or type(tolerance) ~= "number" then
		error("toBeNear requires an expected number and a tolerance", 2)
	end
	local observed = if type(self.actual) == "number" then self.actual else nil
	local matched = observed ~= nil and math.abs(observed - expected) < tolerance
	if matched ~= (getmetatable(self) == negativeMeta) then
		return
	end
	local detail = if observed ~= nil
		then ("%.17g is off %s by %.17g (tolerance %g)"):format(
			observed,
			("%.17g"):format(expected),
			math.abs(observed - expected),
			tolerance
		)
		else "not a number, so no distance exists"
	fail(getmetatable(self) == negativeMeta, "to be near", self.actual, expected, detail)
end

function methods.toBeFloat32(self: Value, authored: number)
	if type(authored) ~= "number" then
		error("toBeFloat32 requires the authored number to compare against", 2)
	end
	local observed = if type(self.actual) == "number" then self.actual else nil

	local stored = float32(authored)
	local rounded = if observed ~= nil then float32(observed) else nil
	if (rounded == stored) ~= (getmetatable(self) == negativeMeta) then
		return
	end
	fail(
		getmetatable(self) == negativeMeta,
		"to be equal at float32 precision",
		self.actual,
		authored,
		("stored: %s vs %.17g"):format(if rounded ~= nil then ("%.17g"):format(rounded) else "not a number", stored)
	)
end

function methods.toBeTrueWith(self: Value, detail: string)
	check(self, self.actual == true, "to be true: " .. detail)
end

function methods.toBeLessThan(self: Value, expected: number)
	check(self, numberValue(self.actual) < expected, "to be less than", expected)
end

function methods.toBeGreaterThan(self: Value, expected: number)
	check(self, numberValue(self.actual) > expected, "to be greater than", expected)
end

function methods.toBeLessThanOrEqual(self: Value, expected: number)
	check(self, numberValue(self.actual) <= expected, "to be at most", expected)
end

function methods.toBeGreaterThanOrEqual(self: Value, expected: number)
	check(self, numberValue(self.actual) >= expected, "to be at least", expected)
end

function methods.toContain(self: Value, expected: unknown)
	check(self, contain(self.actual, expected, false))
end
function methods.toContainExactly(self: Value, expected: unknown)
	check(self, contain(self.actual, expected, true))
end

function methods.toHaveLength(self: Value, expected: number)
	if type(self.actual) == "string" or type(self.actual) == "table" then
		check(self, #self.actual == expected, "to have length", expected)
	else
		error("length expectation requires a string or table", 2)
	end
end

function methods.toThrow(self: CallableExpectation, contains: string?)
	if type(self.actual) ~= "function" then
		error("throw expectation requires a function", 2)
	end
	local ok, thrown: unknown = pcall(self.actual)
	local matched = not ok
	if matched and contains ~= nil then
		matched = string.find(tostring(thrown), contains, 1, true) ~= nil
	end
	check(
		self,
		matched,
		"to throw",
		contains,
		if matched == (getmetatable(self) == negativeMeta) then caught(ok, thrown) else nil
	)
end

function methods.toThrowMatching(self: CallableExpectation, pattern: string)
	if type(self.actual) ~= "function" then
		error("throw expectation requires a function", 2)
	end
	if type(pattern) ~= "string" or pattern == "" then
		error("toThrowMatching requires a non-empty pattern", 2)
	end
	local ok, thrown: unknown = pcall(self.actual)
	local matched = not ok and string.find(tostring(thrown), pattern) ~= nil
	check(
		self,
		matched,
		"to throw matching",
		pattern,
		if matched == (getmetatable(self) == negativeMeta) then caught(ok, thrown) else nil
	)
end

export type Expectation<T = unknown> = setmetatable<{
	read actual: T,
	read never: Expectation<T>,
}, typeof(positiveMeta)>

local function makeExpectation<T>(value: T): Expectation<T>
	local expectation: Expectation<T>
	local pair = { actual = value, never = expectation }
	expectation = setmetatable(pair, positiveMeta)
	local negative: Expectation<T> = setmetatable({ actual = value, never = expectation }, negativeMeta)
	pair.never = negative
	return expectation
end

local function expect<T>(actual: T?): Expectation<T>
	return makeExpectation(actual)
end

return {
	expect = expect,
	describe = describe,
	float32 = float32,
	deepEqual = function(left: unknown, right: unknown): boolean
		return deepEqual(left, right, nil)
	end,
}
