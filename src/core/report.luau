--!strict

local Types = require "./types"
local Shape = require "./shape"

type Artifact = Types.Artifact
type CaseResult = Types.CaseResult
type Failure = Types.Failure
type Origin = Types.Origin
type Report = Types.Report
type ReportSource = Types.ReportSource
type Status = Types.Status
type StepResult = Types.StepResult

local SCHEMA_VERSION = 1

local VALID_STATUS: { [string]: boolean } = {
	passed = true,
	failed = true,
	skipped = true,
	unsupported = true,
	timed_out = true,
	cancelled = true,
}

local VALID_PHASE: { [string]: boolean } = {
	load = true,
	registration = true,
	setup = true,
	case = true,
	step = true,
	teardown = true,
	cleanup = true,
	executor = true,
}

local VALID_OUTCOME: { [string]: boolean } = {
	failed = true,
	timed_out = true,
	cancelled = true,
}

local copyStrings = Shape.copyStrings

local function copyEnvironment(value: unknown, label: string): { [string]: string }
	if type(value) ~= "table" then
		error(label .. " must be a string map", 3)
	end
	local result: { [string]: string } = {}
	for key, item in value :: { [unknown]: unknown } do
		if type(key) ~= "string" or type(item) ~= "string" then
			error(label .. " must contain only string keys and values", 3)
		end
		result[key] = item
	end
	return result
end

local requiredString = Shape.requiredString

local function optionalString(value: unknown, label: string): string?
	if value == nil then
		return nil
	end
	return requiredString(value, label)
end

local nonnegativeNumber = Shape.nonnegativeNumber

local function copyOrigin(value: unknown, label: string): Origin
	if type(value) ~= "table" then
		error(label .. " must be a table", 3)
	end
	local raw = value :: { [string]: unknown }
	return {
		executor = requiredString(raw.executor, label .. ".executor"),
		environment = copyEnvironment(raw.environment, label .. ".environment"),
		capabilities = copyStrings(raw.capabilities, label .. ".capabilities"),
	}
end

local function copyFailures(value: unknown, label: string): { Failure }
	if type(value) ~= "table" then
		error(label .. " must be an array", 3)
	end
	local result: { Failure } = {}
	for index, item in value :: { unknown } do
		if type(index) ~= "number" or index ~= #result + 1 or type(item) ~= "table" then
			error(label .. " must be a dense failure array", 3)
		end
		local raw = item :: { [string]: unknown }
		local phase = requiredString(raw.phase, label .. ".phase")
		local outcome = requiredString(raw.outcome, label .. ".outcome")
		if not VALID_PHASE[phase] then
			error(label .. " contains an unknown failure phase: " .. phase, 3)
		end
		if not VALID_OUTCOME[outcome] then
			error(label .. " contains an unknown failure outcome: " .. outcome, 3)
		end
		table.insert(result, {
			phase = phase :: Types.FailurePhase,
			outcome = outcome :: Types.FailureOutcome,
			message = requiredString(raw.message, label .. ".message"),
		})
	end
	return result
end

local function copySteps(value: unknown, label: string): { StepResult }
	if type(value) ~= "table" then
		error(label .. " must be an array", 3)
	end
	local result: { StepResult } = {}
	for index, item in value :: { unknown } do
		if type(index) ~= "number" or index ~= #result + 1 or type(item) ~= "table" then
			error(label .. " must be a dense step array", 3)
		end
		local raw = item :: { [string]: unknown }
		local status = requiredString(raw.status, label .. ".status")
		if status ~= "passed" and status ~= "failed" and status ~= "timed_out" and status ~= "cancelled" then
			error(label .. " contains an unknown step status: " .. status, 3)
		end
		table.insert(result, {
			name = requiredString(raw.name, label .. ".name"),
			actor = optionalString(raw.actor, label .. ".actor"),
			status = status :: "passed" | "failed" | "timed_out" | "cancelled",
			durationMicros = nonnegativeNumber(raw.durationMicros, label .. ".durationMicros"),
			message = optionalString(raw.message, label .. ".message"),
		})
	end
	return result
end

local function copyArtifacts(value: unknown, label: string): { Artifact }
	if type(value) ~= "table" then
		error(label .. " must be an array", 3)
	end
	local result: { Artifact } = {}
	for index, item in value :: { unknown } do
		if type(index) ~= "number" or index ~= #result + 1 or type(item) ~= "table" then
			error(label .. " must be a dense artifact array", 3)
		end
		local raw = item :: { [string]: unknown }
		table.insert(result, {
			name = requiredString(raw.name, label .. ".name"),
			reference = requiredString(raw.reference, label .. ".reference"),
			mediaType = optionalString(raw.mediaType, label .. ".mediaType"),
		})
	end
	return result
