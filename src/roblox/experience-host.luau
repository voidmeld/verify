--!strict
--!nolint DeprecatedApi

local Experience = require "../core/operations"
local Types = require "../core/types"

export type Context = "server" | "client"
export type Engine = {
	studio: boolean,
	context: Context,
	placeId: number,
	gameId: number,
	version: string,
	now: () -> number,
}
export type Endpoint = {
	run: (payload: unknown, request: Experience.Request) -> unknown,
	requires: { string }?,
}
export type Registry = { actions: { [string]: Endpoint }, queries: { [string]: Endpoint } }
export type WireRequest = {
	kind: "action" | "query",
	actor: string,
	name: string,
	payload: unknown,
	remainingSeconds: number,
}
export type Envelope = { id: string, request: WireRequest }
export type Response = {
	id: string,
	actor: string,
	kind: "action" | "query",
	name: string,
	ok: boolean,
	value: unknown,
	error: string?,
}
export type Transport = { exchange: (Envelope) -> unknown, close: (() -> ())? }
export type Remote = {
	InvokeServer: (self: Remote, envelope: Envelope) -> unknown,
	InvokeClient: (self: Remote, player: unknown, envelope: Envelope) -> unknown,
}
export type Options = {
	engine: Engine,
	actor: string,
	actors: { [string]: Context },
	registry: Registry,
	capabilities: { string }?,
	transport: Transport?,
	maxInFlight: number?,
	sleep: ((number) -> ())?,
	capture: ((actor: string, checkpoint: string) -> { Types.Artifact })?,
	judge: ((Experience.JudgmentRequest) -> Experience.Judgment)?,
}

type RunService = {
	IsStudio: (self: RunService) -> boolean,
	IsRunning: (self: RunService) -> boolean,
	IsServer: (self: RunService) -> boolean,
	IsClient: (self: RunService) -> boolean,
}
type DataModel = {
	PlaceId: number,
	GameId: number,
	GetService: (self: DataModel, name: string) -> RunService,
}
type Globals = { game: DataModel?, version: (() -> string)? }

local function nativeEngine(): Engine
	local globals = (getfenv(0) :: unknown) :: Globals
	local dataModel = globals.game
	local version = globals.version
	assert(dataModel ~= nil and version ~= nil, "experience-host: Roblox engine is unavailable")
	local service = dataModel:GetService "RunService"
	assert(service:IsRunning(), "experience-host: Roblox simulation is not running")
	local server, client = service:IsServer(), service:IsClient()
	assert(server ~= client, "experience-host: run in a live Roblox server or client context")
	return {
		studio = service:IsStudio(),
		context = if server then "server" else "client",
		placeId = dataModel.PlaceId,
		gameId = dataModel.GameId,
		version = version(),
		now = os.clock,
	}
end

local function endpoint<T>(
	decode: (unknown) -> T,
	body: (T, Experience.Request) -> unknown,
	requires: { string }?
): Endpoint
	return {
		requires = requires,
		run = function(payload: unknown, request: Experience.Request): unknown
			return body(decode(payload), request)
		end,
	}
end

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function record(value: unknown): { [string]: unknown }
	assert(type(value) == "table", "experience-host: expected a request or response record")
	return value :: { [string]: unknown }
end

local function request(value: unknown): Experience.Request
	local fields = record(value)
	assert(fields.kind == "action" or fields.kind == "query", "experience-host: invalid operation kind")
	assert(type(fields.actor) == "string" and fields.actor ~= "", "experience-host: missing actor")
	assert(type(fields.name) == "string" and fields.name ~= "", "experience-host: missing operation name")
	assert(finite(fields.deadline), "experience-host: invalid request deadline")
	return {
		kind = fields.kind :: "action" | "query",
		actor = fields.actor :: string,
		name = fields.name :: string,
		payload = fields.payload,
		deadline = fields.deadline :: number,
	}
end

local function wireRequest(value: unknown, now: number): Experience.Request
	local fields = record(value)
	assert(
		finite(fields.remainingSeconds) and (fields.remainingSeconds :: number) > 0,
		"experience-host: invalid remaining request budget"
	)
	return request {
		kind = fields.kind,
		actor = fields.actor,
		name = fields.name,
		payload = fields.payload,
		deadline = now + (fields.remainingSeconds :: number),
	}
