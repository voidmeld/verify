--!strict

local fs = require "@std/fs"
local task = require "@std/task"

local Files = require "../src/lute/files"
local Lute = require "../src/lute"
local Verify = require "../src/core"

return function(suite: Verify.Harness)
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

	suite:suite("worker pool invocation isolation", function()
		suite:case("simultaneous workloads with identical batch ids retain their own results", function(check)
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
			check:expect(firstOk):toEqual(true)
			check:expect(secondOk):toEqual(true)
			check:expect(firstResult.report.passed):toEqual(1)
			check:expect(secondResult.report.passed):toEqual(1)
			check:expect(firstResult.report.results[1].source):toEqual(PASSING)
			check:expect(secondResult.report.results[1].source):toEqual(SECOND)
		end)

		suite:case("two live pools share a base without deleting or stopping one another", function(check)
			local first = poolAt("shared", { size = 1 })
			local firstPlan = planOf("same-id", { PASSING })
			local secondPlan = planOf("same-id", { SECOND })
			local initial = Verify.execute(firstPlan, first)
			local second = poolAt("shared", { size = 1 })
			local other = Verify.execute(secondPlan, second)
			first:close()
			local replay = Verify.execute(secondPlan, second)
			second:close()
			check:expect(initial.report.passed):toEqual(1)
			check:expect(other.report.passed):toEqual(1)
			check:expect(replay.report.passed):toEqual(1)
			check:expect(other.report.results[1].source):toEqual(SECOND)
			check:expect(replay.report.results[1].source):toEqual(SECOND)
		end)
	end)

	suite:suite("worker pool equivalence", function()
		suite:case("agrees with the fresh-process host on the same plan", function(check)
			local plan = planOf("parity", { PASSING, SECOND })
			local fresh =
				Verify.execute(plan, Lute.host { worker = "examples/worker.luau", directory = ROOT .. "/fresh" })
			local pool = poolAt("parity", { size = 2 })
			local pooled = Verify.execute(plan, pool, { batchCount = 2, parallel = 2 })
			pool:close()

			check:expect(fresh.report.passed):toEqual(2)

			check:expect((Verify.verdictDigest(pooled.report))):toEqual(Verify.verdictDigest(fresh.report))
			check:expect(pooled.report.passed):toEqual(2)
			check:expect(pooled.report.results[1].source):toEqual(fresh.report.results[1].source)
		end)

		suite:case("produces the same report serially and in parallel", function(check)
			local plan = planOf("equivalence", { PASSING, SECOND })
			local serial = poolAt("serial", { size = 2 })
			local one = Verify.execute(plan, serial, { batchCount = 2, parallel = 1 })
			serial:close()

			local parallel = poolAt("parallel", { size = 2 })
			local two = Verify.execute(plan, parallel, { batchCount = 2, parallel = 2 })
			parallel:close()

			check:expect((Verify.canonical(two.report))):toEqual(Verify.canonical(one.report))
			check:expect(one.report.passed):toEqual(2)
		end)

		suite:case("produces a byte-identical report on a warm pool", function(check)
			local plan = planOf("warm", { PASSING, SECOND })
			local pool = poolAt("warm", { size = 1 })
			local cold = Verify.execute(plan, pool, { batchCount = 2, parallel = 1 })
			local warm = Verify.execute(plan, pool, { batchCount = 2, parallel = 1 })
			pool:close()
			check:expect((Verify.canonical(warm.report))):toEqual(Verify.canonical(cold.report))
		end)

		suite:case("starts one process per worker and not one per batch", function(check)
			local plan = planOf("amortized", { PASSING, SECOND })
			local pool = poolAt("amortized", { size = 2 })
			Verify.execute(plan, pool, { batchCount = 8, parallel = 2 })
			local statistics = pool:statistics()
			pool:close()

			check:expect(statistics.started):toEqual(2)
			check:expect(statistics.restarted):toEqual(0)
			check:expect(statistics.faults):toEqual(0)
			check:expect(statistics.batches):toEqual(2)
		end)
	end)

	suite:suite("worker pool failure injection", function()
		suite:case("names a worker that died mid-batch instead of waiting for it", function(check)
			local plan = planOf("death", { DIES })
			local pool = poolAt("death", { size = 1 })
			local execution = Verify.execute(plan, pool, { batchCount = 1, parallel = 1 })
			pool:close()

			check:expect(execution.attempts[1].status):toEqual "faulted"
			check:expect((attemptDetail(execution))):toContain "exited without answering"

			check:expect(table.find(factCodes(execution), "batch-not-returned") ~= nil):toEqual(true)
			check:expect(execution.report.failed):toEqual(1)
		end)

		suite:case("replaces a poisoned worker rather than trusting it again", function(check)
			local plan = planOf("recycle", { DIES, PASSING })
			local pool = poolAt("recycle", { size = 1, maxRestarts = 2 })
			local execution = Verify.execute(plan, pool, { batchCount = 2, parallel = 1 })
			local statistics = pool:statistics()
			pool:close()

			check:expect(statistics.restarted >= 1):toEqual(true)

			check:expect(statistics.faults >= 1):toEqual(true)
			check:expect(execution.report.passed):toEqual(1)
			check:expect(execution.report.failed):toEqual(1)
		end)

		suite:case("faults the rest of the run when the pool is exhausted", function(check)
			local plan = planOf("exhausted", { DIES, PASSING, SECOND })
			local pool = poolAt("exhausted", { size = 1, maxRestarts = 0 })
			local execution = Verify.execute(plan, pool, { batchCount = 3, parallel = 1 })
			pool:close()

			check:expect(execution.report.failed):toEqual(3)
			local sawExhaustion = false
			for _, attempt in execution.attempts do
				if
					attempt.detail ~= nil
					and string.find(attempt.detail :: string, "no usable worker", 1, true) ~= nil
				then
					sawExhaustion = true
				end
			end
			check:expect(sawExhaustion):toEqual(true)
		end)

		suite:case("abandons a worker that will not answer in time", function(check)
			local plan = planOf("hang", { HANGS })
			local pool = poolAt("hang", { size = 1, batchTimeoutSeconds = 0.05 })
			local execution = Verify.execute(plan, pool, { batchCount = 1, parallel = 1 })
			pool:close()

			check:expect(execution.attempts[1].status):toEqual "faulted"
			check:expect((attemptDetail(execution))):toContain "did not answer"
			check:expect(execution.report.failed):toEqual(1)
		end)

		suite:case("refuses to be created without a worker to start", function(check)
			check
				:expect((pcall(function()
					(Lute.pool :: any) {}
				end)))
				:toEqual(false)
			check
				:expect((pcall(function()
					(Lute.pool :: any) { worker = "" }
				end)))
				:toEqual(false)
		end)

		suite:case("closes idempotently and answers nothing afterwards", function(check)
			local pool = poolAt("closed", { size = 1 })
			pool:close()
			pool:close()
			local outcome = pool.runBatch { id = "after-close", index = 1, units = {} }
			check:expect(outcome.status):toEqual "faulted"
		end)
	end)
end
