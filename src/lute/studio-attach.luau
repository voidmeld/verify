--!strict

local json = require "@std/json"
local task = require "@std/task"
local Core = require "../core"
local Detached = require "./studio-detached"
local Files = require "./files"
local Mcp = require "./studio-mcp"
local Progress = require "./studio-progress"
local Reply = require "./studio-reply"
local Wire = require "./wire"

export type StudioInfo = { id: string, name: string }

export type Request = {
	tool: string,
	argumentsJson: string,
	fields: { [string]: unknown },
	studioId: string?,
	bytes: string,
	digest: string,
}

export type Authorization = { ok: boolean, reason: string? }

export type Transport = {
	call: (tool: string, argumentsJson: string, deadline: number) -> Mcp.Exchange,
	close: () -> (),
}

export type Options = {
	authorize: (Request) -> Authorization,
	studioId: string?,
	match: ((StudioInfo) -> boolean)?,
	transport: Transport?,
	mcpExecutable: string?,
	directory: string?,
	mode: ("edit" | "play")?,
	callSeconds: number?,
	runSeconds: number?,
	cleanupSeconds: number?,
}

export type RefusalKind =
	"invalid"
	| "refused"
	| "unsent"
	| "possibly_sent"
	| "failed"
	| "absent"
	| "ambiguous"
	| "session_lost"

export type Refusal = {
	kind: RefusalKind,
	detail: string,
	candidates: { StudioInfo }?,
}

export type Response = {
	ok: boolean,
	delivery: "unsent" | "possibly_sent" | "answered",
	refused: boolean,
	expired: boolean,
	sessionLost: boolean?,
	detail: string?,
	result: unknown?,
	text: string?,
	artifact: Reply.Image?,
}

export type ReportResponse = { response: Response, report: Core.Report?, problem: string? }

export type CaptureOptions = { argumentsJson: string?, directory: string?, stem: string? }

export type Cleanup = { acknowledged: boolean, restored: boolean, mode: "edit" | "play", detail: string? }

export type Session = {
	studio: StudioInfo,
	studios: { StudioInfo },
	call: (tool: string, argumentsJson: string) -> Response,
	execute: (datamodel: string, code: string) -> Response,
	play: (start: boolean) -> Response,
	capture: (options: CaptureOptions?) -> Response,
	console: () -> Response,
	report: (datamodel: string, code: string, runId: string, onPoll: (() -> ())?) -> ReportResponse,
	close: () -> Cleanup,
}

export type RunOptions = {
	attach: Options,
	code: string,
	context: ("Server" | "Client")?,
	players: number?,
	finalCapture: boolean?,
	deadlineSeconds: number?,
	directory: string?,
	progressFile: string?,
}

local LIST = "list_roblox_studios"
local EXECUTE = "execute_luau"
local PLAY = "start_stop_play"
local CAPTURE = "screen_capture"
local CONSOLE_READ = "get_console_output"
local DATAMODELS: { [string]: boolean } = { Edit = true, Server = true, Client = true }
local DEFAULT_EXECUTABLE = "/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP"

local digest = Detached.digest

local function unsent(detail: string, refused: boolean?, expired: boolean?): Response
	return {
		ok = false,
		delivery = "unsent",
		refused = refused == true,
		expired = expired == true,
		detail = detail,
	}
end

