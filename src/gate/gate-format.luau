--!strict

local Text = require "../core/format"

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
	local add = Text.append(lines)
	for _, record in outcome.producers do
		local flags: { string } = {}
		if record.reused then
			table.insert(flags, "reused")
		end
		if record.pulledByDependency then
			table.insert(flags, "dependency")
		end
		add(
			"  %-12s %s (%s)%s%s",
			record.status,
			record.id,
			record.kind,
			if #flags > 0 then " [" .. table.concat(flags, ",") .. "]" else "",
			if record.status == "not_selected" then "" else (" %.2fs"):format(record.durationMicros / 1e6)
		)
		if record.status ~= "passed" and record.status ~= "not_selected" and record.detail ~= nil then
			add("      " .. record.detail)
		end
	end
	local acceptance = outcome.acceptance
	add("verdict: %s%s", acceptance.verdict, if acceptance.releasable then " (releasable)" else "")
	if acceptance.verdict ~= "release" then
		for _, reason in acceptance.reasons do
			add("  " .. reason)
		end
	end
	if #acceptance.skippedByTier > 0 then
		add(
			("skipped by tier (%d): %s"):format(#acceptance.skippedByTier, table.concat(acceptance.skippedByTier, ", "))
		)
	end
	if #acceptance.deselected > 0 then
		add("deselected cases (%d): %s", #acceptance.deselected, table.concat(acceptance.deselected, ", "))
	end
	return table.concat(lines, "\n")
end

local function explain(outcome: GateTypes.Outcome, id: string): string?
	local lines: { string } = {}
	local add = Text.append(lines)
	for _, record in outcome.producers do
		if record.id == id then
			add(
				"producer %s (%s%s): %s",
				record.id,
				record.kind,
				if record.tier ~= nil then ", tier " .. record.tier else "",
				record.status
			)
			if record.why ~= nil then
				add("  why it exists: " .. record.why)
			end
			if not record.selected then
				add("  " .. (record.detail or "not selected"))
			elseif record.pulledByDependency then
				add "  selected because a selected producer runs after it"
			else
				add("  selected by this run: " .. outcome.scope.label)
			end
			if record.selected and record.detail ~= nil then
				add("  " .. record.detail)
			end
			if record.deferral ~= nil then
				add("  deferred: " .. record.deferral)
			end
			if record.blockedBy ~= nil then
				add("  blocked by " .. record.blockedBy)
			end
			if record.reused then
				add("  reused from " .. tostring(record.reuseReference))
			end
			add("  %d case(s) reported, %d deselected", #record.caseIds, #record.deselected)
			if record.log ~= nil and record.log.reference ~= nil then
				add("  log: " .. record.log.reference)
			end
			return table.concat(lines, "\n")
		end
	end
	for _, result in outcome.execution.report.results do
		if result.id == id then
			add(
				"case %s%s: %s",
				result.id,
				if result.source ~= nil then " [" .. result.source .. "]" else "",
				result.status
			)
			for _, record in outcome.producers do
				if table.find(record.caseIds, id) ~= nil and record.id ~= id then
					add("  adopted by producer %s (%s)", record.id, record.status)
				end
			end
			if result.skipReason ~= nil then
				add("  skipped: " .. result.skipReason)
			end
			for _, failure in result.failures do
				add("  %s %s: %s", failure.phase, failure.outcome, failure.message)
			end
			if #result.missingCapabilities > 0 then
				add("  missing: " .. table.concat(result.missingCapabilities, ", "))
			end
			return table.concat(lines, "\n")
		end
	end
	return nil
end

local function list(gate: Gate): string
	local lines: { string } = {}
	local add = Text.append(lines)
	for _, producer in gate.producers do
		add(
			"%-14s %-9s %-8s%s%s",
			producer.id,
			producer.kind,
			if producer.tier ~= nil then producer.tier else "-",
			if #producer.after > 0 then " after " .. table.concat(producer.after, ",") else "",
			if producer.why ~= nil then "  " .. producer.why else ""
		)
	end
	return table.concat(lines, "\n")
end

return {
	format = format,
	explain = explain,
	list = list,
}
