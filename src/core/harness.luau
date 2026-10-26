--!strict

local Model = require "./harness-types"
local executeCase = require "./case-execution"

local Capability = require "./capability"
local Attachment = require "./attachment"
local ReportModel = require "./report"
local Types = require "./types"
local Operations = require "./operations"

type Failure = Model.Failure
type Origin = Model.Origin
export type CaseResult = Model.CaseResult
export type Report = Model.Report
export type InvocationResult = Model.InvocationResult
export type Invoker = Model.Invoker
export type StepOptions = Model.StepOptions
export type Disposable<T = unknown> = Model.Disposable<T>
export type Resource<T = unknown> = Model.Resource<T>
export type Context = Model.Context
export type CaseRun = Model.CaseRun
export type CaseOptions = Model.CaseOptions
export type Selection = Model.Selection
export type RunOptions = Model.RunOptions
export type Harness = Model.Harness
export type SyntheticOptions = Model.SyntheticOptions
type CaseEntry = Model.CaseEntry
type Suite = Model.Suite

local DESELECTED_PREFIX = "deselected: "

local function newSuite(name: string, parent: Suite?): Suite
	return {
		name = name,
		parent = parent,
		children = {},
		cases = {},
		beforeEach = {},
		afterEach = {},
	}
end

local checkedName = Model.checkedName
local copySortedUnique = Capability.sorted

local function copyEnvironment(values: { [string]: string }?): { [string]: string }
	local result: { [string]: string } = {}
	local sourceValues: { [string]: string } = if values ~= nil then values else {}
	for key, value in sourceValues do
		if key == "" or type(value) ~= "string" then
			error("environment must contain non-empty string keys and string values", 3)
		end
		result[key] = value
	end
	return result
end

local ancestors = Model.ancestors
local suitePath = Model.suitePath
local function humanId(path: { string }, name: string): string
	local pieces = table.clone(path)
	table.insert(pieces, name)
	return table.concat(pieces, " > ")
end

local micros = Model.micros
local function origin(executor: string, environment: { [string]: string }, capabilities: { string }): Origin
	return {
		executor = executor,
		environment = copyEnvironment(environment),
		capabilities = table.clone(capabilities),
	}
end

local function defaultInvoke(_phase: Types.InvocationPhase, run: () -> ()): InvocationResult
	local ok, result: unknown = pcall(run)
	return if ok then { outcome = "returned" } else { outcome = "failed", error = result }
end

local selectionSet = Capability.set

local function intersects(values: { string }, wanted: { [string]: boolean }): boolean
	for _, value in values do
		if wanted[value] then
			return true
		end
	end
	return false
end

