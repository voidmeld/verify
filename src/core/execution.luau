--!strict

local Capability = require "./capability"
local Harness = require "./harness"
local Plan = require "./plan"
local ReportModel = require "./report"
local Types = require "./types"

type Artifact = Types.Artifact
type AttemptRecord = Types.AttemptRecord
type BatchOutcome = Types.BatchOutcome
type BatchRecord = Types.BatchRecord
type BatchStatus = Types.BatchStatus
type ExecutionReport = Types.ExecutionReport
type Fact = Types.Fact
type PlanBatch = Types.PlanBatch
type PlanDraft = Types.PlanDraft
type PlanUnit = Types.PlanUnit
type Report = Types.Report
type ShardPayload = Types.ShardPayload

local SCHEMA_VERSION = 1

export type Host = {
	name: string,
	capabilities: { string },
	environment: { [string]: string },
	now: () -> number,
	maxParallelBatches: number?,
	runBatch: (batch: PlanBatch) -> BatchOutcome,

	runBatches: ((batches: { PlanBatch }, deliver: (index: number, outcome: BatchOutcome) -> ()) -> ())?,

	artifact: ((unitId: string, artifact: Artifact) -> Artifact)?,

	cancelled: (() -> boolean)?,
}

export type Fixture = {
	name: string,
	acquire: () -> (),
	release: (() -> ())?,
}

export type Options = {
	fixtures: { Fixture }?,
	batchCount: number?,
	parallel: number?,
	selection: Types.PlanSelection?,

	batching: Types.BatchingMode?,
}

local FAILING_FACTS: { [string]: boolean } = {
	["fixture-setup-failed"] = true,
	["fixture-cleanup-failed"] = true,
	["attempt-disagreement"] = true,
	["no-cases"] = true,
}

local function checkedHost(host: Host): Host
	if type(host) ~= "table" then
		error("execute requires a host adapter", 3)
	end
	if type(host.name) ~= "string" or host.name == "" then
		error("a host adapter must name itself", 3)
	end
	if type(host.now) ~= "function" then
		error("a host adapter must supply a monotonic now function", 3)
	end
	if type(host.runBatch) ~= "function" then
		error("a host adapter must supply runBatch", 3)
	end
	if type(host.environment) ~= "table" or type(host.capabilities) ~= "table" then
		error("a host adapter must declare an environment and a capability set", 3)
	end
	return host
end

local function micros(seconds: number): number
	return math.max(0, math.floor(seconds * 1e6 + 0.5))
end

local function unitIds(units: { PlanUnit }): { string }
	local ids: { string } = {}
	for _, unit in units do
		table.insert(ids, unit.id)
	end
	return ids
end

