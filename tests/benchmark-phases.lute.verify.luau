--!strict

local Benchmark = require "../src/benchmark"
local Lute = require "../src/lute"
local Verify = require "../src/core"

type Timeline = { now: number }

local function timeline(): Timeline
	return { now = 0 }
end

local function clockOf(line: Timeline): () -> number
	return function()
		return line.now
	end
end

local function advance(line: Timeline, milliseconds: number)
	line.now += milliseconds / 1000
end

local function rounded(values: { number }): { number }
	local result: { number } = {}
	for _, value in values do
		table.insert(result, math.floor(value * 1000 + 0.5) / 1000)
	end
	return result
end

local function execute(spec: Benchmark.Spec): Verify.Report
	local harness = Verify.createHarness {
		now = function()
			return 0
		end,
	}
	harness:case("bench", Benchmark.case(spec))
	return harness:run { executor = "phases-test" }
end

local function failsWith(spec: Benchmark.Spec, text: string): boolean
	local ok, thrown: unknown = pcall(Benchmark.run, spec)
	return not ok and string.find(tostring(thrown), text, 1, true) ~= nil
end

local function phased(line: Timeline, durations: { { number } }, warmup: number?): Benchmark.Spec
	local skipped = if warmup ~= nil then warmup else 1
	local created = 0
	local function duration(position: number): number
		local row = durations[created - skipped]
		return if row ~= nil then row[position] else 0
	end
	local phases: { Benchmark.Phase } = {
		{
			name = "cold",
			run = function(state: unknown)
				advance(line, duration(1))
				assert(type(state) == "table")
			end,
			budget = { p95 = 10 },
		},
		{
			name = "steady",
			run = function()
				advance(line, duration(2))
			end,
			budget = { p95 = 10 },
		},
	}
	return {
		name = "scenario",
		unit = "milliseconds",
		warmup = skipped,
		warmupScope = "sample",
		samples = #durations,
		environment = { observed = "lab" },
		clock = clockOf(line),
		setup = function()
			created = 0
		end,
		beforeSample = function()
			created += 1
			return { id = created, log = {} }
		end,
		phases = phases,
	}
end