local function startsWithAny(value: string, prefixes: { string }?): boolean
	local sourcePrefixes: { string } = if prefixes ~= nil then prefixes else {}
	for _, prefix in sourcePrefixes do
		if string.sub(value, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

local function selected(entry: CaseEntry, path: { string }, selection: Selection?): boolean
	if selection == nil then
		return true
	end
	local ids = selectionSet(selection.ids)
	local tags = selectionSet(selection.tags)
	local capabilities = selectionSet(selection.capabilities)
	if next(ids) ~= nil and not ids[entry.id] then
		return false
	end
	if
		selection.suitePrefixes ~= nil
		and #selection.suitePrefixes > 0
		and not startsWithAny(table.concat(path, " > "), selection.suitePrefixes)
	then
		return false
	end
	local sources = selectionSet(selection.sources)
	return (next(sources) == nil or (entry.source ~= nil and sources[entry.source] == true))
		and (selection.nameContains == nil or string.find(entry.name, selection.nameContains, 1, true) ~= nil)
		and (next(tags) == nil or intersects(entry.tags, tags))
		and (next(capabilities) == nil or intersects(entry.requires, capabilities))
		and (
			selection.predicate == nil
			or selection.predicate {
				id = entry.id,
				source = entry.source,
				path = path,
				name = entry.name,
				tags = entry.tags,
				requires = entry.requires,
			}
		)
end

local function createHarness(options: {
	now: () -> number,
	source: string?,
	prefixIds: boolean?,
	attachments: Attachment.Limits?,
}): Harness
	if type(options) ~= "table" or type(options.now) ~= "function" then
		error("createHarness requires a monotonic now function", 2)
	end
	if options.source ~= nil and options.source == "" then
		error("harness source must not be empty", 2)
	end
	if options.prefixIds == true and options.source == nil then
		error("createHarness cannot prefix ids without a source", 2)
	end
	local now = options.now
	local execution = { now = now, limits = Attachment.resolve(options.attachments), bytes = 0 }
	local configuredLimits = options.attachments
	local source = options.source
	local prefixIds = if options.prefixIds ~= nil then options.prefixIds else source ~= nil
	local root = newSuite("", nil)
	local current = root
	local running = false
	local caseIds: { [string]: boolean } = {}
	local harness: Harness

	local function harness_suite(self: Harness, name: string, register: () -> ())
		if running then
			error("cannot register a suite while a harness is running", 2)
		end
		local child = newSuite(checkedName("suite", name), current)
		table.insert(current.children, child)
		local previous = current
		current = child
		local ok, registrationError: unknown = pcall(register)
		current = previous
		if not ok then
			error(("suite %q registration failed: %s"):format(name, tostring(registrationError)), 2)
		end
	end

	local function harness_case(self: Harness, name: string, definition: CaseRun | CaseOptions)
		if running then
			error("cannot register a case while a harness is running", 2)
		end
		local run: CaseRun
		local requirements: { string } = {}
		local tags: { string } = {}
		local limitations: { string } = {}
		local explicitId: string? = nil
		local timeoutSeconds: number? = nil
		local cleanupTimeoutSeconds: number? = nil
		if type(definition) == "function" then
			run = definition
		else
			if type(definition.run) ~= "function" then
				error(("case %q requires a run function"):format(name), 2)
			end
			run = definition.run
			requirements = copySortedUnique(definition.requires, "case requirements")
			tags = copySortedUnique(definition.tags, "case tags")
			limitations = copySortedUnique(definition.limitations, "case limitations")
			explicitId = definition.id
			timeoutSeconds = definition.timeoutSeconds
			cleanupTimeoutSeconds = definition.cleanupTimeoutSeconds
			if cleanupTimeoutSeconds ~= nil then
				assert(
					cleanupTimeoutSeconds > 0 and cleanupTimeoutSeconds < math.huge,
					"cleanup timeout must be positive and finite"
				)
			end
			if timeoutSeconds ~= nil then
				assert(timeoutSeconds > 0 and timeoutSeconds < math.huge, "case timeout must be positive and finite")
			end
		end
		local path = suitePath(ancestors(current))
		local id = explicitId or humanId(path, checkedName("case", name))
		if explicitId == "" then
			error("case id must not be empty", 2)
		end
		if prefixIds and source ~= nil and explicitId == nil then
			id = source .. "::" .. id
		end
		if caseIds[id] then
			error("duplicate case id: " .. id, 2)
		end
		caseIds[id] = true
		table.insert(current.cases, {
			id = id,
			name = name,
			source = source,
			timeoutSeconds = timeoutSeconds,
			cleanupTimeoutSeconds = cleanupTimeoutSeconds,
			run = run,
			requires = requirements,
			tags = tags,
			limitations = limitations,
		})
	end

	local function harness_skip(self: Harness, name: string, reason: string, run: CaseRun?)
		if reason == "" then
			error("skip reason must not be empty", 2)
		end
		harness:case(name, run or function() end)
		current.cases[#current.cases].skipReason = reason
	end

	local function harness_beforeEach(self: Harness, run: CaseRun)
		if running then
			error("cannot register a hook while a harness is running", 2)
		end
		table.insert(current.beforeEach, run)
	end

	local function harness_afterEach(self: Harness, run: CaseRun)
		if running then
			error("cannot register a hook while a harness is running", 2)
		end
		table.insert(current.afterEach, run)
	end

	local function harness_run(self: Harness, runOptions: RunOptions): Report
		if running then
			error("a harness cannot run recursively", 2)
		end
		if runOptions.executor == "" then
			error("run executor must not be empty", 2)
		end
		local shard = if runOptions.selection then runOptions.selection.shard else nil
		if shard ~= nil then
			local index, count = shard.index, shard.count
			if count % 1 ~= 0 or index % 1 ~= 0 or count < 1 or index < 1 or index > count then
				error("selection shard needs whole numbers with 1 <= index <= count", 2)
			end
		end
		running = true
		execution.bytes = 0
		execution.limits = Attachment.resolve(runOptions.attachments or configuredLimits)
		local started = now()
		local capabilityList = copySortedUnique(runOptions.capabilities, "capability")
		local environment = copyEnvironment(runOptions.environment)
		local runOrigin = origin(runOptions.executor, environment, capabilityList)
		local available = Capability.set(capabilityList)
		local results: { CaseResult } = {}
		local invoker = runOptions.invoke or defaultInvoke
		local position = 0
		local function inShard(): boolean
			position += 1
			return shard == nil or (position - 1) % shard.count == shard.index - 1
		end
		local function walk(suite: Suite)
			local path = suitePath(ancestors(suite))
			for _, entry in suite.cases do
				local matches = selected(entry, path, runOptions.selection)
				if matches and inShard() then
					local result = executeCase(suite, entry, available, runOrigin, invoker, runOptions, execution)
					table.insert(results, result)
				elseif runOptions.selection ~= nil and runOptions.selection.account == true then
					local skipped = table.clone(entry)
					skipped.requires = {}
					skipped.skipReason = DESELECTED_PREFIX
						.. if matches
							then "the run's shard did not include this case"
							else "the run's selection did not include this case"
					table.insert(
						results,
						executeCase(suite, skipped, available, runOrigin, invoker, runOptions, execution)
					)
				end
			end
			for _, child in suite.children do
				walk(child)
			end
		end
		local ok, walkError: unknown = pcall(walk, root)
		running = false
		if not ok then
			error("harness execution failed: " .. tostring(walkError), 2)
		end
		local passed, failed, skipped, unsupported, timedOut, cancelled = ReportModel.counts(results)
		return {
			schemaVersion = ReportModel.SCHEMA_VERSION,
			executor = runOptions.executor,
			environment = environment,
			capabilities = capabilityList,
			sources = { runOrigin },
			results = results,
			passed = passed,
			failed = failed,
			skipped = skipped,
			unsupported = unsupported,
			timedOut = timedOut,
			cancelled = cancelled,
			total = #results,
			durationMicros = micros(now() - started),
		}
	end

	harness = {
		suite = harness_suite,
		case = harness_case,
		skip = harness_skip,
		beforeEach = harness_beforeEach,
		afterEach = harness_afterEach,
		run = harness_run,
	}
	return harness
end

local function syntheticReport(options: SyntheticOptions): Report
	if options.id == "" or options.name == "" or options.executor == "" then
		error("synthetic report requires non-empty id, name and executor", 2)
	end
	local environment = copyEnvironment(options.environment)
	local capabilities = copySortedUnique(options.capabilities, "capability")
	local runOrigin = origin(options.executor, environment, capabilities)
	local missing = copySortedUnique(options.missingCapabilities, "missing capability")
	local failures: { Failure } = {}

	if options.status == "unsupported" then
		if #missing == 0 then
			error("an unsupported synthetic report must name at least one missing capability", 2)
		end
	elseif options.status == "skipped" then
		if options.skipReason == nil or options.skipReason == "" then
			error("a skipped synthetic report must name a non-empty skip reason", 2)
		end
	else
		local outcome: Types.FailureOutcome = if options.status == "timed_out"
			then "timed_out"
			elseif options.status == "cancelled" then "cancelled"
			else "failed"
		local message: string = options.message or tostring(options.status)
		table.insert(failures, {
			phase = options.phase or "executor",
			outcome = outcome,
			message = message,
		})
	end
	local result: CaseResult = {
		id = options.id,
		source = options.source,
		path = {},
		name = options.name,
		status = options.status,
		durationMicros = 0,
		failures = failures,
		steps = {},
		artifacts = {},
		limitations = copySortedUnique(options.limitations, "limitation"),
		missingCapabilities = missing,
		skipReason = if options.status == "skipped" then options.skipReason else nil,
		origin = runOrigin,
	}
	local passed, failed, skipped, unsupported, timedOut, cancelled = ReportModel.counts { result }
	return {
		schemaVersion = ReportModel.SCHEMA_VERSION,
		executor = options.executor,
		environment = environment,
		capabilities = capabilities,
		sources = { runOrigin },
		results = { result },
		passed = passed,
		failed = failed,
		skipped = skipped,
		unsupported = unsupported,
		timedOut = timedOut,
		cancelled = cancelled,
		total = 1,
		durationMicros = 0,
	}
end

export type NamedCase = CaseOptions & { name: string }
local function runCase(spec: NamedCase, host: Operations.Host): Report
	local harness = createHarness { now = host.now }
	harness:case(spec.name, spec)
	return harness:run {
		executor = host.name,
		capabilities = host.capabilities,
		environment = host.environment,
		bind = function(): Operations.Host
			return host
		end,
	}
end

local function runCases(specs: { NamedCase }, options: RunOptions, now: () -> number, ids: { string }?): Report
	local known: { [string]: NamedCase } = {}
	for _, spec in specs do
		local id = spec.id
		assert(id ~= nil and id ~= "", "runCases requires explicit case ids")
		assert(known[id] == nil, "duplicate case id: " .. id)
		known[id] = spec
	end
	assert(#specs > 0, "case collection is empty")
	local selected: { [string]: boolean } = {}
	if ids ~= nil then
		assert(#ids > 0, "case selection is empty")
		for _, id in ids do
			assert(known[id] ~= nil, "unknown selected case: " .. id)
			assert(not selected[id], "duplicate selected case: " .. id)
			selected[id] = true
		end
	end
	assert(options.selection == nil, "runCases owns selection; pass case ids explicitly")
	local harness = createHarness { now = now }
	for _, spec in specs do
		local id = spec.id
		assert(id ~= nil)
		if ids == nil or selected[id] then
			harness:case(spec.name, spec)
		end
	end
	local settings = table.clone(options)
	settings.environment = table.clone(options.environment or {})
	local environment = settings.environment
	assert(environment ~= nil)
	environment["caseSelection"] = if ids == nil then "all" else "explicit"
	environment["availableCases"] = tostring(#specs)
	return harness:run(settings)
end

return {
	DESELECTED_PREFIX = DESELECTED_PREFIX,
	createHarness = createHarness,
	runCase = runCase,
	runCases = runCases,
	syntheticReport = syntheticReport,
}
