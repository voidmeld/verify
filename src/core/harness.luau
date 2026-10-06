--!strict

local Attachment = require "./attachment"
local Matchers = require "./matchers"
local ReportModel = require "./report"
local Progress = require "./progress"
local Spy = require "./spy"
local Types = require "./types"
local Operations = require "./operations"
local Performance = require "./performance"

export type Status = Types.Status
export type Failure = Types.Failure
export type StepResult = Types.StepResult
export type Artifact = Types.Artifact
export type Origin = Types.Origin
export type CaseResult = Types.CaseResult
export type ReportSource = Types.ReportSource
export type Report = Types.Report
export type ManifestEntry = Types.ManifestEntry
export type Manifest = Types.Manifest
export type ShardPayload = Types.ShardPayload
export type Expectation = Matchers.Expectation
export type Spy = Spy.Spy
export type SpyCall = Spy.Call

export type InvocationResult = {
	outcome: "returned" | "failed" | "timed_out" | "cancelled",
	error: unknown?,
}
export type Invoker = (phase: Types.InvocationPhase, run: () -> ()) -> InvocationResult

export type StepOptions = {
	actor: string?,
	run: () -> (),
}

export type Disposable<T = unknown> = {
	dispose: ((self: T) -> ())?,
	destroy: ((self: T) -> ())?,
}
export type Resource<T = unknown> = (() -> ()) | (T & { dispose: (T) -> () }) | (T & { destroy: (T) -> () })

export type Context = {
	unsupported: (self: Context, requirement: string) -> never,
	await: <I, O>(
		self: Context,
		actor: string,
		operation: Operations.Operation<I, O>,
		input: I,
		predicate: (O) -> boolean,
		pollSeconds: number,
		deadlineSeconds: number?
	) -> O,
	perform: <I, O>(
		self: Context,
		actor: string,
		operation: Operations.Operation<I, O>,
		input: I,
		deadlineSeconds: number?
	) -> O,
	checkpoint: (self: Context, actor: string, name: string) -> (),
	judge: (self: Context, actor: string, checkpoint: string, criterion: string) -> (),
	measure: (self: Context, actor: string, name: string, input: Performance.Input, limits: Performance.Limits) -> (),
	remainingSeconds: (self: Context) -> number,

	expect: (self: Context, value: unknown) -> Expectation,
	defer: (self: Context, cleanup: () -> ()) -> (),
	own: <T>(self: Context, resource: Resource<T>) -> (),
	skip: (self: Context, reason: string) -> never,
	step: (self: Context, name: string, definition: (() -> ()) | StepOptions) -> (),
	artifact: (self: Context, name: string, reference: string, mediaType: string?) -> (),
	attach: (self: Context, name: string, mediaType: string, text: string) -> (),
}

export type CaseRun = (context: Context) -> ()
export type CaseOptions = {
	timeoutSeconds: number?,
	cleanupTimeoutSeconds: number?,
	id: string?,
	run: CaseRun,
	requires: { string }?,
	tags: { string }?,
	limitations: { string }?,
}

local DESELECTED_PREFIX = "deselected: "

export type SelectionSubject = Types.SelectionSubject
export type SelectionPredicate = Types.SelectionPredicate
export type Selection = {
	ids: { string }?,
	suitePrefixes: { string }?,
	sources: { string }?,
	nameContains: string?,
	tags: { string }?,
	capabilities: { string }?,
	predicate: SelectionPredicate?,
	account: boolean?,
}

export type RunOptions = {
	bind: ((context: Context) -> Operations.Host)?,
	cancelled: (() -> boolean)?,
	executor: string,
	capabilities: { string }?,
	environment: { [string]: string }?,
	selection: Selection?,
	invoke: Invoker?,
	progress: Progress.Progress?,
	attachments: Attachment.Limits?,
}