end

local function dispatch(registry: Registry, capabilities: { [string]: true }, invocation: Experience.Request): unknown
	local entries = if invocation.kind == "action" then registry.actions else registry.queries
	local operation = entries[invocation.name]
	assert(operation ~= nil, "experience-host: unavailable " .. invocation.kind .. " " .. invocation.name)
	local required: { string } = operation.requires or {}
	for _, capability in required do
		assert(capabilities[capability] == true, "experience-host: unavailable capability " .. capability)
	end
	return operation.run(invocation.payload, invocation)
end

local function respondRequest(
	registry: Registry,
	capabilities: { string },
	now: () -> number,
	actor: string,
	value: unknown,
	invocation: Experience.Request
): Response
	local fields = record(value)
	assert(type(fields.id) == "string" and fields.id ~= "", "experience-host: missing request identity")
	assert(invocation.actor == actor, "experience-host: request reached the wrong actor")
	local available: { [string]: true } = {}
	for _, capability in capabilities do
		available[capability] = true
	end
	local ok, result: unknown = pcall(function(): unknown
		assert(now() < invocation.deadline, "experience-host: request deadline expired")
		local output = dispatch(registry, available, invocation)
		assert(now() < invocation.deadline, "experience-host: request exceeded its deadline")
		return output
	end)
	return {
		id = fields.id :: string,
		actor = actor,
		kind = invocation.kind,
		name = invocation.name,
		ok = ok,
		value = if ok then result else nil,
		error = if ok then nil else tostring(result),
	}
end

local function respond(
	registry: Registry,
	capabilities: { string },
	now: () -> number,
	actor: string,
	value: unknown
): Response
	local invocation = wireRequest(record(value).request, now())
	return respondRequest(registry, capabilities, now, actor, value, invocation)
end

local function remoteTransport(
	context: Context,
	remote: Remote,
	actors: { [string]: Context },
	playerFor: ((actor: string) -> unknown)?
): Transport
	assert(context == "client" or playerFor ~= nil, "experience-host: server routing requires a player resolver")
	return {
		exchange = function(envelope: Envelope): unknown
			if context == "client" then
				assert(
					actors[envelope.request.actor] == "server",
					"experience-host: client transport only routes to the server"
				)
				return remote:InvokeServer(envelope)
			end
			assert(
				actors[envelope.request.actor] == "client",
				"experience-host: server transport only routes to a client"
			)
			local resolve = playerFor :: (string) -> unknown
			local player = resolve(envelope.request.actor)
			assert(player ~= nil, "experience-host: target player is unavailable")
			return remote:InvokeClient(player, envelope)
		end,
	}
end

local function remoteResponder(
	registry: Registry,
	capabilities: { string },
	now: () -> number,
	actor: string,
	authorize: (caller: unknown, invocation: Experience.Request) -> boolean
): (caller: unknown, envelope: unknown) -> Response
	return function(caller: unknown, envelope: unknown): Response
		local invocation = wireRequest(record(envelope).request, now())
		assert(authorize(caller, invocation), "experience-host: remote caller is unauthorized")
		return respondRequest(registry, capabilities, now, actor, envelope, invocation)
	end
end

