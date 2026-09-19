--!strict

local Verify = require "../core"

type Artifact = Verify.Artifact
type BatchOutcome = Verify.BatchOutcome
type BatchStatus = Verify.BatchStatus
type PlanBatch = Verify.PlanBatch
type Report = Verify.Report

export type UnitRun = (harness: Verify.Harness) -> ()

export type Fault = {
	batch: string?,
	attempt: number?,
	status: BatchStatus,
	detail: string?,
	report: unknown?,
}

export type Options = {
	name: string?,
	capabilities: { string }?,
	environment: { [string]: string }?,

	units: { [string]: UnitRun },

	latency: { [string]: number }?,
	faults: { Fault }?,
	clockStep: number?,
	maxParallelBatches: number?,

	completionOrder: ("index" | "reverse")?,
	dropped: { string }?,
	duplicated: { string }?,
	cancelAfter: number?,
	artifactPrefix: string?,
	artifactFailsFor: string?,
}

export type FakeHost = Verify.Host & {
	dispatched: { string },
	attemptsOf: (batchId: string) -> number,
}

local DEFAULT_CAPABILITIES = { "in-memory" }

local function matches(fault: Fault, batch: PlanBatch, attempt: number): boolean
	if fault.batch ~= nil and fault.batch ~= batch.id then
		return false
	end
	if fault.attempt ~= nil and fault.attempt ~= attempt then
		return false
	end
	return true
end

local function contains(values: { string }?, value: string): boolean
	if values == nil then
		return false
	end
	return table.find(values, value) ~= nil
end

local function create(options: Options): FakeHost
	if type(options) ~= "table" or type(options.units) ~= "table" then
		error("a fake host needs a unit table", 2)
	end
	local name = options.name or "fake"
	local capabilities = options.capabilities or DEFAULT_CAPABILITIES
	local environment = options.environment or { runtime = "fake" }
	local step = options.clockStep or 0.001
	local latency: { [string]: number } = options.latency or {}
	local faults: { Fault } = options.faults or {}
	local completionOrder = options.completionOrder or "index"

	local ticks = 0
	local offset = 0
	local function now(): number
		ticks += 1
		return offset + ticks * step
	end

	local attempts: { [string]: number } = {}
	local dispatched: { string } = {}

	local function reportFor(batch: PlanBatch): Report
		local reports: { Report } = {}
		for _, unit in batch.units do
			offset += latency[unit.id] or 0
			local run = options.units[unit.id]
			if run == nil then
				table.insert(
					reports,
					Verify.syntheticReport {
						executor = name,
						environment = environment,
						capabilities = capabilities,
						id = ("unit:%s:load"):format(unit.id),
						source = unit.locator,
						name = unit.id,
						status = "failed",
						phase = "load",
						message = ("the fake host was given no work for unit %q"):format(unit.id),
					}
				)
				continue
			end

			local harness = Verify.createHarness { now = now, source = unit.locator }
			local registered, thrown: unknown = pcall(run, harness)
			if not registered then
				table.insert(
					reports,
					Verify.syntheticReport {
						executor = name,
						environment = environment,
						capabilities = capabilities,
						id = ("unit:%s:registration"):format(unit.id),
						source = unit.locator,
						name = unit.id,
						status = "failed",
						phase = "registration",
						message = tostring(thrown),
					}
				)
				continue
			end
			table.insert(
				reports,
				harness:run {
					executor = name,
					capabilities = capabilities,
					environment = environment,
				}
			)
		end
		return Verify.merge(reports, name, environment)
	end

	local function runBatch(batch: PlanBatch): BatchOutcome
		local attempt = (attempts[batch.id] or 0) + 1
		attempts[batch.id] = attempt
		table.insert(dispatched, batch.id)
		offset += latency[batch.id] or 0
		for _, fault in faults do
			if matches(fault, batch, attempt) then
				return { status = fault.status, detail = fault.detail, report = fault.report }
			end
		end
		return { status = "returned", report = reportFor(batch) }
	end

	local host = {} :: FakeHost
	host.name = name
	host.capabilities = capabilities
	host.environment = environment
	host.now = now
	host.maxParallelBatches = options.maxParallelBatches
	host.runBatch = runBatch
	host.dispatched = dispatched

	function host.attemptsOf(batchId: string): number
		return attempts[batchId] or 0
	end

	if options.cancelAfter ~= nil then
		host.cancelled = function(): boolean
			return #dispatched >= (options.cancelAfter :: number)
		end
	end

	if options.artifactPrefix ~= nil or options.artifactFailsFor ~= nil then
		host.artifact = function(unitId: string, artifact: Artifact): Artifact
			if options.artifactFailsFor ~= nil and artifact.name == options.artifactFailsFor then
				error(("the fake artifact sink refused %q"):format(artifact.name), 0)
			end
			local prefix = options.artifactPrefix
			if prefix == nil then
				return artifact
			end
			return {
				name = artifact.name,
				reference = ("%s%s/%s"):format(prefix, unitId, artifact.reference),
				mediaType = artifact.mediaType,
			}
		end
	end

	host.runBatches = function(batches: { PlanBatch }, deliver: (number, BatchOutcome) -> ())
		local outcomes: { { index: number, outcome: BatchOutcome, id: string } } = {}
		for _, batch in batches do
			table.insert(outcomes, { index = batch.index, outcome = runBatch(batch), id = batch.id })
		end
		if completionOrder == "reverse" then
			local reversed: typeof(outcomes) = {}
			for position = #outcomes, 1, -1 do
				table.insert(reversed, outcomes[position])
			end
			outcomes = reversed
		end
		for _, entry in outcomes do
			if contains(options.dropped, entry.id) then
				continue
			end
			deliver(entry.index, entry.outcome)
			if contains(options.duplicated, entry.id) then
				deliver(entry.index, entry.outcome)
			end
		end
	end

	return host
end

return {
	create = create,
	DEFAULT_CAPABILITIES = DEFAULT_CAPABILITIES,
}
