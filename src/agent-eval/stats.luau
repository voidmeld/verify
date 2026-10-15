--!strict

local Random = require "./random"

export type Interval = {
	estimate: number?,
	lower: number?,
	upper: number?,
	resamples: number,
	valid: number,
	confidence: number,
}

export type BootstrapOptions<T> = {
	units: { T },
	statistic: (sample: { T }) -> number?,
	resamples: number?,
	seed: number,
	confidence: number?,
}

local function sorted(values: { number }): { number }
	local copy = table.clone(values)
	table.sort(copy)
	return copy
end

local function percentile(values: { number }, rank: number): number?
	assert(rank > 0 and rank <= 100, "a percentile rank is above 0 and at most 100")
	if #values == 0 then
		return nil
	end
	local ordered = sorted(values)
	local index = math.max(1, math.ceil(rank / 100 * #ordered))
	return ordered[index]
end

local function mean(values: { number }): number?
	if #values == 0 then
		return nil
	end
	local sum = 0
	for _, value in values do
		sum += value
	end
	return sum / #values
end

local function median(values: { number }): number?
	if #values == 0 then
		return nil
	end
	local ordered = sorted(values)
	local middle = #ordered // 2
	if #ordered % 2 == 1 then
		return ordered[middle + 1]
	end
	return (ordered[middle] + ordered[middle + 1]) / 2
end

local function quantile(ordered: { number }, fraction: number): number
	local position = fraction * (#ordered - 1) + 1
	local below = math.floor(position)
	local above = math.min(#ordered, below + 1)
	local weight = position - below
	return ordered[below] * (1 - weight) + ordered[above] * weight
end

local function bootstrap<T>(options: BootstrapOptions<T>): Interval
	local confidence = options.confidence or 0.95
	assert(confidence > 0 and confidence < 1, "a confidence level is between 0 and 1")
	local resamples = options.resamples or 2000
	assert(resamples >= 1 and resamples % 1 == 0, "a bootstrap needs a positive whole number of resamples")
	local units = options.units
	local interval: Interval = {
		resamples = resamples,
		valid = 0,
		confidence = confidence,
	}
	if #units == 0 then
		return interval
	end
	interval.estimate = options.statistic(units)
	local generator = Random.generator(options.seed)
	local values: { number } = {}
	local sample: { T } = table.create(#units)
	for _ = 1, resamples do
		for index = 1, #units do
			sample[index] = units[generator.integer(1, #units)]
		end
		local value = options.statistic(sample)
		if value ~= nil and value == value and math.abs(value) ~= math.huge then
			table.insert(values, value)
		end
	end
	interval.valid = #values
	if #values == 0 then
		return interval
	end
	table.sort(values)
	local tail = (1 - confidence) / 2
	interval.lower = quantile(values, tail)
	interval.upper = quantile(values, 1 - tail)
	return interval
end

return {
	percentile = percentile,
	mean = mean,
	median = median,
	bootstrap = bootstrap,
}