export type Harness = {
	suite: (self: Harness, name: string, register: () -> ()) -> (),
	case: (self: Harness, name: string, definition: CaseRun | CaseOptions) -> (),
	skip: (self: Harness, name: string, reason: string, run: CaseRun?) -> (),
	beforeEach: (self: Harness, run: CaseRun) -> (),
	afterEach: (self: Harness, run: CaseRun) -> (),
	run: (self: Harness, options: RunOptions) -> Report,
}

export type SyntheticOptions = {
	executor: string,
	environment: { [string]: string }?,
	capabilities: { string }?,
	id: string,
	source: string?,
	name: string,
	status: "failed" | "skipped" | "unsupported" | "timed_out" | "cancelled",
	phase: Types.FailurePhase?,
	message: string?,
	skipReason: string?,
	missingCapabilities: { string }?,
	limitations: { string }?,
}

type CaseEntry = {
	timeoutSeconds: number?,
	cleanupTimeoutSeconds: number?,
	id: string,
	name: string,
	source: string?,
	run: CaseRun,
	requires: { string },
	tags: { string },
	limitations: { string },
	skipReason: string?,
}

type Suite = {
	name: string,
	parent: Suite?,
	children: { Suite },
	cases: { CaseEntry },
	beforeEach: { CaseRun },
	afterEach: { CaseRun },
}

local RuntimeSkip = {}
local StepAbort = {}
local TimedOut = {}
local Cancelled = {}
local Unsupported = {}

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

local function checkedName(kind: string, name: string): string
	if name == "" then
		error(("%s name must not be empty"):format(kind), 3)
	end
	return name
end

local function copySortedUnique(values: { string }?, label: string): { string }
	local seen: { [string]: boolean } = {}
	local copy: { string } = {}
	local sourceValues: { string } = if values ~= nil then values else {}
	for _, value in sourceValues do
		if value == "" then
			error(label .. " values must not be empty", 3)
		end
		if not seen[value] then
			seen[value] = true
			table.insert(copy, value)
		end
	end
	table.sort(copy)
	return copy
end

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

local function ancestors(suite: Suite): { Suite }
	local values: { Suite } = {}
	local current: Suite? = suite
	while current ~= nil do
		table.insert(values, 1, current)
		current = current.parent
	end
	return values
end

local function suitePath(chain: { Suite }): { string }
	local path: { string } = {}
	for _, suite in chain do
		if suite.name ~= "" then
			table.insert(path, suite.name)
		end
	end
	return path
end

local function humanId(path: { string }, name: string): string
	local pieces = table.clone(path)
	table.insert(pieces, name)
	return table.concat(pieces, " > ")
end

local function micros(seconds: number): number
	return math.max(0, math.floor(seconds * 1e6 + 0.5))
end

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

local function selectionSet(values: { string }?): { [string]: boolean }
	local result: { [string]: boolean } = {}
	local sourceValues: { string } = if values ~= nil then values else {}
	for _, value in sourceValues do
		result[value] = true
	end
	return result
end

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
	if selection.suitePrefixes ~= nil and #selection.suitePrefixes > 0 then
		local suiteName = table.concat(path, " > ")
		if not startsWithAny(suiteName, selection.suitePrefixes) then
			return false
		end
	end
	local sources = selectionSet(selection.sources)
	if next(sources) ~= nil and (entry.source == nil or not sources[entry.source]) then
		return false
	end
	if selection.nameContains ~= nil and string.find(entry.name, selection.nameContains, 1, true) == nil then
		return false
	end
	if next(tags) ~= nil and not intersects(entry.tags, tags) then
		return false
	end
	if next(capabilities) ~= nil and not intersects(entry.requires, capabilities) then
		return false
	end
	if selection.predicate ~= nil then
		local subject: Types.SelectionSubject = {
			id = entry.id,
			source = entry.source,
			path = path,
			name = entry.name,
			tags = entry.tags,
			requires = entry.requires,
		}
		if not selection.predicate(subject) then
			return false
		end
	end
	return true
