--!strict

local Capability = require "./capability"
local Harness = require "./harness"
local Types = require "./types"

type Artifact = Types.Artifact
type Report = Types.Report

local CONTRACT = "verify.observation-bundle.v1"

export type Event = {
	name: string,
	actor: string?,
	atSeconds: number?,
}

export type Bundle = {
	contract: string,
	executor: string,
	environment: { [string]: string },
	capabilities: { string },
	actors: { string },
	artifacts: { Artifact },
	timeline: { Event },
	observations: { [string]: any },
}

export type Draft = {
	executor: string,
	environment: { [string]: any },
	capabilities: { string }?,
	actors: { string }?,
	artifacts: { Artifact }?,
	timeline: { Event }?,
	observations: { [string]: any },
}

export type Register = (harness: Harness.Harness, observations: { [string]: any }) -> ()

export type Verdict = {
	status: "clear" | "held",
	reason: string,
}

local function stringMap(values: { [string]: any }): { [string]: string }
	local result: { [string]: string } = {}
	for key, value in values do
		if type(key) ~= "string" or key == "" then
			error("observation bundle environment keys must be non-empty strings", 2)
		end
		if value == nil then
			continue
		end
		if type(value) == "string" then
			result[key] = value
		elseif type(value) == "number" or type(value) == "boolean" then
			result[key] = tostring(value)
		else
			error(("observation bundle environment field %q is not a scalar"):format(key), 2)
		end
	end
	return result
end

local function frozenSnapshot(value: any, copies: { [any]: any }): any
	if type(value) ~= "table" then
		return value
	end
	if copies[value] ~= nil then
		return copies[value]
	end
	local copy = {}
	copies[value] = copy
	for key, child in value do
		copy[frozenSnapshot(key, copies)] = frozenSnapshot(child, copies)
	end
	return table.freeze(copy)
end

local function copySortedUnique(values: { string }?): { string }
	return Capability.sorted(values, "observation bundle string lists")
end

local function seal(draft: Draft): Bundle
	if type(draft.executor) ~= "string" or draft.executor == "" then
		error("observation bundle executor must not be empty", 2)
	end
	if type(draft.observations) ~= "table" then
		error("observation bundle observations must be a table", 2)
	end
	return frozenSnapshot({
		contract = CONTRACT,
		executor = draft.executor,
		environment = stringMap(draft.environment),
		capabilities = copySortedUnique(draft.capabilities),
		actors = copySortedUnique(draft.actors),
		artifacts = if draft.artifacts ~= nil then draft.artifacts else {},
		timeline = if draft.timeline ~= nil then draft.timeline else {},
		observations = draft.observations,
	}, {}) :: Bundle
end

local function isSealed(value: unknown): boolean
	if type(value) ~= "table" or not table.isfrozen(value :: any) then
		return false
	end
	local candidate = value :: { [string]: unknown }
	return candidate.contract == CONTRACT
end

local function evaluate(bundle: Bundle, source: string, register: Register, now: (() -> number)?): Report
	if not isSealed(bundle) then
		error("evaluate requires a sealed observation bundle", 2)
	end
	if type(source) ~= "string" or source == "" then
		error("evaluate requires a non-empty source name", 2)
	end
	local clock = if now ~= nil
		then now
		else function(): number
			return 0
		end
	local harness = Harness.createHarness { now = clock, source = source }
	local registered, registrationError: unknown = pcall(register, harness, bundle.observations)
	if not registered then
		return Harness.syntheticReport {
			executor = bundle.executor,
			environment = bundle.environment,
			capabilities = bundle.capabilities,
			id = ("source:%s:registration"):format(source),
			source = source,
			name = source,
			status = "failed",
			phase = "registration",
			message = tostring(registrationError),
		}
	end
	return harness:run {
		executor = bundle.executor,
		capabilities = bundle.capabilities,
		environment = bundle.environment,
	}
end

local function verdict(report: Report, clearReason: string): Verdict
	for _, result in report.results do
		for _, step in result.steps do
			if step.status ~= "passed" then
				return { status = "held", reason = step.name }
			end
		end
		for _, failure in result.failures do
			return { status = "held", reason = failure.message }
		end
		if result.status ~= "passed" then
			return { status = "held", reason = "case_" .. result.status }
		end
	end
	if report.total == 0 or #report.results == 0 then
		return { status = "held", reason = "no_cases_evaluated" }
	end
	if
		report.failed ~= 0
		or report.skipped ~= 0
		or report.unsupported ~= 0
		or report.timedOut ~= 0
		or report.cancelled ~= 0
		or report.passed ~= report.total
		or report.total ~= #report.results
	then
		return { status = "held", reason = "observation_counts_not_clear" }
	end
	return { status = "clear", reason = clearReason }
end

return {
	CONTRACT = CONTRACT,
	seal = seal,
	isSealed = isSealed,
	evaluate = evaluate,
	verdict = verdict,
	stringMap = stringMap,
}
