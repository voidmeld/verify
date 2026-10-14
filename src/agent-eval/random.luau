--!strict

export type Generator = {
	next: () -> number,
	integer: (minimum: number, maximum: number) -> number,
}

local function hash(value: string): number
	local state = 2166136261
	for index = 1, #value do
		state = bit32.bxor(state, string.byte(value, index))
		state = bit32.band(state * 403 + bit32.lshift(state, 24), 0xFFFFFFFF)
	end
	return state
end

local function derive(seed: number, label: string): number
	return hash(("%d:%s"):format(seed, label))
end

local function generator(seed: number): Generator
	assert(type(seed) == "number" and seed == seed and math.abs(seed) < 2 ^ 53, "a generator needs a finite seed")
	local state = bit32.band(math.floor(math.abs(seed)), 0xFFFFFFFF)
	state = bit32.bxor(state, 0x9E3779B9)
	if state == 0 then
		state = 0x6D2B79F5
	end
	local function step(): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return state
	end
	for _ = 1, 4 do
		step()
	end
	local function nextValue(): number
		return step() / 4294967296
	end
	local function integer(minimum: number, maximum: number): number
		assert(maximum >= minimum, "an integer range needs maximum >= minimum")
		return minimum + math.floor(nextValue() * (maximum - minimum + 1))
	end
	return { next = nextValue, integer = integer }
end

return {
	hash = hash,
	derive = derive,
	generator = generator,
}
