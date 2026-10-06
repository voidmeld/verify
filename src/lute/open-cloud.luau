--!strict

local json = require "@std/json"
local task = require "@std/task"
local Core = require "../core"
local Channel = require "../roblox/report-channel"
local Attach = require "./studio-attach"
local Wire = require "./wire"

export type Purpose = "submit" | "poll" | "logs"

export type Call = {
	purpose: Purpose,
	method: "GET" | "POST",
	url: string,
	body: string?,
	digest: string,
	universeId: string,
	placeId: string,
	versionId: string,
	taskPath: string?,
}

export type Authorization = Attach.Authorization

export type Exchange = {
	status: "answered" | "unsent" | "unanswered",
	httpStatus: number?,
	body: string?,
	detail: string?,
}

export type Transport = (call: Call, deadline: number) -> Exchange

export type Options = {
	universeId: string,
	placeId: string,
	versionId: string,
	request: Transport,
	authorize: (Call) -> Authorization,
	requestSeconds: number?,
	pollSeconds: number?,
	pollIntervalSeconds: number?,
	logPages: number?,
	logBytes: number?,
	now: (() -> number)?,
	sleep: ((seconds: number) -> ())?,
}

export type Binding = "run" | "caller"

export type Handle = {
	path: string,
	runId: string,
	universeId: string,
	placeId: string,
	versionId: string,
	binding: Binding?,
}

export type Delivery = "unsent" | "possibly_sent" | "answered"

export type Timing = { submitSeconds: number?, pollSeconds: number, totalSeconds: number, polls: number }

export type Outcome = {
	status: "returned" | "faulted" | "timed_out" | "refused",
	passed: boolean,
	delivery: Delivery,
	runId: string,
	binding: Binding,
	state: string?,
	handle: Handle?,
	report: Core.Report?,
	results: { unknown }?,
	task: { [string]: unknown }?,
	detail: string?,
	logs: string,
	diagnostics: { string },
	timing: Timing,
}

export type RunInput = { code: string, runId: string, requires: { string }?, binding: Binding? }

export type Submission = {
	status: "submitted" | "faulted" | "timed_out" | "refused",
	delivery: Delivery,
	runId: string,
	binding: Binding,
	state: string?,
	handle: Handle?,
	task: { [string]: unknown }?,
	detail: string?,
}

export type LogsOutcome = { ok: boolean, text: string, delivery: Delivery, diagnostics: { string } }

export type Session = {
	run: (input: RunInput) -> Outcome,
	submit: (input: RunInput) -> Submission,
	poll: (handle: Handle) -> Outcome,
	logs: (handle: Handle) -> LogsOutcome,
	reconcile: (handle: Handle) -> Outcome,
}

export type HostOptions = {
	connection: Options,
	codeForBatch: (Core.PlanBatch) -> string,
	runId: ((Core.PlanBatch) -> string)?,
	capabilities: { string }?,
	onOutcome: ((batch: Core.PlanBatch, outcome: Outcome) -> ())?,
}

local API_BASE = "https://apis.roblox.com"
local TERMINAL: { [string]: boolean } = { COMPLETE = true, FAILED = true, CANCELLED = true }
local UNSUPPORTED_NAMES: { string } = {
	"native-physics",
	"native-multiplayer",
	"native-input",
	"native-replication",
	"native-rendering",
	"native-audio",
	"place-scripts",
	"joined-clients",
	"capture",
	"judgment",
}
local UNSUPPORTED_PREFIXES: { string } = { "action:input." }
local DEFAULT_CAPABILITIES: { string } = { "open-cloud-server" }
local MAX_DIAGNOSTICS = 50

