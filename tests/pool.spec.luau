--!strict

local fs = require "@std/fs"
local test = require "@std/test"
local task = require "@std/task"

local Files = require "../src/lute/files"
local Lute = require "../src/lute"
local Verify = require "../src/core"

local ROOT = ".lute/tmp/verify-pool-spec"
local UNITS = ROOT .. "/units"
local WORKER = "examples/pool-worker.luau"

local ensureDirectory = Files.ensureDirectory

local function fixture(name: string, body: string): string
	ensureDirectory(ROOT)
	ensureDirectory(UNITS)
	local locator = ("%s/%s.luau"):format(UNITS, name)
	fs.writeStringToFile(locator, body)
	return locator
end

local PASSING = fixture(
	"passing",
	table.concat({
		"--!strict",
		"return function(harness)",
		'\tharness:suite("pooled", function()',
		'\t\tharness:case("passes", function(context)',
		"\t\t\tcontext:expect(2 + 2):toBe(4)",
		"\t\tend)",
		"\tend)",
		"end",
		"",
	}, "\n")
)

local SECOND = fixture(
	"second",
	table.concat({
		"--!strict",
		"return function(harness)",
		'\tharness:suite("pooled", function()',
		'\t\tharness:case("also passes", function(context)',
		"\t\t\tcontext:expect(true):toBe(true)",
		"\t\tend)",
		"\tend)",
		"end",
		"",
	}, "\n")
)

local DIES = fixture(
	"dies",
	table.concat({
		"--!strict",
		'local process = require "@std/process"',
		"process.exit(3)",
		"return function() end",
		"",
	}, "\n")
)

local HANGS = fixture(
	"hangs",
	table.concat({
		"--!strict",
		"return function(harness)",
		'\tharness:case("burns", function(context)',
		"\t\tlocal accumulator = 0.0",
		"\t\tfor index = 1, 40000000 do",
		"\t\t\taccumulator += (index % 7) * 1.000001",
		"\t\tend",
		"\t\tcontext:expect(accumulator >= 0):toBe(true)",
		"\tend)",
		"end",
		"",
	}, "\n")
)

local function planOf(id: string, locators: { string }): Verify.PlanDraft
	local units: { Verify.PlanUnitDraft } = {}
	for index, locator in locators do
		table.insert(units, { id = ("u%d"):format(index), locator = locator })
	end
	return { id = id, units = units }
end

type Knobs = {
	size: number?,
	maxRestarts: number?,
	batchTimeoutSeconds: number?,
	recycleAfter: number?,
}

local function poolAt(directory: string, knobs: Knobs): Lute.Pool
	return Lute.pool {
		worker = WORKER,
		directory = ROOT .. "/" .. directory,
		size = knobs.size,
		maxRestarts = knobs.maxRestarts,
		batchTimeoutSeconds = knobs.batchTimeoutSeconds,
		recycleAfter = knobs.recycleAfter,
	}
end

local function factCodes(execution: Verify.ExecutionReport): { string }
	local codes: { string } = {}
	for _, fact in execution.facts do
		table.insert(codes, fact.code)
	end
	return codes
end

local function attemptDetail(execution: Verify.ExecutionReport): string
	for _, attempt in execution.attempts do
		if attempt.detail ~= nil then
			return attempt.detail :: string
		end
	end
	return ""
end

test.suite("worker pool invocation isolation", function(suite)
	suite:case("simultaneous workloads with identical batch ids retain their own results", function(assert)
		local first = poolAt("concurrent", { size = 1 })
		local second = poolAt("concurrent", { size = 1 })
		local finished = false
		local firstOk = false
		local firstResult: any = nil
		task.spawn(function()
			firstOk, firstResult = pcall(Verify.execute, planOf("collision", { PASSING }), first)
			finished = true
		end)
		local secondOk, secondResult: any = pcall(Verify.execute, planOf("collision", { SECOND }), second)
		while not finished do
			task.wait(0.001)
		end
		first:close()
		second:close()
		assert.eq(firstOk, true)
		assert.eq(secondOk, true)
		assert.eq(firstResult.report.passed, 1)
		assert.eq(secondResult.report.passed, 1)
		assert.eq(firstResult.report.results[1].source, PASSING)
		assert.eq(secondResult.report.results[1].source, SECOND)
	end)

	suite:case("two live pools share a base without deleting or stopping one another", function(assert)
		local first = poolAt("shared", { size = 1 })
		local firstPlan = planOf("same-id", { PASSING })
		local secondPlan = planOf("same-id", { SECOND })
		local initial = Verify.execute(firstPlan, first)
		local second = poolAt("shared", { size = 1 })
		local other = Verify.execute(secondPlan, second)
		first:close()
		local replay = Verify.execute(secondPlan, second)
		second:close()
		assert.eq(initial.report.passed, 1)
		assert.eq(other.report.passed, 1)
		assert.eq(replay.report.passed, 1)
		assert.eq(other.report.results[1].source, SECOND)
		assert.eq(replay.report.results[1].source, SECOND)
	end)
end)

