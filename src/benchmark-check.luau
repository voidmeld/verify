--!strict

local Performance = require "./core/performance"
local Types = require "./benchmark-types"

type Budget = Types.Budget
type Baseline = Types.Baseline
type Yardstick = Types.Yardstick
type Spec = Types.Spec
type Collection = Types.Collection

local function positiveWhole(value: number, label: string)
	assert(
		type(value) == "number" and value >= 1 and value % 1 == 0 and value < math.huge,
		label .. " must be a positive whole number"
	)
end

local function positiveFinite(value: number, label: string)
	assert(type(value) == "number" and value > 0 and value < math.huge, label .. " must be positive and finite")
end

local function nonnegativeFinite(value: number, label: string)
	assert(type(value) == "number" and value >= 0 and value < math.huge, label .. " must be finite and nonnegative")
end

local function checkBudget(budget: Budget?, label: string)
	if budget == nil then
		return
	end
	local limits: { { name: string, value: number? } } = {
		{ name = "p50", value = budget.p50 },
		{ name = "p95", value = budget.p95 },
		{ name = "p99", value = budget.p99 },
		{ name = "maximum", value = budget.maximum },
	}
	for _, limit in limits do
		if limit.value ~= nil then
			nonnegativeFinite(limit.value, label .. "budget." .. limit.name)
		end
	end
end

