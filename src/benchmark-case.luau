--!strict

local Harness = require "./core/harness"
local Performance = require "./core/performance"
local Check = require "./benchmark-check"
local Types = require "./benchmark-types"
type Spec = Types.Spec
type Budget = Types.Budget
type Invalid = Types.Invalid
type Comparison = Types.Comparison
type Result = Types.Result
type Collection = Types.Collection
type CollectionResult = Types.CollectionResult

local function create(run: (Spec) -> Result, collect: (Collection) -> CollectionResult)
	local function limitsFor(spec: Spec, budget: Budget?): Performance.Limits
		local declared: Budget = if budget ~= nil then budget else {}
		return {
			unit = spec.unit,
			minimumSamples = spec.samples,
			p50 = declared.p50,
			p95 = declared.p95,
			p99 = declared.p99,
			maximum = declared.maximum,
			measureOnly = declared.p50 == nil
				and declared.p95 == nil
				and declared.p99 == nil
				and declared.maximum == nil,
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
		context:step(("benchmark %s attempts: %d"):format(spec.name, result.attempts), function() end)
		local plain = spec.phases == nil
		if plain then
			record(context, spec.name, inputOf(spec, result.samples, result.summary, result.series), limitsOf(spec))
		end
		for index, entry in result.phases do
			local phases = spec.phases
			assert(phases ~= nil)
			local phase = phases[index]
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
				error(
					("%s heap grew %.4g %s, above the allowed %.4g"):format(spec.name, heap.growth, heap.unit, limit),
					0
				)
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
			error(result.failure, 0)
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
		Check.check(spec)
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
		Check.checkCollection(collection)
		return {
			run = function(context: Harness.Context)
				local collected = collect(collection)
				if collected.attempts ~= nil and #collected.attempts > 1 then
					local lines: { string } = {}
					local function samples(label: string, values: { number })
						local fields: { string } = { label }
						for _, value in values do
							table.insert(fields, tostring(value))
						end
						table.insert(lines, table.concat(fields, "\t"))
					end
					for index, attempt in collected.attempts do
						table.insert(lines, `attempt\t{index}`)
						samples("yardstick-before", attempt.yardstickBefore)
						samples("yardstick-after", attempt.yardstickAfter)
						for _, issue in attempt.invalid do
							table.insert(lines, `invalid\t{issue.reason}\t{issue.detail}`)
						end
						for _, member in attempt.results do
							samples(`member\t{member.name}\t{member.unit}`, member.samples)
							for _, phase in member.phases do
								samples(`phase\t{member.name}\t{phase.name}\t{member.unit}`, phase.samples)
							end
						end
					end
					context:attach("calibration-attempts.tsv", "text/tab-separated-values", table.concat(lines, "\n"))
				end
				local firstFailure: unknown = nil
				for index, result in collected.results do
					local reported, thrown: unknown = pcall(report, context, collection.benchmarks[index], result)
					if not reported and firstFailure == nil and type(thrown) ~= "table" then
						firstFailure = thrown
					end
				end
				if collected.failure ~= nil then
					error(collected.failure, 0)
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

	return { case = case, collection = collectionCase, limits = limitsOf }
end

return create