test.suite("worker pool equivalence", function(suite)
	suite:case("agrees with the fresh-process host on the same plan", function(assert)
		local plan = planOf("parity", { PASSING, SECOND })
		local fresh = Verify.execute(plan, Lute.host { worker = "examples/worker.luau", directory = ROOT .. "/fresh" })
		local pool = poolAt("parity", { size = 2 })
		local pooled = Verify.execute(plan, pool, { batchCount = 2, parallel = 2 })
		pool:close()

		assert.eq(fresh.report.passed, 2)

		assert.eq(Verify.verdictDigest(pooled.report), Verify.verdictDigest(fresh.report))
		assert.eq(pooled.report.passed, 2)
		assert.eq(pooled.report.results[1].source, fresh.report.results[1].source)
	end)

	suite:case("produces the same report serially and in parallel", function(assert)
		local plan = planOf("equivalence", { PASSING, SECOND })
		local serial = poolAt("serial", { size = 2 })
		local one = Verify.execute(plan, serial, { batchCount = 2, parallel = 1 })
		serial:close()

		local parallel = poolAt("parallel", { size = 2 })
		local two = Verify.execute(plan, parallel, { batchCount = 2, parallel = 2 })
		parallel:close()

		assert.eq(Verify.canonical(two.report), Verify.canonical(one.report))
		assert.eq(one.report.passed, 2)
	end)

	suite:case("produces a byte-identical report on a warm pool", function(assert)
		local plan = planOf("warm", { PASSING, SECOND })
		local pool = poolAt("warm", { size = 1 })
		local cold = Verify.execute(plan, pool, { batchCount = 2, parallel = 1 })
		local warm = Verify.execute(plan, pool, { batchCount = 2, parallel = 1 })
		pool:close()
		assert.eq(Verify.canonical(warm.report), Verify.canonical(cold.report))
	end)

	suite:case("starts one process per worker and not one per batch", function(assert)
		local plan = planOf("amortized", { PASSING, SECOND })
		local pool = poolAt("amortized", { size = 2 })
		Verify.execute(plan, pool, { batchCount = 8, parallel = 2 })
		local statistics = pool:statistics()
		pool:close()

		assert.eq(statistics.started, 2)
		assert.eq(statistics.restarted, 0)
		assert.eq(statistics.faults, 0)
		assert.eq(statistics.batches, 2)
	end)
end)

test.suite("worker pool failure injection", function(suite)
	suite:case("names a worker that died mid-batch instead of waiting for it", function(assert)
		local plan = planOf("death", { DIES })
		local pool = poolAt("death", { size = 1 })
		local execution = Verify.execute(plan, pool, { batchCount = 1, parallel = 1 })
		pool:close()

		assert.eq(execution.attempts[1].status, "faulted")
		assert.strContains(attemptDetail(execution), "exited without answering")

		assert.eq(table.find(factCodes(execution), "batch-not-returned") ~= nil, true)
		assert.eq(execution.report.failed, 1)
	end)

	suite:case("replaces a poisoned worker rather than trusting it again", function(assert)
		local plan = planOf("recycle", { DIES, PASSING })
		local pool = poolAt("recycle", { size = 1, maxRestarts = 2 })
		local execution = Verify.execute(plan, pool, { batchCount = 2, parallel = 1 })
		local statistics = pool:statistics()
		pool:close()

		assert.eq(statistics.restarted >= 1, true)

		assert.eq(statistics.faults >= 1, true)
		assert.eq(execution.report.passed, 1)
		assert.eq(execution.report.failed, 1)
	end)

	suite:case("faults the rest of the run when the pool is exhausted", function(assert)
		local plan = planOf("exhausted", { DIES, PASSING, SECOND })
		local pool = poolAt("exhausted", { size = 1, maxRestarts = 0 })
		local execution = Verify.execute(plan, pool, { batchCount = 3, parallel = 1 })
		pool:close()

		assert.eq(execution.report.failed, 3)
		local sawExhaustion = false
		for _, attempt in execution.attempts do
			if attempt.detail ~= nil and string.find(attempt.detail :: string, "no usable worker", 1, true) ~= nil then
				sawExhaustion = true
			end
		end
		assert.eq(sawExhaustion, true)
	end)

	suite:case("abandons a worker that will not answer in time", function(assert)
		local plan = planOf("hang", { HANGS })
		local pool = poolAt("hang", { size = 1, batchTimeoutSeconds = 0.05 })
		local execution = Verify.execute(plan, pool, { batchCount = 1, parallel = 1 })
		pool:close()

		assert.eq(execution.attempts[1].status, "faulted")
		assert.strContains(attemptDetail(execution), "did not answer")
		assert.eq(execution.report.failed, 1)
	end)

	suite:case("refuses to be created without a worker to start", function(assert)
		assert.eq(
			pcall(function()
				(Lute.pool :: any) {}
			end),
			false
		)
		assert.eq(
			pcall(function()
				(Lute.pool :: any) { worker = "" }
			end),
			false
		)
	end)

	suite:case("closes idempotently and answers nothing afterwards", function(assert)
		local pool = poolAt("closed", { size = 1 })
		pool:close()
		pool:close()
		local outcome = pool.runBatch { id = "after-close", index = 1, units = {} }
		assert.eq(outcome.status, "faulted")
	end)
end)