end

local NEEDS_FAILURE: { [string]: boolean } = {
	failed = true,
	timed_out = true,
	cancelled = true,
}

local function copyResult(value: unknown, label: string): CaseResult
	if type(value) ~= "table" then
		error(label .. " must be a table", 3)
	end
	local raw = value :: { [string]: unknown }
	local status = requiredString(raw.status, label .. ".status")
	if not VALID_STATUS[status] then
		error(label .. " contains an unknown status: " .. status, 3)
	end
	local failures = copyFailures(raw.failures, label .. ".failures")
	if NEEDS_FAILURE[status] and #failures == 0 then
		error(("%s is %s but records no failure"):format(label, status), 3)
	end
	if not NEEDS_FAILURE[status] and #failures > 0 then
		error(("%s is %s but records %d failure(s)"):format(label, status, #failures), 3)
	end
	if status == "skipped" and raw.skipReason == nil then
		error(label .. " is skipped but names no reason", 3)
	end
	if status == "unsupported" and #copyStrings(raw.missingCapabilities, label .. ".missingCapabilities") == 0 then
		error(label .. " is unsupported but names no missing capability", 3)
	end
	return {
		id = requiredString(raw.id, label .. ".id"),
		source = optionalString(raw.source, label .. ".source"),
		path = copyStrings(raw.path, label .. ".path"),
		name = requiredString(raw.name, label .. ".name"),
		status = status :: Status,
		durationMicros = nonnegativeNumber(raw.durationMicros, label .. ".durationMicros"),
		failures = failures,
		steps = copySteps(raw.steps, label .. ".steps"),
		artifacts = copyArtifacts(raw.artifacts, label .. ".artifacts"),
		limitations = copyStrings(raw.limitations, label .. ".limitations"),
		missingCapabilities = copyStrings(raw.missingCapabilities, label .. ".missingCapabilities"),
		skipReason = optionalString(raw.skipReason, label .. ".skipReason"),
		origin = copyOrigin(raw.origin, label .. ".origin"),
	}
end

local function counts(results: { CaseResult }): (number, number, number, number, number, number)
	local passed, failed, skipped, unsupported, timedOut, cancelled = 0, 0, 0, 0, 0, 0
	for _, result in results do
		if result.status == "passed" then
			passed += 1
		elseif result.status == "skipped" then
			skipped += 1
		elseif result.status == "unsupported" then
			unsupported += 1
		elseif result.status == "timed_out" then
			timedOut += 1
		elseif result.status == "cancelled" then
			cancelled += 1
		else
			failed += 1
		end
	end
	return passed, failed, skipped, unsupported, timedOut, cancelled
end

local function decode(value: unknown): Report
	if type(value) ~= "table" then
		error("Verify report must be a table", 2)
	end
	local raw = value :: { [string]: unknown }
	if raw.schemaVersion ~= SCHEMA_VERSION then
		error(
			("unsupported Verify report schema major %s; expected %d"):format(
				tostring(raw.schemaVersion),
				SCHEMA_VERSION
			),
			2
		)
	end
	if type(raw.results) ~= "table" or type(raw.sources) ~= "table" then
		error("Verify report results and sources must be arrays", 2)
	end
	local results: { CaseResult } = {}
	local resultIds: { [string]: boolean } = {}
	for index, item in raw.results :: { unknown } do
		if type(index) ~= "number" or index ~= #results + 1 then
			error("Verify report results must be dense", 2)
		end
		local result = copyResult(item, ("results[%d]"):format(index))
		if resultIds[result.id] then
			error("Verify report contains duplicate result id: " .. result.id, 2)
		end
		resultIds[result.id] = true
		table.insert(results, result)
	end
	local sources: { ReportSource } = {}
	for index, item in raw.sources :: { unknown } do
		if type(index) ~= "number" or index ~= #sources + 1 then
			error("Verify report sources must be dense", 2)
		end
		table.insert(sources, copyOrigin(item, ("sources[%d]"):format(index)))
	end
	local passed, failed, skipped, unsupported, timedOut, cancelled = counts(results)
	local declared: { [string]: unknown } = {
		passed = raw.passed,
		failed = raw.failed,
		skipped = raw.skipped,
		unsupported = raw.unsupported,
		timedOut = raw.timedOut,
		cancelled = raw.cancelled,
		total = raw.total,
	}
	local actual: { [string]: number } = {
		passed = passed,
		failed = failed,
		skipped = skipped,
		unsupported = unsupported,
		timedOut = timedOut,
		cancelled = cancelled,
		total = #results,
	}
	for key, valueInReport in declared do
		if valueInReport ~= actual[key] then
			error(("Verify report count %s is %s; expected %d"):format(key, tostring(valueInReport), actual[key]), 2)
		end
	end
	return {
		schemaVersion = SCHEMA_VERSION,
		executor = requiredString(raw.executor, "executor"),
		environment = copyEnvironment(raw.environment, "environment"),
		capabilities = copyStrings(raw.capabilities, "capabilities"),
		sources = sources,
		results = results,
		passed = passed,
		failed = failed,
		skipped = skipped,
		unsupported = unsupported,
		timedOut = timedOut,
		cancelled = cancelled,
		total = #results,
		durationMicros = nonnegativeNumber(raw.durationMicros, "durationMicros"),
	}
end

local function originKey(origin: Origin): string
	local keys: { string } = {}
	for key in origin.environment do
		table.insert(keys, key)
	end
	table.sort(keys)
	local pieces: { string } = { origin.executor }
	for _, key in keys do
		table.insert(pieces, ("%s=%s"):format(key, origin.environment[key]))
	end
	local capabilities = table.clone(origin.capabilities)
	table.sort(capabilities)
	return table.concat(pieces, "\0") .. "\1" .. table.concat(capabilities, "\0")
end

type Accumulator = {
	results: { CaseResult },
	sources: { ReportSource },
	sourceKeys: { [string]: boolean },
	capabilities: { string },
	capabilitySet: { [string]: boolean },
	ids: { [string]: string },
	durationMicros: number,
}

local function newAccumulator(): Accumulator
	return {
		results = {},
		sources = {},
		sourceKeys = {},
		capabilities = {},
		capabilitySet = {},
		ids = {},
		durationMicros = 0,
	}
end

local function absorbEnvelope(into: Accumulator, report: Report)
	into.durationMicros += report.durationMicros
	for _, source in report.sources do
		local key = originKey(source)
		if not into.sourceKeys[key] then
			into.sourceKeys[key] = true
			table.insert(into.sources, source)
		end
	end
	for _, capability in report.capabilities do
		if not into.capabilitySet[capability] then
			into.capabilitySet[capability] = true
			table.insert(into.capabilities, capability)
		end
	end
end

local function finish(into: Accumulator, executor: string, environment: { [string]: string }): Report
	table.sort(into.capabilities)
	local passed, failed, skipped, unsupported, timedOut, cancelled = counts(into.results)
	return {
		schemaVersion = SCHEMA_VERSION,
		executor = executor,
		environment = copyEnvironment(environment, "merged environment"),
		capabilities = into.capabilities,
		sources = into.sources,
		results = into.results,
		passed = passed,
		failed = failed,
		skipped = skipped,
		unsupported = unsupported,
		timedOut = timedOut,
		cancelled = cancelled,
		total = #into.results,
		durationMicros = into.durationMicros,
	}
end

local function merge(reports: { Report }, executor: string, environment: { [string]: string }): Report
	if executor == "" then
		error("merged report executor must not be empty", 2)
	end
	local into = newAccumulator()
	for index, candidate in reports do
		local report = decode(candidate)
		absorbEnvelope(into, report)
		for _, result in report.results do
			if into.ids[result.id] ~= nil then
				error(("cannot merge report %d: duplicate result id %q"):format(index, result.id), 2)
			end
			into.ids[result.id] = tostring(index)
			table.insert(into.results, result)
		end
	end
	return finish(into, executor, environment)
end

local function compose(payloads: { Types.ShardPayload }, executor: string, environment: { [string]: string }): Report
	if executor == "" then
		error("composed report executor must not be empty", 2)
	end
	local into = newAccumulator()
	local composedOrigin: Origin = {
		executor = executor,
		environment = copyEnvironment(environment, "composed environment"),
		capabilities = {},
	}
	local shardIds: { [string]: boolean } = {}

	local function uniqueId(preferred: string): string
		local candidate = preferred
		local suffix = 2
		while into.ids[candidate] ~= nil do
			candidate = ("%s#%d"):format(preferred, suffix)
			suffix += 1
		end
		return candidate
	end

	local function nameFailure(shardId: string, id: string, name: string, message: string)
		local chosen = uniqueId(id)
		into.ids[chosen] = shardId
		table.insert(into.results, {
			id = chosen,
			source = nil,
			path = {},
			name = name,
			status = "failed" :: Status,
			durationMicros = 0,
			failures = {
				{
					phase = "executor" :: Types.FailurePhase,
					outcome = "failed" :: Types.FailureOutcome,
					message = message,
				},
			},
			steps = {},
			artifacts = {},
			limitations = {},
			missingCapabilities = {},
			skipReason = nil,
			origin = composedOrigin,
		})
	end

	for index, payload in payloads do
		if type(payload) ~= "table" then
			error(("shard payload %d must be a table"):format(index), 2)
		end
		local shardId = requiredString(payload.id, ("shard payload %d id"):format(index))
		if shardIds[shardId] then
			error("duplicate shard id: " .. shardId, 2)
		end
		shardIds[shardId] = true

		if payload.error ~= nil then
			nameFailure(shardId, "shard:" .. shardId, shardId, tostring(payload.error))
			continue
		end
		if payload.report == nil then
			nameFailure(shardId, "shard:" .. shardId, shardId, "shard produced no report")
			continue
		end
		local decoded, decodedReport: any = pcall(decode, payload.report)
		if not decoded then
			nameFailure(shardId, "shard:" .. shardId, shardId, "undecodable shard payload: " .. tostring(decodedReport))
			continue
		end

		local report = decodedReport :: Report
		absorbEnvelope(into, report)
		for _, result in report.results do
			local claimedBy = into.ids[result.id]
			if claimedBy ~= nil then
				nameFailure(
					shardId,
					("shard:%s:duplicate:%s"):format(shardId, result.id),
					result.name,
					("duplicate result id %q: kept the copy from shard %q; discarded a %s copy from shard %q"):format(
						result.id,
						claimedBy,
						result.status,
						shardId
					)
				)
				continue
			end
			into.ids[result.id] = shardId
			table.insert(into.results, result)
		end
	end
	return finish(into, executor, environment)
end

local TIMING_FIELDS: { string } = { "durationMicros" }

local function sortedKeys(map: { [string]: string }): { string }
	local keys: { string } = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function canonical(value: unknown): string
	local report = decode(value)
	local lines: { string } = {
		("schema %d"):format(report.schemaVersion),
		("executor %s"):format(report.executor),
	}
	for _, key in sortedKeys(report.environment) do
		table.insert(lines, ("env %s=%s"):format(key, report.environment[key]))
	end
	local capabilities = table.clone(report.capabilities)
	table.sort(capabilities)
	table.insert(lines, ("capabilities %s"):format(table.concat(capabilities, ",")))
	for _, source in report.sources do
		local sourceCapabilities = table.clone(source.capabilities)
		table.sort(sourceCapabilities)
		local pieces: { string } = { source.executor }
		for _, key in sortedKeys(source.environment) do
			table.insert(pieces, ("%s=%s"):format(key, source.environment[key]))
		end
		table.insert(lines, ("source %s [%s]"):format(table.concat(pieces, " "), table.concat(sourceCapabilities, ",")))
	end
	for _, result in report.results do
		table.insert(
			lines,
			("case %s | %s | %s | %s | %s | %s | %s"):format(
				result.id,
				result.status,
				tostring(result.source),
				table.concat(result.path, " > "),
				result.name,
				table.concat(result.missingCapabilities, ","),
				tostring(result.skipReason)
			)
		)
		for _, limitation in result.limitations do
			table.insert(lines, ("  limitation %s"):format(limitation))
		end
		for _, step in result.steps do
			table.insert(
				lines,
				("  step %s | %s | %s | %s"):format(
					step.name,
					step.status,
					tostring(step.actor),
					tostring(step.message)
				)
			)
		end
		for _, failure in result.failures do
			table.insert(lines, ("  failure %s/%s %s"):format(failure.phase, failure.outcome, failure.message))
		end
		for _, artifact in result.artifacts do
			table.insert(
				lines,
				("  artifact %s %s %s"):format(artifact.name, artifact.reference, tostring(artifact.mediaType))
			)
		end
	end
	table.insert(
		lines,
		("counts %d/%d/%d/%d/%d/%d of %d"):format(
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

local function verdictDigest(report: Report): string
	local lines: { string } = {}
	for _, result in report.results do
		table.insert(lines, ("%s=%s"):format(result.id, result.status))
	end
	table.sort(lines)
	return table.concat(lines, ";")
end

local function verdictDifferences(left: Report, right: Report): { string }
	local statuses: { [string]: string } = {}
	for _, result in left.results do
		statuses[result.id] = result.status
	end
	local differences: { [string]: boolean } = {}
	for _, result in right.results do
		local before = statuses[result.id]
		if before ~= result.status then
			differences[result.id] = true
		end
		statuses[result.id] = nil
	end
	for id in statuses do
		differences[id] = true
	end
	local ids: { string } = {}
	for id in differences do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	TIMING_FIELDS = TIMING_FIELDS,
	counts = counts,
	decode = decode,
	merge = merge,
	compose = compose,
	canonical = canonical,
	verdictDigest = verdictDigest,
	verdictDifferences = verdictDifferences,
}