local function create(options: Options): Experience.Host
	local engine = options.engine
	assert(engine.context == "server" or engine.context == "client", "experience-host: invalid engine context")
	assert(type(engine.studio) == "boolean", "experience-host: missing Studio or Player identity")
	assert(finite(engine.placeId) and engine.placeId >= 0, "experience-host: invalid place identity")
	assert(finite(engine.gameId) and engine.gameId >= 0, "experience-host: invalid game identity")
	assert(type(engine.version) == "string" and engine.version ~= "", "experience-host: missing engine version")
	assert(
		options.actors[options.actor] == engine.context,
		"experience-host: local actor does not match engine context"
	)
	for actor, context in options.actors do
		assert(actor ~= "" and (context == "server" or context == "client"), "experience-host: invalid actor context")
	end
	assert(type(engine.now) == "function" and finite(engine.now()), "experience-host: invalid engine clock")
	local limit = options.maxInFlight or 16
	assert(finite(limit) and limit >= 1 and limit % 1 == 0, "experience-host: invalid in-flight limit")
	local capabilities = table.clone(options.capabilities or {})
	table.insert(capabilities, "roblox-" .. engine.context)
	table.insert(capabilities, if engine.studio then "roblox-studio" else "roblox-player")
	if options.capture ~= nil then
		table.insert(capabilities, "capture")
	end
	if options.judge ~= nil then
		table.insert(capabilities, "judgment")
	end
	for name in options.registry.actions do
		table.insert(capabilities, "action:" .. name)
	end
	for name in options.registry.queries do
		table.insert(capabilities, "query:" .. name)
	end
	local available: { [string]: true } = {}
	for _, capability in capabilities do
		assert(capability ~= "", "experience-host: empty capability")
		assert(
			capability ~= "capture" or options.capture ~= nil,
			"experience-host: capture capability needs a supplied capture"
		)
		assert(
			capability ~= "judgment" or options.judge ~= nil,
			"experience-host: judgment capability needs a supplied reviewer"
		)
		available[capability] = true
	end
	local closed, sequence, inFlight = false, 0, 0
	local function actorReady(actor: string)
		assert(not closed, "experience-host: host is closed")
		assert(options.actors[actor] ~= nil, "experience-host: unknown actor " .. actor)
	end
	return {
		name = if engine.studio then "roblox-studio" else "roblox-player",
		capabilities = capabilities,
		environment = {
			["roblox.context"] = engine.context,
			["roblox.version"] = engine.version,
			["roblox.placeId"] = tostring(engine.placeId),
			["roblox.gameId"] = tostring(engine.gameId),
		},
		now = engine.now,
		sleep = options.sleep,
		invoke = function(invocation: Experience.Request): unknown
			actorReady(invocation.actor)
			invocation = request(invocation)
			assert(engine.now() < invocation.deadline, "experience-host: request deadline expired")
			assert(inFlight < limit, "experience-host: in-flight request limit exceeded")
			inFlight += 1
			local ok, output: unknown = pcall(function(): unknown
				if invocation.actor == options.actor then
					return dispatch(options.registry, available, invocation)
				end
				local transport = options.transport
				assert(transport ~= nil, "experience-host: another actor requires a supplied transport")
				sequence += 1
				local id = options.actor .. ":" .. tostring(sequence)
				local fields = record(transport.exchange {
					id = id,
					request = {
						kind = invocation.kind,
						actor = invocation.actor,
						name = invocation.name,
						payload = invocation.payload,
						remainingSeconds = invocation.deadline - engine.now(),
					},
				})
				assert(
					fields.id == id and fields.actor == invocation.actor,
					"experience-host: response correlation mismatch"
				)
				assert(
					fields.kind == invocation.kind and fields.name == invocation.name,
					"experience-host: response operation mismatch"
				)
				assert(type(fields.ok) == "boolean", "experience-host: invalid response status")
				assert(
					fields.ok,
					if type(fields.error) == "string" then fields.error else "experience-host: remote operation failed"
				)
				return fields.value
			end)
			inFlight -= 1
			if not ok then
				error(output, 0)
			end
			assert(engine.now() < invocation.deadline, "experience-host: request exceeded its deadline")
			return output
		end,
		capture = if options.capture == nil
			then nil
			else function(actor: string, checkpoint: string): { Types.Artifact }
				actorReady(actor)
				return (options.capture :: (string, string) -> { Types.Artifact })(actor, checkpoint)
			end,
		judge = if options.judge == nil
			then nil
			else function(judgment: Experience.JudgmentRequest): Experience.Judgment
				actorReady(judgment.actor)
				return (options.judge :: (Experience.JudgmentRequest) -> Experience.Judgment)(judgment)
			end,
		close = function()
			if closed then
				return
			end
			closed = true
			local transport = options.transport
			if transport ~= nil and transport.close ~= nil then
				transport.close()
			end
		end,
	}
end

return {
	create = create,
	nativeEngine = nativeEngine,
	endpoint = endpoint,
	respond = respond,
	remoteTransport = remoteTransport,
	remoteResponder = remoteResponder,
}