return function(suite: Verify.Harness)
	suite:suite("benchmark sample lifecycle", function()
		suite:case("warms up the workload only by default and the whole sample on request", function(check)
			local log: { string } = {}
			local function lifecycle(scope: Benchmark.WarmupScope?): Benchmark.Spec
				return {
					name = "lifecycle",
					unit = "milliseconds",
					warmup = 2,
					warmupScope = scope,
					samples = 3,
					environment = { observed = "lab" },
					beforeSample = function()
						table.insert(log, "before")
						return nil
					end,
					workload = function()
						table.insert(log, "work")
					end,
					afterSample = function()
						table.insert(log, "after")
					end,
				}
			end
			Benchmark.run(lifecycle(nil))
			check
				:expect(table.concat(log, " "))
				:toEqual "work work before work after before work after before work after"
			table.clear(log)
			Benchmark.run(lifecycle "sample")
			check:expect(#log):toEqual(15)
			check:expect(table.concat(log, " ", 1, 6)):toEqual "before work after before work after"
		end)

		suite:case("hands the per-sample state to the workload, finalize and release", function(check)
			local seen: { string } = {}
			local counter = 0
			Benchmark.run {
				name = "state",
				unit = "milliseconds",
				warmup = 1,
				warmupScope = "sample",
				samples = 2,
				environment = { observed = "lab" },
				beforeSample = function()
					counter += 1
					return counter
				end,
				workload = function(state)
					table.insert(seen, "work" .. tostring(state))
				end,
				finalize = function(state)
					table.insert(seen, "drain" .. tostring(state))
				end,
				afterSample = function(state)
					table.insert(seen, "free" .. tostring(state))
				end,
			}
			check
				:expect(seen)
				:toEqual { "work1", "drain1", "free1", "work2", "drain2", "free2", "work3", "drain3", "free3" }
		end)

		suite:case("fails when a warmup sample cannot be prepared and still releases a failed sample", function(check)
			local released = 0
			local broken = Benchmark.run {
				name = "broken warmup",
				unit = "milliseconds",
				warmup = 1,
				warmupScope = "sample",
				samples = 1,
				environment = { observed = "lab" },
				beforeSample = function()
					error "no environment"
				end,
				workload = function() end,
			}
			check:expect(broken.failure):toContain "no environment"
			check:expect(#broken.samples):toEqual(0)
			local failing = Benchmark.run {
				name = "failing sample",
				unit = "milliseconds",
				warmup = 0,
				samples = 1,
				environment = { observed = "lab" },
				beforeSample = function()
					return nil
				end,
				workload = function()
					error "workload broke"
				end,
				afterSample = function()
					released += 1
				end,
			}
			check:expect(failing.failure):toContain "workload broke"
			check:expect(released):toEqual(1)
		end)

		suite:case("times the finalize step inside the sample and leaves the release untimed", function(check)
			local line = timeline()
			local result = Benchmark.run {
				name = "drain",
				unit = "milliseconds",
				warmup = 0,
				samples = 3,
				environment = { observed = "lab" },
				clock = clockOf(line),
				workload = function()
					advance(line, 2)
				end,
				finalize = function()
					advance(line, 3)
				end,
				afterSample = function()
					advance(line, 50)
				end,
			}
			check:expect(rounded(result.samples)):toEqual { 5, 5, 5 }
			check
				:expect(failsWith({
					name = "drain",
					unit = "milliseconds",
					warmup = 0,
					samples = 1,
					iterations = 4,
					environment = { observed = "lab" },
					workload = function() end,
					finalize = function() end,
				}, "finalize needs one iteration"))
				:toEqual(true)
			local raising = Benchmark.run {
				name = "drain",
				unit = "milliseconds",
				warmup = 0,
				samples = 1,
				environment = { observed = "lab" },
				workload = function() end,
				finalize = function()
					error "drain stuck"
				end,
			}
			check:expect(raising.failure):toContain "drain stuck"
			check:expect(#raising.samples):toEqual(0)
		end)
	end)

	suite:suite("benchmark phases", function()
		suite:case("measures each phase on the per-sample state and keeps raw samples per phase", function(check)
			local line = timeline()
			local result = Benchmark.run(phased(line, { { 4, 1 }, { 6, 1 }, { 5, 2 } }))
			check:expect(rounded(result.phases[1].samples)):toEqual { 4, 6, 5 }
			check:expect(rounded(result.phases[2].samples)):toEqual { 1, 1, 2 }
			check:expect(rounded(result.samples)):toEqual { 5, 7, 7 }
			check:expect(result.phases[1].measurement):toEqual "scenario/cold"
			check:expect(result.phases[1].summary.context.signal):toEqual "scenario/cold"
			check:expect(result.phases[2].summary.p50):toBeCloseTo(1, 1e-9)
			check:expect(result.warmupRuns):toEqual(1)
		end)

		suite:case("reports one measurement per phase with its own budget in the one case", function(check)
			local line = timeline()
			local report = execute(phased(line, { { 4, 1 }, { 4, 1 }, { 4, 1 } }))
			check:expect(report.results[1].status):toEqual "passed"
			local measurements = assert(report.results[1].evidence).measurements
			check:expect(#measurements):toEqual(2)
			check:expect(measurements[1].name):toEqual "scenario/cold"
			check:expect(measurements[2].name):toEqual "scenario/steady"
			check:expect(measurements[1].limits.p95):toEqual(10)
			local over = execute(phased(timeline(), { { 40, 1 }, { 40, 1 }, { 40, 1 } }))
			check:expect(over.results[1].status):toEqual "failed"
			local evidence = assert(over.results[1].evidence)
			check:expect(evidence.measurements[1].evaluation.status):toEqual "failed"
			check:expect(evidence.measurements[2].evaluation.status):toEqual "passed"
		end)

		suite:case("reports unbudgeted phases as measured only", function(check)
			local line = timeline()
			local spec = phased(line, { { 4, 1 }, { 4, 1 } })
			local phases = assert(spec.phases)
			phases[2].budget = nil
			local options = Benchmark.case(spec)
			check:expect(options.limitations):toEqual { "measured only: no budget declared for phase steady" }
		end)

		suite:case("compares and judges each phase on its own and refuses a regression in one", function(check)
			local line = timeline()
			local spec = phased(line, { { 4, 1 }, { 4, 1 }, { 4, 1 } })
			local phases = assert(spec.phases)
			phases[1].baseline = {
				identity = "run-1",
				environment = "lab",
				unit = "milliseconds",
				metric = "p50",
				value = 2,
				tolerance = 0.5,
			}
			local judged: { string } = {}
			phases[2].judge = function(view)
				table.insert(judged, tostring(view.phase))
				return "steady phase looks wrong"
			end
			local result = Benchmark.run(spec)
			check:expect(assert(result.phases[1].comparison).regressed):toEqual(true)
			check:expect(result.phases[2].comparison):toBeNil()
			check:expect(result.phases[2].judgment):toEqual "steady phase looks wrong"
			check:expect(judged):toEqual { "steady" }
			local report = execute(spec)
			check:expect(report.results[1].status):toEqual "failed"
			local messages: { string } = {}
			for _, failure in report.results[1].failures do
				table.insert(messages, failure.message)
			end
			local joined = table.concat(messages, "\n")
			check:expect(joined):toContain "scenario/cold p50"
			check:expect(joined):toContain "scenario/steady was refused by its judge"
		end)

		suite:case("marks an unstable phase unsupported and skips its judge", function(check)
			local line = timeline()
			local spec = phased(line, { { 1, 1 }, { 1, 1 }, { 9, 1 }, { 9, 1 } })
			local phases = assert(spec.phases)
			phases[1].maxSpread = 0.5
			local called = false
			phases[1].judge = function()
				called = true
				return nil
			end
			local result = Benchmark.run(spec)
			check:expect(result.phases[1].invalid[1].reason):toEqual "unstable"
			check:expect(#result.phases[2].invalid):toEqual(0)
			check:expect(called):toEqual(false)
			local report = execute(spec)
			check:expect(report.results[1].status):toEqual "unsupported"
			check:expect(report.results[1].missingCapabilities):toEqual { "measurement:unstable" }
		end)

		suite:case("runs phase baselines through a collection with the shared yardstick", function(check)
			local line = timeline()
			local member = phased(line, { { 4, 1 }, { 4, 1 }, { 4, 1 } }, 0)
			local phases = assert(member.phases)
			phases[1].baseline = {
				identity = "run-1",
				environment = "lab",
				unit = "milliseconds",
				metric = "p50",
				value = 2,
				tolerance = 0.5,
			}
			local collection: Benchmark.Collection = {
				name = "group",
				clock = clockOf(line),
				yardstick = {
					run = function()
						advance(line, 1)
					end,
					samples = 2,
					maxSpread = 1,
					maxDrift = 1,
				},
				benchmarks = { member },
			}
			local collected = Benchmark.collect(collection)
			check:expect(#collected.results[1].phases):toEqual(2)
			check:expect(assert(collected.results[1].phases[1].comparison).regressed):toEqual(true)
			local harness = Verify.createHarness {
				now = function()
					return 0
				end,
			}
			harness:case("group", Benchmark.collection(collection))
			local report = harness:run { executor = "phases-test" }
			check:expect(report.results[1].status):toEqual "failed"
			check:expect(#assert(report.results[1].evidence).measurements):toEqual(2)
		end)

		suite:case("refuses malformed phase declarations", function(check)
			local line = timeline()
			local both = phased(line, { { 1, 1 } })
			both.workload = function() end
			check:expect(failsWith(both, "workload or phases")):toEqual(true)
			local neither = phased(line, { { 1, 1 } })
			neither.phases = nil
			check:expect(failsWith(neither, "workload or phases")):toEqual(true)
			local duplicate = phased(line, { { 1, 1 } })
			assert(duplicate.phases)[2].name = "cold"
			check:expect(failsWith(duplicate, "declared twice")):toEqual(true)
			local budgeted = phased(line, { { 1, 1 } })
			budgeted.budget = { p95 = 1 }
			check:expect(failsWith(budgeted, "on each phase")):toEqual(true)
			local unnamed = phased(line, { { 1, 1 } })
			assert(unnamed.phases)[1].name = " "
			check:expect(failsWith(unnamed, "needs a name")):toEqual(true)
			local cold = phased(line, { { 1, 1 } })
			cold.warmupScope = "workload"
			check:expect(failsWith(cold, "warmupScope sample")):toEqual(true)
			local negative = phased(line, { { 1, 1 } })
			assert(negative.phases)[1].budget = { p95 = -1 }
			check:expect(failsWith(negative, "budget.p95")):toEqual(true)
			local empty = phased(line, { { 1, 1 } })
			empty.phases = {}
			check:expect(failsWith(empty, "nonempty")):toEqual(true)
		end)

		suite:case("fails when a phase raises and keeps the earlier phases consistent", function(check)
			local line = timeline()
			local spec = phased(line, { { 1, 1 }, { 1, 1 } })
			assert(spec.phases)[2].run = function()
				error "second phase broke"
			end
			local result = Benchmark.run(spec)
			check:expect(result.failure):toContain "second phase broke"
			check:expect(#result.phases[1].samples):toEqual(0)
			check:expect(#result.samples):toEqual(0)
			local setup = phased(line, { { 1, 1 } })
			setup.setup = function()
				error "no lab"
			end
			local blank = Benchmark.run(setup)
			check:expect(blank.failure):toContain "no lab"
			check:expect(#blank.phases):toEqual(2)
		end)
	end)

	suite:suite("benchmark auxiliary series and percentiles", function()
		suite:case("keeps recorded series raw in the evidence and shows them to the judge", function(check)
			local line = timeline()
			local seen: { [string]: { { number } } } = {}
			local spec: Benchmark.Spec = {
				name = "frames",
				unit = "milliseconds",
				warmup = 1,
				warmupScope = "sample",
				samples = 2,
				environment = { observed = "lab" },
				clock = clockOf(line),
				workload = function(_, sampler)
					advance(line, 1)
					sampler.series("frame", { 16, 17, 33 })
					sampler.series("count", { 3 })
				end,
				judge = function(view)
					seen = view.series
					return nil
				end,
			}
			local result = Benchmark.run(spec)
			check:expect(result.series.frame):toEqual { { 16, 17, 33 }, { 16, 17, 33 } }
			check:expect(seen.count):toEqual { { 3 }, { 3 } }
			local report = execute(spec)
			local input = assert(report.results[1].evidence).measurements[1].input
			check:expect(assert(input.series).frame):toEqual { { 16, 17, 33 }, { 16, 17, 33 } }
			local wire = Lute.decode(Lute.encode(report))
			local decoded = Verify.decode(wire)
			local restored = assert(decoded.results[1].evidence).measurements[1].input
			check:expect(assert(restored.series).count):toEqual { { 3 }, { 3 } }
		end)

		suite:case("records series after the sample into the case or into the last phase", function(check)
			local plain = Benchmark.run {
				name = "counters",
				unit = "milliseconds",
				warmup = 1,
				warmupScope = "sample",
				samples = 2,
				environment = { observed = "lab" },
				workload = function() end,
				afterSample = function(_, sampler)
					sampler.series("leaked", { 0 })
				end,
			}
			check:expect(plain.series.leaked):toEqual { { 0 }, { 0 } }
			local line = timeline()
			local spec = phased(line, { { 1, 1 }, { 1, 1 } })
			spec.afterSample = function(_, sampler)
				sampler.series("leaked", { 2 })
			end
			local result = Benchmark.run(spec)
			check:expect(result.phases[2].series.leaked):toEqual { { 2 }, { 2 } }
			check:expect((next(result.phases[1].series))):toBeNil()
			check:expect((next(result.series))):toBeNil()
			spec.afterSample = function(_, sampler)
				sampler.series("leaked", { math.nan })
			end
			check:expect(Benchmark.run(spec).failure):toContain "finite"
		end)

		suite:case("keeps phase series with their phase", function(check)
			local line = timeline()
			local spec = phased(line, { { 1, 1 }, { 1, 1 } })
			assert(spec.phases)[2].run = function(_, sampler)
				advance(line, 1)
				sampler.series("burst", { 1, 2 })
			end
			local result = Benchmark.run(spec)
			check:expect(result.phases[2].series.burst):toEqual { { 1, 2 }, { 1, 2 } }
			check:expect((next(result.phases[1].series))):toBeNil()
			check:expect((next(result.series))):toBeNil()
		end)

		suite:case("refuses a series that is not finite numbers", function(check)
			local function recording(values: { number }, name: string): Benchmark.Result
				return Benchmark.run {
					name = "bad series",
					unit = "milliseconds",
					warmup = 0,
					samples = 1,
					environment = { observed = "lab" },
					workload = function(_, sampler)
						sampler.series(name, values)
					end,
				}
			end
			check:expect(recording({ math.nan }, "frame").failure):toContain "finite"
			check:expect(recording({ math.huge }, "frame").failure):toContain "finite"
			check:expect(recording({ 1 }, " ").failure):toContain "needs a name"
			check:expect(recording({ 1 }, "frame").failure):toBeNil()
			local forged = Verify.createHarness {
				now = function()
					return 0
				end,
			}
			forged:case("forged", function(context)
				context:measure("bench", "forged", {
					samples = { 1 },
					unit = "milliseconds",
					context = { environment = "lab", signal = "forged", timing = "observed" },
					series = { frame = { { 1, math.nan } } },
				}, { unit = "milliseconds", minimumSamples = 1, measureOnly = true })
			end)
			check:expect(forged:run({ executor = "phases-test" }).results[1].status):toEqual "failed"
		end)

		suite:case(
			"summarizes caller-chosen percentiles with nearest rank in the result and the report",
			function(check)
				local line = timeline()
				local index = 0
				local spec: Benchmark.Spec = {
					name = "ranks",
					unit = "milliseconds",
					warmup = 0,
					samples = 20,
					percentiles = { 90, 75 },
					environment = { observed = "lab" },
					clock = clockOf(line),
					workload = function()
						index += 1
						advance(line, index)
					end,
					budget = { maximum = 100 },
				}
				local result = Benchmark.run(spec)
				local entries = assert(result.summary.percentiles)
				check:expect(#entries):toEqual(2)
				check:expect(entries[1].percentile):toEqual(75)
				check:expect(entries[1].value):toBeCloseTo(15, 1e-9)
				check:expect(entries[2].percentile):toEqual(90)
				check:expect(entries[2].value):toBeCloseTo(18, 1e-9)
				local report = execute(spec)
				local evaluation = assert(report.results[1].evidence).measurements[1].evaluation
				check:expect(assert(evaluation.summary.percentiles)[1].percentile):toEqual(75)
				local decoded = Verify.decode(Lute.decode(Lute.encode(report)))
				local restored = assert(decoded.results[1].evidence).measurements[1].input
				check:expect(assert(restored.percentiles)):toEqual { 90, 75 }
				local invalid = table.clone(spec)
				invalid.percentiles = { 50, 50 }
				check:expect(failsWith(invalid, "unique")):toEqual(true)
				invalid.percentiles = { 0 }
				check:expect(failsWith(invalid, "greater than 0")):toEqual(true)
				invalid.percentiles = { 101 }
				check:expect(failsWith(invalid, "at most 100")):toEqual(true)
				invalid.percentiles = {}
				check:expect(failsWith(invalid, "nonempty")):toEqual(true)
			end
		)
	end)
end