end

local function statusFor(failures: { Failure }, runtimeSkipReason: string?, missing: { string }): Status
	for _, failure in failures do
		if failure.outcome == "timed_out" then
			return "timed_out"
		end
	end
	for _, failure in failures do
		if failure.outcome == "cancelled" then
			return "cancelled"
		end
	end
	if #failures > 0 then
		return "failed"
	elseif #missing > 0 then
		return "unsupported"
	elseif runtimeSkipReason ~= nil then
		return "skipped"
	end
	return "passed"
end

local function number(value: number?): string
	return if value == nil then "-" else ("%.4g"):format(value)
end

local function measurementLine(measurement: Types.Measurement): string
	local summary = measurement.evaluation.summary
	local parts = {
		("%s [%s] n=%d"):format(measurement.name, summary.unit, summary.sampleCount),
		"p50=" .. number(summary.p50),
		"p95=" .. number(summary.p95),
	}
	local extra: { Performance.PercentileValue } = summary.percentiles or {}
	for _, entry in extra do
		table.insert(parts, ("p%s=%s"):format(number(entry.percentile), number(entry.value)))
	end
	table.insert(parts, measurement.evaluation.reason)
	return table.concat(parts, " ")
end

local function format(report: Report): string
	local lines = { ("Verify receipt v%d — %s"):format(report.schemaVersion, report.executor) }
	local environmentKeys: { string } = {}
	for key in report.environment do
		table.insert(environmentKeys, key)
	end
	table.sort(environmentKeys)
	for _, key in environmentKeys do
		table.insert(lines, ("  %s: %s"):format(key, report.environment[key]))
	end
	for _, result in report.results do
		table.insert(lines, ("  %-11s %s"):format(result.status, result.id))
		if result.skipReason ~= nil then
			table.insert(lines, "              " .. result.skipReason)
		end
		if #result.missingCapabilities > 0 then
			table.insert(lines, "              missing: " .. table.concat(result.missingCapabilities, ", "))
		end
		for _, failure in result.failures do
			table.insert(lines, ("              %s/%s: %s"):format(failure.phase, failure.outcome, failure.message))
		end
		if result.evidence ~= nil then
			for _, measurement in result.evidence.measurements do
				table.insert(lines, "              " .. measurementLine(measurement))
			end
		end
	end
	table.insert(
		lines,
		("%d passed, %d failed, %d skipped, %d unsupported, %d timed out, %d cancelled (%d total)"):format(
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
	local attachmentLimits = Attachment.resolve(options.attachments)
	local configuredLimits = options.attachments
	local source = options.source
	local prefixIds = if options.prefixIds ~= nil then options.prefixIds else source ~= nil
	local root = newSuite("", nil)
	local current = root
	local running = false
	local runAttachmentBytes = 0
	local caseIds: { [string]: boolean } = {}
	local harness = {} :: Harness

	function harness:suite(name: string, register: () -> ())
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

	function harness:case(name: string, definition: CaseRun | CaseOptions)
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

	function harness:skip(name: string, reason: string, run: CaseRun?)
		if reason == "" then
			error("skip reason must not be empty", 2)
		end
		harness:case(name, run or function() end)
		current.cases[#current.cases].skipReason = reason
	end

	function harness:beforeEach(run: CaseRun)
		if running then
			error("cannot register a hook while a harness is running", 2)
		end
		table.insert(current.beforeEach, run)
	end

	function harness:afterEach(run: CaseRun)
		if running then
			error("cannot register a hook while a harness is running", 2)
		end
		table.insert(current.afterEach, run)
	end

	local function executeCase(
		suite: Suite,
		entry: CaseEntry,
		available: { [string]: boolean },
		runOrigin: Origin,
		invoker: Invoker,
		runOptions: RunOptions
	): CaseResult
		local chain = ancestors(suite)
		local path = suitePath(chain)
		local missing: { string } = {}
		for _, requirement in entry.requires do
			if not available[requirement] then
				table.insert(missing, requirement)
			end
		end
		local base = {
			id = entry.id,
			source = entry.source,
			path = path,
			name = entry.name,
			durationMicros = 0,
			failures = {} :: { Failure },
			steps = {} :: { StepResult },
			artifacts = {} :: { Artifact },
			limitations = table.clone(entry.limitations),
			missingCapabilities = missing,
			skipReason = nil :: string?,
			origin = runOrigin,
		}
		if #missing > 0 then
			return {
				id = base.id,
				source = base.source,
				path = base.path,
				name = base.name,
				status = "unsupported",
				durationMicros = 0,
				failures = {},
				steps = {},
				artifacts = {},
				limitations = base.limitations,
				missingCapabilities = missing,
				skipReason = nil,
				origin = runOrigin,
			}
		end
		if entry.skipReason ~= nil then
			local result = table.clone(base) :: CaseResult
			result.status = "skipped"
			result.skipReason = entry.skipReason
			return result :: CaseResult
		end

		local failures = base.failures
		local steps = base.steps
		local artifacts = base.artifacts
		local cleanups: { () -> () } = {}
		local runtimeSkipReason: string? = nil
		local started = now()
		local context = {} :: Context
		local deadline = if entry.timeoutSeconds then started + entry.timeoutSeconds else math.huge
		local host: Operations.Host? = nil
		local evidence: Types.Evidence = { observations = {}, checkpoints = {}, reviews = {}, measurements = {} }
		local releasing = false
		local attachmentNames: { [string]: boolean } = {}
		local attachmentCount = 0
		local cleanupDeadline = math.huge
		local function withinDeadline()
			if releasing then
				if now() >= cleanupDeadline then
					error({ signal = TimedOut }, 0)
				end
				return
			end
			if runOptions.cancelled and runOptions.cancelled() then
				error({ signal = Cancelled }, 0)
			end
			if now() >= deadline then
				error({ signal = TimedOut }, 0)
			end
		end

		local function invoke(phase: Types.InvocationPhase, callback: () -> ()): InvocationResult
			if phase == "cleanup" or phase == "teardown" then
				cleanupDeadline = now() + (entry.cleanupTimeoutSeconds or 5)
			end
			local ok, result: unknown = pcall(invoker, phase, function()
				withinDeadline()
				callback()
				withinDeadline()
			end)
			if not ok then
				return { outcome = "failed", error = "executor invoker failed: " .. tostring(result) }
			end
			if type(result) ~= "table" then
				return { outcome = "failed", error = "executor invoker returned a non-table result" }
			end
			local invocation = result :: InvocationResult
			if
				invocation.outcome ~= "returned"
				and invocation.outcome ~= "failed"
				and invocation.outcome ~= "timed_out"
				and invocation.outcome ~= "cancelled"
			then
				return { outcome = "failed", error = "executor invoker returned an unknown outcome" }
			end
			local abort = type(invocation.error) == "table"
				and (invocation.error :: { [string]: unknown }).signal == StepAbort
			if not abort and now() >= (if releasing then cleanupDeadline else deadline) then
				return {
					outcome = "timed_out",
					error = "case deadline exceeded: " .. tostring(invocation.error or "late completion"),
				}
			end
			if invocation.outcome == "failed" and type(invocation.error) == "table" then
				local signal = (invocation.error :: { [string]: unknown }).signal
				if signal == TimedOut then
					local detail = (invocation.error :: { [string]: unknown }).detail
					return {
						outcome = "timed_out",
						error = if type(detail) == "string" then detail else "case deadline exceeded",
					}
				end
				if signal == Cancelled then
					return { outcome = "cancelled", error = "case cancelled" }
				end
			end
			return invocation
		end

		local function record(phase: Types.FailurePhase, invocation: InvocationResult): boolean
			if invocation.outcome == "returned" then
				return true
			end
			local thrown = invocation.error
			if type(thrown) == "table" then
				local signal = thrown :: { [unknown]: unknown }
				if signal.signal == RuntimeSkip then
					runtimeSkipReason = tostring(signal.reason)
					return false
				elseif signal.signal == Unsupported then
					table.insert(missing, tostring(signal.reason))
					return false
				elseif signal.signal == StepAbort then
					return false
				end
			end
			local outcome: Types.FailureOutcome = if invocation.outcome == "timed_out"
				then "timed_out"
				elseif invocation.outcome == "cancelled" then "cancelled"
				else "failed"
			table.insert(failures, {
				phase = phase,
				outcome = outcome,
				message = tostring(thrown or ("executor reported " .. invocation.outcome)),
			})
			return false
		end

		function context:expect(value: unknown): Expectation
			return Matchers.expect(value)
		end

		function context:defer(cleanup: () -> ())
			if type(cleanup) ~= "function" then
				error("defer requires a cleanup function", 2)
			end
			table.insert(cleanups, cleanup)
		end

		function context:own<T>(resource: Resource<T>)
			if type(resource) == "function" then
				table.insert(cleanups, resource :: () -> ())
				return
			end
			if type(resource) ~= "table" then
				error("own requires a function or a table carrying dispose or destroy", 2)
			end
			local handle = resource :: T & Disposable<T>
			local release = (handle.dispose or handle.destroy) :: ((T) -> ())?
			if type(release) ~= "function" then
				error("own requires a resource with a dispose or destroy method", 2)
			end
			local dispose = release :: (T) -> ()
			table.insert(cleanups, function()
				dispose(handle)
			end)
		end

		function context:unsupported(requirement: string): never
			checkedName("missing requirement", requirement)
			error({ signal = Unsupported, reason = requirement }, 0)
		end

		function context:skip(reason: string): never
			if reason == "" then
				error("runtime skip reason must not be empty", 2)
			end
			error({ signal = RuntimeSkip, reason = reason }, 0)
		end

		function context:step(name: string, definition: (() -> ()) | StepOptions)
			checkedName("step", name)
			local actor: string? = nil
			local stepRun: () -> ()
			if type(definition) == "function" then
				stepRun = definition
			else
				if type(definition.run) ~= "function" then
					error(("step %q requires a run function"):format(name), 2)
				end
				if definition.actor == "" then
					error("step actor must not be empty", 2)
				end
				actor = definition.actor
				stepRun = definition.run
			end
			local stepStarted = now()
			if runOptions.progress ~= nil then
				runOptions.progress.publish(entry.id, actor or "case", name, "started", nil)
			end
			local invocation = invoke("step", stepRun)
			local unsupported = type(invocation.error) == "table"
				and (invocation.error :: { [string]: unknown }).signal == Unsupported
			local stepStatus: "passed" | "failed" | "timed_out" | "cancelled" | "unsupported" = if unsupported
				then "unsupported"
				elseif invocation.outcome == "returned" then "passed"
				elseif invocation.outcome == "timed_out" then "timed_out"
				elseif invocation.outcome == "cancelled" then "cancelled"
				else "failed"
			if runOptions.progress ~= nil then
				runOptions.progress.publish(entry.id, actor or "case", name, "finished", stepStatus)
			end
			table.insert(steps, {
				name = name,
				actor = actor,
				status = stepStatus,
				durationMicros = micros(now() - stepStarted),
				message = if invocation.outcome == "returned" then nil else tostring(invocation.error),
			})
			if invocation.outcome ~= "returned" then
				if not record("step", invocation) then
					error({ signal = StepAbort }, 0)
				end
			end
		end

		function context:artifact(name: string, reference: string, mediaType: string?)
			checkedName("artifact", name)
			if reference == "" then
				error("artifact reference must not be empty", 2)
			end
			if mediaType == "" then
				error("artifact media type must not be empty", 2)
			end
			table.insert(artifacts, { name = name, reference = reference, mediaType = mediaType })
		end

		function context:attach(name: string, mediaType: string, text: string)
			local refusal = Attachment.check(name, mediaType, text, attachmentLimits)
			if refusal ~= nil then
				error(refusal, 2)
			end
			if attachmentCount >= attachmentLimits.maxCount then
				error(
					("attachment %q exceeds the per-case count limit of %d"):format(name, attachmentLimits.maxCount),
					2
				)
			end
			if runAttachmentBytes + #text > attachmentLimits.maxTotalBytes then
				error(
					("attachment %q exceeds the per-report limit of %d bytes"):format(
						name,
						attachmentLimits.maxTotalBytes
					),
					2
				)
			end
			if attachmentNames[name] then
				error(("attachment %q is already attached to this case"):format(name), 2)
			end
			attachmentNames[name] = true
			attachmentCount += 1
			runAttachmentBytes += #text
			table.insert(artifacts, {
				name = name,
				reference = "attachment:" .. name,
				mediaType = mediaType,
				content = text,
			})
		end

		function context:remainingSeconds(): number
			return math.max(0, (if releasing then cleanupDeadline else deadline) - now())
		end

		function context:perform<I, O>(
			actor: string,
			operation: Operations.Operation<I, O>,
			input: I,
			deadlineSeconds: number?
		): O
			if deadlineSeconds ~= nil and not (deadlineSeconds > 0 and deadlineSeconds < math.huge) then
				error("operation deadline must be positive and finite", 2)
			end
			local output: O? = nil
			self:step(operation.kind .. " " .. operation.name, {
				actor = actor,
				run = function()
					assert(actor ~= "", "operation needs an actor")
					local bound = host
					assert(bound ~= nil, "case has no operation host")
					assert(
						table.find(bound.capabilities, operation.kind .. ":" .. operation.name),
						"operation unavailable"
					)
					local payload = Operations.snapshot(operation.input(input))
					local caseLimit = if releasing then cleanupDeadline else deadline
					local callLimit = if deadlineSeconds ~= nil
						then math.min(caseLimit, now() + deadlineSeconds)
						else caseLimit
					local function stuck(cause: string?): never
						error({
							signal = TimedOut,
							detail = ("operation deadline exceeded: %s %s %s%s"):format(
								actor,
								operation.kind,
								operation.name,
								if cause ~= nil then " (" .. cause .. ")" else ""
							),
						}, 0)
					end
					local called, value = pcall(bound.invoke, {
						kind = operation.kind,
						actor = actor,
						name = operation.name,
						payload = payload,
						deadline = callLimit,
					})
					if not called then
						if deadlineSeconds ~= nil and callLimit < caseLimit and now() >= callLimit then
							stuck(tostring(value))
						end
						error(value, 0)
					end
					if deadlineSeconds ~= nil and callLimit < caseLimit and now() >= callLimit then
						stuck(nil)
					end
					withinDeadline()
					output = operation.output(Operations.snapshot(value))
					table.insert(evidence.observations, {
						step = #steps + 1,
						kind = operation.kind,
						actor = actor,
						name = operation.name,
						value = Operations.snapshot(output),
						input = payload,
					})
				end,
			})
			return output :: O
		end

		function context:await<I, O>(
			actor: string,
			operation: Operations.Operation<I, O>,
			input: I,
			predicate: (O) -> boolean,
			pollSeconds: number,
			deadlineSeconds: number?
		): O
			assert(operation.kind == "query", "await only retries queries")
			if deadlineSeconds ~= nil and not (deadlineSeconds > 0 and deadlineSeconds < math.huge) then
				error("await deadline must be positive and finite", 2)
			end
			local awaitLimit = if deadlineSeconds ~= nil then now() + deadlineSeconds else math.huge
			assert(pollSeconds > 0 and pollSeconds < math.huge, "poll interval must be positive and finite")
			assert(deadline < math.huge, "await requires a case timeout")
			local value: O? = nil
			self:step("await " .. operation.name, {
				actor = actor,
				run = function()
					while true do
						local remaining = if awaitLimit < math.huge then awaitLimit - now() else nil
						if remaining ~= nil and remaining <= 0 then
							error({
								signal = TimedOut,
								detail = ("await deadline exceeded: %s %s"):format(actor, operation.name),
							}, 0)
						end
						local observed = self:perform(actor, operation, input, remaining)
						if predicate(observed) then
							value = observed
							return
						end
						local bound = host
						assert(bound ~= nil and bound.sleep ~= nil, "await requires a host clock and sleep")
						bound.sleep(
							math.min(
								pollSeconds,
								self:remainingSeconds(),
								if remaining ~= nil then math.max(awaitLimit - now(), 0) else math.huge
							)
						)
						withinDeadline()
					end
				end,
			})
			return value :: O
		end

		function context:checkpoint(actor: string, name: string)
			self:step("checkpoint " .. name, {
				actor = actor,
				run = function()
					assert(actor ~= "" and name ~= "", "checkpoint needs actor and name")
					for _, prior in evidence.checkpoints do
						assert(prior.actor ~= actor or prior.name ~= name, "duplicate checkpoint")
					end
					local bound = host
					assert(
						bound ~= nil and bound.capture ~= nil and table.find(bound.capabilities, "capture"),
						"capture unavailable"
					)
					local captures = bound.capture(actor, name)
					withinDeadline()
					assert(#captures > 0, "capture returned no evidence")
					local copies: { Types.Artifact } = {}
					for _, artifact in captures do
						self:artifact(artifact.name, artifact.reference, artifact.mediaType)
						table.insert(copies, table.freeze(table.clone(artifact)))
					end
					table.insert(
						evidence.checkpoints,
						{ step = #steps + 1, actor = actor, name = name, artifacts = table.freeze(copies) }
					)
				end,
			})
		end

		function context:judge(actor: string, checkpoint: string, criterion: string)
			self:step("judge " .. criterion, {
				actor = actor,
				run = function()
					assert(criterion ~= "", "judgment needs a criterion")
					local captured: Types.Checkpoint? = nil
					for _, candidate in evidence.checkpoints do
						if candidate.actor == actor and candidate.name == checkpoint then
							captured = candidate
						end
					end
					assert(captured ~= nil, "judgment requires captured evidence")
					local bound = host
					assert(
						bound ~= nil and bound.judge ~= nil and table.find(bound.capabilities, "judgment"),
						"judgment unavailable"
					)
					local result = bound.judge {
						actor = actor,
						checkpoint = checkpoint,
						criterion = criterion,
						artifacts = captured.artifacts,
					}
					withinDeadline()
					assert(result.reviewer ~= "" and result.detail ~= "", "judgment needs reviewer and reasoning")
					assert(
						result.status == "passed" or result.status == "failed" or result.status == "unreviewed",
						"invalid judgment status"
					)
					table.insert(evidence.reviews, {
						step = #steps + 1,
						actor = actor,
						checkpoint = checkpoint,
						criterion = criterion,
						judgment = table.freeze(table.clone(result)),
					})
					if result.status == "unreviewed" then
						self:unsupported("judgment:" .. criterion)
					end
					self:expect(result.status):toBe "passed"
				end,
			})
		end

		function context:measure(actor: string, name: string, input: Performance.Input, limits: Performance.Limits)
			self:step("measure " .. name, {
				actor = actor,
				run = function()
					assert(actor ~= "" and name ~= "", "measurement needs actor and name")
					local capturedInput = Operations.snapshot(input) :: Performance.Input
					local capturedLimits = Operations.snapshot(limits) :: Performance.Limits
					local evaluation = Performance.evaluate(Performance.summarize(capturedInput), capturedLimits)
					table.insert(evidence.measurements, {
						step = #steps + 1,
						actor = actor,
						name = name,
						input = capturedInput,
						limits = capturedLimits,
						evaluation = evaluation,
					})
					if evaluation.status == "unsupported" then
						self:unsupported("measurement:" .. evaluation.reason)
					end
					self:expect(evaluation.status):toBe "passed"
				end,
			})
		end

		local setupPassed = true
		if runOptions.bind ~= nil then
			setupPassed = record(
				"setup",
				invoke("setup", function()
					local bound = (runOptions.bind :: (Context) -> Operations.Host)(context)
					host = bound
					if bound.close then
						context:defer(bound.close)
					end
				end)
			)
		end
		for _, suiteInChain in chain do
			for _, hook in suiteInChain.beforeEach do
				if setupPassed and runtimeSkipReason == nil then
					setupPassed = record(
						"setup",
						invoke("setup", function()
							hook(context)
						end)
					)
				end
			end
		end
		if setupPassed and runtimeSkipReason == nil then
			record(
				"case",
				invoke("case", function()
					entry.run(context)
				end)
			)
		end
		releasing = true
		for index = #chain, 1, -1 do
			for _, hook in chain[index].afterEach do
				record(
					"teardown",
					invoke("teardown", function()
						hook(context)
					end)
				)
			end
		end
		for index = #cleanups, 1, -1 do
			record("cleanup", invoke("cleanup", cleanups[index]))
		end

		return {
			id = base.id,
			source = base.source,
			path = base.path,
			name = base.name,
			status = statusFor(failures, runtimeSkipReason, missing),
			evidence = evidence,
			durationMicros = micros(now() - started),
			failures = failures,
			steps = steps,
			artifacts = artifacts,
			limitations = base.limitations,
			missingCapabilities = missing,
			skipReason = runtimeSkipReason,
			origin = runOrigin,
		}
	end

	function harness:run(runOptions: RunOptions): Report
		if running then
			error("a harness cannot run recursively", 2)
		end
		if runOptions.executor == "" then
			error("run executor must not be empty", 2)
		end
		running = true
		runAttachmentBytes = 0
		attachmentLimits = Attachment.resolve(runOptions.attachments or configuredLimits)
		local started = now()
		local capabilityList = copySortedUnique(runOptions.capabilities, "capability")
		local environment = copyEnvironment(runOptions.environment)
		local runOrigin = origin(runOptions.executor, environment, capabilityList)
		local available: { [string]: boolean } = {}
		for _, capability in capabilityList do
			available[capability] = true
		end
		local results: { CaseResult } = {}
		local invoker = runOptions.invoke or defaultInvoke
		local function walk(suite: Suite)
			local path = suitePath(ancestors(suite))
			for _, entry in suite.cases do
				if selected(entry, path, runOptions.selection) then
					local result = executeCase(suite, entry, available, runOrigin, invoker, runOptions)
					if result.status == nil then
						result.status = "unsupported"
					end
					table.insert(results, result)
				elseif runOptions.selection ~= nil and runOptions.selection.account == true then
					local skipped = table.clone(entry)
					skipped.requires = {}
					skipped.skipReason = DESELECTED_PREFIX .. "the run's selection did not include this case"
					table.insert(results, executeCase(suite, skipped, available, runOrigin, invoker, runOptions))
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
		assert(known[id :: string] == nil, "duplicate case id: " .. (id :: string))
		known[id :: string] = spec
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
		if ids == nil or selected[spec.id :: string] then
			harness:case(spec.name, spec)
		end
	end
	local settings = table.clone(options)
	settings.environment = table.clone(options.environment or {})
	local environment = settings.environment :: { [string]: string }
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
	format = format,
}
