--!strict

local Batch = require "./batch"
local Binding = require "./binding"
local Receipt = require "./receipt"
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
	bind: ((Verify.Context) -> Verify.CaseHost)?,
	cancelled: (() -> boolean)?,
	executor: string?,
	capabilities: { string }?,
	environment: { [string]: string }?,
	caseIdStyle: ("unit-prefixed" | "bare")?,
	selection: Verify.Selection?,
}

export type Arguments = {
	runId: string?,
	extras: { string },
	selection: Verify.Selection?,
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
		bind = settings.bind,
		cancelled = settings.cancelled,
		environment = environment,
		capabilities = capabilities,
		now = operations.now or os.clock,
		prefixCaseIds = (settings.caseIdStyle or "unit-prefixed") == "unit-prefixed",
		selection = settings.selection,
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
			local classified, verdict: unknown =
				pcall(operations.classifyLoadFailure :: (string, unknown) -> LoadDisposition?, unit.locator, value)
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

local function withDefaults(runtime: Binding.Runtime, options: Options?): Options
	local settings: Options = if options ~= nil then options else {}
	local defaulted = table.clone(settings)
	defaulted.executor = settings.executor or runtime.name
	defaulted.environment = settings.environment or { runtime = runtime.name }
	return defaulted
end

local TIER_PREFIX = "tier:"

local function parseArguments(arguments: { string }): Arguments
	local runId: string? = nil
	local extras: { string } = {}
	local separator = table.find(arguments, "--")
	if arguments[3] ~= nil and separator ~= 3 then
		runId = arguments[3]
	end
	if separator ~= nil then
		for index = separator + 1, #arguments do
			table.insert(extras, arguments[index])
		end
	end
	local ids: { string } = {}
	local tags: { string } = {}
	local sources: { string } = {}
	local nameFilter: string? = nil
	local tiers: { [string]: boolean } = {}
	local tiered = false
	for _, extra in extras do
		local case = string.match(extra, "^%-%-case=(.+)$")
		local tag = string.match(extra, "^%-%-tag=(.+)$")
		local tier = string.match(extra, "^%-%-tier=(.+)$")
		local contains = string.match(extra, "^%-%-name=(.+)$")
		local source = string.match(extra, "^%-%-source=(.+)$")
		if case ~= nil then
			table.insert(ids, case)
		elseif contains ~= nil then
			nameFilter = contains
		elseif source ~= nil then
			table.insert(sources, source)
		elseif tag ~= nil then
			table.insert(tags, tag)
		elseif tier ~= nil then
			tiered = true
			for name in string.gmatch(tier, "[^,]+") do
				tiers[name] = true
			end
		end
	end
	if #ids == 0 and #tags == 0 and #sources == 0 and nameFilter == nil and not tiered then
		return { runId = runId, extras = extras, selection = nil }
	end
	local predicate: Verify.SelectionPredicate? = nil
	if tiered then
		predicate = function(subject: Verify.SelectionSubject): boolean
			local declared = false
			for _, tag in subject.tags do
				if string.sub(tag, 1, #TIER_PREFIX) == TIER_PREFIX then
					declared = true
					if tiers[string.sub(tag, #TIER_PREFIX + 1)] then
						return true
					end
				end
			end
			return not declared
		end
	end
	return {
		runId = runId,
		extras = extras,
		selection = {
			ids = if #ids > 0 then ids else nil,
			tags = if #tags > 0 then tags else nil,
			sources = if #sources > 0 then sources else nil,
			nameContains = nameFilter,
			predicate = predicate,
			account = true,
		},
	}
end

local function mainWith(runtime: Binding.Runtime, run: (PlanBatch, Options?) -> Report, options: Options?)
	local arguments = runtime.process.arguments
	local parsed = parseArguments(arguments)
	local batchPath = arguments[1]
	local resultPath = arguments[2]
	if batchPath == nil or resultPath == nil then
		runtime.stdio.print "verify worker: usage: <worker>.luau <batch.json> <result.json> [run-id]"
		runtime.process.exit(1)
		return
	end
	local batch = Batch.create(runtime.json).decode(runtime.fs.read(batchPath))
	local settings = withDefaults(runtime, options)
	if settings.selection == nil then
		settings.selection = parsed.selection
	end
	local report = run(batch, settings)
	local runId = parsed.runId
	if runId ~= nil then
		runtime.fs.write(resultPath, Receipt.encode(runtime.json, runId, batch.id, report))
	else
		runtime.fs.write(resultPath, Wire.create(runtime.json).encode(report))
	end
end

export type Worker = {
	DEFAULT_CAPABILITIES: { string },
	arguments: () -> Arguments,
	runBatch: (batch: PlanBatch, operations: Operations, options: Options?) -> Report,
	runBatchSelfRegistering: (batch: PlanBatch, operations: SelfRegisteringOperations, options: Options?) -> Report,
	main: (operations: Operations, options: Options?) -> (),
	mainSelfRegistering: (operations: SelfRegisteringOperations, options: Options?) -> (),
}

local function create(runtime: Binding.Runtime): Worker
	Binding.validate(runtime)
	return {
		DEFAULT_CAPABILITIES = DEFAULT_CAPABILITIES,
		arguments = function(): Arguments
			return parseArguments(runtime.process.arguments)
		end,
		runBatch = function(batch: PlanBatch, operations: Operations, options: Options?): Report
			return runBatchWith(batch, operations, withDefaults(runtime, options), false)
		end,
		runBatchSelfRegistering = function(
			batch: PlanBatch,
			operations: SelfRegisteringOperations,
			options: Options?
		): Report
			return runBatchWith(batch, operations, withDefaults(runtime, options), true)
		end,
		main = function(operations: Operations, options: Options?)
			mainWith(runtime, function(batch, opts)
				return runBatchWith(batch, operations, opts, false)
			end, options)
		end,
		mainSelfRegistering = function(operations: SelfRegisteringOperations, options: Options?)
			mainWith(runtime, function(batch, opts)
				return runBatchWith(batch, operations, opts, true)
			end, options)
		end,
	}
end

return {
	DEFAULT_CAPABILITIES = DEFAULT_CAPABILITIES,
	parseArguments = parseArguments,
	create = create,
}