local function checkBaseline(baseline: Baseline?, declaresYardstick: boolean, label: string)
	if baseline == nil then
		return
	end
	assert(Types.SCALE[baseline.unit] ~= nil, label .. "baseline unit must be seconds, milliseconds or microseconds")
	assert(
		(baseline.value == nil) ~= (baseline.samples == nil),
		label .. "a baseline holds either a value or recorded samples"
	)
	if baseline.value ~= nil then
		nonnegativeFinite(baseline.value, label .. "baseline.value")
	end
	if baseline.samples ~= nil then
		assert(#baseline.samples > 0, label .. "baseline samples must not be empty")
		for _, sample in baseline.samples do
			nonnegativeFinite(sample, label .. "baseline sample")
		end
	end
	nonnegativeFinite(baseline.tolerance, label .. "baseline.tolerance")
	if baseline.yardstick ~= nil then
		positiveFinite(baseline.yardstick, label .. "baseline.yardstick")
		assert(declaresYardstick, "a yardstick-normalized baseline needs the benchmark to declare a yardstick")
	end
	local statistic = baseline.yardstickStatistic
	if statistic ~= nil then
		assert(
			statistic == "median" or statistic == "p95",
			label .. "baseline.yardstickStatistic must be median or p95"
		)
		assert(baseline.yardstick ~= nil, label .. "baseline.yardstickStatistic needs baseline.yardstick")
	end
	local floor = baseline.floor
	if floor ~= nil then
		nonnegativeFinite(floor.limit, label .. "baseline.floor.limit")
		local floorMetric = floor.metric or baseline.metric
		assert(
			floorMetric == "p50" or floorMetric == "p95" or floorMetric == "p99" or floorMetric == "mean",
			label .. "baseline.floor.metric must be p50, p95, p99 or mean"
		)
		if floor.recorded ~= nil then
			nonnegativeFinite(floor.recorded, label .. "baseline.floor.recorded")
		end
		assert(
			floor.recorded ~= nil or baseline.samples ~= nil or floorMetric == baseline.metric,
			label
				.. "baseline.floor needs recorded when its metric differs from the baseline metric and the baseline holds no samples"
		)
	end
	assert(
		baseline.identity ~= "" and baseline.environment ~= "",
		label .. "baseline must name its identity and environment"
	)
end

local function checkYardstick(tool: Yardstick)
	assert(type(tool.run) == "function", "yardstick needs a run function")
	positiveWhole(tool.samples, "yardstick.samples")
	if tool.iterations ~= nil then
		positiveWhole(tool.iterations, "yardstick.iterations")
	end
	if tool.warmup ~= nil then
		nonnegativeFinite(tool.warmup, "yardstick.warmup")
		assert(tool.warmup % 1 == 0, "yardstick.warmup must be a whole number")
	end
	nonnegativeFinite(tool.maxSpread, "yardstick.maxSpread")
	nonnegativeFinite(tool.maxDrift, "yardstick.maxDrift")
	assert(
		tool.driftStatistic == nil or tool.driftStatistic == "median" or tool.driftStatistic == "p95",
		"yardstick.driftStatistic must be median or p95"
	)
	assert(
		tool.driftBase == nil or tool.driftBase == "first" or tool.driftBase == "mean",
		"yardstick.driftBase must be first or mean"
	)
end

local function check(spec: Spec, owned: boolean?)
	assert(type(spec.name) == "string" and string.find(spec.name, "%S") ~= nil, "benchmark needs a name")
	assert(Types.SCALE[spec.unit] ~= nil, "benchmark unit must be seconds, milliseconds or microseconds")
	assert(
		(spec.workload ~= nil) ~= (spec.phases ~= nil),
		"benchmark declares a workload or phases, not both and not neither"
	)
	assert(spec.workload == nil or type(spec.workload) == "function", "benchmark workload must be a function")
	assert(type(spec.warmup) == "number" and spec.warmup >= 0 and spec.warmup % 1 == 0, "warmup must be a whole count")
	assert(
		spec.warmupScope == nil or spec.warmupScope == "workload" or spec.warmupScope == "sample",
		"warmupScope must be workload or sample"
	)
	positiveWhole(spec.samples, "samples")
	if spec.iterations ~= nil then
		positiveWhole(spec.iterations, "iterations")
	end
	if spec.percentiles ~= nil then
		Performance.summarize {
			samples = {},
			unit = spec.unit,
			context = { environment = "check", signal = "check", timing = "observed" },
			percentiles = spec.percentiles,
		}
	end
	checkBudget(spec.budget, "")
	assert(
		type(spec.environment) == "table"
			and type(spec.environment.observed) == "string"
			and string.find(spec.environment.observed, "%S") ~= nil,
		"benchmark must name the observed environment identity"
	)
	if spec.maxSpread ~= nil then
		nonnegativeFinite(spec.maxSpread, "maxSpread")
	end
	if spec.deadlineSeconds ~= nil then
		positiveFinite(spec.deadlineSeconds, "deadlineSeconds")
	end
	local yardstick = spec.yardstick
	if yardstick ~= nil then
		checkYardstick(yardstick)
	end
	local hooks: { [string]: unknown } = {
		setup = spec.setup,
		teardown = spec.teardown,
		beforeSample = spec.beforeSample,
		afterSample = spec.afterSample,
		finalize = spec.finalize,
		judge = spec.judge,
	}
	for name, value in hooks do
		assert(type(value) == "function", name .. " must be a function")
	end
	if spec.finalize ~= nil then
		assert(spec.iterations == nil or spec.iterations == 1, "finalize needs one iteration per sample")
	end
	if spec.heap ~= nil then
		assert(type(spec.heap.probe) == "function", "heap needs a probe function")
		assert(type(spec.heap.unit) == "string" and spec.heap.unit ~= "", "heap needs a unit")
		if spec.heap.maximumGrowth ~= nil then
			nonnegativeFinite(spec.heap.maximumGrowth, "heap.maximumGrowth")
		end
	end
	local declaresYardstick = spec.yardstick ~= nil or owned == true
	checkBaseline(spec.baseline, declaresYardstick, "")
	local phases = spec.phases
	if phases ~= nil then
		assert(type(phases) == "table" and #phases > 0, "phases must be a nonempty array")
		assert(
			spec.budget == nil
				and spec.baseline == nil
				and spec.judge == nil
				and spec.maxSpread == nil
				and spec.finalize == nil
				and spec.iterations == nil,
			"a benchmark with phases declares budget, baseline, judge and maxSpread on each phase, and declares no finalize or iterations"
		)
		assert(
			spec.warmup == 0 or spec.beforeSample == nil or spec.warmupScope == "sample",
			"phases with a beforeSample need warmupScope sample"
		)
		local names: { [string]: boolean } = {}
		for index, phase in phases do
			assert(type(index) == "number" and index >= 1 and index <= #phases, "phases must be a dense array")
			assert(type(phase.name) == "string" and string.find(phase.name, "%S") ~= nil, "a phase needs a name")
			assert(not names[phase.name], ("phase %q is declared twice"):format(phase.name))
			names[phase.name] = true
			assert(type(phase.run) == "function", ("phase %q needs a run function"):format(phase.name))
			local label = ("phase %q: "):format(phase.name)
			checkBudget(phase.budget, label)
			checkBaseline(phase.baseline, declaresYardstick, label)
			if phase.maxSpread ~= nil then
				nonnegativeFinite(phase.maxSpread, label .. "maxSpread")
			end
			assert(phase.judge == nil or type(phase.judge) == "function", label .. "judge must be a function")
		end
	end
end

local function checkCollection(collection: Collection)
	assert(
		collection.calibrationAttempts == nil
			or collection.calibrationAttempts == 1
			or collection.calibrationAttempts == 2,
		"collection.calibrationAttempts must be one or two"
	)
	assert(type(collection.name) == "string" and string.find(collection.name, "%S") ~= nil, "collection needs a name")
	assert(#collection.benchmarks > 0, "collection needs at least one benchmark")
	local tool = collection.yardstick
	checkYardstick(tool)
	local unit = collection.benchmarks[1].unit
	for _, member in collection.benchmarks do
		check(member, true)
		assert(member.yardstick == nil, "a collection owns the yardstick; a member declares none")
		assert(member.unit == unit, "every member of a collection shares one unit")
	end
end

return {
	check = check,
	checkCollection = checkCollection,
}
