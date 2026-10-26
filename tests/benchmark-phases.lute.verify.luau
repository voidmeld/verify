--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

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

describe("benchmark sample lifecycle", function()
	it("warms up the workload only by default and the whole sample on request", function()
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
		expect(table.concat(log, " ")):toEqual "work work before work after before work after before work after"
		table.clear(log)
		Benchmark.run(lifecycle "sample")
		expect(#log):toEqual(15)
		expect(table.concat(log, " ", 1, 6)):toEqual "before work after before work after"
	end)

	it("hands the per-sample state to the workload, finalize and release", function()
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
		expect(seen):toEqual { "work1", "drain1", "free1", "work2", "drain2", "free2", "work3", "drain3", "free3" }
	end)

	it("fails when a warmup sample cannot be prepared and still releases a failed sample", function()
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
		expect(broken.failure):toContain "no environment"
		expect(#broken.samples):toEqual(0)
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
		expect(failing.failure):toContain "workload broke"
		expect(released):toEqual(1)
	end)

	it("times the finalize step inside the sample and leaves the release untimed", function()
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
		expect(rounded(result.samples)):toEqual { 5, 5, 5 }
		expect(failsWith({
			name = "drain",
			unit = "milliseconds",
			warmup = 0,
			samples = 1,
			iterations = 4,
			environment = { observed = "lab" },
			workload = function() end,
			finalize = function() end,
		}, "finalize needs one iteration")):toEqual(true)
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
		expect(raising.failure):toContain "drain stuck"
		expect(#raising.samples):toEqual(0)
	end)
end)

describe("benchmark phases", function()
	it("measures each phase on the per-sample state and keeps raw samples per phase", function()
		local line = timeline()
		local result = Benchmark.run(phased(line, { { 4, 1 }, { 6, 1 }, { 5, 2 } }))
		expect(rounded(result.phases[1].samples)):toEqual { 4, 6, 5 }
		expect(rounded(result.phases[2].samples)):toEqual { 1, 1, 2 }
		expect(rounded(result.samples)):toEqual { 5, 7, 7 }
		expect(result.phases[1].measurement):toEqual "scenario/cold"
		expect(result.phases[1].summary.context.signal):toEqual "scenario/cold"
		expect(result.phases[2].summary.p50):toBeCloseTo(1, 1e-9)
		expect(result.warmupRuns):toEqual(1)
	end)

	it("reports one measurement per phase with its own budget in the one case", function()
		local line = timeline()
		local report = execute(phased(line, { { 4, 1 }, { 4, 1 }, { 4, 1 } }))
		expect(report.results[1].status):toEqual "passed"
		local measurements = assert(report.results[1].evidence).measurements
		expect(#measurements):toEqual(2)
		expect(measurements[1].name):toEqual "scenario/cold"
		expect(measurements[2].name):toEqual "scenario/steady"
		expect(measurements[1].limits.p95):toEqual(10)
		local over = execute(phased(timeline(), { { 40, 1 }, { 40, 1 }, { 40, 1 } }))
		expect(over.results[1].status):toEqual "failed"
		local evidence = assert(over.results[1].evidence)
		expect(evidence.measurements[1].evaluation.status):toEqual "failed"
		expect(evidence.measurements[2].evaluation.status):toEqual "passed"
	end)

	it("reports unbudgeted phases as measured only", function()
		local line = timeline()
		local spec = phased(line, { { 4, 1 }, { 4, 1 } })
		local phases = assert(spec.phases)
		phases[2].budget = nil
		local options = Benchmark.case(spec)
		expect(options.limitations):toEqual { "measured only: no budget declared for phase steady" }
	end)

	it("compares and judges each phase on its own and refuses a regression in one", function()
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
		expect(assert(result.phases[1].comparison).regressed):toEqual(true)
		expect(result.phases[2].comparison):toBeNil()
		expect(result.phases[2].judgment):toEqual "steady phase looks wrong"
		expect(judged):toEqual { "steady" }
		local report = execute(spec)
		expect(report.results[1].status):toEqual "failed"
		local messages: { string } = {}
		for _, failure in report.results[1].failures do
			table.insert(messages, failure.message)
		end
		local joined = table.concat(messages, "\n")
		expect(joined):toContain "scenario/cold p50"
		expect(joined):toContain "scenario/steady was refused by its judge"
	end)

	it("marks an unstable phase unsupported and skips its judge", function()
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
		expect(result.phases[1].invalid[1].reason):toEqual "unstable"
		expect(#result.phases[2].invalid):toEqual(0)
		expect(called):toEqual(false)
		local report = execute(spec)
		expect(report.results[1].status):toEqual "unsupported"
		expect(report.results[1].missingCapabilities):toEqual { "measurement:unstable" }
	end)

	it("runs phase baselines through a collection with the shared yardstick", function()
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
		expect(#collected.results[1].phases):toEqual(2)
		expect(assert(collected.results[1].phases[1].comparison).regressed):toEqual(true)
		local harness = Verify.createHarness {
			now = function()
				return 0
			end,
		}
		harness:case("group", Benchmark.collection(collection))
		local report = harness:run { executor = "phases-test" }
		expect(report.results[1].status):toEqual "failed"
		expect(#assert(report.results[1].evidence).measurements):toEqual(2)
	end)

	it("refuses malformed phase declarations", function()
		local line = timeline()
		local both = phased(line, { { 1, 1 } })
		both.workload = function() end
		expect(failsWith(both, "workload or phases")):toEqual(true)
		local neither = phased(line, { { 1, 1 } })
		neither.phases = nil
		expect(failsWith(neither, "workload or phases")):toEqual(true)
		local duplicate = phased(line, { { 1, 1 } })
		assert(duplicate.phases)[2].name = "cold"
		expect(failsWith(duplicate, "declared twice")):toEqual(true)
		local budgeted = phased(line, { { 1, 1 } })
		budgeted.budget = { p95 = 1 }
		expect(failsWith(budgeted, "on each phase")):toEqual(true)
		local unnamed = phased(line, { { 1, 1 } })
		assert(unnamed.phases)[1].name = " "
		expect(failsWith(unnamed, "needs a name")):toEqual(true)
		local cold = phased(line, { { 1, 1 } })
		cold.warmupScope = "workload"
		expect(failsWith(cold, "warmupScope sample")):toEqual(true)
		local negative = phased(line, { { 1, 1 } })
		assert(negative.phases)[1].budget = { p95 = -1 }
		expect(failsWith(negative, "budget.p95")):toEqual(true)
		local empty = phased(line, { { 1, 1 } })
		empty.phases = {}
		expect(failsWith(empty, "nonempty")):toEqual(true)
	end)

	it("fails when a phase raises and keeps the earlier phases consistent", function()
		local line = timeline()
		local spec = phased(line, { { 1, 1 }, { 1, 1 } })
		assert(spec.phases)[2].run = function()
			error "second phase broke"
		end
		local result = Benchmark.run(spec)
		expect(result.failure):toContain "second phase broke"
		expect(#result.phases[1].samples):toEqual(0)
		expect(#result.samples):toEqual(0)
		local setup = phased(line, { { 1, 1 } })
		setup.setup = function()
			error "no lab"
		end
		local blank = Benchmark.run(setup)
		expect(blank.failure):toContain "no lab"
		expect(#blank.phases):toEqual(2)
	end)
end)

describe("benchmark auxiliary series and percentiles", function()
	it("keeps recorded series raw in the evidence and shows them to the judge", function()
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
		expect(result.series.frame):toEqual { { 16, 17, 33 }, { 16, 17, 33 } }
		expect(seen.count):toEqual { { 3 }, { 3 } }
		local report = execute(spec)
		local input = assert(report.results[1].evidence).measurements[1].input
		expect(assert(input.series).frame):toEqual { { 16, 17, 33 }, { 16, 17, 33 } }
		local wire = Lute.decode(Lute.encode(report))
		local decoded = Verify.decode(wire)
		local restored = assert(decoded.results[1].evidence).measurements[1].input
		expect(assert(restored.series).count):toEqual { { 3 }, { 3 } }
	end)

	it("records series after the sample into the case or into the last phase", function()
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
		expect(plain.series.leaked):toEqual { { 0 }, { 0 } }
		local line = timeline()
		local spec = phased(line, { { 1, 1 }, { 1, 1 } })
		spec.afterSample = function(_, sampler)
			sampler.series("leaked", { 2 })
		end
		local result = Benchmark.run(spec)
		expect(result.phases[2].series.leaked):toEqual { { 2 }, { 2 } }
		expect((next(result.phases[1].series))):toBeNil()
		expect((next(result.series))):toBeNil()
		spec.afterSample = function(_, sampler)
			sampler.series("leaked", { math.nan })
		end
		expect(Benchmark.run(spec).failure):toContain "finite"
	end)

	it("keeps phase series with their phase", function()
		local line = timeline()
		local spec = phased(line, { { 1, 1 }, { 1, 1 } })
		assert(spec.phases)[2].run = function(_, sampler)
			advance(line, 1)
			sampler.series("burst", { 1, 2 })
		end
		local result = Benchmark.run(spec)
		expect(result.phases[2].series.burst):toEqual { { 1, 2 }, { 1, 2 } }
		expect((next(result.phases[1].series))):toBeNil()
		expect((next(result.series))):toBeNil()
	end)

	it("refuses a series that is not finite numbers", function()
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
		expect(recording({ math.nan }, "frame").failure):toContain "finite"
		expect(recording({ math.huge }, "frame").failure):toContain "finite"
		expect(recording({ 1 }, " ").failure):toContain "needs a name"
		expect(recording({ 1 }, "frame").failure):toBeNil()
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
		expect(forged:run({ executor = "phases-test" }).results[1].status):toEqual "failed"
	end)

	it("summarizes caller-chosen percentiles with nearest rank in the result and the report", function()
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
		expect(#entries):toEqual(2)
		expect(entries[1].percentile):toEqual(75)
		expect(entries[1].value):toBeCloseTo(15, 1e-9)
		expect(entries[2].percentile):toEqual(90)
		expect(entries[2].value):toBeCloseTo(18, 1e-9)
		local report = execute(spec)
		local evaluation = assert(report.results[1].evidence).measurements[1].evaluation
		expect(assert(evaluation.summary.percentiles)[1].percentile):toEqual(75)
		local decoded = Verify.decode(Lute.decode(Lute.encode(report)))
		local restored = assert(decoded.results[1].evidence).measurements[1].input
		expect(assert(restored.percentiles)):toEqual { 90, 75 }
		local invalid = table.clone(spec)
		invalid.percentiles = { 50, 50 }
		expect(failsWith(invalid, "unique")):toEqual(true)
		invalid.percentiles = { 0 }
		expect(failsWith(invalid, "greater than 0")):toEqual(true)
		invalid.percentiles = { 101 }
		expect(failsWith(invalid, "at most 100")):toEqual(true)
		invalid.percentiles = {}
		expect(failsWith(invalid, "nonempty")):toEqual(true)
	end)
end)

return nil
