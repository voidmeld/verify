--!strict

local Core = require "../core"

export type Run = (Core.PlanBatch) -> Core.BatchOutcome
export type Options = {
	deadlineSeconds: number,
	executor: string,
	environment: { [string]: string },
	progress: ((string) -> ())?,
}

local function run(batch: Core.PlanBatch, execute: Run, options: Options): Core.Report
	local reports: { Core.Report } = {}
	local ids: { [string]: boolean } = {}
	for index, unit in batch.units do
		local seconds = unit.deadlineSeconds or options.deadlineSeconds
		if options.progress ~= nil then
			options.progress("running " .. unit.locator)
		end
		local outcome = execute {
			id = batch.id .. "-spec-" .. tostring(index),
			index = index,
			deadlineSeconds = seconds,
			units = { unit },
		}
		if outcome.status == "returned" then
			local report = Core.decode(outcome.report)
			for _, result in report.results do
				if ids[result.id] then
					result.id = unit.id .. ":" .. result.id
				end
				assert(not ids[result.id], "duplicate result within spec: " .. result.id)
				ids[result.id] = true
			end
			table.insert(reports, report)
		else
			table.insert(
				reports,
				Core.syntheticReport {
					executor = options.executor,
					environment = options.environment,
					capabilities = {},
					id = "unit:" .. unit.id .. ":execution",
					source = unit.locator,
					name = unit.locator,
					status = if outcome.status == "timed_out" then "timed_out" else "failed",
					message = if outcome.status == "timed_out"
						then ("exceeded %ss"):format(tostring(seconds))
						else outcome.detail or "worker failed",
				}
			)
		end
	end
	return Core.merge(reports, options.executor, options.environment)
end

return { run = run }
