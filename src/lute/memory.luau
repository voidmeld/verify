--!strict

export type Options = { cycles: number?, maxAllocations: number?, deadlineSeconds: number? }
export type Reading = { heapKb: number, cycles: number, allocations: number }
export type Result = {
	method: string,
	baseline: Reading,
	mounted: Reading,
	teardown: Reading,
	mountedKb: number,
	releasedKb: number,
	teardownRetainedKb: number,
}
export type Spec<T> = {
	setup: () -> T,
	run: (state: T) -> (),
	afterRun: ((state: T) -> ())?,
	teardown: (state: T) -> (),
	warmup: number?,
	iterations: number,
	rehearsals: number?,
}
local function witness()
	local weak: { token: {}? } = { token = {} }
	return setmetatable(weak, { __mode = "v" })
end

export type Witness = typeof(witness())
export type Host = {
	now: () -> number,
	heap: () -> number,
	witness: () -> Witness,
	growStringTable: (() -> { string })?,
	pressure: () -> (),
}
export type Memory = {
	settle: (options: Options?) -> Reading,
	measure: <T>(spec: Spec<T>, options: Options?) -> Result,
}

local METHOD = "gc-witness-low-water/5"
local STRING_TABLE_GROWTH = 300000

local function integer(value: number, minimum: number): boolean
	return value >= minimum and value < math.huge and value % 1 == 0
end

local function create(host: Host): Memory
	local function settle(options: Options?): Reading
		local settings: Options = options or {}
		local cycles = settings.cycles or 4
		local maximum = settings.maxAllocations or 1000000
		local seconds = settings.deadlineSeconds or 5
		assert(integer(cycles, 2), "memory cycles must be an integer of at least two")
		assert(integer(maximum, 1), "memory maxAllocations must be a positive integer")
		assert(seconds > 0 and seconds < math.huge, "memory deadlineSeconds must be positive and finite")
		local deadline = host.now() + seconds
		local low = math.huge
		local allocations = 0
		for cycle = 1, cycles do
			local witness = host.witness()
			while witness.token ~= nil do
				assert(host.now() < deadline, "memory collection progress exceeded its deadline")
				assert(allocations < maximum, "memory collection progress exceeded its allocation limit")
				host.pressure()
				allocations += 1
				if cycle > 1 then
					local heap = host.heap()
					assert(heap >= 0 and heap < math.huge, "memory heap reading must be finite and nonnegative")
					low = math.min(low, heap)
				end
			end
			if cycle > 1 then
				local heap = host.heap()
				assert(heap >= 0 and heap < math.huge, "memory heap reading must be finite and nonnegative")
				low = math.min(low, heap)
			end
		end
		return { heapKb = low, cycles = cycles, allocations = allocations }
	end

	local function measure<T>(spec: Spec<T>, options: Options?): Result
		local warmup = spec.warmup or 0
		local rehearsals = spec.rehearsals or 0
		assert(integer(warmup, 0), "memory warmup must be a nonnegative integer")
		assert(integer(spec.iterations, 1), "memory iterations must be a positive integer")
		assert(integer(rehearsals, 0), "memory rehearsals must be a nonnegative integer")
		local mounted: Reading? = nil
		local measuring = false
		local function exercise()
			local state = spec.setup()
			local ran, problem = pcall(function()
				for _ = 1, warmup + spec.iterations do
					spec.run(state)
					if spec.afterRun then
						spec.afterRun(state)
					end
				end
				local reading = settle(options)
				if measuring then
					mounted = reading
				end
			end)
			local cleaned, cleanupProblem = pcall(function()
				spec.teardown(state)
				return true
			end)
			if not ran then
				error(
					tostring(problem) .. (if cleaned then "" else "; cleanup failed: " .. tostring(cleanupProblem)),
					0
				)
			end
			if not cleaned then
				error("memory cleanup failed: " .. tostring(cleanupProblem), 0)
			end
		end
		local anchored = if host.growStringTable then host.growStringTable() else nil
		if anchored then
			settle(options)
		end
		for _ = 1, rehearsals do
			exercise()
		end
		local baseline = settle(options)
		measuring = true
		exercise()
		local teardown = settle(options)
		local held = assert(mounted)
		if anchored then
			assert(#anchored > 0, "memory string table anchor was released")
		end
		return {
			method = METHOD,
			baseline = baseline,
			mounted = held,
			teardown = teardown,
			mountedKb = math.max(0, held.heapKb - baseline.heapKb),
			releasedKb = math.max(0, held.heapKb - teardown.heapKb),
			teardownRetainedKb = math.max(0, teardown.heapKb - baseline.heapKb),
		}
	end

	return { settle = settle, measure = measure }
end

local bound = create {
	now = os.clock,
	heap = gcinfo,
	witness = witness,
	growStringTable = function()
		local held = table.create(STRING_TABLE_GROWTH, "")
		for index = 1, STRING_TABLE_GROWTH do
			held[index] = `capacity{index}`
		end
		assert(#held == STRING_TABLE_GROWTH, "memory string table growth failed")
		local headroom = table.create(STRING_TABLE_GROWTH, "")
		for index = 1, STRING_TABLE_GROWTH do
			headroom[index] = `headroom{index}`
		end
		assert(#headroom == STRING_TABLE_GROWTH, "memory string table headroom failed")
		return held
	end,
	pressure = function()
		local scratch = buffer.create(8192)
		assert(buffer.len(scratch) == 8192, "memory pressure allocation failed")
	end,
}

return { METHOD = METHOD, create = create, settle = bound.settle, measure = bound.measure }