local function mcpTransport(executable: string, directory: string): Transport
	local connection: Mcp.Connection? = nil
	local generation = 0
	local wasLost = false
	local function open(limit: number): (Mcp.Connection?, string?)
		generation += 1
		local opened, value: unknown =
			pcall(Mcp.connect, executable, ("%s/mcp-%d"):format(directory, generation), limit)
		if not opened then
			return nil, tostring(value)
		end
		wasLost = false
		return value :: Mcp.Connection, nil
	end
	local function drop()
		local active = connection
		connection = nil
		if active ~= nil then
			active.close()
		end
	end
	return {
		call = function(tool, argumentsJson, deadline)
			if connection == nil then
				local fresh, problem = open(deadline)
				if fresh == nil then
					if wasLost then
						return { status = "unsent", detail = "session_lost: " .. (problem or Mcp.EXITED), lost = true }
					end
					return { status = "unsent", detail = problem }
				end
				connection = fresh
			end
			local first = (connection :: Mcp.Connection).callRaw(tool, argumentsJson, deadline)
			if first.lost ~= true then
				return first
			end
			drop()
			wasLost = true
			if first.status ~= "unsent" then
				return {
					status = first.status,
					detail = "session_lost: " .. (first.detail or Mcp.EXITED),
					lost = true,
				}
			end
			local fresh, problem = open(deadline)
			if fresh == nil then
				return { status = "unsent", detail = "session_lost: " .. (problem or Mcp.EXITED), lost = true }
			end
			connection = fresh
			local second = fresh.callRaw(tool, argumentsJson, deadline)
			if second.lost == true then
				drop()
				wasLost = true
				return {
					status = second.status,
					detail = "session_lost: " .. (second.detail or Mcp.EXITED),
					lost = true,
				}
			end
			return second
		end,
		close = drop,
	}
end

local function discovered(text: string): { StudioInfo }
	local seen: { [string]: string } = {}
	local function visit(value: unknown)
		if type(value) ~= "table" then
			return
		end
		local fields = value :: { [unknown]: unknown }
		if type(fields.id) == "string" and type(fields.name) == "string" then
			seen[fields.id] = fields.name
		end
		for _, child in fields do
			visit(child)
		end
	end
	visit(Wire.parse(text))
	local studios: { StudioInfo } = {}
	for id, name in seen do
		table.insert(studios, { id = id, name = name })
	end
	table.sort(studios, function(left, right)
		return left.id < right.id
	end)
	return studios
end

local function refusalOf(kind: RefusalKind, detail: string): Refusal
	return { kind = kind, detail = detail, candidates = nil }
end

