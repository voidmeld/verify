--!strict

local Core = require "./core"
local Performance = require "./core/performance"

export type StoredMeasurement = {
	name: string,
	unit: string,
	environment: string,
	samples: { number },
}

export type Stored = {
	schemaVersion: number,
	name: string,
	measurements: { StoredMeasurement },
}

export type CompareMetric = "p50" | "p95" | "p99" | "maximum"
export type SpreadMetric = "p50" | "p95" | "p99" | "maximum" | "mean"

export type Rule = {
	ratio: number,
	floor: number,
	metric: CompareMetric?,
}

export type CompareOptions = {
	rule: Rule,
	rules: { [string]: Rule }?,
	minimumSamples: number?,
	executor: string?,
	now: (() -> number)?,
}

export type SpreadOptions = {
	metric: SpreadMetric?,
}

export type Noise = {
	name: string,
	unit: string,
	runs: number,
	metric: SpreadMetric,
	values: { number },
	minimum: number,
	maximum: number,
	median: number,
	mean: number,
	deviation: number,
	relativeRange: number?,
}

export type SpreadSummary = {
	runs: number,
	noise: { Noise },
	incomplete: { string },
}

local SCHEMA_VERSION = 1

local function text(value: unknown, label: string): string
	assert(type(value) == "string" and string.find(value, "%S") ~= nil, label .. " must be a nonempty string")
	return value :: string
end

local function nonnegativeFinite(value: unknown, label: string): number
	assert(
		type(value) == "number" and value == value and value >= 0 and value < math.huge,
		label .. " must be finite and nonnegative"
	)
	return value :: number
end

