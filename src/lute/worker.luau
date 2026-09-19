--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local task = require "@std/task"

local Batch = require "./batch"
local Files = require "./files"
local Mailbox = require "./mailbox"
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

	idleTimeoutSeconds: number?,
	pollSeconds: number?,
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
	if batchPath == "--pool" then
		print "verify worker: this entry point is one-shot; a pooled worker must call poolMain"
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

local function poolLoopWith(run: (PlanBatch, Options?) -> Report, options: Options?)
	local directory = process.args[3]
	local slotText = process.args[4]
	local slot = tonumber(slotText)
	if directory == nil or slot == nil then
		print "verify worker: usage: <worker>.luau --pool <directory> <slot>"
		process.exit(1)
		return
	end

	local settings: Options = if options ~= nil then options else {}
	local idleTimeout = settings.idleTimeoutSeconds or 300
	local poll = settings.pollSeconds or 0.002

	fs.writeStringToFile(Mailbox.readyPath(directory :: string, slot :: number), "ready")

	local lastWork = os.clock()
	while true do
		if fs.exists(Mailbox.stopPath(directory :: string)) then
			return
		end
		if os.clock() - lastWork >= idleTimeout then
			return
		end

		local pending: { name: string, sequence: number } = { name = "", sequence = 0 }

		local prefix = "w" .. tostring(slot :: number) .. "%-"
		for _, name in Files.listFileNames(directory :: string) do
			local sequence = string.match(name, "^" .. prefix .. "(%d+)%-request%.done$")
			if sequence ~= nil then
				pending = { name = name, sequence = tonumber(sequence) :: number }
				break
			end
		end
		if pending.name == "" then
			task.wait(poll)
			continue
		end

		local names = Mailbox.names(directory :: string, slot :: number, pending.sequence)

		if not pcall(fs.remove, names.requestReady) then
			task.wait(poll)
			continue
		end
		local read, encoded: any = pcall(fs.readFileToString, names.request)
		if not read then
			task.wait(poll)
			continue
		end
		pcall(fs.remove, names.request)

		local payload: string
		local decoded, batch: any = pcall(Batch.decode, encoded :: string)
		if decoded then
			local ran, value: any = pcall(run, batch :: PlanBatch, options)
			if ran then
				payload = Wire.encode(value :: Report)
			else
				payload = Mailbox.RAISED_PREFIX .. tostring(value)
			end
		else
			payload = Mailbox.RAISED_PREFIX .. "undecodable batch: " .. tostring(batch)
		end

		fs.writeStringToFile(names.response, payload)

		fs.writeStringToFile(names.sentinel, "")
		lastWork = os.clock()
	end
end

local function poolMain(operations: Operations, options: Options?)
	poolLoopWith(function(batch, opts)
		return runBatch(batch, operations, opts)
	end, options)
end

local function poolMainSelfRegistering(operations: SelfRegisteringOperations, options: Options?)
	poolLoopWith(function(batch, opts)
		return runBatchSelfRegistering(batch, operations, opts)
	end, options)
end

return {
	DEFAULT_CAPABILITIES = DEFAULT_CAPABILITIES,
	runBatch = runBatch,
	runBatchSelfRegistering = runBatchSelfRegistering,
	main = main,
	mainSelfRegistering = mainSelfRegistering,
	poolMain = poolMain,
	poolMainSelfRegistering = poolMainSelfRegistering,
}