local function execute(planDraft: PlanDraft, host: Host, options: Options?): ExecutionReport
	local checkedPlan = Plan.validate(planDraft)
	local selected = if options ~= nil and options.selection ~= nil
		then Plan.select(checkedPlan, options.selection)
		else checkedPlan

	local complete = #selected.units == #checkedPlan.units
	local adapter = checkedHost(host)
	local settings: Options = if options ~= nil then options else {}
	local policy = selected.policy
	local declared = Capability.sorted(adapter.capabilities, "host capabilities")
	local digest = Plan.digest(selected)

	local facts: { Fact } = {}
	local function fact(code: string, subject: string, detail: string)
		table.insert(facts, {
			code = code,
			subject = subject,
			detail = detail,
			severity = if FAILING_FACTS[code] then "failure" else "limitation",
		})
	end

	local environment: { [string]: string } = {}
	for key, value in adapter.environment do
		environment[key] = value
	end
	environment["verify.executionSchema"] = tostring(SCHEMA_VERSION)
	environment["verify.plan"] = selected.id
	environment["verify.planSchema"] = tostring(selected.schemaVersion)
	environment["verify.planDigest"] = digest

	local payloads: { ShardPayload } = {}
	local payloadCount = 0
	local function addReport(report: Report)
		payloadCount += 1
		table.insert(payloads, { id = ("payload-%d"):format(payloadCount), report = report })
	end
	local function synthetic(options2: Harness.SyntheticOptions): Report
		return Harness.syntheticReport(options2)
	end
	local function unitReport(
		unit: PlanUnit,
		suffix: string,
		status: "failed" | "skipped" | "unsupported" | "timed_out" | "cancelled",
		phase: Types.FailurePhase?,
		message: string?,
		skipReason: string?,
		missing: { string }?
	)
		addReport(synthetic {
			executor = adapter.name,
			environment = environment,
			capabilities = declared,
			id = ("unit:%s:%s"):format(unit.id, suffix),
			source = unit.locator,
			name = unit.id,
			status = status,
			phase = phase,
			message = message,
			skipReason = skipReason,
			missingCapabilities = missing,
		})
	end

	if not complete then
		fact(
			"focused-run",
			selected.id,
			("%d of %d unit(s) were selected; this run proves nothing about the %d it did not run, and is not the plan"):format(
				#selected.units,
				#checkedPlan.units,
				#checkedPlan.units - #selected.units
			)
		)
	end

	local planNegotiation = Capability.negotiate(declared, selected.requires)
	if not planNegotiation.satisfied then
		fact("plan-capability-missing", selected.id, Capability.explain(planNegotiation))
	end
	local runnable: { PlanUnit } = {}
	local unsupportedIds: { string } = {}
	for _, unit in selected.units do
		local required = Capability.union(selected.requires, unit.requires)
		local negotiation = Capability.negotiate(declared, required)
		if negotiation.satisfied then
			table.insert(runnable, unit)
		else
			table.insert(unsupportedIds, unit.id)
			unitReport(unit, "unsupported", "unsupported", nil, nil, nil, negotiation.missing)
		end
	end
	if #unsupportedIds > 0 then
		fact(
			"capability-missing",
			table.concat(unsupportedIds, ","),
			("%d unit(s) were not dispatched; the host declared %s"):format(
				#unsupportedIds,
				if #declared > 0 then table.concat(declared, ", ") else "no capability"
			)
		)
	end

	local requested = if settings.parallel ~= nil then settings.parallel else policy.maxParallelBatches
	local ceiling = if adapter.maxParallelBatches ~= nil then adapter.maxParallelBatches else requested
	local parallel = math.max(1, math.floor(math.min(requested, ceiling)))

	local groups: { [string]: boolean } = {}
	local groupCount = 0
	for _, unit in runnable do
		local key = if unit.group ~= nil then "g:" .. (unit.group :: string) else "u:" .. unit.id
		if not groups[key] then
			groups[key] = true
			groupCount += 1
		end
	end
	local batchCount = settings.batchCount or policy.batchCount or math.max(1, math.min(parallel, groupCount))
	local batching: Types.BatchingMode = if settings.batching ~= nil then settings.batching else "count"
	local batches = Plan.partition({
		schemaVersion = selected.schemaVersion,
		id = selected.id,
		requires = selected.requires,
		policy = policy,
		units = runnable,
	}, batchCount, batching)

	if policy.failFast and parallel > 1 then
		fact(
			"fail-fast-granularity",
			selected.id,
			("fail-fast is evaluated between dispatch chunks of %d batch(es), so batches already in flight when a failure appeared still ran"):format(
				parallel
			)
		)
	end

	local fixtures: { Fixture } = if settings.fixtures ~= nil then settings.fixtures else {}
	local acquired: { Fixture } = {}
	local fixtureFailure: string? = nil
	for _, fixture in fixtures do
		if fixture.name == "" then
			error("a fixture must be named", 2)
		end
		local ok, thrown: unknown = pcall(fixture.acquire)
		if not ok then
			fixtureFailure = fixture.name
			fact("fixture-setup-failed", fixture.name, tostring(thrown))
			break
		end
		table.insert(acquired, fixture)
	end

	local attempts: { AttemptRecord } = {}
	local batchRecords: { BatchRecord } = {}
	local adopted: { [number]: Report } = {}
	local lastDetail: { [number]: string } = {}
	local lastStatus: { [number]: BatchStatus } = {}
	local attemptCount: { [number]: number } = {}
	local producedReports: { [number]: { Report } } = {}
	local dispatched: { [number]: boolean } = {}
	local stopped: string? = if fixtureFailure ~= nil
		then ("fixture %s did not acquire"):format(fixtureFailure :: string)
		else nil
	local stopKind: string = if fixtureFailure ~= nil then "fixture" else ""

	local runStarted = adapter.now()
	local function runElapsed(): number
		return adapter.now() - runStarted
	end

	local function normalize(outcome: unknown): BatchOutcome
		if type(outcome) ~= "table" then
			return { status = "faulted", detail = "the host returned no batch outcome" }
		end
		local candidate = outcome :: BatchOutcome
		if
			candidate.status ~= "returned"
			and candidate.status ~= "faulted"
			and candidate.status ~= "timed_out"
			and candidate.status ~= "cancelled"
		then
			return { status = "faulted", detail = "the host returned an unknown batch status" }
		end
		return candidate
	end

	local function recordAttempt(batch: PlanBatch, attempt: number, raw: unknown, elapsedSeconds: number): BatchStatus
		local outcome = normalize(raw)
		local status: BatchStatus = outcome.status
		local detail: string? = outcome.detail
		local report: Report? = nil
		if outcome.report ~= nil then
			local decoded, value: any = pcall(ReportModel.decode, outcome.report)
			if decoded then
				report = value :: Report
			elseif status == "returned" then
				status = "faulted"
				detail = "undecodable batch report: " .. tostring(value)
			end
		elseif status == "returned" then
			status = "faulted"
			detail = "the host reported a returned batch with no report"
		end
		if report ~= nil then
			local list = producedReports[batch.index]
			if list == nil then
				list = {}
				producedReports[batch.index] = list
			end
			table.insert(list, report :: Report)

			if status == "returned" then
				adopted[batch.index] = report
			end
		end
		table.insert(attempts, {
			batchId = batch.id,
			batchIndex = batch.index,
			attempt = attempt,
			status = status,
			detail = detail,
			produced = report ~= nil,
			verdictDigest = if report ~= nil then ReportModel.verdictDigest(report :: Report) else nil,
			durationMicros = micros(elapsedSeconds),
			adopted = false,
		})
		attemptCount[batch.index] = attempt
		lastStatus[batch.index] = status
		lastDetail[batch.index] = detail or tostring(status)
		dispatched[batch.index] = true
		return status
	end

	local function runOne(batch: PlanBatch): unknown
		local ok, value: any = pcall(adapter.runBatch, batch)
		if not ok then
			return { status = "faulted", detail = "the host raised while running a batch: " .. tostring(value) }
		end
		return value
	end

	local function runChunk(chunk: { PlanBatch }, attempt: number)
		if #chunk == 1 or adapter.runBatches == nil then
			for _, batch in chunk do
				local started = adapter.now()
				local outcome = runOne(batch)
				recordAttempt(batch, attempt, outcome, adapter.now() - started)
			end
			return
		end
		local collected: { [number]: unknown } = {}
		local duplicates: { string } = {}
		local started = adapter.now()
		local ok, thrown: unknown = pcall(adapter.runBatches :: any, chunk, function(index: number, outcome: unknown)
			if collected[index] ~= nil then
				table.insert(duplicates, tostring(index))
			end
			collected[index] = outcome
		end)
		local elapsed = adapter.now() - started
		if #duplicates > 0 then
			fact(
				"duplicate-batch-outcome",
				table.concat(duplicates, ","),
				"the host delivered more than one outcome for a batch; the last one was kept"
			)
		end
		for _, batch in chunk do
			local outcome = collected[batch.index]
			if outcome == nil then
				local reason = if ok
					then "the host delivered no outcome for this batch"
					else "the host raised during parallel dispatch: " .. tostring(thrown)
				fact("missing-batch-outcome", batch.id, reason)
				recordAttempt(batch, attempt, { status = "faulted", detail = reason }, elapsed)
			else
				recordAttempt(batch, attempt, outcome, elapsed)
			end
		end
	end

	local function shouldStop(): string?
		if adapter.cancelled ~= nil then
			local ok, answer: any = pcall(adapter.cancelled :: any)
			if ok and answer == true then
				stopKind = "cancelled"
				return "the host cancelled the run"
			end
		end
		local limit = policy.runDeadlineSeconds
		if limit ~= nil and runElapsed() >= limit then
			stopKind = "run-deadline"
			return ("the run deadline of %s second(s) elapsed"):format(tostring(limit))
		end
		return nil
	end

	local function hasFailure(report: Report): boolean
		return report.failed + report.timedOut + report.cancelled > 0
	end

	local queue: { number } = {}
	for _, batch in batches do
		if #batch.units > 0 then
			table.insert(queue, batch.index)
		end
	end

	local attempt = 1
	while #queue > 0 and stopped == nil do
		local retryQueue: { number } = {}
		local cursor = 1
		while cursor <= #queue and stopped == nil do
			stopped = shouldStop()
			if stopped ~= nil then
				break
			end
			local chunk: { PlanBatch } = {}
			while cursor <= #queue and #chunk < parallel do
				table.insert(chunk, batches[queue[cursor]])
				cursor += 1
			end
			runChunk(chunk, attempt)
			for _, batch in chunk do
				local status = lastStatus[batch.index]
				local report = adopted[batch.index]
				if
					status ~= "returned"
					and attempt < policy.retry.maxAttempts
					and table.find(policy.retry.on, status) ~= nil
				then
					table.insert(retryQueue, batch.index)
				end
				if policy.failFast and report ~= nil and hasFailure(report :: Report) then
					stopKind = "fail-fast"
					stopped = ("fail-fast stopped the run after %s"):format(batch.id)
				end
			end
		end
		if stopped ~= nil or #retryQueue == 0 or attempt >= policy.retry.maxAttempts then
			break
		end
		queue = retryQueue
		attempt += 1
	end

	for index = #acquired, 1, -1 do
		local fixture = acquired[index]
		local release = fixture.release
		if release == nil then
			continue
		end
		local ok, thrown: unknown = pcall(release :: () -> ())
		if not ok then
			fact("fixture-cleanup-failed", fixture.name, tostring(thrown))
		end
	end

	for _, batch in batches do
		local index = batch.index
		local record: BatchRecord = {
			id = batch.id,
			index = index,
			units = unitIds(batch.units),
			dispatched = dispatched[index] == true,
			attempts = attemptCount[index] or 0,
			outcome = lastStatus[index],
			reason = lastDetail[index],
		}
		table.insert(batchRecords, record)

		local produced = producedReports[index]
		if produced ~= nil and #produced > 1 then
			local first = produced[1]
			local last = produced[#produced]
			if ReportModel.verdictDigest(first) ~= ReportModel.verdictDigest(last) then
				fact(
					"attempt-disagreement",
					batch.id,
					("%d attempts produced different verdicts for %s: %s"):format(
						#produced,
						table.concat(ReportModel.verdictDifferences(first, last), ", "),
						"every attempt is retained below"
					)
				)
			end
		end
		if (attemptCount[index] or 0) > 1 then
			fact(
				"retry-performed",
				batch.id,
				("%d attempts were made under the plan's infrastructure retry policy; %s"):format(
					attemptCount[index],
					"no correctness verdict was retried"
				)
			)
		end

		local report = adopted[index]
		if report ~= nil then
			for position = #attempts, 1, -1 do
				local candidate = attempts[position]
				if candidate.batchIndex == index and candidate.produced and candidate.status == "returned" then
					candidate.adopted = true
					break
				end
			end
			if adapter.artifact ~= nil then
				for _, result in (report :: Report).results do
					for artifactIndex, artifact in result.artifacts do
						local ok, replaced: any = pcall(adapter.artifact :: any, result.id, artifact)
						if ok and type(replaced) == "table" then
							result.artifacts[artifactIndex] = replaced :: Artifact
						elseif not ok then
							fact("artifact-sink-failed", artifact.name, tostring(replaced))
						end
					end
				end
			end
			payloadCount += 1
			table.insert(payloads, { id = batch.id, report = report })
			continue
		end
		if #batch.units == 0 then
			continue
		end
		if not record.dispatched then
			continue
		end

		local status = lastStatus[index]
		local detail = lastDetail[index]
		fact("batch-not-returned", batch.id, ("%s: %s"):format(tostring(status), detail))
		for _, unit in batch.units do
			if status == "timed_out" then
				unitReport(unit, "timed-out", "timed_out", "executor", detail)
			elseif status == "cancelled" then
				unitReport(unit, "cancelled", "cancelled", "executor", detail)
			else
				unitReport(unit, "faulted", "failed", "executor", detail)
			end
		end
	end

	if stopped ~= nil then
		if stopKind == "cancelled" then
			fact("cancelled", selected.id, stopped :: string)
		elseif stopKind == "run-deadline" then
			fact("run-deadline-exceeded", selected.id, stopped :: string)
		elseif stopKind == "fail-fast" then
			fact("fail-fast-stopped", selected.id, stopped :: string)
		end
		for _, batch in batches do
			if dispatched[batch.index] == true then
				continue
			end
			for _, unit in batch.units do
				if stopKind == "run-deadline" then
					unitReport(unit, "not-dispatched", "timed_out", "executor", stopped)
				elseif stopKind == "fail-fast" then
					unitReport(unit, "not-dispatched", "skipped", nil, nil, stopped)
				else
					unitReport(unit, "not-dispatched", "cancelled", "executor", stopped)
				end
			end
		end
	end

	local composed = ReportModel.compose(payloads, adapter.name, environment)
	if composed.total == 0 then
		fact("no-cases", selected.id, "the plan dispatched no case at all, so this run proved nothing")
	end

	local factPayloads: { ShardPayload } = {}
	for index, entry in facts do
		if entry.severity ~= "failure" then
			continue
		end
		table.insert(factPayloads, {
			id = ("fact-%d"):format(index),
			report = synthetic {
				executor = adapter.name,
				environment = environment,
				capabilities = declared,
				id = ("execution:%s:%s"):format(entry.code, entry.subject),
				name = entry.code,
				status = "failed",
				phase = "executor",
				message = entry.detail,
			},
		})
	end
	local report = if #factPayloads > 0
		then ReportModel.compose(
			(function(): { ShardPayload }
				local all: { ShardPayload } = table.clone(payloads)
				for _, entry in factPayloads do
					table.insert(all, entry)
				end
				return all
			end)(),
			adapter.name,
			environment
		)
		else composed

	return {
		schemaVersion = SCHEMA_VERSION,
		provenance = {
			planId = selected.id,
			planSchemaVersion = selected.schemaVersion,
			planDigest = digest,
			unitCount = #selected.units,
			planUnitCount = #checkedPlan.units,
			complete = complete,
			host = adapter.name,
			batchCount = batchCount,
			parallelism = parallel,
			batching = batching,
		},
		capabilities = declared,
		batches = batchRecords,
		attempts = attempts,
		facts = facts,
		report = report,
	}
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	execute = execute,
}
