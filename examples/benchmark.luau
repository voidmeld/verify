--!strict

local Verify = require "../src/core"
local Benchmark = require "../src/benchmark"
local Lute = require "../src/lute"

local data: { number } = {}
for index = 1, 2000 do
	data[index] = (index * 7919) % 1009
end

local harness = Verify.createHarness { now = os.clock }
harness:case(
	"sort 2000 numbers",
	Benchmark.case {
		name = "sort",
		unit = "milliseconds",
		warmup = 3,
		samples = 15,
		iterations = 5,
		workload = function()
			local copy = table.clone(data)
			table.sort(copy)
		end,
		budget = { p95 = 250, maximum = 1000 },
		environment = { observed = "example-machine", accepted = { "example-machine" } },
		yardstick = {
			run = function()
				local total = 0
				for index = 1, 20000 do
					total += index % 7
				end
			end,
			samples = 5,
			maxSpread = 50,
			maxDrift = 50,
		},
	}
)

local report = harness:run { executor = "benchmark-example" }
print(Verify.format(report))
local measurement = assert(report.results[1].evidence).measurements[1]
print(
	("%d raw samples kept; p50 %.4f %s, p95 %.4f %s"):format(
		#measurement.input.samples,
		measurement.evaluation.summary.p50 or 0,
		measurement.input.unit,
		measurement.evaluation.summary.p95 or 0,
		measurement.input.unit
	)
)
assert(report.passed == report.total, "the benchmark did not pass")

local phases: { Benchmark.Phase } = {
	{
		name = "sort",
		run = function(state: unknown)
			table.sort(state :: { number })
		end,
		budget = { p95 = 250 },
	},
	{
		name = "scan",
		run = function(state: unknown, sampler: Benchmark.Sampler)
			local largest: { number } = {}
			for _, value in state :: { number } do
				largest[1] = math.max(largest[1] or 0, value)
			end
			sampler.series("largest", largest)
		end,
		budget = { p95 = 250 },
	},
}

local screen: Benchmark.Spec = {
	name = "screen",
	unit = "milliseconds",
	warmup = 2,
	warmupScope = "sample",
	samples = 8,
	environment = { observed = "example-machine" },
	beforeSample = function()
		return table.clone(data)
	end,
	phases = phases,
}

local stored = Benchmark.store("baseline", { Benchmark.run(screen) })
local baseline = Benchmark.decode(Lute.parse(Lute.encode(stored)))
local candidate = Benchmark.store("candidate", { Benchmark.run(screen) })
local comparison = Benchmark.compare(baseline, candidate, { rule = { ratio = 5, floor = 25 } })
print(Verify.format(comparison))
assert(comparison.passed == comparison.total, "the candidate regressed")
local spread = Benchmark.spread { baseline, candidate }
print(("%d measurements across %d runs"):format(#spread.noise, spread.runs))