local function unsupported(capability: string): boolean
	if table.find(UNSUPPORTED_NAMES, capability) ~= nil then
		return true
	end
	for _, prefix in UNSUPPORTED_PREFIXES do
		if string.sub(capability, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

local function refusedCapabilities(required: { string }?): { string }
	local found: { string } = {}
	local requested: { string } = if required ~= nil then required else {}
	for _, capability in requested do
		if unsupported(capability) and table.find(found, capability) == nil then
			table.insert(found, capability)
		end
	end
	table.sort(found)
	return found
end

local function taskUrl(path: string): string
	return API_BASE .. "/cloud/v2/" .. path
end

local function submitUrl(universeId: string, placeId: string, versionId: string): string
	return ("%s/cloud/v2/universes/%s/places/%s/versions/%s/luau-execution-session-tasks"):format(
		API_BASE,
		universeId,
		placeId,
		versionId
	)
end

local function canonicalTaskPath(value: unknown, universeId: string, placeId: string, versionId: string): boolean
	if type(value) ~= "string" or #value > 256 then
		return false
	end
	local prefix = ("universes/%s/places/%s/versions/%s/luau-execution-sessions/"):format(
		universeId,
		placeId,
		versionId
	)
	if string.sub(value, 1, #prefix) ~= prefix then
		return false
	end
	local sessionId, taskId = string.match(string.sub(value, #prefix + 1), "^([^/]+)/tasks/([^/]+)$")
	if sessionId == nil or taskId ~= sessionId then
		return false
	end
	local a, b, c, d, e = string.match(sessionId, "^(%x+)%-(%x+)%-(%x+)%-(%x+)%-(%x+)$")
	if a == nil or b == nil or c == nil or d == nil or e == nil then
		return false
	end
	return #a == 8 and #b == 4 and #c == 4 and #d == 4 and #e == 12
end

local function note(list: { string }, message: string)
	if #list < MAX_DIAGNOSTICS then
		table.insert(list, message)
	end
end

local function finiteSeconds(value: number?, fallback: number): number
	local seconds = if value == nil then fallback else value
	if not (seconds > 0 and seconds < math.huge) then
		error("Open Cloud durations must be finite and positive", 3)
	end
	return seconds
end

local function digits(value: unknown): boolean
	return type(value) == "string" and string.match(value, "^[1-9][0-9]*$") ~= nil
end

type Config = {
	options: Options,
	requestSeconds: number,
	pollSeconds: number,
	intervalSeconds: number,
	logPages: number,
	logBytes: number,
	now: () -> number,
	sleep: (number) -> (),
}

type Sent = { exchange: Exchange, refused: boolean, expired: boolean }

local function send(config: Config, call: Call, seconds: number): Sent
	local asked, verdict: unknown = pcall(config.options.authorize, call)
	if not asked then
		return {
			exchange = { status = "unsent", detail = "authorize raised: " .. tostring(verdict) },
			refused = true,
			expired = false,
		}
	end
	local decision = verdict :: Authorization
	if type(decision) ~= "table" or decision.ok ~= true then
		return {
			exchange = {
				status = "unsent",
				detail = if type(decision) == "table" and decision.reason ~= nil
					then decision.reason
					else "request refused",
			},
			refused = true,
			expired = false,
		}
	end
	local limit = config.now() + seconds
	local slot: { done: boolean, exchange: Exchange? } = { done = false, exchange = nil }
	task.spawn(function()
		local sent, value: unknown = pcall(config.options.request, call, limit)
		slot.exchange = if sent
			then value :: Exchange
			else { status = "unanswered", detail = "transport raised: " .. tostring(value) }
		slot.done = true
	end)
	while not slot.done and config.now() < limit do
		config.sleep(0.005)
	end
	local exchange = slot.exchange
	if not slot.done or exchange == nil then
		return {
			exchange = { status = "unanswered", detail = call.purpose .. " exceeded its request deadline" },
			refused = false,
			expired = true,
		}
	end
	if type(exchange) ~= "table" then
		return {
			exchange = { status = "unanswered", detail = "transport returned a malformed exchange" },
			refused = false,
			expired = false,
		}
	end
	return { exchange = exchange, refused = false, expired = config.now() >= limit }
end

local function callFor(
	options: Options,
	purpose: Purpose,
	method: "GET" | "POST",
	url: string,
	body: string?,
	taskPath: string?
): Call
	return {
		purpose = purpose,
		method = method,
		url = url,
		body = body,
		digest = Attach.digest(method .. " " .. url .. "\n" .. (body or "")),
		universeId = options.universeId,
		placeId = options.placeId,
		versionId = options.versionId,
		taskPath = taskPath,
	}
end

local function success(exchange: Exchange): boolean
	return exchange.status == "answered"
		and type(exchange.httpStatus) == "number"
		and exchange.httpStatus >= 200
		and exchange.httpStatus < 300
end

local function httpDetail(label: string, exchange: Exchange): string
	return ("%s: HTTP %s %s"):format(label, tostring(exchange.httpStatus), string.sub(exchange.body or "", 1, 300))
end

local function decoded(exchange: Exchange): { [string]: unknown }?
	local parsed, value: unknown = pcall(Wire.parse, exchange.body or "")
	if parsed and type(value) == "table" then
		return value :: { [string]: unknown }
	end
	return nil
end

local function outcomeOf(runId: string, fields: { [string]: unknown }): Outcome
	return {
		status = fields.status :: "returned" | "faulted" | "timed_out" | "refused",
		passed = fields.passed == true,
		delivery = (fields.delivery or "unsent") :: Delivery,
		runId = runId,
		binding = (fields.binding or "run") :: Binding,
		state = fields.state :: string?,
		handle = fields.handle :: Handle?,
		report = fields.report :: Core.Report?,
		results = fields.results :: { unknown }?,
		task = fields.task :: { [string]: unknown }?,
		detail = fields.detail :: string?,
		logs = (fields.logs or "") :: string,
		diagnostics = (fields.diagnostics or {}) :: { string },
		timing = (fields.timing or { pollSeconds = 0, totalSeconds = 0, polls = 0 }) :: Timing,
	}
end

local function encodeQuery(value: string): string
	local encoded = string.gsub(value, "[^%w%-%._~]", function(character: string): string
		return ("%%%02X"):format(string.byte(character))
	end)
	return encoded
end

local function collectLogs(config: Config, handle: Handle, diagnostics: { string }): string
	local lines: { string } = {}
	local token: string? = nil
	local spent: { [string]: boolean } = {}
	for _ = 1, config.logPages do
		local base = taskUrl(handle.path) .. "/logs"
		local url = if token == nil then base else base .. "?pageToken=" .. encodeQuery(token)
		local sent = send(config, callFor(config.options, "logs", "GET", url, nil, handle.path), config.requestSeconds)
		if not success(sent.exchange) then
			note(diagnostics, "logs unavailable: " .. (sent.exchange.detail or httpDetail("logs", sent.exchange)))
			break
		end
		local page = decoded(sent.exchange)
		if page == nil then
			note(diagnostics, "logs response was not a JSON object")
			break
		end
		local chunks = page.luauExecutionSessionTaskLogs
		if type(chunks) == "table" then
			for _, chunk in chunks :: { unknown } do
				local messages = if type(chunk) == "table" then (chunk :: { [string]: unknown }).messages else nil
				if type(messages) == "table" then
					for _, message in messages :: { unknown } do
						if type(message) == "string" then
							table.insert(lines, message)
						end
					end
				end
			end
		end
		local following = page.nextPageToken
		if type(following) ~= "string" or following == "" or spent[following] then
			break
		end
		spent[following] = true
		token = following
	end
	local text = table.concat(lines, "\n")
	if #text > config.logBytes then
		note(diagnostics, ("logs truncated to the last %d bytes"):format(config.logBytes))
		text = string.sub(text, -config.logBytes)
	end
	return text
end

local function boundReport(results: unknown, runId: string): (Core.Report?, string?)
	local matched: { Core.Report } = {}
	local foreign = 0
	local problem: string? = nil
	local function visit(value: unknown)
		if type(value) == "string" then
			local parsed, inner: unknown = pcall(Wire.parse, value)
			if parsed then
				visit(inner)
			end
		elseif type(value) == "table" then
			local object = value :: { [unknown]: unknown }
			if object.runId ~= nil then
				if object.runId == runId then
					local received, report: unknown = pcall(Channel.receive, value, runId)
					if received then
						table.insert(matched, report :: Core.Report)
					else
						problem = "the run-bound envelope is not a valid report: " .. tostring(report)
					end
				else
					foreign += 1
				end
				return
			end
			for _, child in object do
				visit(child)
			end
		end
	end
	visit(results)
	if #matched == 1 then
		return matched[1], nil
	elseif #matched > 1 then
		return nil, "the task returned several reports bound to this run id"
	elseif problem ~= nil then
		return nil, problem
	elseif foreign > 0 then
		return nil, "the task returned a report bound to a different run id; it is not this run's evidence"
	end
	return nil, "the task returned no run-bound report envelope"
end

local function allPassed(report: Core.Report): boolean
	return report.total > 0 and report.passed == report.total
end

local function finish(
	config: Config,
	handle: Handle,
	delivery: Delivery,
	terminal: { [string]: unknown },
	diagnostics: { string },
	collect: boolean
): Outcome
	local binding: Binding = handle.binding or "run"
	local state = terminal.state :: string
	local logs = if collect then collectLogs(config, handle, diagnostics) else ""
	local output = terminal.output
	local results = if type(output) == "table" then (output :: { [string]: unknown }).results else nil
	local function done(status: string, detail: string?, report: Core.Report?): Outcome
		return outcomeOf(handle.runId, {
			status = status,
			passed = binding == "run" and status == "returned" and report ~= nil and allPassed(report),
			delivery = delivery,
			binding = binding,
			state = state,
			handle = handle,
			report = report,
			results = if type(results) == "table" then results else nil,
			task = terminal,
			detail = detail,
			logs = logs,
			diagnostics = diagnostics,
		})
	end
	if state ~= "COMPLETE" then
		local failure = terminal.error
		local text = if type(failure) == "table"
			then ("%s: %s"):format(
				tostring((failure :: { [string]: unknown }).code or "ERROR"),
				tostring((failure :: { [string]: unknown }).message or "")
			)
			else "task ended " .. state
		return done("faulted", "task " .. state .. ": " .. text, nil)
	end
	if binding == "caller" then
		return done("returned", nil, nil)
	end
	local report, problem = boundReport(results, handle.runId)
	if report == nil then
		return done("faulted", problem, nil)
	end
	return done("returned", nil, report)
end

local function watch(config: Config, handle: Handle, delivery: Delivery, collect: boolean): Outcome
	local diagnostics: { string } = {}
	local started = config.now()
	local limit = started + config.pollSeconds
	local state: string? = nil
	local attempts = 0
	local function timing(): Timing
		local elapsed = config.now() - started
		return { submitSeconds = nil, pollSeconds = elapsed, totalSeconds = elapsed, polls = attempts }
	end
	local function stopped(status: string, detail: string): Outcome
		return outcomeOf(handle.runId, {
			status = status,
			delivery = delivery,
			binding = handle.binding,
			state = state,
			handle = handle,
			detail = detail,
			diagnostics = diagnostics,
			timing = timing(),
		})
	end
	while true do
		local remaining = limit - config.now()
		if remaining <= 0 then
			return stopped(
				"timed_out",
				("local poll deadline reached after %d polls; the task was not cancelled and may still be running or complete; reconcile %s instead of resubmitting"):format(
					attempts,
					handle.path
				)
			)
		end
		attempts += 1
		local sent = send(
			config,
			callFor(config.options, "poll", "GET", taskUrl(handle.path), nil, handle.path),
			math.min(config.requestSeconds, remaining)
		)
		local exchange = sent.exchange
		if sent.refused then
			return stopped("faulted", "poll refused by authorize: " .. (exchange.detail or "refused"))
		elseif success(exchange) then
			local current = decoded(exchange)
			if current == nil or type(current.state) ~= "string" then
				return stopped("faulted", "task poll response is not a task with a state")
			end
			if current.path ~= handle.path then
				return stopped("faulted", "task poll answered for a different task path")
			end
			state = current.state :: string
			if TERMINAL[state :: string] then
				local finished = finish(config, handle, delivery, current, diagnostics, collect)
				finished.timing = timing()
				return finished
			end
		elseif exchange.status == "answered" then
			local code = exchange.httpStatus
			note(diagnostics, httpDetail("poll " .. attempts, exchange))
			if code ~= 429 and code ~= nil and code < 500 and code ~= 408 then
				return stopped("faulted", httpDetail("poll", exchange))
			end
		else
			note(diagnostics, ("poll %d: %s"):format(attempts, exchange.detail or exchange.status))
		end
		config.sleep(math.max(0.001, math.min(config.intervalSeconds, limit - config.now())))
	end
end

local function configure(options: Options): Config
	if type(options) ~= "table" or type(options.request) ~= "function" or type(options.authorize) ~= "function" then
		error("Open Cloud requires caller-supplied request and authorize functions", 3)
	end
	if not (digits(options.universeId) and digits(options.placeId) and digits(options.versionId)) then
		error("Open Cloud requires exact positive-integer universeId, placeId and versionId strings", 3)
	end
	return {
		options = options,
		requestSeconds = finiteSeconds(options.requestSeconds, 30),
		pollSeconds = finiteSeconds(options.pollSeconds, 330),
		intervalSeconds = finiteSeconds(options.pollIntervalSeconds, 2),
		logPages = math.floor(finiteSeconds(options.logPages, 20)),
		logBytes = math.floor(finiteSeconds(options.logBytes, 65536)),
		now = options.now or os.clock,
		sleep = options.sleep or task.wait,
	}
end

local function connect(options: Options): Session
	local config = configure(options)

	local function refuse(runId: string, status: "refused" | "faulted", detail: string, binding: Binding?): Outcome
		return outcomeOf(runId, { status = status, delivery = "unsent", detail = detail, binding = binding })
	end

	local function submit(input: RunInput): Submission
		local binding: Binding = if type(input) == "table" and input.binding == "caller" then "caller" else "run"
		local runId = if type(input) == "table" and type(input.runId) == "string" then input.runId else ""
		local function stopped(status: string, delivery: Delivery, detail: string): Submission
			return {
				status = status :: "faulted" | "timed_out" | "refused",
				delivery = delivery,
				runId = runId,
				binding = binding,
				detail = detail,
			}
		end
		if runId == "" or type(input.code) ~= "string" or input.code == "" then
			return stopped("refused", "unsent", "a run needs a non-empty runId and code")
		end
		local banned = refusedCapabilities(input.requires)
		if #banned > 0 then
			return stopped(
				"refused",
				"unsent",
				"Open Cloud execution cannot provide: " .. table.concat(banned, ", ") .. "; the cases were not run"
			)
		end
		local script = if binding == "caller" then input.code else ("local runId = %q; %s"):format(runId, input.code)
		local body = json.serialize(({ script = script } :: unknown) :: json.Value)
		local url = submitUrl(options.universeId, options.placeId, options.versionId)
		local sent = send(config, callFor(options, "submit", "POST", url, body, nil), config.requestSeconds)
		local exchange = sent.exchange
		if sent.refused then
			return stopped("refused", "unsent", exchange.detail or "request refused")
		end
		if exchange.status == "unsent" then
			return stopped("faulted", "unsent", exchange.detail or "request was not sent")
		elseif exchange.status ~= "answered" then
			return stopped(
				if sent.expired then "timed_out" else "faulted",
				"possibly_sent",
				(exchange.detail or "no answer") .. "; a task may have been created and the submit is not retried"
			)
		end
		local code = exchange.httpStatus
		if not success(exchange) then
			local ambiguous = code == nil or code == 408 or code >= 500
			return stopped(
				"faulted",
				if ambiguous then "possibly_sent" else "unsent",
				httpDetail("submit", exchange) .. (if ambiguous then "; a task may have been created" else "")
			)
		end
		local created = decoded(exchange)
		if created == nil or type(created.path) ~= "string" or type(created.state) ~= "string" then
			return stopped(
				"faulted",
				"possibly_sent",
				"submit answered without a task path and state; a task may exist"
			)
		end
		if not canonicalTaskPath(created.path, options.universeId, options.placeId, options.versionId) then
			return stopped(
				"faulted",
				"answered",
				("the task path %q is outside the requested universe, place and version"):format(
					string.sub(created.path :: string, 1, 256)
				)
			)
		end
		return {
			status = "submitted",
			delivery = "answered",
			runId = runId,
			binding = binding,
			state = created.state :: string,
			task = created,
			handle = {
				path = created.path :: string,
				runId = runId,
				universeId = options.universeId,
				placeId = options.placeId,
				versionId = options.versionId,
				binding = binding,
			},
		}
	end

	local function owned(handle: Handle): string?
		if
			type(handle) ~= "table"
			or type(handle.runId) ~= "string"
			or handle.runId == ""
			or handle.universeId ~= options.universeId
			or handle.placeId ~= options.placeId
			or handle.versionId ~= options.versionId
			or not canonicalTaskPath(handle.path, options.universeId, options.placeId, options.versionId)
		then
			return "handle does not belong to this universe, place, version and run"
		end
		return nil
	end

	local function runIdOf(handle: Handle): string
		return if type(handle) == "table" and type(handle.runId) == "string" then handle.runId else ""
	end

	local function run(input: RunInput): Outcome
		local began = config.now()
		local submission = submit(input)
		if submission.handle == nil then
			return outcomeOf(submission.runId, {
				status = submission.status,
				delivery = submission.delivery,
				binding = submission.binding,
				detail = submission.detail,
			})
		end
		local submitted = config.now()
		local watched = watch(config, submission.handle, "answered", true)
		watched.timing.submitSeconds = submitted - began
		watched.timing.totalSeconds = config.now() - began
		return watched
	end

	local function poll(handle: Handle): Outcome
		local problem = owned(handle)
		if problem ~= nil then
			return refuse(runIdOf(handle), "refused", problem, nil)
		end
		return watch(config, handle, "answered", false)
	end

	local function reconcile(handle: Handle): Outcome
		local problem = owned(handle)
		if problem ~= nil then
			return refuse(runIdOf(handle), "refused", problem, nil)
		end
		return watch(config, handle, "answered", true)
	end

	local function logs(handle: Handle): LogsOutcome
		local diagnostics: { string } = {}
		if owned(handle) ~= nil then
			return {
				ok = false,
				text = "",
				delivery = "unsent",
				diagnostics = { "handle is not owned by this session" },
			}
		end
		local text = collectLogs(config, handle, diagnostics)
		return { ok = #diagnostics == 0, text = text, delivery = "answered", diagnostics = diagnostics }
	end

	return { run = run, submit = submit, poll = poll, logs = logs, reconcile = reconcile }
end

local function describe(outcome: Outcome): string
	local parts: { string } = { outcome.detail or outcome.status, "delivery " .. outcome.delivery }
	if outcome.state ~= nil then
		table.insert(parts, "task state " .. outcome.state)
	end
	if outcome.handle ~= nil then
		table.insert(parts, "task " .. outcome.handle.path)
	end
	return "open-cloud: " .. table.concat(parts, "; ")
end

local function host(options: HostOptions): Core.Host
	local session = connect(options.connection)
	local declared: { string } = {}
	for _, capability in options.capabilities or DEFAULT_CAPABILITIES do
		if unsupported(capability) then
			error("Open Cloud host cannot declare capability " .. capability, 2)
		end
		table.insert(declared, capability)
	end
	local counter = 0
	local prior: { [string]: Outcome } = {}
	local now = options.connection.now or os.clock

	local function runBatch(batch: Core.PlanBatch): Core.BatchOutcome
		local required: { string } = {}
		for _, unit in batch.units do
			for _, requirement in unit.requires do
				table.insert(required, requirement)
			end
		end
		local previous = prior[batch.id]
		local outcome: Outcome
		if previous ~= nil and previous.handle ~= nil and previous.status == "timed_out" then
			outcome = session.reconcile(previous.handle :: Handle)
		elseif previous ~= nil and previous.delivery == "possibly_sent" then
			outcome = outcomeOf(previous.runId, {
				status = "faulted",
				delivery = "possibly_sent",
				detail = "an earlier submit for this batch has an unknown outcome and is not resubmitted",
			})
		else
			counter += 1
			local runId = if options.runId ~= nil
				then options.runId(batch)
				else ("%s:%d:%d"):format(batch.id, math.floor(now() * 1000), counter)
			outcome = session.run { code = options.codeForBatch(batch), runId = runId, requires = required }
		end
		prior[batch.id] = outcome
		if options.onOutcome ~= nil then
			pcall(options.onOutcome, batch, outcome)
		end
		if outcome.status == "returned" and outcome.report ~= nil then
			return { status = "returned", report = outcome.report }
		end
		return {
			status = if outcome.status == "timed_out" then "timed_out" else "faulted",
			detail = describe(outcome),
		}
	end

	return {
		name = "roblox-open-cloud",
		capabilities = declared,
		environment = {
			runtime = "roblox-open-cloud",
			universeId = options.connection.universeId,
			placeId = options.connection.placeId,
			versionId = options.connection.versionId,
		},
		now = now,
		runBatch = runBatch,
	}
end

return {
	connect = connect,
	host = host,
	canonicalTaskPath = canonicalTaskPath,
	describe = describe,
	refusedCapabilities = refusedCapabilities,
	CAPABILITIES = DEFAULT_CAPABILITIES,
	UNSUPPORTED = UNSUPPORTED_NAMES,
}
