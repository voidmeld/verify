--!strict

local Benchmark = require "../src/benchmark"
local Lute = require "../src/lute"
local Verify = require "../src/core"

local function stored(
	name: string,
	entries: { [string]: { number } },
	unit: string?,
	environment: string?
): Benchmark.Stored
	local names: { string } = {}
	for key in entries do
		table.insert(names, key)
	end
	table.sort(names)
	local measurements: { Benchmark.StoredMeasurement } = {}
	for _, key in names do
		table.insert(measurements, {
			name = key,
			unit = unit or "milliseconds",
			environment = environment or "lab",
			samples = entries[key],
		})
	end
	return { schemaVersion = 1, name = name, measurements = measurements }
end

local function statusOf(report: Verify.Report, id: string): string
	for _, result in report.results do
		if result.id == id then
			return result.status
		end
	end
	return "absent"
end

local rule: Benchmark.CompareRule = { ratio = 1.5, floor = 0.5 }

local function fails(callback: () -> ()): boolean
	return not pcall(callback)
end

return function(suite: Verify.Harness)
	suite:suite("stored benchmark runs", function()
		suite:case("stores a result with its phases and survives the JSON round trip", function(check)
			local tick = 0
			local result = Benchmark.run {
				name = "scenario",
				unit = "milliseconds",
				warmup = 0,
				samples = 2,
				environment = { observed = "lab" },
				clock = function()
					return tick
				end,
				phases = {
					{
						name = "cold",
						run = function()
							tick += 0.004
						end,
					},
					{
						name = "steady",
						run = function()
							tick += 0.001
						end,
					},
				},
			}
			local plain = Benchmark.run {
				name = "single",
				unit = "milliseconds",
				warmup = 0,
				samples = 2,
				environment = { observed = "lab" },
				clock = function()
					tick += 0.002
					return tick
				end,
				workload = function() end,
			}
			local run = Benchmark.store("candidate", { result, plain })
			check:expect(#run.measurements):toEqual(3)
			check:expect(run.measurements[1].name):toEqual "scenario/cold"
			check:expect(run.measurements[2].name):toEqual "scenario/steady"
			check:expect(run.measurements[3].name):toEqual "single"
			check:expect(run.measurements[1].environment):toEqual "lab"
			local restored = Benchmark.decode(Lute.parse(Lute.encode(run)))
			check:expect(restored):toEqual(run)
			check
				:expect(fails(function()
					Benchmark.store("empty", {})
				end))
				:toEqual(true)
		end)

		suite:case("stores a gate report from its measurement evidence, phases included", function(check)
			local tick = 0
			local harness = Verify.createHarness { now = os.clock }
			harness:case(
				"scenario",
				Benchmark.case {
					name = "scenario",
					unit = "milliseconds",
					warmup = 0,
					samples = 3,
					environment = { observed = "lab" },
					clock = function()
						return tick
					end,
					phases = {
						{
							name = "cold",
							run = function()
								tick += 0.004
							end,
						},
						{
							name = "steady",
							run = function()
								tick += 0.001
							end,
						},
					},
				}
			)
			harness:case(
				"single",
				Benchmark.case {
					name = "single",
					unit = "milliseconds",
					warmup = 0,
					samples = 2,
					environment = { observed = "lab" },
					clock = function()
						return tick
					end,
					workload = function()
						tick += 0.002
					end,
				}
			)
			local report = harness:run { executor = "bench-test" }
			local run = Benchmark.storeReport("candidate", report)
			check:expect(#run.measurements):toEqual(3)
			check:expect(run.measurements[1].name):toEqual "scenario/cold"
			check:expect(run.measurements[2].name):toEqual "scenario/steady"
			check:expect(run.measurements[3].name):toEqual "single"
			check:expect(#run.measurements[1].samples):toEqual(3)
			check:expect(run.measurements[3].environment):toEqual "lab"
			check:expect(Benchmark.decode(Lute.parse(Lute.encode(run)))):toEqual(run)
			local compared = Benchmark.compare(run, run, { rule = rule })
			check:expect(compared.passed):toEqual(3)
			check:expect(#Benchmark.spread({ run, run }, nil).noise):toEqual(3)
		end)

		suite:case("refuses to store a report without measurement evidence or a name", function(check)
			local harness = Verify.createHarness { now = os.clock }
			harness:case("plain", function() end)
			local report = harness:run { executor = "bench-test" }
			check
				:expect(fails(function()
					Benchmark.storeReport("candidate", report)
				end))
				:toEqual(true)
			local measured = Verify.createHarness { now = os.clock }
			measured:case(
				"one",
				Benchmark.case {
					name = "one",
					unit = "milliseconds",
					warmup = 0,
					samples = 1,
					environment = { observed = "lab" },
					clock = function()
						return 0
					end,
					workload = function() end,
				}
			)
			local withMeasurement = measured:run { executor = "bench-test" }
			check:expect(#Benchmark.storeReport("ok", withMeasurement).measurements):toEqual(1)
			check
				:expect(fails(function()
					Benchmark.storeReport(" ", withMeasurement)
				end))
				:toEqual(true)
		end)

		suite:case("refuses malformed stored runs", function(check)
			local good = stored("run", { a = { 1, 2 } })
			check:expect(Benchmark.decode(good).name):toEqual "run"
			local future: Benchmark.Stored = table.clone(good)
			future.schemaVersion = 2
			check
				:expect(fails(function()
					Benchmark.decode(future)
				end))
				:toEqual(true)
			check
				:expect(fails(function()
					Benchmark.decode(stored("run", { a = { -1 } }))
				end))
				:toEqual(true)
			check
				:expect(fails(function()
					Benchmark.decode(stored("run", { a = {} }))
				end))
				:toEqual(true)
			check
				:expect(fails(function()
					Benchmark.decode(stored("run", {}))
				end))
				:toEqual(true)
			local twice = stored("run", { a = { 1 } })
			table.insert(twice.measurements, twice.measurements[1])
			check
				:expect(fails(function()
					Benchmark.decode(twice)
				end))
				:toEqual(true)
			check
				:expect(fails(function()
					Benchmark.decode "text"
				end))
				:toEqual(true)
		end)
	end)

	suite:suite("comparing stored runs", function()
		suite:case("passes within the ratio, within the floor and fails only past both", function(check)
			local baseline = stored("base", { fast = { 10, 10, 10 }, tiny = { 0.1, 0.1, 0.1 }, slow = { 10, 10, 10 } })
			local candidate = stored("head", { fast = { 12, 12, 12 }, tiny = { 0.4, 0.4, 0.4 }, slow = { 20, 20, 20 } })
			local report = Benchmark.compare(baseline, candidate, { rule = rule })
			check:expect(statusOf(report, "fast")):toEqual "passed"
			check:expect(statusOf(report, "tiny")):toEqual "passed"
			check:expect(statusOf(report, "slow")):toEqual "failed"
			check:expect(report.passed):toEqual(2)
			check:expect(report.failed):toEqual(1)
			check:expect(Verify.decode(Lute.decode(Lute.encode(report))).failed):toEqual(1)
			local evidence = assert(report.results[2].evidence)
			check:expect(report.results[2].id):toEqual "slow"
			check:expect(evidence.measurements[1].limits.p50):toBeCloseTo(15, 1e-9)
			check:expect(#evidence.measurements[1].input.samples):toEqual(3)
		end)

		suite:case("applies a per-measurement rule and metric", function(check)
			local baseline = stored("base", { a = { 10, 10, 10, 10, 50 }, b = { 10, 10, 10 } })
			local candidate = stored("head", { a = { 10, 10, 10, 10, 90 }, b = { 20, 20, 20 } })
			local strict = Benchmark.compare(baseline, candidate, { rule = { ratio = 1.1, floor = 0 } })
			check:expect(statusOf(strict, "a")):toEqual "passed"
			check:expect(statusOf(strict, "b")):toEqual "failed"
			local mixed = Benchmark.compare(baseline, candidate, {
				rule = { ratio = 1.1, floor = 0 },
				rules = { b = { ratio = 3, floor = 0 }, a = { ratio = 1.1, floor = 0, metric = "maximum" } },
			})
			check:expect(statusOf(mixed, "a")):toEqual "failed"
			check:expect(statusOf(mixed, "b")):toEqual "passed"
		end)

		suite:case(
			"fails a measurement that is missing, extra, in another unit or in another environment",
			function(check)
				local baseline = stored("base", { kept = { 1, 1 }, gone = { 1, 1 } })
				local candidate = stored("head", { kept = { 1, 1 }, added = { 1, 1 } })
				local report = Benchmark.compare(baseline, candidate, { rule = rule })
				check:expect(statusOf(report, "kept")):toEqual "passed"
				check:expect(statusOf(report, "gone")):toEqual "failed"
				check:expect(statusOf(report, "added")):toEqual "failed"
				local seconds = Benchmark.compare(
					stored("a", { x = { 1 } }),
					stored("b", { x = { 1 } }, "seconds"),
					{ rule = rule }
				)
				check:expect(seconds.results[1].failures[1].message):toContain "stored in"
				local elsewhere = Benchmark.compare(
					stored("a", { x = { 1 } }),
					stored("b", { x = { 1 } }, nil, "laptop"),
					{ rule = rule }
				)
				check:expect(elsewhere.results[1].failures[1].message):toContain "observed in"
			end
		)

		suite:case("refuses a malformed rule or run", function(check)
			local run = stored("a", { x = { 1 } })
			check
				:expect(fails(function()
					Benchmark.compare(run, run, { rule = { ratio = 0.9, floor = 0 } })
				end))
				:toEqual(true)
			check
				:expect(fails(function()
					Benchmark.compare(run, run, { rule = { ratio = 1, floor = -1 } })
				end))
				:toEqual(true)
			check
				:expect(fails(function()
					Benchmark.compare(
						run,
						run,
						{ rule = { ratio = 1, floor = 0 }, rules = { x = { ratio = 0, floor = 0 } } }
					)
				end))
				:toEqual(true)
			check
				:expect(fails(function()
					Benchmark.compare(run, stored("b", {}), { rule = rule })
				end))
				:toEqual(true)
		end)
	end)

	suite:suite("noise across stored runs", function()
		suite:case("summarizes the spread of each measurement across runs", function(check)
			local runs = {
				stored("one", { a = { 10, 10 }, b = { 5, 5 } }),
				stored("two", { a = { 12, 12 }, b = { 5, 5 } }),
				stored("three", { a = { 11, 11 }, b = { 5, 5 }, c = { 1 } }),
			}
			local summary = Benchmark.spread(runs, nil)
			check:expect(summary.runs):toEqual(3)
			check:expect(summary.incomplete):toEqual { "c" }
			check:expect(#summary.noise):toEqual(2)
			local noise = summary.noise[1]
			check:expect(noise.name):toEqual "a"
			check:expect(noise.values):toEqual { 10, 12, 11 }
			check:expect(noise.minimum):toEqual(10)
			check:expect(noise.maximum):toEqual(12)
			check:expect(noise.median):toEqual(11)
			check:expect(noise.mean):toBeCloseTo(11, 1e-9)
			check:expect(assert(noise.relativeRange)):toBeCloseTo(2 / 11, 1e-9)
			check:expect(summary.noise[2].relativeRange):toEqual(0)
			local byMean = Benchmark.spread(runs, { metric = "mean" })
			check:expect(byMean.noise[1].metric):toEqual "mean"
		end)

		suite:case("refuses too few runs, mixed units and a bad metric", function(check)
			local one = stored("one", { a = { 1 } })
			check
				:expect(fails(function()
					Benchmark.spread({ one }, nil)
				end))
				:toEqual(true)
			check
				:expect(fails(function()
					Benchmark.spread({ one, stored("two", { a = { 1 } }, "seconds") }, nil)
				end))
				:toEqual(true)
			check
				:expect(fails(function()
					Benchmark.spread({ one, one }, { metric = ("p10" :: unknown) :: Benchmark.SpreadMetric })
				end))
				:toEqual(true)
		end)
	end)
end
