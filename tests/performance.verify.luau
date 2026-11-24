--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

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

describe("performance samples", function()
	it("uses nearest ranks without mutating input or losing context", function()
		local samples: { number } = {}
		for value = 20, 1, -1 do
			table.insert(samples, value)
		end
		local request = input(samples)
		local summary = Performance.summarize(request)
		expect(summary.sampleCount):toEqual(20)
		expect(summary.minimum):toEqual(1)
		expect(summary.mean):toEqual(10.5)
		expect(summary.p50):toEqual(10)
		expect(summary.p95):toEqual(19)
		expect(summary.p99):toEqual(20)
		expect(summary.maximum):toEqual(20)
		expect(samples[1]):toEqual(20)
		expect(summary.unit):toEqual "milliseconds"
		expect(summary.context):toEqual(request.context)
		request.context.environment = "different-session"
		expect(summary.context.environment):toEqual "client-session"
	end)

	it("distinguishes an empty observation from measured zero and keeps large means finite", function()
		local empty = Performance.summarize(input {})
		expect(empty.sampleCount):toEqual(0)
		expect(empty.p95):toEqual(nil)
		expect(empty.maximum):toEqual(nil)
		expect(empty.mean):toEqual(nil)
		expect(Performance.evaluate(empty, { unit = "milliseconds", minimumSamples = 1, maximum = 0 }).reason):toEqual "unmeasured"
		local zero = Performance.summarize(input { 0 })
		expect(Performance.evaluate(zero, { unit = "milliseconds", minimumSamples = 1, maximum = 0 }).status):toEqual "passed"
		local large = Performance.summarize(input { 1e308, 1e308 })
		expect(large.mean):toEqual(1e308)
	end)

	it("evaluates caller limits inclusively and counts only samples above the bound", function()
		local request = input { 0, 5, 10, 10 }
		request.threshold = 5
		local summary = Performance.summarize(request)
		expect(summary.aboveThresholdCount):toEqual(2)
		expect(summary.aboveThresholdRatio):toEqual(0.5)
		local passed = Performance.evaluate(summary, {
			unit = "milliseconds",
			minimumSamples = 4,
			p95 = 10,
			maximum = 10,
			threshold = 5,
			aboveThresholdRatio = 0.5,
		})
		expect(passed.status):toEqual "passed"
		local failed = Performance.evaluate(summary, {
			unit = "milliseconds",
			minimumSamples = 4,
			p95 = 9,
			maximum = 9,
			threshold = 5,
			aboveThresholdRatio = 0.25,
		})
		expect(failed.status):toEqual "failed"
		expect(failed.reason):toEqual "limit_exceeded"
		expect(failed.violations):toEqual {
			{ metric = "p95", observed = 10, limit = 9 },
			{ metric = "maximum", observed = 10, limit = 9 },
			{ metric = "aboveThresholdRatio", observed = 0.5, limit = 0.25 },
		}
	end)

	it("refuses insufficient, mismatched and missing measurements", function()
		local summary = Performance.summarize(input { 1, 2 })
		expect(Performance.evaluate(summary, { unit = "milliseconds", minimumSamples = 3, p95 = 5 }).reason):toEqual "insufficient_samples"
		expect(Performance.evaluate(summary, { unit = "seconds", minimumSamples = 1, p95 = 5 }).reason):toEqual "unit_mismatch"
		expect(Performance.evaluate(summary, {
			unit = "milliseconds",
			minimumSamples = 1,
			threshold = 5,
			aboveThresholdRatio = 0.1,
		}).reason):toEqual "threshold_mismatch"
		summary.p95 = nil
		local missing = Performance.evaluate(summary, { unit = "milliseconds", minimumSamples = 1, p95 = 5 })
		expect(missing.status):toEqual "unsupported"
		expect(missing.reason):toEqual "unmeasured"
		local request = input { 1, 2 }
		request.threshold = 1
		local measured = Performance.summarize(request)
		expect(Performance.evaluate(measured, {
			unit = "milliseconds",
			minimumSamples = 1,
			threshold = 2,
			aboveThresholdRatio = 1,
		}).reason):toEqual "threshold_mismatch"
	end)

	it("retains simulated sample statistics without qualifying frame performance", function()
		local summary = Performance.summarize(input({ 0, 0, 0 }, "simulated"))
		expect(summary.maximum):toEqual(0)
		local result = Performance.evaluate(summary, { unit = "milliseconds", minimumSamples = 3, maximum = 10 })
		expect(result.status):toEqual "unsupported"
		expect(result.reason):toEqual "simulated"
		expect(result.summary.context.timing):toEqual "simulated"
	end)

	it("rejects nonfinite, negative and sparse samples and empty labels", function()
		for _, value in { -1, math.huge, -math.huge, math.nan } do
			expect(refuses(function()
				Performance.summarize(input { value })
			end)):toEqual(true)
		end
		local sparse: { number } = { [1] = 1, [3] = 3 }
		expect(refuses(function()
			Performance.summarize(input(sparse))
		end)):toEqual(true)
		for _, field in { "unit", "environment", "signal" } do
			local request = input { 1 }
			if field == "unit" then
				request.unit = " "
			elseif field == "environment" then
				request.context.environment = ""
			else
				request.context.signal = ""
			end
			expect(refuses(function()
				Performance.summarize(request)
			end)):toEqual(true)
		end
	end)

	it("rejects invalid count, ratio and numeric limits rather than weakening them", function()
		local summary = Performance.summarize(input { 1 })
		for _, count in { 0, -1, 1.5, math.huge, math.nan } do
			expect(refuses(function()
				Performance.evaluate(summary, { unit = "milliseconds", minimumSamples = count, maximum = 2 })
			end)):toEqual(true)
		end
		for _, maximum in { -1, math.huge, math.nan } do
			expect(refuses(function()
				Performance.evaluate(summary, { unit = "milliseconds", minimumSamples = 1, maximum = maximum })
			end)):toEqual(true)
		end
		expect(refuses(function()
			Performance.evaluate(summary, { unit = "milliseconds", minimumSamples = 1 })
		end)):toEqual(true)
		expect(refuses(function()
			Performance.evaluate(
				summary,
				{ unit = "milliseconds", minimumSamples = 1, aboveThresholdRatio = 2, threshold = 1 }
			)
		end)):toEqual(true)
		expect(refuses(function()
			Performance.evaluate(summary, { unit = "milliseconds", minimumSamples = 1, aboveThresholdRatio = 1 })
		end)):toEqual(true)
	end)
end)

