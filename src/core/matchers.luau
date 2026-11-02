--!strict

type CallableExpectation = { read actual: () -> ...unknown }

export type Expectation<T = unknown> = {
	read actual: T,
	toBe: (self: Expectation<T>, expected: unknown) -> (),
	toEqual: (self: Expectation<T>, expected: unknown) -> (),
	toBeNil: (self: Expectation<T>) -> (),
	toBeOk: (self: Expectation<T>) -> (),
	toBeTruthy: (self: Expectation<T>) -> (),
	toBeFalsy: (self: Expectation<T>) -> (),
	toBeCloseTo: (self: Expectation<T>, expected: number, tolerance: number?) -> (),
	toBeNear: (self: Expectation<T>, expected: number, tolerance: number) -> (),
	toBeFloat32: (self: Expectation<T>, authored: number) -> (),
	toBeTrueWith: (self: Expectation<T>, detail: string) -> (),
	toBeLessThan: (self: Expectation<T>, expected: number) -> (),
	toBeGreaterThan: (self: Expectation<T>, expected: number) -> (),
	toBeLessThanOrEqual: (self: Expectation<T>, expected: number) -> (),
	toBeGreaterThanOrEqual: (self: Expectation<T>, expected: number) -> (),
	toContain: (self: Expectation<T>, expected: unknown) -> (),
	toContainExactly: (self: Expectation<T>, expected: unknown) -> (),
	toHaveLength: (self: Expectation<T>, expected: number) -> (),
	toThrow: (self: CallableExpectation, contains: string?) -> (),
	toThrowMatching: (self: CallableExpectation, pattern: string) -> (),
	read never: Expectation<T>,
}

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
	__index = function(_: unknown, key: unknown): never
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

local function makeExpectation<T>(value: T): Expectation<T>
	local actual: unknown = value
	local negative: Expectation<T>
	local expectation = { actual = value }

	local function check(self: unknown, condition: boolean, verb: string, expected: unknown?, detail: string?)
		local negated = self == negative
		if condition == negated then
			fail(negated, verb, actual, expected, detail)
		end
	end

	function expectation.toBe(self: Expectation<T>, expected: unknown)
		check(self, actual == expected, "to be", expected)
	end

	function expectation.toEqual(self: Expectation<T>, expected: unknown)
		check(self, deepEqual(actual, expected, nil), "to deeply equal", expected)
	end

	function expectation.toBeNil(self: Expectation<T>)
		check(self, actual == nil, "to be nil")
	end

	function expectation.toBeOk(self: Expectation<T>)
		check(self, actual ~= nil, "to be non-nil")
	end

	function expectation.toBeTruthy(self: Expectation<T>)
		check(self, not not actual, "to be truthy")
	end

	function expectation.toBeFalsy(self: Expectation<T>)
		check(self, not actual, "to be falsy")
	end

	function expectation.toBeCloseTo(self: Expectation<T>, expected: number, tolerance: number?)
		local epsilon = tolerance or 1e-9
		check(self, math.abs(numberValue(actual) - expected) <= epsilon, "to be close to", expected)
	end

	function expectation.toBeNear(self: Expectation<T>, expected: number, tolerance: number)
		if type(expected) ~= "number" or type(tolerance) ~= "number" then
			error("toBeNear requires an expected number and a tolerance", 2)
		end
		local observed = if type(actual) == "number" then actual else nil
		local matched = observed ~= nil and math.abs(observed - expected) < tolerance
		if matched ~= (self == negative) then
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
		fail(self == negative, "to be near", actual, expected, detail)
	end

	function expectation.toBeFloat32(self: Expectation<T>, authored: number)
		if type(authored) ~= "number" then
			error("toBeFloat32 requires the authored number to compare against", 2)
		end
		local observed = if type(actual) == "number" then actual else nil

		local stored = float32(authored)
		local rounded = if observed ~= nil then float32(observed) else nil
		if (rounded == stored) ~= (self == negative) then
			return
		end
		fail(
			self == negative,
			"to be equal at float32 precision",
			actual,
			authored,
			("stored: %s vs %.17g"):format(if rounded ~= nil then ("%.17g"):format(rounded) else "not a number", stored)
		)
	end

	function expectation.toBeTrueWith(self: Expectation<T>, detail: string)
		check(self, actual == true, "to be true: " .. detail)
	end

	function expectation.toBeLessThan(self: Expectation<T>, expected: number)
		check(self, numberValue(actual) < expected, "to be less than", expected)
	end

	function expectation.toBeGreaterThan(self: Expectation<T>, expected: number)
		check(self, numberValue(actual) > expected, "to be greater than", expected)
	end

	function expectation.toBeLessThanOrEqual(self: Expectation<T>, expected: number)
		check(self, numberValue(actual) <= expected, "to be at most", expected)
	end

	function expectation.toBeGreaterThanOrEqual(self: Expectation<T>, expected: number)
		check(self, numberValue(actual) >= expected, "to be at least", expected)
	end

	function expectation.toContain(self: Expectation<T>, expected: unknown)
		check(self, contain(actual, expected, false))
	end
	function expectation.toContainExactly(self: Expectation<T>, expected: unknown)
		check(self, contain(actual, expected, true))
	end

	function expectation.toHaveLength(self: Expectation<T>, expected: number)
		if type(actual) == "string" or type(actual) == "table" then
			check(self, #actual == expected, "to have length", expected)
		else
			error("length expectation requires a string or table", 2)
		end
	end

	function expectation.toThrow(self: CallableExpectation, contains: string?)
		if type(actual) ~= "function" then
			error("throw expectation requires a function", 2)
		end
		local ok, thrown: unknown = pcall(self.actual)
		local matched = not ok
		if matched and contains ~= nil then
			matched = string.find(tostring(thrown), contains, 1, true) ~= nil
		end
		check(self, matched, "to throw", contains, if matched == (self == negative) then caught(ok, thrown) else nil)
	end

	function expectation.toThrowMatching(self: CallableExpectation, pattern: string)
		if type(actual) ~= "function" then
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
			if matched == (self == negative) then caught(ok, thrown) else nil
		)
	end

	expectation.never = expectation

	setmetatable(expectation, unknownMatcher)
	negative = table.clone(expectation)
	expectation.never = negative
	negative.never = expectation
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