local function decode(value: unknown): Stored
	assert(type(value) == "table", "a stored run must be a table")
	local raw = value :: { [string]: unknown }
	assert(raw.schemaVersion == SCHEMA_VERSION, "unsupported stored run schema version")
	local rows = raw.measurements
	assert(type(rows) == "table" and #(rows :: { unknown }) > 0, "a stored run needs measurements")
	local measurements: { StoredMeasurement } = {}
	local seen: { [string]: boolean } = {}
	for index, item in rows :: { unknown } do
		assert(type(item) == "table", "a stored measurement must be a table")
		local row = item :: { [string]: unknown }
		local name = text(row.name, "measurement name")
		assert(not seen[name], ("stored measurement %q is listed twice"):format(name))
		seen[name] = true
		local listed = row.samples
		assert(type(listed) == "table" and #(listed :: { unknown }) > 0, "stored samples must not be empty")
		local samples: { number } = {}
		for position, sample in listed :: { unknown } do
			assert(position == #samples + 1, "stored samples must be a dense array")
			table.insert(samples, nonnegativeFinite(sample, "stored sample"))
		end
		assert(index == #measurements + 1, "stored measurements must be a dense array")
		table.insert(measurements, {
			name = name,
			unit = text(row.unit, "measurement unit"),
			environment = text(row.environment, "measurement environment"),
			samples = samples,
		})
	end
	return { schemaVersion = SCHEMA_VERSION, name = text(raw.name, "stored run name"), measurements = measurements }
end

local function metricOf(measurement: StoredMeasurement, metric: SpreadMetric): number
	local summary = Performance.summarize {
		samples = measurement.samples,
		unit = measurement.unit,
		context = { environment = measurement.environment, signal = measurement.name, timing = "observed" },
	}
	local value = if metric == "mean"
		then summary.mean
		elseif metric == "maximum" then summary.maximum
		else summary[metric]
	return value :: number
end

local function indexOf(run: Stored): { [string]: StoredMeasurement }
	local byName: { [string]: StoredMeasurement } = {}
	for _, measurement in run.measurements do
		byName[measurement.name] = measurement
	end
	return byName
end

local function checkRule(rule: Rule, label: string)
	assert(type(rule) == "table", label .. " must be a table")
	assert(
		type(rule.ratio) == "number" and rule.ratio >= 1 and rule.ratio < math.huge,
		label .. ".ratio must be finite and at least one"
	)
	nonnegativeFinite(rule.floor, label .. ".floor")
	assert(
		rule.metric == nil
			or rule.metric == "p50"
			or rule.metric == "p95"
			or rule.metric == "p99"
			or rule.metric == "maximum",
		label .. ".metric must be p50, p95, p99 or maximum"
	)
end

local function compare(baseline: Stored, candidate: Stored, options: CompareOptions): Core.Report
	local left = decode(baseline)
	local right = decode(candidate)
	checkRule(options.rule, "rule")
	local overrides: { [string]: Rule } = options.rules or {}
	for name, rule in overrides do
		checkRule(rule, ("rules[%q]"):format(name))
	end
	local minimumSamples = if options.minimumSamples ~= nil then options.minimumSamples else 1
	assert(minimumSamples >= 1 and minimumSamples % 1 == 0, "minimumSamples must be a positive whole count")
	local baselineIndex = indexOf(left)
	local candidateIndex = indexOf(right)
	local harness = Core.createHarness { now = options.now or os.clock }
	local order: { string } = {}
	for _, measurement in left.measurements do
		table.insert(order, measurement.name)
	end
	local extra: { string } = {}
	for _, measurement in right.measurements do
		if baselineIndex[measurement.name] == nil then
			table.insert(extra, measurement.name)
		end
	end
	table.sort(extra)
	for _, name in extra do
		table.insert(order, name)
	end
	for _, name in order do
		harness:case(name, function(context)
			local before = baselineIndex[name]
			local after = candidateIndex[name]
			if before == nil then
				error(("the baseline run %q has no measurement %q"):format(left.name, name), 0)
			end
			if after == nil then
				error(("the candidate run %q has no measurement %q"):format(right.name, name), 0)
			end
			if before.unit ~= after.unit then
				error(("%s was stored in %s and %s"):format(name, before.unit, after.unit), 0)
			end
			if before.environment ~= after.environment then
				error(("%s was observed in %q and %q"):format(name, before.environment, after.environment), 0)
			end
			local rule: Rule = if options.rules ~= nil and options.rules[name] ~= nil
				then options.rules[name]
				else options.rule
			local metric: CompareMetric = rule.metric or "p50"
			local reference = metricOf(before, metric)
			local limit = math.max(reference * rule.ratio, reference + rule.floor)
			context:step(
				("%s %s: baseline %.4g, candidate %.4g, limit %.4g %s"):format(
					name,
					metric,
					reference,
					metricOf(after, metric),
					limit,
					after.unit
				),
				function() end
			)
			context:measure("compare", name, {
				samples = after.samples,
				unit = after.unit,
				context = { environment = after.environment, signal = name, timing = "observed" },
			}, {
				unit = after.unit,
				minimumSamples = minimumSamples,
				p50 = if metric == "p50" then limit else nil,
				p95 = if metric == "p95" then limit else nil,
				p99 = if metric == "p99" then limit else nil,
				maximum = if metric == "maximum" then limit else nil,
			})
		end)
	end
	return harness:run {
		executor = options.executor or "benchmark-compare",
		capabilities = {},
		environment = { baseline = left.name, candidate = right.name },
	}
end

local function spread(runs: { Stored }, options: SpreadOptions?): SpreadSummary
	assert(type(runs) == "table" and #runs >= 2, "spread needs at least two stored runs")
	local metric: SpreadMetric = if options ~= nil and options.metric ~= nil then options.metric else "p50"
	assert(
		metric == "p50" or metric == "p95" or metric == "p99" or metric == "maximum" or metric == "mean",
		"metric must be p50, p95, p99, maximum or mean"
	)
	local checked: { Stored } = {}
	for _, run in runs do
		table.insert(checked, decode(run))
	end
	local indexes: { { [string]: StoredMeasurement } } = {}
	for _, run in checked do
		table.insert(indexes, indexOf(run))
	end
	local noise: { Noise } = {}
	local incomplete: { string } = {}
	local names: { string } = {}
	local known: { [string]: boolean } = {}
	for _, run in checked do
		for _, measurement in run.measurements do
			if not known[measurement.name] then
				known[measurement.name] = true
				table.insert(names, measurement.name)
			end
		end
	end
	for _, name in names do
		local present: { StoredMeasurement } = {}
		for _, index in indexes do
			if index[name] ~= nil then
				table.insert(present, index[name])
			end
		end
		if #present < #checked then
			table.insert(incomplete, name)
			continue
		end
		local values: { number } = {}
		for _, measurement in present do
			assert(
				measurement.unit == present[1].unit and measurement.environment == present[1].environment,
				("%s differs in unit or environment between runs"):format(name)
			)
			table.insert(values, metricOf(measurement, metric))
		end
		local summary = Performance.summarize {
			samples = values,
			unit = present[1].unit,
			context = { environment = present[1].environment, signal = name, timing = "observed" },
		}
		local midpoint = summary.p50 :: number
		local range = (summary.maximum :: number) - (summary.minimum :: number)
		table.insert(noise, {
			name = name,
			unit = present[1].unit,
			runs = #present,
			metric = metric,
			values = values,
			minimum = summary.minimum :: number,
			maximum = summary.maximum :: number,
			median = midpoint,
			mean = summary.mean :: number,
			deviation = summary.deviation :: number,
			relativeRange = if midpoint > 0 then range / midpoint elseif range == 0 then 0 else nil,
		})
	end
	return { runs = #checked, noise = noise, incomplete = incomplete }
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	decode = decode,
	compare = compare,
	spread = spread,
}
