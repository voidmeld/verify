--!strict

export type Context = { environment: string, signal: string, timing: "observed" | "simulated" }
export type Series = { [string]: { { number } } }
export type Input = {
	samples: { number },
	unit: string,
	context: Context,
	threshold: number?,
	percentiles: { number }?,
	series: Series?,
}
export type PercentileValue = { percentile: number, value: number }
export type Summary = {
	unit: string,
	context: Context,
	sampleCount: number,
	minimum: number?,
	mean: number?,
	total: number?,
	deviation: number?,
	p50: number?,
	p95: number?,
	p99: number?,
	percentiles: { PercentileValue }?,
	maximum: number?,
	threshold: number?,
	aboveThresholdCount: number?,
	aboveThresholdRatio: number?,
}
export type Limits = {
	unit: string,
	minimumSamples: number,
	p50: number?,
	p95: number?,
	p99: number?,
	maximum: number?,
	aboveThresholdRatio: number?,
	threshold: number?,
	measureOnly: boolean?,
}
export type Metric = "p50" | "p95" | "p99" | "maximum" | "aboveThresholdRatio"
export type Violation = { metric: Metric, observed: number, limit: number }
export type Evaluation = {
	status: "passed" | "failed" | "unsupported",
	reason: "within_limits"
		| "limit_exceeded"
		| "measured"
		| "unmeasured"
		| "insufficient_samples"
		| "simulated"
		| "unit_mismatch"
		| "threshold_mismatch",
	summary: Summary,
	violations: { Violation },
}

local function nonnegative(value: number): boolean
	return value == value and value >= 0 and value < math.huge
end

local function label(value: string, name: string)
	assert(string.find(value, "%S") ~= nil, name .. " must name its measurement context")
end

local function context(value: Context)
	label(value.environment, "environment")
	label(value.signal, "signal")
	assert(value.timing == "observed" or value.timing == "simulated", "timing must be observed or simulated")
end

