--!strict

local GateTypes = require "./gate-types"
local Types = require "../core/types"

type Producer = GateTypes.Producer
type ProducerRecord = GateTypes.ProducerRecord
type Gate = GateTypes.Gate
type Status = GateTypes.Status
type Report = Types.Report

local function format(outcome: GateTypes.Outcome): string
	local lines: { string } = {
		("gate %s run %s [%s]"):format(outcome.gate, outcome.runId, outcome.digest),
		"scope: " .. outcome.scope.label,
	}
	for _, record in outcome.producers do
		local flags: { string } = {}
		if record.reused then
			table.insert(flags, "reused")
		end
		if record.pulledByDependency then
			table.insert(flags, "dependency")
		end
		table.insert(
			lines,
			("  %-12s %s (%s)%s%s"):format(
				record.status,
				record.id,
				record.kind,
				if #flags > 0 then " [" .. table.concat(flags, ",") .. "]" else "",
				if record.status == "not_selected" then "" else (" %.2fs"):format(record.durationMicros / 1e6)
			)
		)
		if record.status ~= "passed" and record.status ~= "not_selected" and record.detail ~= nil then
			table.insert(lines, "      " .. record.detail)
		end
	end
	local acceptance = outcome.acceptance
	table.insert(
		lines,
		("verdict: %s%s"):format(acceptance.verdict, if acceptance.releasable then " (releasable)" else "")
	)
	if acceptance.verdict ~= "release" then
		for _, reason in acceptance.reasons do
			table.insert(lines, "  " .. reason)
		end
	end
	if #acceptance.skippedByTier > 0 then
		table.insert(
			lines,
			("skipped by tier (%d): %s"):format(#acceptance.skippedByTier, table.concat(acceptance.skippedByTier, ", "))
		)
	end
	if #acceptance.deselected > 0 then
		table.insert(
			lines,
			("deselected cases (%d): %s"):format(#acceptance.deselected, table.concat(acceptance.deselected, ", "))
		)
	end
	return table.concat(lines, "\n")
end

local function explain(outcome: GateTypes.Outcome, id: string): string?
	local lines: { string } = {}
	for _, record in outcome.producers do
		if record.id == id then
			table.insert(
				lines,
				("producer %s (%s%s): %s"):format(
					record.id,
					record.kind,
					if record.tier ~= nil then ", tier " .. record.tier else "",
					record.status
				)
			)
			if record.why ~= nil then
				table.insert(lines, "  why it exists: " .. record.why)
			end
			if not record.selected then
				table.insert(lines, "  " .. (record.detail or "not selected"))
			elseif record.pulledByDependency then
				table.insert(lines, "  selected because a selected producer runs after it")
			else
				table.insert(lines, "  selected by this run: " .. outcome.scope.label)
			end
			if record.selected and record.detail ~= nil then
				table.insert(lines, "  " .. record.detail)
			end
			if record.deferral ~= nil then
				table.insert(lines, "  deferred: " .. record.deferral)
			end
			if record.blockedBy ~= nil then
				table.insert(lines, "  blocked by " .. record.blockedBy)
			end
			if record.reused then
				table.insert(lines, "  reused from " .. tostring(record.reuseReference))
			end
			table.insert(lines, ("  %d case(s) reported, %d deselected"):format(#record.caseIds, #record.deselected))
			if record.log ~= nil and record.log.reference ~= nil then
				table.insert(lines, "  log: " .. record.log.reference)
			end
			return table.concat(lines, "\n")
		end
	end
	for _, result in outcome.execution.report.results do
		if result.id == id then
			table.insert(
				lines,
				("case %s%s: %s"):format(
					result.id,
					if result.source ~= nil then " [" .. result.source .. "]" else "",
					result.status
				)
			)
			for _, record in outcome.producers do
				if table.find(record.caseIds, id) ~= nil and record.id ~= id then
					table.insert(lines, ("  adopted by producer %s (%s)"):format(record.id, record.status))
				end
			end
			if result.skipReason ~= nil then
				table.insert(lines, "  skipped: " .. result.skipReason)
			end
			for _, failure in result.failures do
				table.insert(lines, ("  %s %s: %s"):format(failure.phase, failure.outcome, failure.message))
			end
			if #result.missingCapabilities > 0 then
				table.insert(lines, "  missing: " .. table.concat(result.missingCapabilities, ", "))
			end
			return table.concat(lines, "\n")
		end
	end
	return nil
end

local function list(gate: Gate): string
	local lines: { string } = {}
	for _, producer in gate.producers do
		table.insert(
			lines,
			("%-14s %-9s %-8s%s%s"):format(
				producer.id,
				producer.kind,
				if producer.tier ~= nil then producer.tier else "-",
				if #producer.after > 0 then " after " .. table.concat(producer.after, ",") else "",
				if producer.why ~= nil then "  " .. producer.why else ""
			)
		)
	end
	return table.concat(lines, "\n")
end

return {
	format = format,
	explain = explain,
	list = list,
}
