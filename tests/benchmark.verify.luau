--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Verify = require "../src/core"
local Benchmark = require "../src/benchmark"
local Gate = require "../src/gate"

type Timeline = {
	now: number,
	calls: number,
}

type Extra = {
	maxSpread: number?,
	environment: { observed: string, accepted: { string }? }?,
	baseline: Benchmark.Baseline?,
	acceptedBaselines: { string }?,
	yardstick: Benchmark.Yardstick?,
	deadlineSeconds: number?,
	budget: { p50: number?, p95: number?, p99: number?, maximum: number? }?,
}

local function spec(timeline: Timeline, durations: { number }, extra: Extra?): Benchmark.Spec
	local more: Extra = extra or {}
	local index = 0
	local result: Benchmark.Spec = {
		name = "workload",
		unit = "milliseconds",
		warmup = 2,
		samples = #durations,
		workload = function()
			timeline.calls += 1
			if timeline.calls > 2 then
				index += 1
				timeline.now += durations[(index - 1) % #durations + 1] / 1000
			end
		end,
		budget = { p95 = 10 },
		environment = { observed = "lab-a", accepted = { "lab-a" } },
		clock = function()
			return timeline.now
		end,
		maxSpread = more.maxSpread,
		baseline = more.baseline,
		acceptedBaselines = more.acceptedBaselines,
		yardstick = more.yardstick,
		deadlineSeconds = more.deadlineSeconds,
	}
	if more.environment ~= nil then
		result.environment = more.environment
	end
	if more.budget ~= nil then
		result.budget = more.budget
	end
	return result
end

local function execute(benchmark: Benchmark.Spec): Verify.Report
	local harness = Verify.createHarness {
		now = function()
			return 0
		end,
	}
	harness:case("bench", Benchmark.case(benchmark))
	return harness:run { executor = "bench-test" }
end

local function rounded(values: { number }): { number }
	local result: { number } = {}
	for _, value in values do
		table.insert(result, math.floor(value * 1000 + 0.5) / 1000)
	end
	return result
end

local function steady(): { number }
	return { 2, 2, 2, 2, 2, 2, 2, 2 }
end

describe("benchmark execution", function()
	it("measures a real workload with the system clock and reports raw samples", function()
		local total = 0
		local report = execute {
			name = "sum",
			unit = "milliseconds",
			warmup = 2,
			samples = 5,
			iterations = 50,
			workload = function()
				for value = 1, 200 do
					total += value
				end
			end,
			budget = { maximum = 5000 },
			environment = { observed = "any" },
		}
		expect(report.results[1].status):toEqual "passed"
		local measurement = assert(report.results[1].evidence).measurements[1]
		expect(#measurement.input.samples):toEqual(5)
		expect(measurement.input.unit):toEqual "milliseconds"
		expect(measurement.evaluation.status):toEqual "passed"
		expect(total > 0):toEqual(true)
	end)

	it("warms up, samples exactly as declared and never retries", function()
		local timeline = { now = 0, calls = 0 }
		local result = Benchmark.run(spec(timeline, steady()))
		expect(timeline.calls):toEqual(10)
		expect(result.warmupRuns):toEqual(2)
		expect(rounded(result.samples)):toEqual { 2, 2, 2, 2, 2, 2, 2, 2 }
		expect(#result.invalid):toEqual(0)
		expect(result.summary.p50):toBeCloseTo(2, 1e-9)
	end)

	it("passes within budget and fails over it, keeping the samples either way", function()
		local within = execute(spec({ now = 0, calls = 0 }, steady()))
		expect(within.results[1].status):toEqual "passed"
		local over = execute(spec({ now = 0, calls = 0 }, { 20, 20, 20, 20 }))
		expect(over.results[1].status):toEqual "failed"
		local evidence = assert(over.results[1].evidence)
		expect(rounded(evidence.measurements[1].input.samples)):toEqual { 20, 20, 20, 20 }
		expect(evidence.measurements[1].evaluation.reason):toEqual "limit_exceeded"
	end)

	it("reports an unstable run as unsupported rather than passing or retrying", function()
		local timeline = { now = 0, calls = 0 }
		local report = execute(spec(timeline, { 1, 1, 1, 1, 1, 1, 9, 9 }, { maxSpread = 0.5 }))
		local result = report.results[1]
		expect(result.status):toEqual "unsupported"
		expect(result.missingCapabilities):toEqual { "measurement:unstable" }
		expect(timeline.calls):toEqual(10)
		local evidence = assert(result.evidence)
		expect(rounded(evidence.measurements[1].input.samples)):toEqual { 1, 1, 1, 1, 1, 1, 9, 9 }
	end)

	it("does not run in an unaccepted environment", function()
		local timeline = { now = 0, calls = 0 }
		local report =
			execute(spec(timeline, steady(), { environment = { observed = "ci-shared", accepted = { "lab-a" } } }))
		expect(report.results[1].status):toEqual "unsupported"
		expect(report.results[1].missingCapabilities):toEqual { "measurement:environment_mismatch" }
		expect(timeline.calls):toEqual(0)
	end)

	it("refuses a baseline of another identity, environment or unit", function()
		local baseline: Benchmark.Baseline = {
			identity = "run-7",
			environment = "lab-a",
			unit = "milliseconds",
			metric = "p50",
			value = 2,
			tolerance = 0.1,
		}
		local wrongIdentity = Benchmark.run(
			spec({ now = 0, calls = 0 }, steady(), { baseline = baseline, acceptedBaselines = { "run-9" } })
		)
		expect(wrongIdentity.invalid[1].reason):toEqual "baseline_mismatch"
		expect(#wrongIdentity.samples):toEqual(0)
		local elsewhere = table.clone(baseline)
		elsewhere.environment = "laptop"
		local wrongEnvironment = execute(spec({ now = 0, calls = 0 }, steady(), { baseline = elsewhere }))
		expect(wrongEnvironment.results[1].status):toEqual "unsupported"
		expect(wrongEnvironment.results[1].missingCapabilities):toEqual { "measurement:baseline_mismatch" }
		local otherUnit = table.clone(baseline)
		otherUnit.unit = "seconds"
		local wrongUnit = Benchmark.run(spec({ now = 0, calls = 0 }, steady(), { baseline = otherUnit }))
		expect(wrongUnit.invalid[1].detail):toContain "unit"
	end)

	it("compares against a matching baseline and fails a regression", function()
		local baseline: Benchmark.Baseline = {
			identity = "run-7",
			environment = "lab-a",
			unit = "milliseconds",
			metric = "p50",
			value = 2,
			tolerance = 0.25,
		}
		local good =
			execute(spec({ now = 0, calls = 0 }, steady(), { baseline = baseline, acceptedBaselines = { "run-7" } }))
		expect(good.results[1].status):toEqual "passed"
		local slow = execute(
			spec(
				{ now = 0, calls = 0 },
				{ 4, 4, 4, 4, 4, 4, 4, 4 },
				{ baseline = baseline, acceptedBaselines = { "run-7" } }
			)
		)
		expect(slow.results[1].status):toEqual "failed"
		expect(slow.results[1].failures[1].message):toContain "exceeds the baseline"
		local comparison =
			Benchmark.run(spec({ now = 0, calls = 0 }, { 4, 4, 4, 4, 4, 4, 4, 4 }, { baseline = baseline })).comparison
		expect(comparison ~= nil and comparison.regressed):toEqual(true)
		expect(comparison ~= nil and comparison.limit):toBeCloseTo(2.5, 1e-9)
	end)

	local function retrySpec(durations: { number }): Benchmark.Spec
		local timeline = { now = 0, calls = 0 }
		local calls = 0
		return spec(timeline, steady(), {
			yardstick = {
				run = function()
					calls += 1
					timeline.now += durations[(calls - 1) % #durations + 1] / 1000
				end,
				samples = 1,
				maxSpread = 0.5,
				maxDrift = 0.2,
			},
		})
	end

	it("remeasures one drifted timing with fresh calibration and two attempts", function()
		local benchmark = retrySpec { 1, 3, 2, 2 }
		local setups = 0
		local teardowns = 0
		local judgments = 0
		benchmark.setup = function()
			setups += 1
		end
		benchmark.teardown = function()
			teardowns += 1
		end
		benchmark.judge = function()
			judgments += 1
			return nil
		end
		local result = Benchmark.run(benchmark)
		expect(result.attempts):toEqual(2)
		expect(#result.invalid):toEqual(0)
		expect(result.failure):toBeNil()
		expect(rounded(result.samples)):toEqual(steady())
		expect(rounded(result.yardstickBefore)):toEqual { 2 }
		expect(rounded(result.yardstickAfter)):toEqual { 2 }
		expect(setups):toEqual(1)
		expect(teardowns):toEqual(1)
		expect(judgments):toEqual(1)
		local measured = retrySpec { 1, 3, 2, 2 }
		measured.budget = nil
		local report = execute(measured)
		expect(report.results[1].status):toEqual "passed"
		expect(report.results[1].steps[1].name):toEqual "benchmark workload attempts: 2"
		expect(assert(report.results[1].evidence).measurements[1].evaluation.reason):toEqual "measured"
	end)

	it("reports persistent timing drift as unsupported after three attempts", function()
		local result = Benchmark.run(retrySpec { 1, 3 })
		expect(result.attempts):toEqual(3)
		expect(result.failure):toBeNil()
		local reasons: { string } = {}
		for _, issue in result.invalid do
			table.insert(reasons, issue.reason)
		end
		expect(reasons):toContain "yardstick_drift"
		local report = execute(retrySpec { 1, 3 })
		expect(report.results[1].status):toEqual "unsupported"
		expect(report.results[1].steps[1].name):toEqual "benchmark workload attempts: 3"
		expect(report.results[1].missingCapabilities):toContain "measurement:yardstick_drift"
	end)

	it("measures a timing without drift in one attempt", function()
		local result = Benchmark.run(retrySpec { 1, 1 })
		expect(result.attempts):toEqual(1)
		expect(#result.invalid):toEqual(0)
		expect(result.failure):toBeNil()
		local report = execute(retrySpec { 1, 1 })
		expect(report.results[1].status):toEqual "passed"
		expect(report.results[1].steps[1].name):toEqual "benchmark workload attempts: 1"
	end)

	it("keeps timing failures, budgets and the original deadline across retries", function()
		local broken = retrySpec { 1, 3 }
		broken.workload = function()
			error "broken workload"
		end
		expect(Benchmark.run(broken).attempts):toEqual(1)
		local slow = retrySpec { 1, 1 }
		slow.budget = { p95 = 1 }
		expect(Benchmark.run(slow).attempts):toEqual(1)
		expect(execute(slow).results[1].status):toEqual "failed"
		local retriedSlow = retrySpec { 1, 3, 2, 2 }
		retriedSlow.budget = { p95 = 1 }
		expect(execute(retriedSlow).results[1].status):toEqual "failed"
		local limited = retrySpec { 1, 3 }
		limited.deadlineSeconds = 0.025
		local result = Benchmark.run(limited)
		expect(result.attempts):toEqual(2)
		expect(result.invalid[1].reason):toEqual "deadline_exceeded"
		expect(#result.samples < limited.samples):toEqual(true)
	end)

	it("detects an unsteady CPU yardstick before and after sampling", function()
		local calls = 0
		local timeline = { now = 0, calls = 0 }
		local yardstickDurations = { 1, 1, 1, 3, 3, 3 }
		local drifting = spec(timeline, steady(), {
			yardstick = {
				run = function()
					calls += 1
					timeline.now += yardstickDurations[(calls - 1) % #yardstickDurations + 1] / 1000
				end,
				samples = 3,
				maxSpread = 0.5,
				maxDrift = 0.2,
			},
		})
		local result = Benchmark.run(drifting)
		local reasons: { string } = {}
		for _, entry in result.invalid do
			table.insert(reasons, entry.reason)
		end
		expect(reasons):toContain "yardstick_drift"
		expect(rounded(result.yardstickBefore)):toEqual { 1, 1, 1 }
		expect(rounded(result.yardstickAfter)):toEqual { 3, 3, 3 }
		expect(#result.samples):toEqual(8)
	end)

	it("reads drift from the selected statistic and base", function()
		local function drifted(statistic: Benchmark.YardstickStatistic?, base: Benchmark.DriftBase?): boolean
			local calls = 0
			local timeline = { now = 0, calls = 0 }
			local durations = { 1, 1, 1, 2, 1, 1, 1, 3 }
			local result = Benchmark.run(spec(timeline, steady(), {
				yardstick = {
					run = function()
						calls += 1
						timeline.now += durations[(calls - 1) % #durations + 1] / 1000
					end,
					samples = 4,
					maxSpread = 5,
					maxDrift = 0.45,
					driftStatistic = statistic,
					driftBase = base,
				},
			}))
			for _, entry in result.invalid do
				if entry.reason == "yardstick_drift" then
					return true
				end
			end
			return false
		end
		expect(drifted(nil, nil)):toEqual(false)
		expect(drifted("median", "mean")):toEqual(false)
		expect(drifted("p95", nil)):toEqual(true)
		expect(drifted("p95", "first")):toEqual(true)
		expect(drifted("p95", "mean")):toEqual(false)
		expect(function()
			Benchmark.run(spec({ now = 0, calls = 0 }, steady(), {
				yardstick = {
					run = function() end,
					samples = 1,
					maxSpread = 1,
					maxDrift = 1,
					driftBase = ("last" :: unknown) :: Benchmark.DriftBase,
				},
			}))
		end):toThrow "driftBase must be first or mean"
	end)

	it("warms each endpoint and records batched time per call", function()
		local timeline = { now = 0, calls = 0 }
		local calls = 0
		local tool: Benchmark.Yardstick = {
			run = function()
				calls += 1
				timeline.now += if calls <= 6 or (calls > 18 and calls <= 24) then 0.100 else 0.002
			end,
			samples = 4,
			iterations = 3,
			warmup = 2,
			maxSpread = 0.1,
			maxDrift = 0.15,
		}
		local member = spec(timeline, steady())
		local result = Benchmark.collect {
			name = "batched",
			clock = member.clock,
			benchmarks = { member },
			yardstick = tool,
		}
		expect(calls):toBe(36)
		expect(rounded(result.yardstickBefore)):toEqual { 2, 2, 2, 2 }
		expect(rounded(result.yardstickAfter)):toEqual { 2, 2, 2, 2 }
		expect(#result.invalid):toBe(0)
	end)

	it("keeps drift rejection and workload failures with batched yardsticks", function()
		local timeline = { now = 0, calls = 0 }
		local calls = 0
		local tool: Benchmark.Yardstick = {
			run = function()
				calls += 1
				timeline.now += if (calls - 1) % 16 < 8 then 0.001 else 0.002
			end,
			samples = 4,
			iterations = 2,
			maxSpread = 100,
			maxDrift = 0.15,
		}
		local result = Benchmark.run(spec(timeline, steady(), { yardstick = tool }))
		expect(result.invalid[1].reason):toBe "yardstick_drift"
		tool.warmup = 1
		tool.run = function()
			error "warmup failed"
		end
		local failed = Benchmark.run(spec(timeline, steady(), { yardstick = tool }))
		expect(assert(failed.failure)):toContain "warmup failed"
		for _, value in { 0, -1, 1.5, math.huge } do
			tool.iterations = value
			expect(function()
				Benchmark.run(spec(timeline, steady(), { yardstick = tool }))
			end):toThrow "yardstick.iterations"
		end
		tool.iterations = 1
		for _, value in { -1, 1.5, math.huge } do
			tool.warmup = value
			expect(function()
				Benchmark.run(spec(timeline, steady(), { yardstick = tool }))
			end):toThrow "yardstick.warmup"
		end
	end)

	it("accepts a steady yardstick", function()
		local timeline = { now = 0, calls = 0 }
		local result = Benchmark.run(spec(timeline, steady(), {
			yardstick = {
				run = function()
					timeline.now += 0.001
				end,
				samples = 4,
				maxSpread = 0.2,
				maxDrift = 0.2,
			},
		}))
		expect(#result.invalid):toEqual(0)
	end)

	it("stops at its deadline and reports too few samples", function()
		local timeline = { now = 0, calls = 0 }
		local report = execute(spec(timeline, { 600, 600, 600, 600 }, { deadlineSeconds = 1, budget = { p95 = 2000 } }))
		local result = report.results[1]
		expect(result.status):toEqual "unsupported"
		local evidence = assert(result.evidence)
		expect(#evidence.measurements[1].input.samples < 4):toEqual(true)
		expect(table.find(result.missingCapabilities, "measurement:deadline_exceeded")):toBeTruthy()
	end)

	it("fails when the workload raises and when the clock misbehaves", function()
		local raising = execute {
			name = "raises",
			unit = "milliseconds",
			warmup = 0,
			samples = 3,
			workload = function()
				error "workload broke"
			end,
			budget = { p95 = 5 },
			environment = { observed = "any" },
		}
		expect(raising.results[1].status):toEqual "failed"
		expect(raising.results[1].failures[1].message):toContain "workload broke"
		local ticks = { 5, 5, 3, 3 }
		local position = 0
		local backwards = Benchmark.run {
			name = "backwards",
			unit = "milliseconds",
			warmup = 0,
			samples = 1,
			workload = function() end,
			budget = { p95 = 5 },
			environment = { observed = "any" },
			clock = function()
				position += 1
				return ticks[math.min(position, #ticks)]
			end,
		}
		expect(backwards.failure):toContain "invalid"
	end)

	it("rejects a malformed specification", function()
		local base = spec({ now = 0, calls = 0 }, steady())
		local noSamples = table.clone(base)
		noSamples.samples = 0
		expect(function()
			Benchmark.run(noSamples)
		end):toThrow "samples"
		local noEnvironment = table.clone(base)
		noEnvironment.environment = { observed = " " }
		expect(function()
			Benchmark.run(noEnvironment)
		end):toThrow "environment"
	end)
end)

describe("benchmark measurement without a budget", function()
	it("measures without a budget, reports it as measured only and compares samples to a recorded baseline", function()
		local unbudgeted = spec({ now = 0, calls = 0 }, steady())
		unbudgeted.budget = nil
		local report = execute(unbudgeted)
		expect(report.results[1].status):toEqual "passed"
		expect(report.results[1].limitations):toEqual { "measured only: no budget declared" }
		local measurement = assert(report.results[1].evidence).measurements[1]
		expect(measurement.evaluation.reason):toEqual "measured"
		expect(measurement.evaluation.summary.total):toBeCloseTo(16, 1e-9)
		expect(measurement.evaluation.summary.deviation):toBeCloseTo(0, 1e-9)
		local decoded = Verify.decode(report)
		expect(decoded.results[1].evidence ~= nil):toEqual(true)
		local recorded: Benchmark.Baseline = {
			identity = "run-7",
			environment = "lab-a",
			unit = "milliseconds",
			metric = "p50",
			samples = { 2, 2, 2, 2 },
			tolerance = 0.25,
		}
		local good = Benchmark.run(spec({ now = 0, calls = 0 }, steady(), { baseline = recorded }))
		expect(assert(good.comparison).baseline):toBeCloseTo(2, 1e-9)
		expect(assert(good.comparison).regressed):toEqual(false)
		local slow = Benchmark.run(spec({ now = 0, calls = 0 }, { 4, 4, 4, 4, 4, 4, 4, 4 }, { baseline = recorded }))
		expect(assert(slow.comparison).regressed):toEqual(true)
		local both = table.clone(recorded)
		both.value = 2
		expect(function()
			Benchmark.run(spec({ now = 0, calls = 0 }, steady(), { baseline = both }))
		end):toThrow "either a value or recorded samples"
		local deviating = Benchmark.run(spec({ now = 0, calls = 0 }, { 1, 3, 1, 3, 1, 3, 1, 3 }))
		expect(deviating.summary.deviation):toBeCloseTo(1, 1e-9)
	end)
end)

describe("benchmark collections, normalization, judgment, hooks and heap", function()
	local function member(timeline: Timeline, name: string, milliseconds: number): Benchmark.Spec
		return {
			name = name,
			unit = "milliseconds",
			warmup = 0,
			samples = 4,
			workload = function()
				timeline.now += milliseconds / 1000
			end,
			budget = { p95 = 10 },
			environment = { observed = "lab-a" },
		}
	end

	local function collection(timeline: Timeline, yardsticks: { number }, maxDrift: number): Benchmark.Collection
		local calls = 0
		return {
			name = "suite-of-two",
			yardstick = {
				run = function()
					calls += 1
					timeline.now += yardsticks[calls] / 1000
				end,
				samples = 2,
				maxSpread = 5,
				maxDrift = maxDrift,
			},
			benchmarks = { member(timeline, "first", 2), member(timeline, "second", 3) },
			clock = function()
				return timeline.now
			end,
		}
	end

	local function executeCollection(options: Benchmark.Collection): Verify.Report
		local harness = Verify.createHarness {
			now = function()
				return 0
			end,
		}
		harness:case("group", Benchmark.collection(options))
		return harness:run { executor = "bench-test" }
	end

	it("checks one yardstick before and after the whole collection", function()
		local steadyTimeline = { now = 0, calls = 0 }
		local passed = executeCollection(collection(steadyTimeline, { 1, 1, 1, 1 }, 0.2))
		expect(passed.results[1].status):toEqual "passed"
		expect(#assert(passed.results[1].evidence).measurements):toEqual(2)
		local drifting = { now = 0, calls = 0 }
		local report = executeCollection(collection(drifting, { 1, 1, 3, 3 }, 0.2))
		expect(report.results[1].status):toEqual "unsupported"
		expect(report.results[1].missingCapabilities):toEqual { "measurement:yardstick_drift" }
		expect(#assert(report.results[1].evidence).measurements):toEqual(2)
		local raw = Benchmark.collect(collection({ now = 0, calls = 0 }, { 1, 1, 3, 3 }, 0.2))
		expect(rounded(raw.yardstickBefore)):toEqual { 1, 1 }
		expect(rounded(raw.yardstickAfter)):toEqual { 3, 3 }
		expect(#raw.results):toEqual(2)
		expect(raw.attempts):toEqual(nil)
	end)

	it("retries invalid calibration once and retains both complete attempts", function()
		local timeline = { now = 0, calls = 0 }
		local group = collection(timeline, { 1, 1, 3, 3, 1, 1, 1, 1 }, 0.2)
		group.calibrationAttempts = 2
		local cleaned = 0
		group.benchmarks[1].afterSample = function()
			cleaned += 1
		end
		local raw = Benchmark.collect(group)
		local attempts = assert(raw.attempts)
		expect(#attempts):toEqual(2)
		expect(#attempts[1].invalid):toEqual(1)
		expect(rounded(attempts[1].yardstickAfter)):toEqual { 3, 3 }
		expect(rounded(attempts[1].results[1].samples)):toEqual { 2, 2, 2, 2 }
		expect(#attempts[2].invalid):toEqual(0)
		expect(#raw.invalid):toEqual(0)
		expect(cleaned):toEqual(8)
		local reported = collection({ now = 0, calls = 0 }, { 1, 1, 3, 3, 1, 1, 1, 1 }, 0.2)
		reported.calibrationAttempts = 2
		local report = executeCollection(reported)
		expect(report.results[1].status):toEqual "passed"
		local artifact = report.results[1].artifacts[1]
		expect(artifact.name):toEqual "calibration-attempts.tsv"
		expect(assert(artifact.content)):toContain "attempt\t1"
		expect(assert(artifact.content)):toContain "attempt\t2"
		expect(assert(artifact.content)):toContain "yardstick_drift"
	end)

	it("binds the calibration attempt policy into a gate definition", function()
		local function digest(attempts: number?): string
			local group = collection({ now = 0, calls = 0 }, { 1, 1, 1, 1 }, 0.2)
			group.calibrationAttempts = attempts
			return Gate.define({
				id = "calibration-policy",
				producers = { { id = "benchmark", kind = "benchmark", collection = group } },
			}).digest
		end
		expect(digest(nil)):toEqual(digest(1))
		expect(digest(1) == digest(2)):toEqual(false)
	end)

	it("a second invalid calibration remains unsupported and the attempt bound is validated", function()
		local group = collection({ now = 0, calls = 0 }, { 1, 1, 3, 3, 1, 1, 3, 3 }, 0.2)
		group.calibrationAttempts = 2
		local report = executeCollection(group)
		expect(report.results[1].status):toEqual "unsupported"
		expect(#report.results[1].artifacts):toEqual(1)
		for _, count in { 0, 3, 1.5, math.huge, math.nan } do
			local invalid = collection({ now = 0, calls = 0 }, { 1, 1, 1, 1 }, 0.2)
			invalid.calibrationAttempts = count
			expect(function()
				Benchmark.collect(invalid)
			end):toThrow "calibrationAttempts"
		end
	end)

	it("workload failures and valid budget regressions do not trigger calibration retries", function()
		local calls = 0
		local broken = collection({ now = 0, calls = 0 }, { 1, 1, 3, 3 }, 0.2)
		broken.calibrationAttempts = 2
		broken.benchmarks[1].workload = function()
			calls += 1
			error "workload failed"
		end
		local failed = Benchmark.collect(broken)
		expect(#assert(failed.attempts)):toEqual(1)
		expect(failed.results[1].failure ~= nil):toEqual(true)
		expect(calls):toEqual(1)
		local slow = collection({ now = 0, calls = 0 }, { 1, 1, 1, 1 }, 0.2)
		slow.calibrationAttempts = 2
		slow.benchmarks[1].budget = { p95 = 1 }
		local raw = Benchmark.collect(slow)
		expect(#assert(raw.attempts)):toEqual(1)
		local judged = collection({ now = 0, calls = 0 }, { 1, 1, 1, 1 }, 0.2)
		judged.calibrationAttempts = 2
		judged.benchmarks[1].budget = { p95 = 1 }
		expect(executeCollection(judged).results[1].status):toEqual "failed"
	end)

	it("gives collection members the collection yardstick for judgment and normalized baselines", function()
		local timeline = { now = 0, calls = 0 }
		local order: { string } = {}
		local seen: Benchmark.Judgment? = nil
		local group = collection(timeline, { 1, 1, 2, 2 }, 5)
		local first = group.benchmarks[1]
		first.baseline = {
			identity = "run-7",
			environment = "laptop",
			unit = "milliseconds",
			metric = "p50",
			value = 4,
			tolerance = 0.25,
			yardstick = 2,
		}
		group.benchmarks[2].baseline = {
			identity = "run-7",
			environment = "laptop",
			unit = "milliseconds",
			metric = "p50",
			value = 1,
			tolerance = 0.25,
			yardstick = 2,
		}
		first.judge = function(view)
			seen = view
			table.insert(order, "judge")
			return nil
		end
		local raw = Benchmark.collect(group)
		table.insert(order, "collected")
		expect(order):toEqual { "judge", "collected" }
		local view = assert(seen)
		expect(rounded(view.yardstickBefore)):toEqual { 1, 1 }
		expect(rounded(view.yardstickAfter)):toEqual { 2, 2 }
		expect(assert(view.yardstickBeforeSummary.p50)):toBeCloseTo(1, 1e-9)
		expect(assert(view.yardstickAfterSummary.p50)):toBeCloseTo(2, 1e-9)
		expect(#view.samples):toEqual(4)
		local comparison = assert(raw.results[1].comparison)
		expect(comparison.normalized):toEqual(true)
		expect(comparison.observed):toBeCloseTo(2, 1e-9)
		expect(comparison.regressed):toEqual(false)
		local second = assert(raw.results[2].comparison)
		expect(second.regressed):toEqual(true)
		local report = executeCollection(collection({ now = 0, calls = 0 }, { 1, 1, 1, 1 }, 5))
		expect(report.results[1].status):toEqual "passed"
	end)

	it("skips member judgment when the collection yardstick drifted and fails a judged refusal", function()
		local judged = 0
		local drifting = collection({ now = 0, calls = 0 }, { 1, 1, 3, 3 }, 0.2)
		drifting.benchmarks[1].judge = function()
			judged += 1
			return nil
		end
		local report = executeCollection(drifting)
		expect(report.results[1].status):toEqual "unsupported"
		expect(judged):toEqual(0)
		local refusing = collection({ now = 0, calls = 0 }, { 1, 1, 1, 1 }, 5)
		refusing.benchmarks[2].judge = function(view)
			return if #view.yardstickAfter == 2 then "own rule refused" else nil
		end
		local refused = executeCollection(refusing)
		expect(refused.results[1].status):toEqual "failed"
		expect(refused.results[1].failures[1].message):toContain "own rule refused"
	end)

	it("refuses a member that owns a yardstick and an empty collection", function()
		local timeline = { now = 0, calls = 0 }
		local owned = collection(timeline, { 1, 1, 1, 1 }, 0.2)
		owned.benchmarks[1].yardstick = owned.yardstick
		expect(function()
			Benchmark.collect(owned)
		end):toThrow "owns the yardstick"
		local empty = collection(timeline, { 1, 1, 1, 1 }, 0.2)
		empty.benchmarks = {}
		expect(function()
			Benchmark.collect(empty)
		end):toThrow "at least one benchmark"
	end)

	it("compares against a baseline from another machine when both are yardstick-normalized", function()
		local function normalized(milliseconds: number, yardstick: number, baselineYardstick: number): Benchmark.Spec
			local timeline = { now = 0, calls = 0 }
			local result = member(timeline, "scaled", milliseconds)
			result.clock = function()
				return timeline.now
			end
			result.environment = { observed = "lab-a" }
			result.yardstick = {
				run = function()
					timeline.now += yardstick / 1000
				end,
				samples = 2,
				maxSpread = 1,
				maxDrift = 1,
			}
			result.baseline = {
				identity = "run-7",
				environment = "laptop",
				unit = "milliseconds",
				metric = "p50",
				value = 2,
				tolerance = 0.25,
				yardstick = baselineYardstick,
			}
			return result
		end
		local slowerMachine = Benchmark.run(normalized(4, 2, 1))
		expect(#slowerMachine.invalid):toEqual(0)
		local held = assert(slowerMachine.comparison)
		expect(held.normalized):toEqual(true)
		expect(held.regressed):toEqual(false)
		expect(held.observed):toBeCloseTo(2, 1e-9)
		local regressed = execute(normalized(8, 2, 1))
		expect(regressed.results[1].status):toEqual "failed"
		expect(regressed.results[1].failures[1].message):toContain "yardstick-normalized baseline"
		local unnormalized = normalized(4, 2, 1)
		assert(unnormalized.baseline).yardstick = nil
		expect(Benchmark.run(unnormalized).invalid[1].reason):toEqual "baseline_mismatch"
		local lacking = normalized(4, 2, 1)
		lacking.yardstick = nil
		expect(function()
			Benchmark.run(lacking)
		end):toThrow "declare a yardstick"
	end)

	it("normalizes by the declared yardstick statistic and holds results under a floor", function()
		local function measured(milliseconds: number, readings: { number }): Benchmark.Spec
			local timeline = { now = 0, calls = 0 }
			local result = member(timeline, "scaled", milliseconds)
			result.clock = function()
				return timeline.now
			end
			result.environment = { observed = "lab-a" }
			local reading = 0
			result.yardstick = {
				run = function()
					reading += 1
					timeline.now += readings[(reading - 1) % #readings + 1] / 1000
				end,
				samples = #readings,
				maxSpread = 100,
				maxDrift = 100,
			}
			result.baseline = {
				identity = "run-9",
				environment = "laptop",
				unit = "milliseconds",
				metric = "p50",
				value = 2,
				tolerance = 0.25,
				yardstick = 1,
			}
			return result
		end
		local byMedian = Benchmark.run(measured(10, { 1, 1, 1, 5 }))
		expect(assert(byMedian.comparison).observed):toBeCloseTo(10, 1e-9)
		expect(assert(byMedian.comparison).regressed):toEqual(true)
		local byTail = measured(10, { 1, 1, 1, 5 })
		assert(byTail.baseline).yardstickStatistic = "p95"
		local tail = assert(Benchmark.run(byTail).comparison)
		expect(tail.observed):toBeCloseTo(2, 1e-9)
		expect(tail.regressed):toEqual(false)
		expect(tail.floored):toEqual(false)

		local quiet = measured(8, { 1, 1 })
		assert(quiet.baseline).floor = { limit = 10 }
		local held = assert(Benchmark.run(quiet).comparison)
		expect(held.observed > held.limit):toEqual(true)
		expect(held.floored):toEqual(true)
		expect(held.regressed):toEqual(false)
		local loud = measured(8, { 1, 1 })
		assert(loud.baseline).floor = { limit = 5 }
		local raised = assert(Benchmark.run(loud).comparison)
		expect(raised.floored):toEqual(false)
		expect(raised.regressed):toEqual(true)
		local recorded = measured(8, { 1, 1 })
		assert(recorded.baseline).floor = { limit = 10, metric = "p95", recorded = 12 }
		expect(assert(Benchmark.run(recorded).comparison).regressed):toEqual(true)

		local undeclared = measured(8, { 1, 1 })
		assert(undeclared.baseline).floor = { limit = 10, metric = "p95" }
		expect(function()
			Benchmark.run(undeclared)
		end):toThrow "baseline.floor needs recorded"
		local orphan = measured(8, { 1, 1 })
		assert(orphan.baseline).yardstick = nil
		assert(orphan.baseline).yardstickStatistic = "p95"
		expect(function()
			Benchmark.run(orphan)
		end):toThrow "yardstickStatistic needs baseline.yardstick"
	end)

	it("applies a caller-defined judgment to the raw samples after the budget", function()
		local function judged(judge: (view: Benchmark.Judgment) -> string?): Benchmark.Spec
			local timeline = { now = 0, calls = 0 }
			local result = spec(timeline, { 1, 1, 1, 9 })
			result.judge = judge
			return result
		end
		local seen = 0
		local accepted = execute(judged(function(view)
			seen = #view.samples
			return nil
		end))
		expect(accepted.results[1].status):toEqual "passed"
		expect(seen):toEqual(4)
		local refused = execute(judged(function(view)
			local peak = 0
			for _, sample in view.samples do
				peak = math.max(peak, sample)
			end
			return if peak > 5 then ("a sample reached %g"):format(peak) else nil
		end))
		expect(refused.results[1].status):toEqual "failed"
		expect(refused.results[1].failures[1].message):toContain "refused by its judge: a sample reached 9"
		local raising = execute(judged(function()
			error "judge broke"
		end))
		expect(raising.results[1].status):toEqual "failed"
		expect(raising.results[1].failures[1].message):toContain "judge raised"
		local skipped = 0
		local unstable = spec({ now = 0, calls = 0 }, { 1, 1, 1, 1, 1, 1, 9, 9 }, { maxSpread = 0.5 })
		unstable.judge = function()
			skipped += 1
			return nil
		end
		expect(execute(unstable).results[1].status):toEqual "unsupported"
		expect(skipped):toEqual(0)
	end)

	it("runs setup, per-sample hooks and teardown around the workload, untimed", function()
		local timeline = { now = 0, calls = 0 }
		local order: { string } = {}
		local hooked = spec(timeline, { 2, 2, 2 })
		hooked.warmup = 0
		hooked.setup = function()
			table.insert(order, "setup")
			timeline.now += 100
		end
		hooked.beforeSample = function()
			table.insert(order, "before")
			timeline.now += 50
		end
		hooked.afterSample = function()
			table.insert(order, "after")
			timeline.now += 50
		end
		hooked.teardown = function()
			table.insert(order, "teardown")
		end
		local result = Benchmark.run(hooked)
		expect(order):toEqual { "setup", "before", "after", "before", "after", "before", "after", "teardown" }
		expect(#result.samples):toEqual(3)
		expect(result.summary.maximum):toBeLessThan(1e6)
	end)

	it("tears down after a failure and reports setup and teardown failures", function()
		local torn = 0
		local timeline = { now = 0, calls = 0 }
		local raising = spec(timeline, { 1, 1 })
		raising.workload = function()
			error "workload broke"
		end
		raising.teardown = function()
			torn += 1
		end
		expect(Benchmark.run(raising).failure):toContain "workload broke"
		expect(torn):toEqual(1)
		local ran = 0
		local failingSetup = spec({ now = 0, calls = 0 }, { 1, 1 })
		failingSetup.setup = function()
			error "scene missing"
		end
		failingSetup.workload = function()
			ran += 1
		end
		failingSetup.teardown = function()
			torn += 1
		end
		local outcome = execute(failingSetup)
		expect(outcome.results[1].status):toEqual "failed"
		expect(outcome.results[1].failures[1].message):toContain "setup raised: "
		expect(ran):toEqual(0)
		expect(torn):toEqual(2)
		local failingTeardown = spec({ now = 0, calls = 0 }, { 1, 1 })
		failingTeardown.teardown = function()
			error "scene stuck"
		end
		expect(Benchmark.run(failingTeardown).failure):toContain "teardown raised"
	end)

	it("checkpoints the heap through an injected probe", function()
		local function withHeap(readings: { number? }, limit: number?): Benchmark.Spec
			local position = 0
			local result = spec({ now = 0, calls = 0 }, { 1, 1, 1, 1 })
			result.heap = {
				unit = "kilobytes",
				maximumGrowth = limit,
				probe = function(): number?
					position += 1
					return readings[position]
				end,
			}
			return result
		end
		local within = Benchmark.run(withHeap({ 100, 120 }, 50))
		expect(within.heap):toEqual { before = 100, after = 120, growth = 20, unit = "kilobytes" }
		expect(execute(withHeap({ 100, 120 }, 50)).results[1].status):toEqual "passed"
		local grew = execute(withHeap({ 100, 400 }, 50))
		expect(grew.results[1].status):toEqual "failed"
		expect(grew.results[1].failures[1].message):toContain "heap grew 300 kilobytes"
		local unsupported = execute(withHeap({}, nil))
		expect(unsupported.results[1].status):toEqual "unsupported"
		expect(unsupported.results[1].missingCapabilities):toEqual { "measurement:heap_unsupported" }
		local lateLoss = execute(withHeap({ 100 }, nil))
		expect(lateLoss.results[1].missingCapabilities):toEqual { "measurement:heap_unsupported" }
	end)
end)

return nil
