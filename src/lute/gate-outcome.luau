--!strict

local Core = require "../core"
local Provenance = require "../core/provenance"
local Gate = require "../gate"
local Wire = require "./wire"

local Types = require "../core/types"

local function text(value: unknown): string
	assert(type(value) == "string", "gate field must be a string")
	return value
end

local function number(value: unknown): number
	assert(type(value) == "number", "gate field must be a number")
	return value
end

local function boolean(value: unknown): boolean
	assert(type(value) == "boolean", "gate field must be a boolean")
	return value
end

local function optionalText(value: unknown): string?
	return if value == nil then nil else text(value)
end

local function optionalNumber(value: unknown): number?
	return if value == nil then nil else number(value)
end

local function strings(value: unknown): { string }
	local result: { string } = {}
	for _, item in Wire.array(value) do
		table.insert(result, text(item))
	end
	return result
end

local function choice<T>(value: unknown, options: { T }): T
	for _, option in options do
		if value == option then
			return option
		end
	end
	error("unknown gate field value: " .. tostring(value), 2)
end

local function scope(value: unknown): Gate.Scope
	local raw = Wire.record(value)
	return {
		complete = boolean(raw.complete),
		label = text(raw.label),
		ids = strings(raw.ids),
		tiers = strings(raw.tiers),
		tags = strings(raw.tags),
		cases = strings(raw.cases),
		nameContains = optionalText(raw.nameContains),
		sources = strings(raw.sources),
		selected = strings(raw.selected),
		notSelected = strings(raw.notSelected),
		skippedByTier = strings(raw.skippedByTier),
		deselected = strings(raw.deselected),
	}
end

local function acceptance(value: unknown): Gate.Acceptance
	local raw = Wire.record(value)
	return {
		verdict = choice(raw.verdict, { "release", "deferred", "selected", "failed" }),
		releasable = boolean(raw.releasable),
		complete = boolean(raw.complete),
		reasons = strings(raw.reasons),
		passed = strings(raw.passed),
		failed = strings(raw.failed),
		deferred = strings(raw.deferred),
		reused = strings(raw.reused),
		notSelected = strings(raw.notSelected),
		skippedByTier = strings(raw.skippedByTier),
		deselected = strings(raw.deselected),
	}
end

local function producer(value: unknown): Gate.Record
	local raw = Wire.record(value)
	local log = if raw.log ~= nil then Wire.record(raw.log) else nil
	return {
		id = text(raw.id),
		kind = choice(raw.kind, { "command", "tests", "native" }),
		tier = optionalText(raw.tier),
		why = optionalText(raw.why),
		status = choice(
			raw.status,
			{ "passed", "failed", "timed_out", "unsupported", "deferred", "blocked", "not_run", "not_selected" }
		),
		selected = boolean(raw.selected),
		pulledByDependency = boolean(raw.pulledByDependency),
		exitcode = optionalNumber(raw.exitcode),
		timedOut = boolean(raw.timedOut),
		durationMicros = number(raw.durationMicros),
		detail = optionalText(raw.detail),
		log = if log == nil
			then nil
			else {
				stdout = text(log.stdout),
				stderr = text(log.stderr),
				bytes = number(log.bytes),
				truncated = boolean(log.truncated),
				reference = optionalText(log.reference),
			},
		reportAccounted = boolean(raw.reportAccounted),
		caseIds = strings(raw.caseIds),
		deselected = strings(raw.deselected),
		reused = boolean(raw.reused),
		reuseReference = optionalText(raw.reuseReference),
		deferral = optionalText(raw.deferral),
		blockedBy = optionalText(raw.blockedBy),
	}
end

local function execution(value: unknown): Core.ExecutionReport
	local raw = Wire.record(value)
	local provenance = Wire.record(raw.provenance)
	local batches: { Types.BatchRecord } = {}
	for _, value in Wire.array(raw.batches) do
		local item = Wire.record(value)
		local entry: Types.BatchRecord = {
			id = text(item.id),
			index = number(item.index),
			units = strings(item.units),
			dispatched = boolean(item.dispatched),
			attempts = number(item.attempts),
			outcome = if item.outcome == nil
				then nil
				else choice(item.outcome, { "returned", "faulted", "timed_out", "cancelled" }),
			reason = optionalText(item.reason),
		}
		table.insert(batches, entry)
	end
	local attempts: { Types.AttemptRecord } = {}
	for _, value in Wire.array(raw.attempts) do
		local item = Wire.record(value)
		local entry: Types.AttemptRecord = {
			batchId = text(item.batchId),
			batchIndex = number(item.batchIndex),
			attempt = number(item.attempt),
			status = choice(item.status, { "returned", "faulted", "timed_out", "cancelled" }),
			detail = optionalText(item.detail),
			produced = boolean(item.produced),
			verdictDigest = optionalText(item.verdictDigest),
			durationMicros = number(item.durationMicros),
			adopted = boolean(item.adopted),
		}
		table.insert(attempts, entry)
	end
	local facts: { Types.Fact } = {}
	for _, value in Wire.array(raw.facts) do
		local item = Wire.record(value)
		local entry: Types.Fact = {
			code = text(item.code),
			subject = text(item.subject),
			detail = text(item.detail),
			severity = choice(item.severity, { "failure", "limitation" }),
		}
		table.insert(facts, entry)
	end
	return {
		schemaVersion = number(raw.schemaVersion),
		capabilities = strings(raw.capabilities),
		batches = batches,
		attempts = attempts,
		facts = facts,
		report = Core.decode(raw.report),
		provenance = {
			planId = text(provenance.planId),
			planSchemaVersion = number(provenance.planSchemaVersion),
			planDigest = text(provenance.planDigest),
			unitCount = number(provenance.unitCount),
			planUnitCount = number(provenance.planUnitCount),
			complete = boolean(provenance.complete),
			host = text(provenance.host),
			batchCount = number(provenance.batchCount),
			parallelism = number(provenance.parallelism),
			batching = choice(provenance.batching, { "count", "weighted" }),
		},
	}
end

local function decode(value: unknown): Gate.Outcome
	local raw = Wire.record(value)
	assert(raw.schemaVersion == Gate.SCHEMA_VERSION, "unsupported gate outcome schema")
	local producers: { Gate.Record } = {}
	for _, value in Wire.array(raw.producers) do
		table.insert(producers, producer(value))
	end
	return {
		schemaVersion = Gate.SCHEMA_VERSION,
		gate = text(raw.gate),
		digest = text(raw.digest),
		runId = text(raw.runId),
		build = if raw.build == nil then nil else Provenance.copyBuild(raw.build, "gate build"),
		scope = scope(raw.scope),
		execution = execution(raw.execution),
		producers = producers,
		acceptance = acceptance(raw.acceptance),
	}
end

return { decode = decode }