local function attach(options: Options): (Session?, Refusal?)
	if type(options) ~= "table" or type(options.authorize) ~= "function" then
		return nil, refusalOf("invalid", "attach requires an authorize hook; return { ok = true } to accept a request")
	end
	if options.studioId == nil and options.match == nil then
		return nil,
			refusalOf("invalid", "attach requires a studioId or a match predicate; it never picks a Studio implicitly")
	end
	local callSeconds = options.callSeconds or 60
	local runSeconds = options.runSeconds or 300
	local cleanupSeconds = options.cleanupSeconds or 30
	for _, seconds in { callSeconds, runSeconds, cleanupSeconds } do
		if not (seconds > 0 and seconds < math.huge) then
			return nil, refusalOf("invalid", "attach deadlines must be finite and positive")
		end
	end
	local priorMode: "edit" | "play" = options.mode or "edit"
	local transport = options.transport
		or mcpTransport(
			options.mcpExecutable or DEFAULT_EXECUTABLE,
			options.directory or Files.claimDirectory "/tmp/verify-attach"
		)
	local runDeadline = os.clock() + runSeconds
	local studio: StudioInfo? = nil
	local playing: boolean? = if priorMode == "play" then true else false
	local closed: Cleanup? = nil

	local function dispatch(tool: string, argumentsJson: string, cleaning: boolean): Response
		local decoded, fields: unknown = pcall(Wire.parse, argumentsJson)
		if not decoded or type(fields) ~= "table" then
			return unsent "request arguments are not a JSON object"
		end
		local record = fields :: { [string]: unknown }
		local target = studio
		if tool ~= LIST and (target == nil or record.studio_id ~= target.id) then
			return unsent "request does not target the attached Studio"
		end
		local now = os.clock()
		if not cleaning and now >= runDeadline then
			return unsent("run deadline expired before " .. tool, false, true)
		end
		local limit = if cleaning then now + cleanupSeconds else math.min(now + callSeconds, runDeadline)
		local bytes = '{"name":' .. json.serialize(tool) .. ',"arguments":' .. argumentsJson .. "}"
		local request: Request = {
			tool = tool,
			argumentsJson = argumentsJson,
			fields = record,
			studioId = if target ~= nil then target.id else nil,
			bytes = bytes,
			digest = digest(bytes),
		}
		local asked, verdict: unknown = pcall(options.authorize, request)
		if not asked then
			return unsent("authorize raised: " .. tostring(verdict), true)
		end
		local decision = verdict :: Authorization
		if type(decision) ~= "table" or decision.ok ~= true then
			return unsent(
				if type(decision) == "table" and decision.reason ~= nil then decision.reason else "request refused",
				true
			)
		end
		local slot: { done: boolean, exchange: Mcp.Exchange? } = { done = false, exchange = nil }
		task.spawn(function()
			local sent, value: unknown = pcall(transport.call, tool, argumentsJson, limit)
			slot.exchange = if sent
				then value :: Mcp.Exchange
				else { status = "unanswered", detail = "transport raised: " .. tostring(value) }
			slot.done = true
		end)
		while not slot.done and os.clock() < limit do
			task.wait(0.005)
		end
		local exchange = slot.exchange
		if not slot.done or exchange == nil then
			pcall(transport.close)
			return {
				ok = false,
				delivery = "possibly_sent",
				refused = false,
				expired = true,
				detail = tool .. " exceeded its deadline; the request may have been applied",
			}
		end
		if exchange.status == "unsent" then
			local response = unsent(exchange.detail or "request was not sent")
			response.sessionLost = exchange.lost == true
			return response
		end
		if exchange.status == "unanswered" then
			return {
				ok = false,
				delivery = "possibly_sent",
				refused = false,
				expired = exchange.lost ~= true and os.clock() >= limit,
				sessionLost = exchange.lost == true,
				detail = (exchange.detail or "no answer") .. "; the request may have been applied",
			}
		end
		if exchange.detail ~= nil then
			return { ok = false, delivery = "answered", refused = false, expired = false, detail = exchange.detail }
		end
		local parsed, text: unknown = pcall(Reply.texts, exchange.result)
		local flagged = type(exchange.result) == "table" and (exchange.result :: { [string]: unknown }).isError == true
		return {
			ok = parsed and not flagged,
			delivery = "answered",
			refused = false,
			expired = false,
			detail = if not parsed then tostring(text) elseif flagged then text :: string else nil,
			result = exchange.result,
			text = if parsed then text :: string else nil,
		}
	end

	local function listed(): ({ StudioInfo }?, Refusal?)
		local response = dispatch(LIST, "{}", false)
		if not response.ok then
			local kind: RefusalKind = if response.refused
				then "refused"
				elseif response.sessionLost == true then "session_lost"
				elseif response.delivery == "unsent" then "unsent"
				elseif response.delivery == "possibly_sent" then "possibly_sent"
				else "failed"
			return nil, refusalOf(kind, response.detail or "Studio listing failed")
		end
		local parsed, studios: unknown = pcall(discovered, response.text or "")
		if not parsed then
			return nil, refusalOf("failed", "Studio listing was unreadable: " .. tostring(studios))
		end
		return studios :: { StudioInfo }, nil
	end

	local studios, listing = listed()
	if studios == nil then
		pcall(transport.close)
		return nil, listing
	end
	local matches: { StudioInfo } = {}
	for _, candidate in studios do
		if
			(options.studioId == nil or candidate.id == options.studioId)
			and (options.match == nil or options.match(candidate))
		then
			table.insert(matches, candidate)
		end
	end
	if #matches ~= 1 then
		pcall(transport.close)
		local refusal = refusalOf(
			if #matches == 0 then "absent" else "ambiguous",
			if #matches == 0
				then "no open Studio matches the requested target"
				else ("%d open Studios match the requested target; refusing to choose"):format(#matches)
		)
		refusal.candidates = if #matches == 0 then studios else matches
		return nil, refusal
	end
	local selected = matches[1]
	studio = selected

	local function argumentsFor(extra: string): string
		return '{"studio_id":' .. json.serialize(selected.id) .. extra .. "}"
	end

	local function call(tool: string, argumentsJson: string): Response
		return dispatch(tool, argumentsJson, false)
	end

	local function execute(datamodel: string, code: string): Response
		if not DATAMODELS[datamodel] then
			return unsent("unknown datamodel " .. datamodel)
		end
		return dispatch(
			EXECUTE,
			argumentsFor(',"datamodel_type":' .. json.serialize(datamodel) .. ',"code":' .. json.serialize(code)),
			false
		)
	end

	local function toggle(start: boolean, cleaning: boolean): Response
		local response = dispatch(PLAY, argumentsFor(',"is_start":' .. tostring(start)), cleaning)
		if response.ok then
			playing = start
		elseif response.delivery == "possibly_sent" then
			playing = nil
		end
		return response
	end

	local function capture(captureOptions: CaptureOptions?): Response
		local settings: CaptureOptions = captureOptions or {}
		local response =
			dispatch(CAPTURE, settings.argumentsJson or argumentsFor ',"capture_id":"verify-capture"', false)
		if response.ok and settings.directory ~= nil then
			Files.ensureDirectory(settings.directory)
			local saved, image: unknown =
				pcall(Reply.saveCapture, response.result, settings.directory, settings.stem or "capture")
			if saved then
				response.artifact = image :: Reply.Image
			else
				response.ok = false
				response.detail = tostring(image)
			end
		end
		return response
	end

	local function console(): Response
		return dispatch(CONSOLE_READ, argumentsFor "", false)
	end

	local function report(datamodel: string, code: string, runId: string, onPoll: (() -> ())?): ReportResponse
		local last: Response? = nil
		local outcome = Detached.run {
			execute = function(model: string, source: string): Detached.Reply
				local response = execute(model, source)
				last = response
				return {
					ok = response.ok,
					text = response.text,
					detail = response.detail,
					lost = response.sessionLost == true,
					expired = response.expired,
				}
			end,
			datamodel = datamodel,
			code = code,
			runId = runId,
			deadline = runDeadline,
			pollSeconds = if onPoll ~= nil then 1 else nil,
			onPoll = onPoll,
		}
		local answered = last
		local response: Response = if answered ~= nil
			then table.clone(answered)
			else unsent "the detached run sent nothing"
		if outcome.status ~= "done" then
			response.ok = false
			response.detail = outcome.detail
			response.expired = outcome.status == "timed_out"
			response.sessionLost = outcome.status == "session_lost"
			if response.delivery == "unsent" and not response.refused then
				response.delivery = "possibly_sent"
			end
			return { response = response, report = nil, problem = outcome.detail }
		end
		response.ok = true
		response.detail = nil
		response.text = outcome.text
		local parsed, found: unknown = pcall(Reply.report, outcome.text or "", runId)
		if not parsed then
			return { response = response, report = nil, problem = tostring(found) }
		end
		if found == nil then
			return {
				response = response,
				report = nil,
				problem = "engine did not return the run-bound report envelope: " .. (outcome.text or ""):sub(1, 1000),
			}
		end
		return { response = response, report = found :: Core.Report, problem = nil }
	end

	local function close(): Cleanup
		if closed ~= nil then
			return closed
		end
		local wanted = priorMode == "play"
		local outcome: Cleanup = { acknowledged = true, restored = true, mode = priorMode, detail = nil }
		if playing ~= wanted then
			local response = toggle(wanted, true)
			if not response.ok then
				outcome = {
					acknowledged = false,
					restored = false,
					mode = priorMode,
					detail = response.detail or "restore failed",
				}
			end
		end
		pcall(transport.close)
		closed = outcome
		return outcome
	end

	return {
		studio = selected,
		studios = studios,
		call = call,
		execute = execute,
		play = function(start: boolean): Response
			return toggle(start, false)
		end,
		capture = capture,
		console = console,
		report = report,
		close = close,
	},
		nil
end

local function describe(label: string, response: Response): string
	return ("%s: %s (%s)"):format(label, response.detail or "failed", response.delivery)
end

local function run(options: RunOptions): Core.BatchOutcome
	if options.code == "" then
		return { status = "faulted", detail = "attached run requires code" }
	end
	if options.players ~= nil then
		return { status = "faulted", detail = "attached runs execute in the open Studio and do not support multiplayer" }
	end
	local seconds = options.deadlineSeconds or options.attach.runSeconds or 90
	if not (seconds > 0 and seconds < math.huge) then
		return { status = "faulted", detail = "Studio deadline must be finite and positive" }
	end
	local directory = Files.claimDirectory(options.directory or "/tmp/verify-studio-attach")
	local settings = table.clone(options.attach)
	settings.runSeconds = seconds
	settings.directory = settings.directory or directory
	local session, refusal = attach(settings)
	if session == nil then
		local why = refusal :: Refusal
		return { status = "faulted", detail = ("attach %s: %s"):format(why.kind, why.detail) }
	end
	local opened = session
	local outcome: Core.BatchOutcome = { status = "faulted", detail = "attached run did not complete" }
	local body, thrown: unknown = pcall(function()
		if (options.attach.mode or "edit") ~= "play" then
			local started = opened.play(true)
			if not started.ok then
				outcome = {
					status = if started.expired then "timed_out" else "faulted",
					detail = describe("start play", started),
				}
				return
			end
		end
		local token = string.format("%q", directory)
		local progressPath = options.progressFile
		local listening: Progress.Listener? = nil
		local injected = ""
		if progressPath ~= nil and progressPath ~= "" then
			listening = Progress.listener(progressPath, directory, function(): string
				local read = opened.console()
				if not read.ok or read.text == nil then
					error(describe("console read", read), 0)
				end
				return read.text
			end)
			injected = "local progressToken = " .. string.format("%q", (listening :: Progress.Listener).token) .. "; "
		end
		local result = opened.report(
			options.context or "Server",
			"local runId = " .. token .. "; " .. injected .. options.code,
			directory,
			if listening ~= nil then (listening :: Progress.Listener).poll else nil
		)
		if listening ~= nil then
			(listening :: Progress.Listener).finish()
		end
		if result.report == nil then
			outcome = {
				status = if result.response.expired then "timed_out" else "faulted",
				detail = if result.response.ok
					then result.problem or "no report"
					else describe("execute", result.response),
			}
			return
		end
		local found = result.report
		if options.finalCapture then
			local image = opened.capture { directory = directory, stem = "final" }
			local last = found.results[#found.results]
			if not image.ok or image.artifact == nil or last == nil then
				outcome = { status = "faulted", detail = describe("capture", image) }
				return
			end
			table.insert(last.artifacts, {
				name = "final Studio view",
				reference = image.artifact.reference,
				mediaType = image.artifact.mediaType,
			})
		end
		outcome = { status = "returned", report = found }
	end)
	if not body then
		outcome = { status = "faulted", detail = "attached run raised: " .. tostring(thrown) }
	end
	local cleanup = opened.close()
	if not cleanup.acknowledged then
		outcome = {
			status = "faulted",
			detail = "Studio cleanup was not acknowledged: "
				.. (cleanup.detail or "unknown")
				.. "; the attached Studio may still be in play",
		}
	end
	return outcome
end

return { attach = attach, run = run, digest = digest, CONSOLE_READ = CONSOLE_READ }