describe("performance percentiles and series", function()
	it("adds caller-chosen nearest-rank percentiles in ascending order", function()
		local samples: { number } = {}
		for value = 1, 20 do
			table.insert(samples, value)
		end
		local request = input(samples)
		request.percentiles = { 90, 75, 99.5 }
		local summary = Performance.summarize(request)
		local entries = assert(summary.percentiles)
		expect(#entries):toEqual(3)
		expect(entries[1]):toEqual { percentile = 75, value = 15 }
		expect(entries[2]):toEqual { percentile = 90, value = 18 }
		expect(entries[3]):toEqual { percentile = 99.5, value = 20 }
		expect(summary.p95):toEqual(19)
		expect(Performance.summarize(input(samples)).percentiles):toBeNil()
		local empty = input {}
		empty.percentiles = { 75 }
		expect(#assert(Performance.summarize(empty).percentiles)):toEqual(0)
	end)

	it("refuses percentiles that are repeated, out of range or not numbers", function()
		local function summarizing(values: { number }): boolean
			local request = input { 1, 2, 3 }
			request.percentiles = values
			return refuses(function()
				Performance.summarize(request)
			end)
		end
		expect(summarizing { 50, 50 }):toEqual(true)
		expect(summarizing { 0 }):toEqual(true)
		expect(summarizing { 100.5 }):toEqual(true)
		expect(summarizing { math.nan }):toEqual(true)
		expect(summarizing {}):toEqual(true)
		expect(summarizing { 100 }):toEqual(false)
	end)

	it("validates the auxiliary series without interpreting it", function()
		local function summarizing(series: Performance.Series): boolean
			local request = input { 1 }
			request.series = series
			return not refuses(function()
				Performance.summarize(request)
			end)
		end
		expect(summarizing { frame = { { 16, -1, 0.5 }, {} } }):toEqual(true)
		expect(summarizing { frame = { { math.nan } } }):toEqual(false)
		expect(summarizing { frame = { { math.huge } } }):toEqual(false)
		expect(summarizing { [" "] = { { 1 } } }):toEqual(false)
	end)
end)

return nil
