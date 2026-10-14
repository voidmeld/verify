--!strict

local Performance = require "./performance"
local Types = require "./types"

local function number(value: number?): string
	return if value == nil then "-" else ("%.4g"):format(value)
end

local function measurementLine(measurement: Types.Measurement): string
	local summary = measurement.evaluation.summary
	local parts = {
		("%s [%s] n=%d"):format(measurement.name, summary.unit, summary.sampleCount),
		"p50=" .. number(summary.p50),
		"p95=" .. number(summary.p95),
	}
	local extra: { Performance.PercentileValue } = summary.percentiles or {}
	for _, entry in extra do
		table.insert(parts, ("p%s=%s"):format(number(entry.percentile), number(entry.value)))
	end
	table.insert(parts, measurement.evaluation.reason)
	return table.concat(parts, " ")
end

local function format(report: Types.Report): string
	local lines = { ("Verify receipt v%d — %s"):format(report.schemaVersion, report.executor) }
	local environmentKeys: { string } = {}
	for key in report.environment do
		table.insert(environmentKeys, key)
	end
	table.sort(environmentKeys)
	for _, key in environmentKeys do
		table.insert(lines, ("  %s: %s"):format(key, report.environment[key]))
	end
	for _, result in report.results do
		table.insert(lines, ("  %-11s %s"):format(result.status, result.id))
		if result.skipReason ~= nil then
			table.insert(lines, "              " .. result.skipReason)
		end
		if #result.missingCapabilities > 0 then
			table.insert(lines, "              missing: " .. table.concat(result.missingCapabilities, ", "))
		end
		for _, failure in result.failures do
			table.insert(lines, ("              %s/%s: %s"):format(failure.phase, failure.outcome, failure.message))
		end
		if result.evidence ~= nil then
			for _, measurement in result.evidence.measurements do
				table.insert(lines, "              " .. measurementLine(measurement))
			end
		end
	end
	table.insert(
		lines,
		("%d passed, %d failed, %d skipped, %d unsupported, %d timed out, %d cancelled (%d total)"):format(
			report.passed,
			report.failed,
			report.skipped,
			report.unsupported,
			report.timedOut,
			report.cancelled,
			report.total
		)
	)
	return table.concat(lines, "\n")
end

return { format = format }