local function nearestRank(sorted: { number }, percentile: number): number?
	if #sorted == 0 then
		return nil
	end
	return sorted[math.min(#sorted, math.max(1, math.ceil(#sorted * percentile / 100)))]
end

local function checkedPercentiles(values: { number }?): { number }?
	if values == nil then
		return nil
	end
	assert(type(values) == "table" and #values > 0, "percentiles must be a nonempty array")
	local sorted: { number } = {}
	for index, value in values do
		assert(index >= 1 and index % 1 == 0 and index <= #values, "percentiles must be a dense array")
		assert(
			type(value) == "number" and value == value and value > 0 and value <= 100,
			"a percentile must be greater than 0 and at most 100"
		)
		table.insert(sorted, value)
	end
	table.sort(sorted)
	for index = 2, #sorted do
		assert(sorted[index] ~= sorted[index - 1], "percentiles must be unique")
	end
	return sorted
end

local function checkedSeries(series: Series?)
	if series == nil then
		return
	end
	assert(type(series) == "table", "series must be a table")
	for name, runs in series do
		assert(type(name) == "string" and string.find(name, "%S") ~= nil, "a series needs a name")
		assert(type(runs) == "table", "a series holds an array of arrays")
		local runCount = 0
		for index, values in runs do
			assert(type(index) == "number" and index >= 1 and index % 1 == 0, "series must hold dense arrays")
			assert(type(values) == "table", "a series holds an array of arrays")
			runCount += 1
			local valueCount = 0
			for position, value in values do
				assert(
					type(position) == "number" and position >= 1 and position % 1 == 0,
					"series values must be a dense array"
				)
				assert(
					type(value) == "number" and value == value and value > -math.huge and value < math.huge,
					"series values must be finite numbers"
				)
				valueCount += 1
			end
			assert(valueCount == #values, "series values must be a dense array")
		end
		assert(runCount == #runs, "series must hold dense arrays")
	end
end

local function summarize(input: Input): Summary
	label(input.unit, "unit")
	context(input.context)
	if input.threshold ~= nil then
		assert(nonnegative(input.threshold), "threshold must be finite and nonnegative")
	end
	local requested = checkedPercentiles(input.percentiles)
	checkedSeries(input.series)
	local count = 0
	for index, value in input.samples do
		assert(index >= 1 and index % 1 == 0 and index <= #input.samples, "samples must be a dense array")
		assert(nonnegative(value), "samples must be finite and nonnegative")
		count += 1
	end
	assert(count == #input.samples, "samples must be a dense array")
	local sorted = table.clone(input.samples)
	table.sort(sorted)
	local mean = 0
	local total = 0
	local above = 0
	for index, value in sorted do
		total += value
		mean += (value - mean) / index
		if input.threshold ~= nil and value > input.threshold then
			above += 1
		end
	end
	local squares = 0
	for _, value in sorted do
		squares += (value - mean) ^ 2
	end
	local extra: { PercentileValue }? = nil
	if requested ~= nil then
		extra = {}
		for _, percentile in requested do
			local value = nearestRank(sorted, percentile)
			if value ~= nil then
				table.insert(extra :: { PercentileValue }, { percentile = percentile, value = value })
			end
		end
	end
	return {
		unit = input.unit,
		context = table.clone(input.context),
		sampleCount = count,
		minimum = sorted[1],
		mean = if count > 0 then mean else nil,
		total = if count > 0 then total else nil,
		deviation = if count > 0 then math.sqrt(squares / count) else nil,
		p50 = nearestRank(sorted, 50),
		p95 = nearestRank(sorted, 95),
		p99 = nearestRank(sorted, 99),
		percentiles = extra,
		maximum = sorted[count],
		threshold = input.threshold,
		aboveThresholdCount = if input.threshold ~= nil and count > 0 then above else nil,
		aboveThresholdRatio = if input.threshold ~= nil and count > 0 then above / count else nil,
	}
end

local function evaluate(summary: Summary, limits: Limits): Evaluation
	label(summary.unit, "unit")
	label(limits.unit, "limit unit")
	context(summary.context)
	assert(nonnegative(summary.sampleCount) and summary.sampleCount % 1 == 0, "sampleCount must be a whole count")
	assert(
		nonnegative(limits.minimumSamples) and limits.minimumSamples >= 1 and limits.minimumSamples % 1 == 0,
		"minimumSamples must be a positive whole count"
	)
	local checks: { { metric: Metric, observed: number?, limit: number? } } = {
		{ metric = "p50", observed = summary.p50, limit = limits.p50 },
		{ metric = "p95", observed = summary.p95, limit = limits.p95 },
		{ metric = "p99", observed = summary.p99, limit = limits.p99 },
		{ metric = "maximum", observed = summary.maximum, limit = limits.maximum },
		{ metric = "aboveThresholdRatio", observed = summary.aboveThresholdRatio, limit = limits.aboveThresholdRatio },
	}
	local declared = 0
	for _, check in checks do
		if check.observed ~= nil then
			assert(nonnegative(check.observed), "observed metrics must be finite and nonnegative")
		end
		if check.limit ~= nil then
			assert(nonnegative(check.limit), "limits must be finite and nonnegative")
			declared += 1
		end
	end
	assert(declared > 0 or limits.measureOnly == true, "at least one performance limit is required")
	if limits.aboveThresholdRatio ~= nil then
		assert(limits.aboveThresholdRatio <= 1, "ratio limit must not exceed one")
		assert(
			limits.threshold ~= nil and nonnegative(limits.threshold),
			"ratio limit requires a finite nonnegative threshold"
		)
	end
	local result: Evaluation = { status = "unsupported", reason = "unmeasured", summary = summary, violations = {} }
	if summary.sampleCount == 0 then
		return result
	end
	if summary.context.timing == "simulated" then
		result.reason = "simulated"
		return result
	end
	if summary.unit ~= limits.unit then
		result.reason = "unit_mismatch"
		return result
	end
	if summary.sampleCount < limits.minimumSamples then
		result.reason = "insufficient_samples"
		return result
	end
	if limits.aboveThresholdRatio ~= nil and summary.threshold ~= limits.threshold then
		result.reason = "threshold_mismatch"
		return result
	end
	if declared == 0 then
		result.status = "passed"
		result.reason = "measured"
		return result
	end
	for _, check in checks do
		if check.limit ~= nil then
			if check.observed == nil then
				return result
			end
			if check.observed > check.limit then
				table.insert(
					result.violations,
					{ metric = check.metric, observed = check.observed, limit = check.limit }
				)
			end
		end
	end
	result.status = if #result.violations == 0 then "passed" else "failed"
	result.reason = if #result.violations == 0 then "within_limits" else "limit_exceeded"
	return result
end

return { summarize = summarize, evaluate = evaluate, checkSeries = checkedSeries }
