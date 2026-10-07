--!strict

local Harness = require "./core/harness"
local Performance = require "./core/performance"
local Store = require "./benchmark-store"

export type Stored = Store.Stored
export type StoredMeasurement = Store.StoredMeasurement
export type CompareRule = Store.Rule
export type CompareOptions = Store.CompareOptions
export type CompareMetric = Store.CompareMetric
export type SpreadOptions = Store.SpreadOptions
export type SpreadMetric = Store.SpreadMetric
export type Noise = Store.Noise
export type SpreadSummary = Store.SpreadSummary
export type Unit = "seconds" | "milliseconds" | "microseconds"
export type Clock = () -> number
export type Metric = "p50" | "p95" | "p99" | "mean"
export type HeapReading = { before: number, after: number, growth: number, unit: string }

export type Budget = {
	p50: number?,
	p95: number?,
	p99: number?,
	maximum: number?,
}

export type Yardstick = {
	run: () -> (),
	samples: number,
	maxSpread: number,
	maxDrift: number,
}

export type Baseline = {
	identity: string,
	environment: string,
	unit: Unit,
	metric: Metric,
	value: number?,
	samples: { number }?,
	tolerance: number,
	yardstick: number?,
	yardstickStatistic: YardstickStatistic?,
	floor: Floor?,
}

export type YardstickStatistic = "median" | "p95"

export type Floor = {
	limit: number,
	metric: Metric?,
	recorded: number?,
}

export type Heap = {
	probe: () -> number?,
	unit: string,
	maximumGrowth: number?,
}

export type Judgment = {
	phase: string?,
	samples: { number },
	summary: Performance.Summary,
	series: Performance.Series,
	unit: Unit,
	yardstickBefore: { number },
	yardstickAfter: { number },
	yardstickBeforeSummary: Performance.Summary,
	yardstickAfterSummary: Performance.Summary,
	heap: HeapReading?,
}

export type Sampler = {
	series: (name: string, values: { number }) -> (),
}

export type WarmupScope = "workload" | "sample"

export type Phase = {
	name: string,
	run: (state: unknown, sampler: Sampler) -> (),
	budget: Budget?,
	maxSpread: number?,
	baseline: Baseline?,
	judge: ((view: Judgment) -> string?)?,
}

export type Spec = {
	name: string,
	unit: Unit,
	workload: ((state: unknown, sampler: Sampler) -> ())?,
	phases: { Phase }?,
	finalize: ((state: unknown, sampler: Sampler) -> ())?,
	warmup: number,
	warmupScope: WarmupScope?,
	samples: number,
	iterations: number?,
	percentiles: { number }?,
	budget: Budget?,
	environment: { observed: string, accepted: { string }? },
	maxSpread: number?,
	yardstick: Yardstick?,
	baseline: Baseline?,
	acceptedBaselines: { string }?,
	deadlineSeconds: number?,
	clock: Clock?,
	signal: string?,
	tags: { string }?,
	setup: (() -> ())?,
	teardown: (() -> ())?,
	beforeSample: (() -> ...unknown)?,
	afterSample: ((state: unknown, sampler: Sampler) -> ())?,
	heap: Heap?,
	judge: ((view: Judgment) -> string?)?,
}

export type Collection = {
	name: string,
	yardstick: Yardstick,
	benchmarks: { Spec },
	clock: Clock?,
}

export type InvalidReason =
	"environment_mismatch"
	| "baseline_mismatch"
	| "unstable"
	| "yardstick_unstable"
	| "yardstick_drift"
	| "heap_unsupported"
	| "deadline_exceeded"

export type Invalid = { reason: InvalidReason, detail: string }

export type Comparison = {
	metric: Metric,
	observed: number,
	baseline: number,
	limit: number,
	regressed: boolean,
	normalized: boolean,
	floored: boolean,
}

export type PhaseResult = {
	name: string,
	measurement: string,
	samples: { number },
	summary: Performance.Summary,
	spread: number?,
	invalid: { Invalid },
	comparison: Comparison?,
	judgment: string?,
	series: Performance.Series,
}

export type Result = {
	name: string,
	unit: Unit,
	samples: { number },
	phases: { PhaseResult },
	series: Performance.Series,
	warmupRuns: number,
	iterations: number,
	yardstickBefore: { number },
	yardstickAfter: { number },
	summary: Performance.Summary,
	spread: number?,
	invalid: { Invalid },
	comparison: Comparison?,
	heap: HeapReading?,
	judgment: string?,
	failure: string?,
	elapsedSeconds: number,
}

