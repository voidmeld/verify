--!strict

local fs = require "@std/fs"
local process = require "@std/process"

local Batch = require "./batch"
local Verify = require "../core"
local Wire = require "./wire"

type PlanBatch = Verify.PlanBatch
type Report = Verify.Report

export type Load = (locator: string) -> unknown

export type Registrar = (locator: string, harness: Verify.Harness) -> ()

export type LoadDisposition = {
	status: "skipped" | "unsupported",
	reason: string?,
	missingCapabilities: { string }?,
}

export type Operations = {
	load: Load,
	now: (() -> number)?,

	classifyLoadFailure: ((locator: string, thrown: unknown) -> LoadDisposition?)?,
}

export type SelfRegisteringOperations = {
	load: Registrar,
	now: (() -> number)?,
	classifyLoadFailure: ((locator: string, thrown: unknown) -> LoadDisposition?)?,
}

export type Options = {
	executor: string?,
	capabilities: { string }?,
	environment: { [string]: string }?,
	caseIdStyle: ("unit-prefixed" | "bare")?,
}

local DEFAULT_CAPABILITIES = { "local-luau", "worker" }

local function runBatchWith(
	batch: PlanBatch,
	operations: Operations | SelfRegisteringOperations,
	options: Options?,
	selfRegistering: boolean
): Report
	local settings: Options = if options ~= nil then options else {}
	local executor = settings.executor or "lute"
	local capabilities = settings.capabilities or DEFAULT_CAPABILITIES
	local environment = settings.environment or { runtime = "lute" }
	local session = Verify.createSession {
		executor = executor,
		environment = environment,
		capabilities = capabilities,
		now = operations.now or os.clock,
		prefixCaseIds = (settings.caseIdStyle or "unit-prefixed") == "unit-prefixed",
	}

	for _, unit in batch.units do
		local phase = if selfRegistering then "registration" else "load"
		local classify = true
		local succeeded: boolean
		local value: unknown
		if selfRegistering then
			session:open(unit.locator)
			succeeded, value = pcall((operations :: SelfRegisteringOperations).load, unit.locator, session:harness())
			session:close()
		else
			succeeded, value = pcall((operations :: Operations).load, unit.locator)
			if succeeded then
				classify = false
				if type(value) == "function" then
					phase = "registration"
					session:open(unit.locator)
					succeeded, value = pcall(value :: (Verify.Harness) -> (), session:harness())
					session:close()
				else
					succeeded = false
					value = "the loaded value is not a registration function"
				end
			end
		end
		if succeeded then
			continue
		end

		local disposition: LoadDisposition? = nil
		if classify and operations.classifyLoadFailure ~= nil then
			local classified, verdict: any = pcall(operations.classifyLoadFailure :: any, unit.locator, value)
			if classified and type(verdict) == "table" then
				disposition = verdict :: LoadDisposition
			end
		end
		local id = ("unit:%s:%s"):format(unit.id, phase)
		if disposition ~= nil and disposition.status == "unsupported" then
			session:adoptReport(
				unit.locator,
				Verify.syntheticReport {
					executor = executor,
					environment = environment,
					capabilities = capabilities,
					id = id,
					source = unit.locator,
					name = unit.id,
					status = "unsupported",
					missingCapabilities = disposition.missingCapabilities or { "unnamed-prerequisite" },
				}
			)
		else
			local skipped = disposition ~= nil and disposition.status == "skipped"
			session:adoptReport(
				unit.locator,
				session:sourceReport(
					id,
					unit.locator,
					if skipped then "skipped" else "failed",
					if skipped then (disposition :: LoadDisposition).reason or tostring(value) else tostring(value)
				)
			)
		end
	end
	return session:run()
end

local function runBatch(batch: PlanBatch, operations: Operations, options: Options?): Report
	return runBatchWith(batch, operations, options, false)
end

local function runBatchSelfRegistering(
	batch: PlanBatch,
	operations: SelfRegisteringOperations,
	options: Options?
): Report
	return runBatchWith(batch, operations, options, true)
end

local function mainWith(run: (PlanBatch, Options?) -> Report, options: Options?)
	local batchPath = process.args[2]
	local resultPath = process.args[3]
	if batchPath == nil or resultPath == nil then
		print "verify worker: usage: <worker>.luau <batch.json> <result.json>"
		process.exit(1)
		return
	end
	local batch = Batch.decode(fs.readFileToString(batchPath :: string))
	local report = run(batch, options)
	fs.writeStringToFile(resultPath :: string, Wire.encode(report))
end

local function main(operations: Operations, options: Options?)
	mainWith(function(batch, opts)
		return runBatch(batch, operations, opts)
	end, options)
end

local function mainSelfRegistering(operations: SelfRegisteringOperations, options: Options?)
	mainWith(function(batch, opts)
		return runBatchSelfRegistering(batch, operations, opts)
	end, options)
end

return {
	DEFAULT_CAPABILITIES = DEFAULT_CAPABILITIES,
	runBatch = runBatch,
	runBatchSelfRegistering = runBatchSelfRegistering,
	main = main,
	mainSelfRegistering = mainSelfRegistering,
}
