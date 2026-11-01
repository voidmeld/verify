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

local function checkedString(value: unknown): string
	assert(type(value) == "string")
	return value
end

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

local function deepEqual(left: unknown, right: unknown, seen: { [unknown]: unknown }): boolean
	if left == right then
		return true
	end
	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end
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

local function makeExpectation<T>(value: T): Expectation<T>
	local actual: unknown = value
	local function build(negated: boolean)
		local expectation = { actual = value }

		local function check(condition: boolean, verb: string, expected: unknown?, detail: string?)
			if condition == negated then
				fail(negated, verb, actual, expected, detail)
			end
		end

		local function numberValue(): number
			if type(actual) ~= "number" then
				return error("numeric expectation received " .. describe(actual), 3)
			end
			return actual
		end

		local function optionalNumber(): number?
			return if type(actual) == "number" then actual else nil
		end

		function expectation.toBe(_self: Expectation<T>, expected: unknown)
			check(actual == expected, "to be", expected)
		end

		function expectation.toEqual(_self: Expectation<T>, expected: unknown)
			check(deepEqual(actual, expected, {}), "to deeply equal", expected)
		end

		function expectation.toBeNil(_self: Expectation<T>)
			check(actual == nil, "to be nil")
		end

		function expectation.toBeOk(_self: Expectation<T>)
			check(actual ~= nil, "to be non-nil")
		end

		function expectation.toBeTruthy(_self: Expectation<T>)
			check(not not actual, "to be truthy")
		end

		function expectation.toBeFalsy(_self: Expectation<T>)
			check(not actual, "to be falsy")
		end

		function expectation.toBeCloseTo(_self: Expectation<T>, expected: number, tolerance: number?)
			local epsilon = tolerance or 1e-9
			check(math.abs(numberValue() - expected) <= epsilon, "to be close to", expected)
		end

		function expectation.toBeNear(_self: Expectation<T>, expected: number, tolerance: number)
			if type(expected) ~= "number" or type(tolerance) ~= "number" then
				error("toBeNear requires an expected number and a tolerance", 2)
			end
			local observed = optionalNumber()
			local detail = if observed ~= nil
				then ("%.17g is off %s by %.17g (tolerance %g)"):format(
					observed,
					("%.17g"):format(expected),
					math.abs(observed - expected),
					tolerance
				)
				else "not a number, so no distance exists"
			check(observed ~= nil and math.abs(observed - expected) < tolerance, "to be near", expected, detail)
		end

		function expectation.toBeFloat32(_self: Expectation<T>, authored: number)
			if type(authored) ~= "number" then
				error("toBeFloat32 requires the authored number to compare against", 2)
			end
			local observed = optionalNumber()

			local stored = float32(authored)
			local observedText = if observed ~= nil then ("%.17g"):format(float32(observed)) else "not a number"
			check(
				observed ~= nil and float32(observed) == stored,
				"to be equal at float32 precision",
				authored,
				("stored: %s vs %.17g"):format(observedText, stored)
			)
		end

		function expectation.toBeTrueWith(_self: Expectation<T>, detail: string)
			check(actual == true, "to be true: " .. detail)
		end

		function expectation.toBeLessThan(_self: Expectation<T>, expected: number)
			check(numberValue() < expected, "to be less than", expected)
		end

		function expectation.toBeGreaterThan(_self: Expectation<T>, expected: number)
			check(numberValue() > expected, "to be greater than", expected)
		end

		function expectation.toBeLessThanOrEqual(_self: Expectation<T>, expected: number)
			check(numberValue() <= expected, "to be at most", expected)
		end

		function expectation.toBeGreaterThanOrEqual(_self: Expectation<T>, expected: number)
			check(numberValue() >= expected, "to be at least", expected)
		end

		local function containsSubstring(expected: unknown): boolean
			local needle = if type(expected) == "string" then expected else tostring(expected)
			return string.find(checkedString(actual), needle, 1, true) ~= nil
		end

		local function requireHaystack()
			if type(actual) ~= "table" then
				error("containment expectation requires a string or table", 3)
			end
			return actual
		end

		function expectation.toContain(_self: Expectation<T>, expected: unknown)
			if type(actual) == "string" then
				local needle = if type(expected) == "string" then expected else tostring(expected)
				check(containsSubstring(expected), "to contain substring", needle)
				return
			end
			local found = false
			for _, value in requireHaystack() do
				if deepEqual(value, expected, {}) then
					found = true
					break
				end
			end
			check(found, "to contain a deeply equal member", expected)
		end

		function expectation.toContainExactly(_self: Expectation<T>, expected: unknown)
			if type(actual) == "string" then
				local needle = if type(expected) == "string" then expected else tostring(expected)
				check(containsSubstring(expected), "to contain substring", needle)
				return
			end
			local found = false
			for _, value in requireHaystack() do
				if value == expected then
					found = true
					break
				end
			end
			check(found, "to contain the identical member", expected)
		end

		function expectation.toHaveLength(_self: Expectation<T>, expected: number)
			if type(actual) == "string" then
				check(#actual == expected, "to have length", expected)
			elseif type(actual) == "table" then
				check(#actual == expected, "to have length", expected)
			else
				error("length expectation requires a string or table", 2)
			end
		end

		function expectation.toThrow(_self: CallableExpectation, contains: string?)
			if type(actual) ~= "function" then
				error("throw expectation requires a function", 2)
			end
			local ok, thrown: unknown = pcall(_self.actual)
			local matched = not ok
			if matched and contains ~= nil then
				matched = string.find(tostring(thrown), contains, 1, true) ~= nil
			end
			check(matched, "to throw", contains, caught(ok, thrown))
		end

		function expectation.toThrowMatching(_self: CallableExpectation, pattern: string)
			if type(actual) ~= "function" then
				error("throw expectation requires a function", 2)
			end
			if type(pattern) ~= "string" or pattern == "" then
				error("toThrowMatching requires a non-empty pattern", 2)
			end
			local ok, thrown: unknown = pcall(_self.actual)
			local matched = not ok and string.find(tostring(thrown), pattern) ~= nil
			check(matched, "to throw matching", pattern, caught(ok, thrown))
		end

		expectation.never = expectation
		return expectation
	end

	local unknownMatcher = {
		__index = function(_: unknown, key: unknown): never
			return error(("unknown matcher %q"):format(tostring(key)), 2)
		end,
	}

	local positive = build(false)
	local negative = build(true)
	local function attach(value: Expectation<T>)
		setmetatable(value, unknownMatcher)
	end
	attach(positive)
	attach(negative)
	positive.never = negative
	negative.never = positive
	return positive
end

local function expect<T>(actual: T?): Expectation<T>
	return makeExpectation(actual)
end

return {
	expect = expect,
	describe = describe,
	float32 = float32,
	deepEqual = function(left: unknown, right: unknown): boolean
		return deepEqual(left, right, {})
	end,
}
