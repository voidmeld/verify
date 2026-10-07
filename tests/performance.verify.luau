--!strict

local Verify = require "../src/core"
local Performance = require "../src/core/performance"

local function input(samples: { number }, timing: ("observed" | "simulated")?): Performance.Input
	return {
		samples = samples,
		unit = "milliseconds",
		context = { environment = "client-session", signal = "render", timing = timing or "observed" },
	}
end

local function refuses(callback: () -> ()): boolean
	return not pcall(callback)
end

return function(suite: Verify.Harness)
	suite:suite("performance samples", function()
		suite:case("uses nearest ranks without mutating input or losing context", function(check)
			local samples: { number } = {}
			for value = 20, 1, -1 do
				table.insert(samples, value)
			end
			local request = input(samples)
			local summary = Performance.summarize(request)
			check:expect(summary.sampleCount):toEqual(20)
			check:expect(summary.minimum):toEqual(1)
			check:expect(summary.mean):toEqual(10.5)
			check:expect(summary.p50):toEqual(10)
			check:expect(summary.p95):toEqual(19)
			check:expect(summary.p99):toEqual(20)
			check:expect(summary.maximum):toEqual(20)
			check:expect(samples[1]):toEqual(20)
			check:expect(summary.unit):toEqual "milliseconds"
			check:expect(summary.context):toEqual(request.context)
			request.context.environment = "different-session"
			check:expect(summary.context.environment):toEqual "client-session"
		end)

		suite:case("distinguishes an empty observation from measured zero and keeps large means finite", function(check)
			local empty = Performance.summarize(input {})
			check:expect(empty.sampleCount):toEqual(0)
			check:expect(empty.p95):toEqual(nil)
			check:expect(empty.maximum):toEqual(nil)
			check:expect(empty.mean):toEqual(nil)
			check
				:expect(Performance.evaluate(empty, { unit = "milliseconds", minimumSamples = 1, maximum = 0 }).reason)
				:toEqual "unmeasured"
			local zero = Performance.summarize(input { 0 })
			check
				:expect(Performance.evaluate(zero, { unit = "milliseconds", minimumSamples = 1, maximum = 0 }).status)
				:toEqual "passed"
			local large = Performance.summarize(input { 1e308, 1e308 })
			check:expect(large.mean):toEqual(1e308)
		end)

		suite:case("evaluates caller limits inclusively and counts only samples above the bound", function(check)
			local request = input { 0, 5, 10, 10 }
			request.threshold = 5
			local summary = Performance.summarize(request)
			check:expect(summary.aboveThresholdCount):toEqual(2)
			check:expect(summary.aboveThresholdRatio):toEqual(0.5)
			local passed = Performance.evaluate(summary, {
				unit = "milliseconds",
				minimumSamples = 4,
				p95 = 10,
				maximum = 10,
				threshold = 5,
				aboveThresholdRatio = 0.5,
			})
			check:expect(passed.status):toEqual "passed"
			local failed = Performance.evaluate(summary, {
				unit = "milliseconds",
				minimumSamples = 4,
				p95 = 9,
				maximum = 9,
				threshold = 5,
				aboveThresholdRatio = 0.25,
			})
			check:expect(failed.status):toEqual "failed"
			check:expect(failed.reason):toEqual "limit_exceeded"
			check:expect(failed.violations):toEqual {
				{ metric = "p95", observed = 10, limit = 9 },
				{ metric = "maximum", observed = 10, limit = 9 },
				{ metric = "aboveThresholdRatio", observed = 0.5, limit = 0.25 },
			}
		end)

		suite:case("refuses insufficient, mismatched and missing measurements", function(check)
			local summary = Performance.summarize(input { 1, 2 })
			check
				:expect(Performance.evaluate(summary, { unit = "milliseconds", minimumSamples = 3, p95 = 5 }).reason)
				:toEqual "insufficient_samples"
			check
				:expect(Performance.evaluate(summary, { unit = "seconds", minimumSamples = 1, p95 = 5 }).reason)
				:toEqual "unit_mismatch"
			check
				:expect(Performance.evaluate(summary, {
					unit = "milliseconds",
					minimumSamples = 1,
					threshold = 5,
					aboveThresholdRatio = 0.1,
				}).reason)
				:toEqual "threshold_mismatch"
			summary.p95 = nil
			local missing = Performance.evaluate(summary, { unit = "milliseconds", minimumSamples = 1, p95 = 5 })
			check:expect(missing.status):toEqual "unsupported"
			check:expect(missing.reason):toEqual "unmeasured"
			local request = input { 1, 2 }
			request.threshold = 1
			local measured = Performance.summarize(request)
			check
				:expect(Performance.evaluate(measured, {
					unit = "milliseconds",
					minimumSamples = 1,
					threshold = 2,
					aboveThresholdRatio = 1,
				}).reason)
				:toEqual "threshold_mismatch"
		end)

		suite:case("retains simulated sample statistics without qualifying frame performance", function(check)
			local summary = Performance.summarize(input({ 0, 0, 0 }, "simulated"))
			check:expect(summary.maximum):toEqual(0)
			local result = Performance.evaluate(summary, { unit = "milliseconds", minimumSamples = 3, maximum = 10 })
			check:expect(result.status):toEqual "unsupported"
			check:expect(result.reason):toEqual "simulated"
			check:expect(result.summary.context.timing):toEqual "simulated"
		end)

		suite:case("rejects nonfinite, negative and sparse samples and empty labels", function(check)
			for _, value in { -1, math.huge, -math.huge, math.nan } do
				check
					:expect(refuses(function()
						Performance.summarize(input { value })
					end))
					:toEqual(true)
			end
			local sparse: { number } = { [1] = 1, [3] = 3 }
			check
				:expect(refuses(function()
					Performance.summarize(input(sparse))
				end))
				:toEqual(true)
			for _, field in { "unit", "environment", "signal" } do
				local request = input { 1 }
				if field == "unit" then
					request.unit = " "
				elseif field == "environment" then
					request.context.environment = ""
				else
					request.context.signal = ""
				end
				check
					:expect(refuses(function()
						Performance.summarize(request)
					end))
					:toEqual(true)
			end
		end)

		suite:case("rejects invalid count, ratio and numeric limits rather than weakening them", function(check)
			local summary = Performance.summarize(input { 1 })
			for _, count in { 0, -1, 1.5, math.huge, math.nan } do
				check
					:expect(refuses(function()
						Performance.evaluate(summary, { unit = "milliseconds", minimumSamples = count, maximum = 2 })
					end))
					:toEqual(true)
			end
			for _, maximum in { -1, math.huge, math.nan } do
				check
					:expect(refuses(function()
						Performance.evaluate(summary, { unit = "milliseconds", minimumSamples = 1, maximum = maximum })
					end))
					:toEqual(true)
			end
			check
				:expect(refuses(function()
					Performance.evaluate(summary, { unit = "milliseconds", minimumSamples = 1 })
				end))
				:toEqual(true)
			check
				:expect(refuses(function()
					Performance.evaluate(
						summary,
						{ unit = "milliseconds", minimumSamples = 1, aboveThresholdRatio = 2, threshold = 1 }
					)
				end))
				:toEqual(true)
			check
				:expect(refuses(function()
					Performance.evaluate(
						summary,
						{ unit = "milliseconds", minimumSamples = 1, aboveThresholdRatio = 1 }
					)
				end))
				:toEqual(true)
		end)
	end)

	suite:suite("performance percentiles and series", function()
		suite:case("adds caller-chosen nearest-rank percentiles in ascending order", function(check)
			local samples: { number } = {}
			for value = 1, 20 do
				table.insert(samples, value)
			end
			local request = input(samples)
			request.percentiles = { 90, 75, 99.5 }
			local summary = Performance.summarize(request)
			local entries = assert(summary.percentiles)
			check:expect(#entries):toEqual(3)
			check:expect(entries[1]):toEqual { percentile = 75, value = 15 }
			check:expect(entries[2]):toEqual { percentile = 90, value = 18 }
			check:expect(entries[3]):toEqual { percentile = 99.5, value = 20 }
			check:expect(summary.p95):toEqual(19)
			check:expect(Performance.summarize(input(samples)).percentiles):toBeNil()
			local empty = input {}
			empty.percentiles = { 75 }
			check:expect(#assert(Performance.summarize(empty).percentiles)):toEqual(0)
		end)

		suite:case("refuses percentiles that are repeated, out of range or not numbers", function(check)
			local function summarizing(values: { number }): boolean
				local request = input { 1, 2, 3 }
				request.percentiles = values
				return refuses(function()
					Performance.summarize(request)
				end)
			end
			check:expect(summarizing { 50, 50 }):toEqual(true)
			check:expect(summarizing { 0 }):toEqual(true)
			check:expect(summarizing { 100.5 }):toEqual(true)
			check:expect(summarizing { math.nan }):toEqual(true)
			check:expect(summarizing {}):toEqual(true)
			check:expect(summarizing { 100 }):toEqual(false)
		end)

		suite:case("validates the auxiliary series without interpreting it", function(check)
			local function summarizing(series: Performance.Series): boolean
				local request = input { 1 }
				request.series = series
				return not refuses(function()
					Performance.summarize(request)
				end)
			end
			check:expect(summarizing { frame = { { 16, -1, 0.5 }, {} } }):toEqual(true)
			check:expect(summarizing { frame = { { math.nan } } }):toEqual(false)
			check:expect(summarizing { frame = { { math.huge } } }):toEqual(false)
			check:expect(summarizing { [" "] = { { 1 } } }):toEqual(false)
		end)
	end)
end