export type CollectionResult = {
	name: string,
	results: { Result },
	yardstickBefore: { number },
	yardstickAfter: { number },
	invalid: { Invalid },
	failure: string?,
}

local SCALE: { [Unit]: number } = { seconds = 1, milliseconds = 1e3, microseconds = 1e6 }

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
	assert(SCALE[baseline.unit] ~= nil, label .. "baseline unit must be seconds, milliseconds or microseconds")
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

local function check(spec: Spec, owned: boolean?)
	assert(type(spec.name) == "string" and string.find(spec.name, "%S") ~= nil, "benchmark needs a name")
	assert(SCALE[spec.unit] ~= nil, "benchmark unit must be seconds, milliseconds or microseconds")
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
		assert(type(yardstick.run) == "function", "yardstick needs a run function")
		positiveWhole(yardstick.samples, "yardstick.samples")
		nonnegativeFinite(yardstick.maxSpread, "yardstick.maxSpread")
		nonnegativeFinite(yardstick.maxDrift, "yardstick.maxDrift")
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

local function contains(values: { string }?, value: string): boolean
	return values ~= nil and table.find(values, value) ~= nil
end

local function relativeSpread(samples: { number }): number?
	if #samples == 0 then
		return nil
	end
	local sorted = table.clone(samples)
	table.sort(sorted)
	local median = sorted[math.max(1, math.ceil(#sorted * 0.5))]
	local high = sorted[math.max(1, math.ceil(#sorted * 0.95))]
	if median == 0 then
		return if high == 0 then 0 else math.huge
	end
	return (high - median) / median
end

local function median(samples: { number }): number
	local sorted = table.clone(samples)
	table.sort(sorted)
	return sorted[math.max(1, math.ceil(#sorted * 0.5))]
end

local function metricValue(summary: Performance.Summary, metric: Metric): number?
	if metric == "mean" then
		return summary.mean
	elseif metric == "p50" then
		return summary.p50
	elseif metric == "p95" then
		return summary.p95
	end
	return summary.p99
end

local function summaryOf(spec: Spec, samples: { number }, phase: string?): Performance.Summary
	local signal = spec.signal or spec.name
	return Performance.summarize {
		samples = samples,
		unit = spec.unit,
		percentiles = spec.percentiles,
		context = {
			environment = spec.environment.observed,
			signal = if phase ~= nil then signal .. "/" .. phase else signal,
			timing = "observed",
		},
	}
end

local function baselineValue(spec: Spec, baseline: Baseline): number?
	if baseline.value ~= nil then
		return baseline.value
	end
	return metricValue(summaryOf(spec, baseline.samples :: { number }), baseline.metric)
end

local function yardstickIssues(tool: Yardstick, before: { number }, after: { number }): { Invalid }
	local issues: { Invalid } = {}
	if #before == 0 or #after == 0 then
		return issues
	end
	local combined = table.clone(before)
	for _, value in after do
		table.insert(combined, value)
	end
	local spread = relativeSpread(combined)
	if spread ~= nil and spread > tool.maxSpread then
		table.insert(issues, {
			reason = "yardstick_unstable",
			detail = ("yardstick spread was %.3f, above the allowed %.3f"):format(spread, tool.maxSpread),
		})
	end
	local first = median(before)
	local last = median(after)
	local drift = if first == 0 then (if last == 0 then 0 else math.huge) else math.abs(last - first) / first
	if drift > tool.maxDrift then
		table.insert(issues, {
			reason = "yardstick_drift",
			detail = ("yardstick median moved %.3f between the start and end, above the allowed %.3f"):format(
				drift,
				tool.maxDrift
			),
		})
	end
	return issues
end

local function timeYardstick(clock: Clock, scale: number, tool: Yardstick, into: { number }): string?
	for _ = 1, tool.samples do
		local before = clock()
		local ok, thrown: unknown = pcall(tool.run)
		if not ok then
			return "workload raised: " .. tostring(thrown)
		end
		local elapsed = clock() - before
		if elapsed ~= elapsed or elapsed < 0 or elapsed == math.huge then
			return "the clock produced an invalid yardstick duration"
		end
		table.insert(into, elapsed * scale)
	end
	return nil
end

local function readHeap(heap: Heap): number?
	local ok, value: unknown = pcall(heap.probe)
	if ok and type(value) == "number" and value == value and value >= 0 and value < math.huge then
		return value
	end
	return nil
end

local function yardstickNow(spec: Spec, statistic: YardstickStatistic?, before: { number }, after: { number }): number?
	if statistic == "p95" then
		local first = summaryOf(spec, before).p95
		local last = summaryOf(spec, after).p95
		if first == nil or last == nil then
			return nil
		end
		return (first + last) / 2
	end
	local combined = table.clone(before)
	for _, entry in after do
		table.insert(combined, entry)
	end
	return median(combined)
end

local function underFloor(spec: Spec, baseline: Baseline, summary: Performance.Summary): boolean
	local floor = baseline.floor
	if floor == nil then
		return false
	end
	local floorMetric: Metric = floor.metric or baseline.metric
	local observed = metricValue(summary, floorMetric)
	local recorded = floor.recorded
	if recorded == nil then
		if baseline.samples ~= nil then
			recorded = metricValue(summaryOf(spec, baseline.samples), floorMetric)
		else
			recorded = baseline.value
		end
	end
	return observed ~= nil and recorded ~= nil and observed <= floor.limit and recorded <= floor.limit
end

local function comparisonOf(
	spec: Spec,
	baseline: Baseline?,
	summary: Performance.Summary,
	samples: { number },
	before: { number },
	after: { number }
): Comparison?
	local recorded = if baseline ~= nil then baselineValue(spec, baseline) else nil
	if baseline == nil or recorded == nil or #samples == 0 or baseline.unit ~= spec.unit then
		return nil
	end
	local value = metricValue(summary, baseline.metric)
	if value == nil then
		return nil
	end
	if baseline.yardstick ~= nil then
		if #before == 0 or #after == 0 then
			return nil
		end
		local current = yardstickNow(spec, baseline.yardstickStatistic, before, after)
		if current == nil or current <= 0 then
			return nil
		end
		local reference = recorded / baseline.yardstick
		local observed = value / current
		local limit = reference * (1 + baseline.tolerance)
		local floored = underFloor(spec, baseline, summary)
		return {
			metric = baseline.metric,
			observed = observed,
			baseline = reference,
			limit = limit,
			regressed = observed > limit and not floored,
			normalized = true,
			floored = floored,
		}
	end
	if baseline.environment ~= spec.environment.observed then
		return nil
	end
	local limit = recorded * (1 + baseline.tolerance)
	local floored = underFloor(spec, baseline, summary)
	return {
		metric = baseline.metric,
		observed = value,
		baseline = recorded,
		limit = limit,
		regressed = value > limit and not floored,
		normalized = false,
		floored = floored,
	}
end

local function baselineProblems(spec: Spec, baseline: Baseline): { string }
	local problems: { string } = {}
	if spec.acceptedBaselines ~= nil and not contains(spec.acceptedBaselines, baseline.identity) then
		table.insert(problems, ("baseline identity %q is not accepted"):format(baseline.identity))
	end
	if baseline.yardstick == nil and baseline.environment ~= spec.environment.observed then
		table.insert(
			problems,
			("baseline was recorded in %q, not the observed %q"):format(baseline.environment, spec.environment.observed)
		)
	end
	if baseline.unit ~= spec.unit then
		table.insert(problems, ("baseline unit %s differs from %s"):format(baseline.unit, spec.unit))
	end
	return problems
end

local function mismatches(spec: Spec): { string }
	local problems: { string } = {}
	if spec.baseline ~= nil then
		for _, problem in baselineProblems(spec, spec.baseline) do
			table.insert(problems, problem)
		end
	end
	local declared: { Phase } = spec.phases or {}
	for _, phase in declared do
		if phase.baseline ~= nil then
			for _, problem in baselineProblems(spec, phase.baseline) do
				table.insert(problems, ("phase %s: %s"):format(phase.name, problem))
			end
		end
	end
	return problems
end

local function phaseResult(
	spec: Spec,
	phase: Phase,
	samples: { number },
	series: Performance.Series,
	before: { number },
	after: { number }
): PhaseResult
	local summary = summaryOf(spec, samples, phase.name)
	local result: PhaseResult = {
		name = phase.name,
		measurement = spec.name .. "/" .. phase.name,
		samples = samples,
		summary = summary,
		spread = relativeSpread(samples),
		invalid = {},
		comparison = comparisonOf(spec, phase.baseline, summary, samples, before, after),
		judgment = nil,
		series = series,
	}
	if phase.maxSpread ~= nil and #samples > 0 then
		local spread = result.spread
		if spread ~= nil and spread > phase.maxSpread then
			table.insert(result.invalid, {
				reason = "unstable",
				detail = ("relative spread (p95-p50)/p50 of phase %s was %.3f, above the allowed %.3f"):format(
					phase.name,
					spread,
					phase.maxSpread
				),
			})
		end
	end
	return result
end

local function judgeResult(spec: Spec, result: Result)
	if result.failure ~= nil or #result.invalid > 0 or #result.samples ~= spec.samples then
		return
	end
	local function ask(
		judge: ((view: Judgment) -> string?)?,
		phase: string?,
		samples: { number },
		summary: Performance.Summary,
		series: Performance.Series
	): string?
		if judge == nil then
			return nil
		end
		local ok, verdict: unknown = pcall(judge, {
			phase = phase,
			samples = table.clone(samples),
			summary = summary,
			series = series,
			unit = spec.unit,
			yardstickBefore = table.clone(result.yardstickBefore),
			yardstickAfter = table.clone(result.yardstickAfter),
			yardstickBeforeSummary = summaryOf(spec, result.yardstickBefore),
			yardstickAfterSummary = summaryOf(spec, result.yardstickAfter),
			heap = result.heap,
		})
		if not ok then
			result.failure = "judge raised: " .. tostring(verdict)
			return nil
		end
		return if verdict ~= nil then tostring(verdict) else nil
	end
	result.judgment = ask(spec.judge, nil, result.samples, result.summary, result.series)
	for index, entry in result.phases do
		local phase = (spec.phases :: { Phase })[index]
		if #entry.invalid == 0 then
			entry.judgment = ask(phase.judge, phase.name, entry.samples, entry.summary, entry.series)
		end
	end
end

local function samplerFor(into: Performance.Series?): Sampler
	return {
		series = function(name: string, values: { number })
			assert(type(name) == "string" and string.find(name, "%S") ~= nil, "a series needs a name")
			assert(type(values) == "table", "a series holds an array of numbers")
			Performance.checkSeries { [name] = { values } }
			if into == nil then
				return
			end
			local runs = into[name]
			if runs == nil then
				runs = {}
				into[name] = runs
			end
			table.insert(runs, table.clone(values))
		end,
	}
end

local function invalidDuration(elapsed: number): boolean
	return elapsed ~= elapsed or elapsed < 0 or elapsed == math.huge
end

local function measure(spec: Spec, clock: Clock, started: number): Result
	local scale = SCALE[spec.unit]
	local iterations = spec.iterations or 1
	local phases: { Phase } = spec.phases or {}
	local samples: { number } = {}
	local series: Performance.Series = {}
	local phaseSamples: { { number } } = {}
	local phaseSeries: { Performance.Series } = {}
	for index in phases do
		phaseSamples[index] = {}
		phaseSeries[index] = {}
	end
	local yardstickBefore: { number } = {}
	local yardstickAfter: { number } = {}
	local invalid: { Invalid } = {}
	local failure: string? = nil
	local warmupRuns = 0
	local heapBefore: number? = nil

	local function finish(): Result
		local summary = summaryOf(spec, samples)
		local entries: { PhaseResult } = {}
		for index, phase in phases do
			table.insert(
				entries,
				phaseResult(spec, phase, phaseSamples[index], phaseSeries[index], yardstickBefore, yardstickAfter)
			)
		end
		local result: Result = {
			name = spec.name,
			unit = spec.unit,
			samples = samples,
			phases = entries,
			series = series,
			warmupRuns = warmupRuns,
			iterations = iterations,
			yardstickBefore = yardstickBefore,
			yardstickAfter = yardstickAfter,
			summary = summary,
			spread = relativeSpread(samples),
			invalid = invalid,
			comparison = nil,
			heap = nil,
			judgment = nil,
			failure = failure,
			elapsedSeconds = math.max(0, clock() - started),
		}
		result.comparison = comparisonOf(spec, spec.baseline, summary, samples, yardstickBefore, yardstickAfter)
		if spec.maxSpread ~= nil and #samples > 0 then
			local spread = result.spread
			if spread ~= nil and spread > spec.maxSpread then
				table.insert(invalid, {
					reason = "unstable",
					detail = ("relative spread (p95-p50)/p50 was %.3f, above the allowed %.3f"):format(
						spread,
						spec.maxSpread
					),
				})
			end
		end
		local tool = spec.yardstick
		if tool ~= nil then
			for _, issue in yardstickIssues(tool, yardstickBefore, yardstickAfter) do
				table.insert(invalid, issue)
			end
		end
		return result
	end

	local accepted = spec.environment.accepted
	if accepted ~= nil and not contains(accepted, spec.environment.observed) then
		table.insert(invalid, {
			reason = "environment_mismatch",
			detail = ("observed environment %q is not among the accepted %s"):format(
				spec.environment.observed,
				table.concat(accepted, ", ")
			),
		})
	end
	local problems = mismatches(spec)
	if #problems > 0 then
		table.insert(invalid, { reason = "baseline_mismatch", detail = table.concat(problems, "; ") })
	end
	if #invalid > 0 then
		return finish()
	end

	local function attempt(work: () -> ()): boolean
		local ok, thrown: unknown = pcall(work)
		if not ok then
			failure = "workload raised: " .. tostring(thrown)
			return false
		end
		return true
	end

	local function expired(): boolean
		return spec.deadlineSeconds ~= nil and clock() - started >= spec.deadlineSeconds
	end

	local heap = spec.heap
	local function heapReading(): HeapReading?
		if heap == nil or heapBefore == nil then
			return nil
		end
		local after = readHeap(heap)
		if after == nil then
			return nil
		end
		return { before = heapBefore, after = after, growth = after - heapBefore, unit = heap.unit }
	end
	local function finishWithHeap(): Result
		local result = finish()
		if heap ~= nil and failure == nil and #samples == spec.samples then
			result.heap = heapReading()
			if result.heap == nil then
				table.insert(result.invalid, {
					reason = "heap_unsupported",
					detail = "the heap probe did not return a finite non-negative reading",
				})
			end
		end
		return result
	end

	local function runSample(record: boolean): boolean
		local state: unknown = nil
		local prepare = spec.beforeSample
		if prepare ~= nil and not attempt(function()
			state = prepare()
		end) then
			return false
		end
		local ok = true
		if spec.phases ~= nil then
			local durations: { number } = {}
			for index, phase in phases do
				local tools = samplerFor(if record then phaseSeries[index] else nil)
				local before = if record then clock() else 0
				ok = attempt(function()
					phase.run(state, tools)
				end)
				if not ok then
					break
				end
				if record then
					local elapsed = clock() - before
					if invalidDuration(elapsed) then
						failure = "the clock produced an invalid sample duration"
						ok = false
						break
					end
					table.insert(durations, elapsed * scale)
				end
			end
			if ok and record then
				local total = 0
				for index, duration in durations do
					table.insert(phaseSamples[index], duration)
					total += duration
				end
				table.insert(samples, total)
			end
		else
			local work = spec.workload :: (unknown, Sampler) -> ()
			local tools = samplerFor(if record then series else nil)
			local before = if record then clock() else 0
			for _ = 1, if record then iterations else 1 do
				ok = attempt(function()
					work(state, tools)
				end)
				if not ok then
					break
				end
			end
			local finalize = spec.finalize
			if ok and finalize ~= nil and (record or spec.warmupScope == "sample") then
				ok = attempt(function()
					finalize(state, tools)
				end)
			end
			if ok and record then
				local elapsed = clock() - before
				if invalidDuration(elapsed) then
					failure = "the clock produced an invalid sample duration"
					ok = false
				else
					table.insert(samples, elapsed / iterations * scale)
				end
			end
		end
		local release = spec.afterSample
		if release ~= nil then
			local priorFailure = failure
			local tail =
				samplerFor(if not record then nil elseif spec.phases ~= nil then phaseSeries[#phases] else series)
			local released = attempt(function()
				release(state, tail)
			end)
			if priorFailure ~= nil then
				failure = priorFailure
			end
			ok = ok and released
		end
		return ok
	end

	for _ = 1, spec.warmup do
		if spec.warmupScope == "sample" then
			if not runSample(false) then
				return finish()
			end
		else
			local tools = samplerFor(nil)
			local ok = true
			if spec.phases ~= nil then
				for _, phase in phases do
					ok = attempt(function()
						phase.run(nil, tools)
					end)
					if not ok then
						break
					end
				end
			else
				local work = spec.workload :: (unknown, Sampler) -> ()
				ok = attempt(function()
					work(nil, tools)
				end)
			end
			if not ok then
				return finish()
			end
		end
		warmupRuns += 1
	end
	if heap ~= nil then
		heapBefore = readHeap(heap)
		if heapBefore == nil then
			table.insert(invalid, {
				reason = "heap_unsupported",
				detail = "the heap probe did not return a finite non-negative reading",
			})
			return finish()
		end
	end
	local tool = spec.yardstick
	if tool ~= nil then
		failure = timeYardstick(clock, scale, tool, yardstickBefore)
		if failure ~= nil then
			return finish()
		end
	end
	for _ = 1, spec.samples do
		if expired() then
			table.insert(invalid, {
				reason = "deadline_exceeded",
				detail = ("the %s second deadline elapsed after %d of %d samples"):format(
					tostring(spec.deadlineSeconds),
					#samples,
					spec.samples
				),
			})
			return finish()
		end
		if not runSample(true) then
			return finish()
		end
	end
	if tool ~= nil then
		failure = timeYardstick(clock, scale, tool, yardstickAfter)
		if failure ~= nil then
			return finish()
		end
	end
	return finishWithHeap()
end

local function blankResult(spec: Spec, failure: string?): Result
	local entries: { PhaseResult } = {}
	local declared: { Phase } = spec.phases or {}
	for _, phase in declared do
		table.insert(entries, phaseResult(spec, phase, {}, {}, {}, {}))
	end
	return {
		name = spec.name,
		unit = spec.unit,
		samples = {},
		phases = entries,
		series = {},
		warmupRuns = 0,
		iterations = spec.iterations or 1,
		yardstickBefore = {},
		yardstickAfter = {},
		summary = summaryOf(spec, {}),
		spread = nil,
		invalid = {},
		comparison = nil,
		heap = nil,
		judgment = nil,
		failure = failure,
		elapsedSeconds = 0,
	}
end

local function run(spec: Spec): Result
	check(spec)
	local clock: Clock = spec.clock or os.clock
	local started = clock()
	local setupFailure: string? = nil
	if spec.setup ~= nil then
		local ok, thrown: unknown = pcall(spec.setup)
		if not ok then
			setupFailure = "setup raised: " .. tostring(thrown)
		end
	end
	local result: Result
	if setupFailure ~= nil then
		result = blankResult(spec, setupFailure)
	else
		result = measure(spec, clock, started)
	end
	if spec.teardown ~= nil then
		local ok, thrown: unknown = pcall(spec.teardown)
		if not ok and result.failure == nil then
			result.failure = "teardown raised: " .. tostring(thrown)
		end
	end
	judgeResult(spec, result)
	result.elapsedSeconds = math.max(0, clock() - started)
	return result
end

local function withoutVerdicts(member: Spec): Spec
	local copy = table.clone(member)
	copy.baseline = nil
	copy.judge = nil
	if member.phases ~= nil then
		local stripped: { Phase } = {}
		for _, phase in member.phases do
			local plain = table.clone(phase)
			plain.baseline = nil
			plain.judge = nil
			table.insert(stripped, plain)
		end
		copy.phases = stripped
	end
	return copy
end

local function checkCollection(collection: Collection)
	assert(type(collection.name) == "string" and string.find(collection.name, "%S") ~= nil, "collection needs a name")
	assert(#collection.benchmarks > 0, "collection needs at least one benchmark")
	local tool = collection.yardstick
	assert(type(tool.run) == "function", "yardstick needs a run function")
	positiveWhole(tool.samples, "yardstick.samples")
	nonnegativeFinite(tool.maxSpread, "yardstick.maxSpread")
	nonnegativeFinite(tool.maxDrift, "yardstick.maxDrift")
	local unit = collection.benchmarks[1].unit
	for _, member in collection.benchmarks do
		check(member, true)
		assert(member.yardstick == nil, "a collection owns the yardstick; a member declares none")
		assert(member.unit == unit, "every member of a collection shares one unit")
	end
end

local function collect(collection: Collection): CollectionResult
	checkCollection(collection)
	local tool = collection.yardstick
	local clock: Clock = collection.clock or os.clock
	local unit: Unit = collection.benchmarks[1].unit
	local scale = SCALE[unit]
	local before: { number } = {}
	local after: { number } = {}
	local results: { Result } = {}
	local invalid: { Invalid } = {}
	local failure = timeYardstick(clock, scale, tool, before)
	if failure == nil then
		for _, member in collection.benchmarks do
			local copy = withoutVerdicts(member)
			copy.clock = member.clock or clock
			table.insert(results, run(copy))
		end
		failure = timeYardstick(clock, scale, tool, after)
		if failure == nil then
			invalid = yardstickIssues(tool, before, after)
			for index, result in results do
				local member = collection.benchmarks[index]
				result.yardstickBefore = table.clone(before)
				result.yardstickAfter = table.clone(after)
				local problems = mismatches(member)
				if #problems > 0 then
					table.insert(
						result.invalid,
						{ reason = "baseline_mismatch", detail = table.concat(problems, "; ") }
					)
				end
				result.comparison = comparisonOf(member, member.baseline, result.summary, result.samples, before, after)
				for position, entry in result.phases do
					local phase = (member.phases :: { Phase })[position]
					entry.comparison = comparisonOf(member, phase.baseline, entry.summary, entry.samples, before, after)
				end
				if #invalid == 0 then
					judgeResult(member, result)
				end
			end
		end
	end
	return {
		name = collection.name,
		results = results,
		yardstickBefore = before,
		yardstickAfter = after,
		invalid = invalid,
		failure = failure,
	}
end

local function limitsFor(spec: Spec, budget: Budget?): Performance.Limits
	local declared: Budget = if budget ~= nil then budget else {}
	return {
		unit = spec.unit,
		minimumSamples = spec.samples,
		p50 = declared.p50,
		p95 = declared.p95,
		p99 = declared.p99,
		maximum = declared.maximum,
		measureOnly = declared.p50 == nil and declared.p95 == nil and declared.p99 == nil and declared.maximum == nil,
	}
end

local function limitsOf(spec: Spec): Performance.Limits
	return limitsFor(spec, spec.budget)
end

local function inputOf(
	spec: Spec,
	samples: { number },
	summary: Performance.Summary,
	series: Performance.Series
): Performance.Input
	return {
		samples = samples,
		unit = spec.unit,
		context = summary.context,
		percentiles = spec.percentiles,
		series = if next(series) ~= nil then series else nil,
	}
end

local function record(context: Harness.Context, label: string, input: Performance.Input, limits: Performance.Limits)
	if #input.samples == 0 then
		return
	end
	local measured, thrown: unknown = pcall(context.measure, context, "benchmark", label, input, limits)
	if not measured and type(thrown) ~= "table" then
		error(thrown, 0)
	end
end

local function regression(label: string, comparison: Comparison?): string?
	if comparison == nil or not comparison.regressed then
		return nil
	end
	return ("%s %s %.4g exceeds the %sbaseline %.4g plus tolerance (limit %.4g)"):format(
		label,
		comparison.metric,
		comparison.observed,
		if comparison.normalized then "yardstick-normalized " else "",
		comparison.baseline,
		comparison.limit
	)
end

local function noteInvalid(context: Harness.Context, prefix: string, entries: { Invalid })
	for _, entry in entries do
		pcall(context.step, context, ("%s: %s (%s)"):format(prefix, entry.reason, entry.detail), function()
			context:unsupported("measurement:" .. entry.reason)
		end)
	end
end

local function report(context: Harness.Context, spec: Spec, result: Result)
	local plain = spec.phases == nil
	if plain then
		record(context, spec.name, inputOf(spec, result.samples, result.summary, result.series), limitsOf(spec))
	end
	for index, entry in result.phases do
		local phase = (spec.phases :: { Phase })[index]
		record(
			context,
			entry.measurement,
			inputOf(spec, entry.samples, entry.summary, entry.series),
			limitsFor(spec, phase.budget)
		)
	end
	local heap = result.heap
	if heap ~= nil then
		context:step(
			("heap %s: %.4g -> %.4g %s (growth %.4g)"):format(
				spec.name,
				heap.before,
				heap.after,
				heap.unit,
				heap.growth
			),
			function() end
		)
		local limit = if spec.heap ~= nil then spec.heap.maximumGrowth else nil
		if limit ~= nil and heap.growth > limit then
			error(("%s heap grew %.4g %s, above the allowed %.4g"):format(spec.name, heap.growth, heap.unit, limit), 0)
		end
	end
	for _, entry in result.phases do
		local refusal = regression(entry.measurement, entry.comparison)
		if refusal == nil and entry.judgment ~= nil then
			refusal = ("%s was refused by its judge: %s"):format(entry.measurement, entry.judgment)
		end
		if refusal ~= nil then
			local message = refusal
			pcall(context.step, context, "refused " .. entry.measurement, function()
				error(message, 0)
			end)
		end
	end
	local refusal = regression(spec.name, result.comparison)
	if refusal ~= nil then
		error(refusal, 0)
	end
	if result.judgment ~= nil then
		error(("%s was refused by its judge: %s"):format(spec.name, result.judgment), 0)
	end
	if result.failure ~= nil then
		error(result.failure :: string, 0)
	end
	noteInvalid(context, "benchmark invalid", result.invalid)
	for _, entry in result.phases do
		noteInvalid(context, "benchmark invalid " .. entry.measurement, entry.invalid)
	end
end

local function limitations(spec: Spec): { string }?
	local notes: { string } = {}
	if spec.phases == nil then
		if limitsOf(spec).measureOnly == true then
			table.insert(notes, "measured only: no budget declared")
		end
	else
		for _, phase in spec.phases do
			if limitsFor(spec, phase.budget).measureOnly == true then
				table.insert(notes, ("measured only: no budget declared for phase %s"):format(phase.name))
			end
		end
	end
	return if #notes > 0 then notes else nil
end

local function case(spec: Spec): Harness.CaseOptions
	check(spec)
	return {
		timeoutSeconds = if spec.deadlineSeconds ~= nil then spec.deadlineSeconds + 5 else nil,
		tags = spec.tags,
		limitations = limitations(spec),
		run = function(context: Harness.Context)
			report(context, spec, run(spec))
		end,
	}
end

local function collectionCase(collection: Collection): Harness.CaseOptions
	checkCollection(collection)
	return {
		run = function(context: Harness.Context)
			local collected = collect(collection)
			local firstFailure: unknown = nil
			for index, result in collected.results do
				local reported, thrown: unknown = pcall(report, context, collection.benchmarks[index], result)
				if not reported and firstFailure == nil and type(thrown) ~= "table" then
					firstFailure = thrown
				end
			end
			if collected.failure ~= nil then
				error(collected.failure :: string, 0)
			end
			if firstFailure ~= nil then
				error(firstFailure, 0)
			end
			for _, entry in collected.invalid do
				pcall(
					context.step,
					context,
					("collection invalid: %s (%s)"):format(entry.reason, entry.detail),
					function()
						context:unsupported("measurement:" .. entry.reason)
					end
				)
			end
		end,
	}
end

local luauHeap: Heap = {
	unit = "kilobytes",
	probe = function(): number?
		local compiled = if loadstring ~= nil then loadstring "return collectgarbage('count')" else nil
		if compiled == nil then
			return nil
		end
		local ok, value: unknown = pcall(compiled)
		return if ok and type(value) == "number" then value else nil
	end,
}

local function store(name: string, results: { Result }): Stored
	assert(type(name) == "string" and string.find(name, "%S") ~= nil, "a stored run needs a name")
	assert(#results > 0, "a stored run needs at least one result")
	local measurements: { StoredMeasurement } = {}
	for _, result in results do
		local environment = result.summary.context.environment
		if #result.phases == 0 then
			local entry: StoredMeasurement = {
				name = result.name,
				unit = result.unit,
				environment = environment,
				samples = table.clone(result.samples),
			}
			table.insert(measurements, entry)
		end
		for _, phase in result.phases do
			local entry: StoredMeasurement = {
				name = phase.measurement,
				unit = result.unit,
				environment = environment,
				samples = table.clone(phase.samples),
			}
			table.insert(measurements, entry)
		end
	end
	return Store.decode { schemaVersion = Store.SCHEMA_VERSION, name = name, measurements = measurements }
end

local function storeReport(name: string, report: Harness.Report): Stored
	assert(type(name) == "string" and string.find(name, "%S") ~= nil, "a stored run needs a name")
	assert(type(report) == "table" and type(report.results) == "table", "a stored run needs a report")
	local measurements: { StoredMeasurement } = {}
	for _, result in report.results do
		if result.evidence ~= nil then
			for _, measurement in result.evidence.measurements do
				local entry: StoredMeasurement = {
					name = measurement.name,
					unit = measurement.input.unit,
					environment = measurement.input.context.environment,
					samples = table.clone(measurement.input.samples),
				}
				table.insert(measurements, entry)
			end
		end
	end
	assert(#measurements > 0, "the report carries no measurement evidence")
	return Store.decode { schemaVersion = Store.SCHEMA_VERSION, name = name, measurements = measurements }
end

return {
	store = store,
	storeReport = storeReport,
	decode = Store.decode,
	compare = Store.compare,
	spread = Store.spread,
	check = check,
	checkCollection = checkCollection,
	run = run,
	case = case,
	collect = collect,
	collection = collectionCase,
	luauHeap = luauHeap,
	limits = limitsOf,
}
