--!strict

local Model = require "./harness-types"
local Attachment = require "./attachment"
local Matchers = require "./matchers"
local Types = require "./types"
local Operations = require "./operations"
local Performance = require "./performance"

type Status = Model.Status
type Failure = Model.Failure
type Origin = Model.Origin
type CaseResult = Model.CaseResult
type Expectation = Model.Expectation
type InvocationResult = Model.InvocationResult
type Invoker = Model.Invoker
type StepOptions = Model.StepOptions
type Disposable<T = unknown> = Model.Disposable<T>
type Resource<T = unknown> = Model.Resource<T>
type Context = Model.Context
type RunOptions = Model.RunOptions
type CaseEntry = Model.CaseEntry
type Suite = Model.Suite

local RuntimeSkip = {}
local StepAbort = {}
local TimedOut = {}
local Cancelled = {}
local Unsupported = {}

local checkedName = Model.checkedName
local ancestors = Model.ancestors
local suitePath = Model.suitePath
local micros = Model.micros
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

local function executeCase(
	suite: Suite,
	entry: CaseEntry,
	available: { [string]: boolean },
	runOrigin: Origin,
	invoker: Invoker,
	runOptions: RunOptions,
	settings: { now: () -> number, limits: Attachment.Resolved, bytes: number }
): CaseResult
	local now = settings.now
	local attachmentLimits = settings.limits
	local chain = ancestors(suite)
	local path = suitePath(chain)
	local missing: { string } = {}
	for _, requirement in entry.requires do
		if not available[requirement] then
			table.insert(missing, requirement)
		end
	end
	local base: CaseResult = {
		status = "passed",
		id = entry.id,
		source = entry.source,
		path = path,
		name = entry.name,
		durationMicros = 0,
		failures = {},
		steps = {},
		artifacts = {},
		limitations = table.clone(entry.limitations),
		missingCapabilities = missing,
		skipReason = nil,
		origin = runOrigin,
	}
	if #missing > 0 then
		base.status = "unsupported"
		return base
	end
	if entry.skipReason ~= nil then
		local result = table.clone(base)
		result.status = "skipped"
		result.skipReason = entry.skipReason
		return result
	end

	local failures = base.failures
	local steps = base.steps
	local artifacts = base.artifacts
	local cleanups: { () -> () } = {}
	local runtimeSkipReason: string? = nil
	local started = now()
	local context: Context
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
		local ok, result = pcall(invoker, phase, function()
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
		local invocation = result
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

	local function context_expect(self: Context, value: unknown): Expectation
		return Matchers.expect(value)
	end

	local function context_defer(self: Context, cleanup: () -> ())
		if type(cleanup) ~= "function" then
			error("defer requires a cleanup function", 2)
		end
		table.insert(cleanups, cleanup)
	end

	local function context_own<T>(self: Context, resource: Resource<T>)
		if type(resource) == "function" then
			table.insert(cleanups, resource)
			return
		end
		if type(resource) ~= "table" then
			error("own requires a function or a table carrying dispose or destroy", 2)
		end
		local handle = resource :: T & Disposable<T>
		local release = (handle.dispose or handle.destroy)
		if type(release) ~= "function" then
			error("own requires a resource with a dispose or destroy method", 2)
		end
		local dispose = release :: (T) -> ()
		table.insert(cleanups, function()
			dispose(handle)
		end)
	end

	local function context_unsupported(self: Context, requirement: string): never
		checkedName("missing requirement", requirement)
		error({ signal = Unsupported, reason = requirement }, 0)
	end

	local function context_skip(self: Context, reason: string): never
		if reason == "" then
			error("runtime skip reason must not be empty", 2)
		end
		error({ signal = RuntimeSkip, reason = reason }, 0)
	end

	local function context_step(self: Context, name: string, definition: (() -> ()) | StepOptions)
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

	local function context_artifact(self: Context, name: string, reference: string, mediaType: string?)
		checkedName("artifact", name)
		if reference == "" then
			error("artifact reference must not be empty", 2)
		end
		if mediaType == "" then
			error("artifact media type must not be empty", 2)
		end
		table.insert(artifacts, { name = name, reference = reference, mediaType = mediaType })
	end

	local function context_attach(self: Context, name: string, mediaType: string, text: string)
		local refusal = Attachment.check(
			name,
			mediaType,
			text,
			attachmentLimits,
			{ count = attachmentCount, total = settings.bytes, names = attachmentNames }
		)
		if refusal ~= nil then
			error(refusal, 2)
		end
		attachmentNames[name] = true
		attachmentCount += 1
		settings.bytes += #text
		table.insert(artifacts, {
			name = name,
			reference = "attachment:" .. name,
			mediaType = mediaType,
			content = text,
		})
	end

	local function context_remainingSeconds(self: Context): number
		return math.max(0, (if releasing then cleanupDeadline else deadline) - now())
	end

	local function context_perform<I, O>(
		self: Context,
		actor: string,
		operation: Operations.Operation<I, O>,
		input: I,
		deadlineSeconds: number?
	): O
		if deadlineSeconds ~= nil and not (deadlineSeconds > 0 and deadlineSeconds < math.huge) then
			error("operation deadline must be positive and finite", 2)
		end
		local output: { O } = {}
		self:step(operation.kind .. " " .. operation.name, {
			actor = actor,
			run = function()
				assert(actor ~= "", "operation needs an actor")
				local bound = host
				assert(bound ~= nil, "case has no operation host")
				assert(table.find(bound.capabilities, operation.kind .. ":" .. operation.name), "operation unavailable")
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
				output[1] = operation.output(Operations.snapshot(value))
				table.insert(evidence.observations, {
					step = #steps + 1,
					kind = operation.kind,
					actor = actor,
					name = operation.name,
					value = Operations.snapshot(output[1]),
					input = payload,
				})
			end,
		})
		return output[1]
	end

	local function context_await<I, O>(
		self: Context,
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
		local values: { O } = {}
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
						values[1] = observed
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
		return values[1]
	end

	local function context_checkpoint(self: Context, actor: string, name: string)
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

	local function context_judge(self: Context, actor: string, checkpoint: string, criterion: string)
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

	local function context_measure(
		self: Context,
		actor: string,
		name: string,
		input: Performance.Input,
		limits: Performance.Limits
	)
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

	context = {
		id = entry.id,
		expect = context_expect,
		defer = context_defer,
		own = context_own,
		unsupported = context_unsupported,
		skip = context_skip,
		step = context_step,
		artifact = context_artifact,
		attach = context_attach,
		remainingSeconds = context_remainingSeconds,
		perform = context_perform,
		await = context_await,
		checkpoint = context_checkpoint,
		judge = context_judge,
		measure = context_measure,
	}
	local setupPassed = true
	if runOptions.bind ~= nil then
		setupPassed = record(
			"setup",
			invoke("setup", function()
				local bound = (runOptions.bind)(context)
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

	base.status = statusFor(failures, runtimeSkipReason, missing)
	base.evidence = evidence
	base.durationMicros = micros(now() - started)
	base.skipReason = runtimeSkipReason
	return base
end

return executeCase
