--!strict

local createCases = require "./benchmark-case"
local Performance = require "./core/performance"
local Check = require "./benchmark-check"
local Store = require "./benchmark-store"
local Types = require "./benchmark-types"

export type Stored = Store.Stored
export type StoredMeasurement = Store.StoredMeasurement
export type CompareRule = Store.Rule
export type CompareOptions = Store.CompareOptions
export type CollectionAttempt = Types.CollectionAttempt
export type CompareMetric = Store.CompareMetric
export type SpreadOptions = Store.SpreadOptions
export type SpreadMetric = Store.SpreadMetric
export type Noise = Store.Noise
export type SpreadSummary = Store.SpreadSummary
export type Unit = Types.Unit
export type Clock = Types.Clock
export type Metric = Types.Metric
export type HeapReading = Types.HeapReading
export type Budget = Types.Budget
export type Yardstick = Types.Yardstick
export type DriftBase = Types.DriftBase
export type Baseline = Types.Baseline
export type YardstickStatistic = Types.YardstickStatistic
export type Floor = Types.Floor
export type Heap = Types.Heap
export type Judgment = Types.Judgment
export type Sampler = Types.Sampler
export type WarmupScope = Types.WarmupScope
export type Phase = Types.Phase
export type Spec = Types.Spec
export type Collection = Types.Collection
export type InvalidReason = Types.InvalidReason
export type Invalid = Types.Invalid
export type Comparison = Types.Comparison
export type PhaseResult = Types.PhaseResult
export type Result = Types.Result
export type CollectionResult = Types.CollectionResult

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
	local samples = baseline.samples
	assert(samples ~= nil)
	return metricValue(summaryOf(spec, samples), baseline.metric)
end

local function yardstickIssues(spec: Spec, tool: Yardstick, before: { number }, after: { number }): { Invalid }
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
	local statistic: YardstickStatistic = tool.driftStatistic or "median"
	local first = if statistic == "p95" then summaryOf(spec, before).p95 or 0 else median(before)
	local last = if statistic == "p95" then summaryOf(spec, after).p95 or 0 else median(after)
	local base = if tool.driftBase == "mean" then (first + last) / 2 else first
	local drift = if base == 0 then (if last == first then 0 else math.huge) else math.abs(last - first) / base
	if drift > tool.maxDrift then
		table.insert(issues, {
			reason = "yardstick_drift",
			detail = ("yardstick %s moved %.3f between the start and end, above the allowed %.3f"):format(
				statistic,
				drift,
				tool.maxDrift
			),
		})
	end
	return issues
end

local function timeYardstick(clock: Clock, scale: number, tool: Yardstick, into: { number }): string?
	local iterations = tool.iterations or 1
	local function batch()
		for _ = 1, iterations do
			tool.run()
		end
	end
	for _ = 1, tool.warmup or 0 do
		local ok, thrown: unknown = pcall(batch)
		if not ok then
			return "workload raised: " .. tostring(thrown)
		end
	end
	for _ = 1, tool.samples do
		local before = clock()
		local ok, thrown: unknown = pcall(batch)
		if not ok then
			return "workload raised: " .. tostring(thrown)
		end
		local elapsed = clock() - before
		if elapsed ~= elapsed or elapsed < 0 or elapsed == math.huge then
			return "the clock produced an invalid yardstick duration"
		end
		table.insert(into, elapsed * scale / iterations)
	end
	return nil
end

local function readHeap(heap: Heap): number?
	local ok, value = pcall(heap.probe)
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
		local ok, verdict = pcall(judge, {
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
		local phases = spec.phases
		assert(phases ~= nil)
		local phase = phases[index]
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
	local scale = Types.SCALE[spec.unit]
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
			attempts = 1,
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
			for _, issue in yardstickIssues(spec, tool, yardstickBefore, yardstickAfter) do
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
			local work = spec.workload
			assert(work ~= nil)
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
				local work = spec.workload
				assert(work ~= nil)
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
		attempts = 0,
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
		invalid = {},
		failure = failure,
		elapsedSeconds = 0,
	}
end

local function retryDrift(result: Result): boolean
	if result.failure ~= nil then
		return false
	end
	local drifted = false
	for _, issue in result.invalid do
		if issue.reason == "yardstick_drift" then
			drifted = true
		elseif issue.reason ~= "yardstick_unstable" then
			return false
		end
	end
	for _, phase in result.phases do
		if #phase.invalid > 0 then
			return false
		end
	end
	return drifted
end

local function run(spec: Spec): Result
	Check.check(spec)
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
		for attempt = 2, 3 do
			if not retryDrift(result) then
				break
			end
			result = measure(spec, clock, started)
			result.attempts = attempt
		end
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

local function collectOnce(collection: Collection): CollectionResult
	Check.checkCollection(collection)
	local tool = collection.yardstick
	local clock: Clock = collection.clock or os.clock
	local unit: Unit = collection.benchmarks[1].unit
	local scale = Types.SCALE[unit]
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
			invalid = yardstickIssues(collection.benchmarks[1], tool, before, after)
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
					local phases = member.phases
					assert(phases ~= nil)
					local phase = phases[position]
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

local function retryCalibration(result: CollectionResult): boolean
	if result.failure ~= nil or #result.invalid == 0 then
		return false
	end
	for _, issue in result.invalid do
		if issue.reason ~= "yardstick_drift" and issue.reason ~= "yardstick_unstable" then
			return false
		end
	end
	for _, member in result.results do
		if member.failure ~= nil or #member.invalid > 0 then
			return false
		end
		for _, phase in member.phases do
			if #phase.invalid > 0 then
				return false
			end
		end
	end
	return true
end

local function collect(collection: Collection): CollectionResult
	Check.checkCollection(collection)
	local result = collectOnce(collection)
	local allowed = collection.calibrationAttempts or 1
	if allowed < 2 then
		return result
	end
	local attempts: { CollectionAttempt } = { table.clone(result) }
	while #attempts < allowed and retryCalibration(result) do
		result = collectOnce(collection)
		table.insert(attempts, table.clone(result))
	end
	result.attempts = attempts
	return result
end

local cases = createCases(run, collect)

return {
	store = Store.store,
	storeReport = Store.storeReport,
	decode = Store.decode,
	compare = Store.compare,
	spread = Store.spread,
	check = Check.check,
	checkCollection = Check.checkCollection,
	run = run,
	case = cases.case,
	collect = collect,
	collection = cases.collection,
	limits = cases.limits,
}
