--!strict

local Verify = require "../src/core"
local Benchmark = require "../src/benchmark"

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
				timeline.now += durations[index] / 1000
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

return function(suite: Verify.Harness)
	suite:suite("benchmark execution", function()
		suite:case("measures a real workload with the system clock and reports raw samples", function(check)
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
			check:expect(report.results[1].status):toEqual "passed"
			local measurement = assert(report.results[1].evidence).measurements[1]
			check:expect(#measurement.input.samples):toEqual(5)
			check:expect(measurement.input.unit):toEqual "milliseconds"
			check:expect(measurement.evaluation.status):toEqual "passed"
			check:expect(total > 0):toEqual(true)
		end)

		suite:case("warms up, samples exactly as declared and never retries", function(check)
			local timeline = { now = 0, calls = 0 }
			local result = Benchmark.run(spec(timeline, steady()))
			check:expect(timeline.calls):toEqual(10)
			check:expect(result.warmupRuns):toEqual(2)
			check:expect(rounded(result.samples)):toEqual { 2, 2, 2, 2, 2, 2, 2, 2 }
			check:expect(#result.invalid):toEqual(0)
			check:expect(result.summary.p50):toBeCloseTo(2, 1e-9)
		end)

		suite:case("passes within budget and fails over it, keeping the samples either way", function(check)
			local within = execute(spec({ now = 0, calls = 0 }, steady()))
			check:expect(within.results[1].status):toEqual "passed"
			local over = execute(spec({ now = 0, calls = 0 }, { 20, 20, 20, 20 }))
			check:expect(over.results[1].status):toEqual "failed"
			local evidence = assert(over.results[1].evidence)
			check:expect(rounded(evidence.measurements[1].input.samples)):toEqual { 20, 20, 20, 20 }
			check:expect(evidence.measurements[1].evaluation.reason):toEqual "limit_exceeded"
		end)

		suite:case("reports an unstable run as unsupported rather than passing or retrying", function(check)
			local timeline = { now = 0, calls = 0 }
			local report = execute(spec(timeline, { 1, 1, 1, 1, 1, 1, 9, 9 }, { maxSpread = 0.5 }))
			local result = report.results[1]
			check:expect(result.status):toEqual "unsupported"
			check:expect(result.missingCapabilities):toEqual { "measurement:unstable" }
			check:expect(timeline.calls):toEqual(10)
			local evidence = assert(result.evidence)
			check:expect(rounded(evidence.measurements[1].input.samples)):toEqual { 1, 1, 1, 1, 1, 1, 9, 9 }
		end)

		suite:case("does not run in an unaccepted environment", function(check)
			local timeline = { now = 0, calls = 0 }
			local report =
				execute(spec(timeline, steady(), { environment = { observed = "ci-shared", accepted = { "lab-a" } } }))
			check:expect(report.results[1].status):toEqual "unsupported"
			check:expect(report.results[1].missingCapabilities):toEqual { "measurement:environment_mismatch" }
			check:expect(timeline.calls):toEqual(0)
		end)

		suite:case("refuses a baseline of another identity, environment or unit", function(check)
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
			check:expect(wrongIdentity.invalid[1].reason):toEqual "baseline_mismatch"
			check:expect(#wrongIdentity.samples):toEqual(0)
			local elsewhere = table.clone(baseline)
			elsewhere.environment = "laptop"
			local wrongEnvironment = execute(spec({ now = 0, calls = 0 }, steady(), { baseline = elsewhere }))
			check:expect(wrongEnvironment.results[1].status):toEqual "unsupported"
			check:expect(wrongEnvironment.results[1].missingCapabilities):toEqual { "measurement:baseline_mismatch" }
			local otherUnit = table.clone(baseline)
			otherUnit.unit = "seconds"
			local wrongUnit = Benchmark.run(spec({ now = 0, calls = 0 }, steady(), { baseline = otherUnit }))
			check:expect(wrongUnit.invalid[1].detail):toContain "unit"
		end)

		suite:case("compares against a matching baseline and fails a regression", function(check)
			local baseline: Benchmark.Baseline = {
				identity = "run-7",
				environment = "lab-a",
				unit = "milliseconds",
				metric = "p50",
				value = 2,
				tolerance = 0.25,
			}
			local good = execute(
				spec({ now = 0, calls = 0 }, steady(), { baseline = baseline, acceptedBaselines = { "run-7" } })
			)
			check:expect(good.results[1].status):toEqual "passed"
			local slow = execute(
				spec(
					{ now = 0, calls = 0 },
					{ 4, 4, 4, 4, 4, 4, 4, 4 },
					{ baseline = baseline, acceptedBaselines = { "run-7" } }
				)
			)
			check:expect(slow.results[1].status):toEqual "failed"
			check:expect(slow.results[1].failures[1].message):toContain "exceeds the baseline"
			local comparison = Benchmark.run(
				spec({ now = 0, calls = 0 }, { 4, 4, 4, 4, 4, 4, 4, 4 }, { baseline = baseline })
			).comparison
			check:expect(comparison ~= nil and comparison.regressed):toEqual(true)
			check:expect(comparison ~= nil and comparison.limit):toBeCloseTo(2.5, 1e-9)
		end)

		suite:case("detects an unsteady CPU yardstick before and after sampling", function(check)
			local calls = 0
			local timeline = { now = 0, calls = 0 }
			local yardstickDurations = { 1, 1, 1, 3, 3, 3 }
			local drifting = spec(timeline, steady(), {
				yardstick = {
					run = function()
						calls += 1
						timeline.now += yardstickDurations[calls] / 1000
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
			check:expect(reasons):toContain "yardstick_drift"
			check:expect(rounded(result.yardstickBefore)):toEqual { 1, 1, 1 }
			check:expect(rounded(result.yardstickAfter)):toEqual { 3, 3, 3 }
			check:expect(#result.samples):toEqual(8)
		end)

		suite:case("accepts a steady yardstick", function(check)
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
			check:expect(#result.invalid):toEqual(0)
		end)

		suite:case("stops at its deadline and reports too few samples", function(check)
			local timeline = { now = 0, calls = 0 }
			local report =
				execute(spec(timeline, { 600, 600, 600, 600 }, { deadlineSeconds = 1, budget = { p95 = 2000 } }))
			local result = report.results[1]
			check:expect(result.status):toEqual "unsupported"
			local evidence = assert(result.evidence)
			check:expect(#evidence.measurements[1].input.samples < 4):toEqual(true)
			check:expect(table.find(result.missingCapabilities, "measurement:deadline_exceeded")):toBeTruthy()
		end)

		suite:case("fails when the workload raises and when the clock misbehaves", function(check)
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
			check:expect(raising.results[1].status):toEqual "failed"
			check:expect(raising.results[1].failures[1].message):toContain "workload broke"
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
			check:expect(backwards.failure):toContain "invalid"
		end)

		suite:case("rejects a malformed specification", function(check)
			local base = spec({ now = 0, calls = 0 }, steady())
			local noSamples = table.clone(base)
			noSamples.samples = 0
			check
				:expect(function()
					Benchmark.run(noSamples)
				end)
				:toThrow "samples"
			local noEnvironment = table.clone(base)
			noEnvironment.environment = { observed = " " }
			check
				:expect(function()
					Benchmark.run(noEnvironment)
				end)
				:toThrow "environment"
		end)
	end)

	suite:suite("benchmark measurement without a budget", function()
		suite:case(
			"measures without a budget, reports it as measured only and compares samples to a recorded baseline",
			function(check)
				local unbudgeted = spec({ now = 0, calls = 0 }, steady())
				unbudgeted.budget = nil
				local report = execute(unbudgeted)
				check:expect(report.results[1].status):toEqual "passed"
				check:expect(report.results[1].limitations):toEqual { "measured only: no budget declared" }
				local measurement = assert(report.results[1].evidence).measurements[1]
				check:expect(measurement.evaluation.reason):toEqual "measured"
				check:expect(measurement.evaluation.summary.total):toBeCloseTo(16, 1e-9)
				check:expect(measurement.evaluation.summary.deviation):toBeCloseTo(0, 1e-9)
				local decoded = Verify.decode(report)
				check:expect(decoded.results[1].evidence ~= nil):toEqual(true)
				local recorded: Benchmark.Baseline = {
					identity = "run-7",
					environment = "lab-a",
					unit = "milliseconds",
					metric = "p50",
					samples = { 2, 2, 2, 2 },
					tolerance = 0.25,
				}
				local good = Benchmark.run(spec({ now = 0, calls = 0 }, steady(), { baseline = recorded }))
				check:expect(assert(good.comparison).baseline):toBeCloseTo(2, 1e-9)
				check:expect(assert(good.comparison).regressed):toEqual(false)
				local slow =
					Benchmark.run(spec({ now = 0, calls = 0 }, { 4, 4, 4, 4, 4, 4, 4, 4 }, { baseline = recorded }))
				check:expect(assert(slow.comparison).regressed):toEqual(true)
				local both = table.clone(recorded)
				both.value = 2
				check
					:expect(function()
						Benchmark.run(spec({ now = 0, calls = 0 }, steady(), { baseline = both }))
					end)
					:toThrow "either a value or recorded samples"
				local deviating = Benchmark.run(spec({ now = 0, calls = 0 }, { 1, 3, 1, 3, 1, 3, 1, 3 }))
				check:expect(deviating.summary.deviation):toBeCloseTo(1, 1e-9)
			end
		)
	end)

	suite:suite("benchmark collections, normalization, judgment, hooks and heap", function()
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

		suite:case("checks one yardstick before and after the whole collection", function(check)
			local steadyTimeline = { now = 0, calls = 0 }
			local passed = executeCollection(collection(steadyTimeline, { 1, 1, 1, 1 }, 0.2))
			check:expect(passed.results[1].status):toEqual "passed"
			check:expect(#assert(passed.results[1].evidence).measurements):toEqual(2)
			local drifting = { now = 0, calls = 0 }
			local report = executeCollection(collection(drifting, { 1, 1, 3, 3 }, 0.2))
			check:expect(report.results[1].status):toEqual "unsupported"
			check:expect(report.results[1].missingCapabilities):toEqual { "measurement:yardstick_drift" }
			check:expect(#assert(report.results[1].evidence).measurements):toEqual(2)
			local raw = Benchmark.collect(collection({ now = 0, calls = 0 }, { 1, 1, 3, 3 }, 0.2))
			check:expect(rounded(raw.yardstickBefore)):toEqual { 1, 1 }
			check:expect(rounded(raw.yardstickAfter)):toEqual { 3, 3 }
			check:expect(#raw.results):toEqual(2)
		end)

		suite:case(
			"gives collection members the collection yardstick for judgment and normalized baselines",
			function(check)
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
				check:expect(order):toEqual { "judge", "collected" }
				local view = assert(seen)
				check:expect(rounded(view.yardstickBefore)):toEqual { 1, 1 }
				check:expect(rounded(view.yardstickAfter)):toEqual { 2, 2 }
				check:expect(assert(view.yardstickBeforeSummary.p50)):toBeCloseTo(1, 1e-9)
				check:expect(assert(view.yardstickAfterSummary.p50)):toBeCloseTo(2, 1e-9)
				check:expect(#view.samples):toEqual(4)
				local comparison = assert(raw.results[1].comparison)
				check:expect(comparison.normalized):toEqual(true)
				check:expect(comparison.observed):toBeCloseTo(2, 1e-9)
				check:expect(comparison.regressed):toEqual(false)
				local second = assert(raw.results[2].comparison)
				check:expect(second.regressed):toEqual(true)
				local report = executeCollection(collection({ now = 0, calls = 0 }, { 1, 1, 1, 1 }, 5))
				check:expect(report.results[1].status):toEqual "passed"
			end
		)

		suite:case(
			"skips member judgment when the collection yardstick drifted and fails a judged refusal",
			function(check)
				local judged = 0
				local drifting = collection({ now = 0, calls = 0 }, { 1, 1, 3, 3 }, 0.2)
				drifting.benchmarks[1].judge = function()
					judged += 1
					return nil
				end
				local report = executeCollection(drifting)
				check:expect(report.results[1].status):toEqual "unsupported"
				check:expect(judged):toEqual(0)
				local refusing = collection({ now = 0, calls = 0 }, { 1, 1, 1, 1 }, 5)
				refusing.benchmarks[2].judge = function(view)
					return if #view.yardstickAfter == 2 then "own rule refused" else nil
				end
				local refused = executeCollection(refusing)
				check:expect(refused.results[1].status):toEqual "failed"
				check:expect(refused.results[1].failures[1].message):toContain "own rule refused"
			end
		)

		suite:case("refuses a member that owns a yardstick and an empty collection", function(check)
			local timeline = { now = 0, calls = 0 }
			local owned = collection(timeline, { 1, 1, 1, 1 }, 0.2)
			owned.benchmarks[1].yardstick = owned.yardstick
			check
				:expect(function()
					Benchmark.collect(owned)
				end)
				:toThrow "owns the yardstick"
			local empty = collection(timeline, { 1, 1, 1, 1 }, 0.2)
			empty.benchmarks = {}
			check
				:expect(function()
					Benchmark.collect(empty)
				end)
				:toThrow "at least one benchmark"
		end)

		suite:case(
			"compares against a baseline from another machine when both are yardstick-normalized",
			function(check)
				local function normalized(
					milliseconds: number,
					yardstick: number,
					baselineYardstick: number
				): Benchmark.Spec
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
				check:expect(#slowerMachine.invalid):toEqual(0)
				local held = assert(slowerMachine.comparison)
				check:expect(held.normalized):toEqual(true)
				check:expect(held.regressed):toEqual(false)
				check:expect(held.observed):toBeCloseTo(2, 1e-9)
				local regressed = execute(normalized(8, 2, 1))
				check:expect(regressed.results[1].status):toEqual "failed"
				check:expect(regressed.results[1].failures[1].message):toContain "yardstick-normalized baseline"
				local unnormalized = normalized(4, 2, 1)
				assert(unnormalized.baseline).yardstick = nil
				check:expect(Benchmark.run(unnormalized).invalid[1].reason):toEqual "baseline_mismatch"
				local lacking = normalized(4, 2, 1)
				lacking.yardstick = nil
				check
					:expect(function()
						Benchmark.run(lacking)
					end)
					:toThrow "declare a yardstick"
			end
		)

		suite:case("normalizes by the declared yardstick statistic and holds results under a floor", function(check)
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
			check:expect(assert(byMedian.comparison).observed):toBeCloseTo(10, 1e-9)
			check:expect(assert(byMedian.comparison).regressed):toEqual(true)
			local byTail = measured(10, { 1, 1, 1, 5 })
			assert(byTail.baseline).yardstickStatistic = "p95"
			local tail = assert(Benchmark.run(byTail).comparison)
			check:expect(tail.observed):toBeCloseTo(2, 1e-9)
			check:expect(tail.regressed):toEqual(false)
			check:expect(tail.floored):toEqual(false)

			local quiet = measured(8, { 1, 1 })
			assert(quiet.baseline).floor = { limit = 10 }
			local held = assert(Benchmark.run(quiet).comparison)
			check:expect(held.observed > held.limit):toEqual(true)
			check:expect(held.floored):toEqual(true)
			check:expect(held.regressed):toEqual(false)
			local loud = measured(8, { 1, 1 })
			assert(loud.baseline).floor = { limit = 5 }
			local raised = assert(Benchmark.run(loud).comparison)
			check:expect(raised.floored):toEqual(false)
			check:expect(raised.regressed):toEqual(true)
			local recorded = measured(8, { 1, 1 })
			assert(recorded.baseline).floor = { limit = 10, metric = "p95", recorded = 12 }
			check:expect(assert(Benchmark.run(recorded).comparison).regressed):toEqual(true)

			local undeclared = measured(8, { 1, 1 })
			assert(undeclared.baseline).floor = { limit = 10, metric = "p95" }
			check
				:expect(function()
					Benchmark.run(undeclared)
				end)
				:toThrow "baseline.floor needs recorded"
			local orphan = measured(8, { 1, 1 })
			assert(orphan.baseline).yardstick = nil
			assert(orphan.baseline).yardstickStatistic = "p95"
			check
				:expect(function()
					Benchmark.run(orphan)
				end)
				:toThrow "yardstickStatistic needs baseline.yardstick"
		end)

		suite:case("applies a caller-defined judgment to the raw samples after the budget", function(check)
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
			check:expect(accepted.results[1].status):toEqual "passed"
			check:expect(seen):toEqual(4)
			local refused = execute(judged(function(view)
				local peak = 0
				for _, sample in view.samples do
					peak = math.max(peak, sample)
				end
				return if peak > 5 then ("a sample reached %g"):format(peak) else nil
			end))
			check:expect(refused.results[1].status):toEqual "failed"
			check:expect(refused.results[1].failures[1].message):toContain "refused by its judge: a sample reached 9"
			local raising = execute(judged(function()
				error "judge broke"
			end))
			check:expect(raising.results[1].status):toEqual "failed"
			check:expect(raising.results[1].failures[1].message):toContain "judge raised"
			local skipped = 0
			local unstable = spec({ now = 0, calls = 0 }, { 1, 1, 1, 1, 1, 1, 9, 9 }, { maxSpread = 0.5 })
			unstable.judge = function()
				skipped += 1
				return nil
			end
			check:expect(execute(unstable).results[1].status):toEqual "unsupported"
			check:expect(skipped):toEqual(0)
		end)

		suite:case("runs setup, per-sample hooks and teardown around the workload, untimed", function(check)
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
			check:expect(order):toEqual { "setup", "before", "after", "before", "after", "before", "after", "teardown" }
			check:expect(#result.samples):toEqual(3)
			check:expect(result.summary.maximum):toBeLessThan(1e6)
		end)

		suite:case("tears down after a failure and reports setup and teardown failures", function(check)
			local torn = 0
			local timeline = { now = 0, calls = 0 }
			local raising = spec(timeline, { 1, 1 })
			raising.workload = function()
				error "workload broke"
			end
			raising.teardown = function()
				torn += 1
			end
			check:expect(Benchmark.run(raising).failure):toContain "workload broke"
			check:expect(torn):toEqual(1)
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
			check:expect(outcome.results[1].status):toEqual "failed"
			check:expect(outcome.results[1].failures[1].message):toContain "setup raised: "
			check:expect(ran):toEqual(0)
			check:expect(torn):toEqual(2)
			local failingTeardown = spec({ now = 0, calls = 0 }, { 1, 1 })
			failingTeardown.teardown = function()
				error "scene stuck"
			end
			check:expect(Benchmark.run(failingTeardown).failure):toContain "teardown raised"
		end)

		suite:case("checkpoints the heap through an injected probe", function(check)
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
			check:expect(within.heap):toEqual { before = 100, after = 120, growth = 20, unit = "kilobytes" }
			check:expect(execute(withHeap({ 100, 120 }, 50)).results[1].status):toEqual "passed"
			local grew = execute(withHeap({ 100, 400 }, 50))
			check:expect(grew.results[1].status):toEqual "failed"
			check:expect(grew.results[1].failures[1].message):toContain "heap grew 300 kilobytes"
			local unsupported = execute(withHeap({}, nil))
			check:expect(unsupported.results[1].status):toEqual "unsupported"
			check:expect(unsupported.results[1].missingCapabilities):toEqual { "measurement:heap_unsupported" }
			local lateLoss = execute(withHeap({ 100 }, nil))
			check:expect(lateLoss.results[1].missingCapabilities):toEqual { "measurement:heap_unsupported" }
			local reading = Benchmark.luauHeap.probe()
			check:expect(reading == nil or reading > 0):toEqual(true)
		end)
	end)
end
