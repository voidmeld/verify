--!strict

local Benchmark = require "../../src/benchmark"
local Verify = require "../../src/core"

return function(suite: Verify.Harness)
	suite:suite("benchmark heap on the Lune runtime", function()
		suite:case("reads a real heap size and checkpoints growth around a workload", function(check)
			local reading = Benchmark.luauHeap.probe()
			check:expect(reading ~= nil and reading > 0):toEqual(true)
			local kept: { { number } } = {}
			local result = Benchmark.run {
				name = "allocates",
				unit = "milliseconds",
				warmup = 0,
				samples = 2,
				workload = function()
					for index = 1, 2000 do
						table.insert(kept, { index, index + 1, index + 2 })
					end
				end,
				budget = { maximum = 1000 },
				environment = { observed = "lune-test" },
				heap = Benchmark.luauHeap,
			}
			local heap = assert(result.heap)
			check:expect(heap.unit):toEqual "kilobytes"
			check:expect(heap.growth > 0):toEqual(true)
			check:expect(#kept > 0):toEqual(true)
		end)
	end)

	suite:suite("benchmark phases on the Lune runtime", function()
		suite:case("measures phases, series and percentiles with an injected clock", function(check)
			local now = 0
			local phases: { Benchmark.Phase } = {
				{
					name = "cold",
					run = function()
						now += 0.004
					end,
				},
				{
					name = "steady",
					run = function(_: unknown, sampler: Benchmark.Sampler)
						now += 0.001
						sampler.series("frame", { 1, 1, 1 })
					end,
				},
			}
			local result = Benchmark.run {
				name = "scenario",
				unit = "milliseconds",
				warmup = 1,
				warmupScope = "sample",
				samples = 4,
				percentiles = { 75 },
				environment = { observed = "lune-test" },
				clock = function()
					return now
				end,
				beforeSample = function()
					return { frames = 3 }
				end,
				phases = phases,
			}
			check:expect(#result.phases):toEqual(2)
			check:expect(result.phases[1].summary.p50):toBeCloseTo(4, 1e-9)
			check:expect(assert(result.phases[2].summary.percentiles)[1].value):toBeCloseTo(1, 1e-9)
			check:expect(#result.phases[2].series.frame):toEqual(4)
			check:expect(Benchmark.store("lune", { result }).measurements[2].name):toEqual "scenario/steady"
		end)
	end)
end
