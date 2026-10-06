--!strict

local Core = require "../core"
local Native = require "./experience-host"

export type Connection = { Disconnect: (Connection) -> () }
export type Player = { UserId: number, Name: string, Parent: unknown }
export type Remote = {
	FireClient: (Remote, Player, unknown) -> (),
	FireServer: (Remote, unknown) -> (),
	OnServerEvent: { Connect: (unknown, (Player, unknown) -> ()) -> Connection },
	OnClientEvent: { Connect: (unknown, (unknown) -> ()) -> Connection },
}
export type ServerOptions = {
	remote: Remote,
	runId: string,
	clients: number,
	authorize: (Player) -> boolean,
	registry: Native.Registry,
	engine: Native.Engine,
	sleep: (number) -> (),
	deadlineSeconds: number,
	armed: (() -> ())?,
}
export type ClientOptions = {
	remote: Remote,
	runId: string,
	registry: Native.Registry,
	capabilities: { string },
	now: () -> number,
	capture: ((string) -> { Core.Artifact })?,
	close: (() -> ())?,
	spawn: (() -> ()) -> (),
}

local function record(value: unknown): { [string]: unknown }
	assert(type(value) == "table", "session message must be a record")
	return value :: { [string]: unknown }
end
local function strings(value: unknown): { string }
	assert(type(value) == "table", "expected capability list")
	local result: { string } = {}
	for _, item in value :: { unknown } do
		assert(type(item) == "string" and item ~= "", "invalid capability")
		table.insert(result, item)
	end
	return result
end
local function artifacts(value: unknown): { Core.Artifact }
	assert(type(value) == "table", "expected capture artifacts")
	local result: { Core.Artifact } = {}
	for _, item in value :: { unknown } do
		local fields = record(item)
		assert(type(fields.name) == "string" and type(fields.reference) == "string", "invalid capture")
		assert(fields.mediaType == nil or type(fields.mediaType) == "string", "invalid capture media type")
		table.insert(
			result,
			{ name = fields.name, reference = fields.reference, mediaType = fields.mediaType :: string? }
		)
	end
	return result
end

local function server(context: Core.Context, options: ServerOptions): Core.CaseHost
	assert(options.engine.context == "server", "multiplayer coordinator must run on the server")
	assert(
		options.runId ~= "" and options.clients >= 1 and options.clients <= 8 and options.clients % 1 == 0,
		"invalid session identity or client count"
	)
	local players: { [string]: Player } = {}
	local assigned: { [Player]: string } = {}
	local ready: { [string]: { string } } = {}
	local pending: { [string]: { actor: string, response: unknown } } = {}
	local sequence, joined = 0, 0
	local closed = false
	local closing = false
	local acknowledgments: { [string]: string } = {}
	local connection: Connection? = nil
	local function close()
		if closed or closing then
			return
		end
		closing = true
		local failures: { string } = {}
		for actor, player in players do
			if player.Parent ~= nil then
				local ok, reason = pcall(function(): unknown
					options.remote:FireClient(player, { runId = options.runId, kind = "close" })
					return nil
				end)
				if not ok then
					acknowledgments[actor] = tostring(reason)
				end
			end
		end
		local limit = options.engine.now() + math.min(3, context:remainingSeconds())
		while options.engine.now() < limit do
			local waiting = false
			for actor in players do
				if players[actor].Parent ~= nil and acknowledgments[actor] == nil then
					waiting = true
				end
			end
			if not waiting then
				break
			end
			options.sleep(0.01)
		end
		for actor in players do
			if players[actor].Parent ~= nil and acknowledgments[actor] ~= "" then
				table.insert(failures, actor .. ": " .. (acknowledgments[actor] or "cleanup acknowledgment timed out"))
			end
		end
		closed = true
		if connection then
			connection:Disconnect()
		end
		table.clear(pending)
		assert(#failures == 0, table.concat(failures, "; "))
	end
	context:defer(close)
	connection = options.remote.OnServerEvent:Connect(function(player: Player, value: unknown)
		if closed or not options.authorize(player) or type(value) ~= "table" then
			return
		end
		local fields = record(value)
		if fields.runId ~= options.runId then
			return
		end
		if fields.kind == "closed" and closing and assigned[player] ~= nil then
			acknowledgments[assigned[player]] = if fields.ok == true then "" else tostring(fields.error)
		elseif closing then
			return
		elseif fields.kind == "hello" then
			if assigned[player] == nil then
				if joined >= options.clients then
					return
				end
				joined += 1
				local actor = "client-" .. tostring(joined)
				assigned[player], players[actor] = actor, player
			end
			options.remote:FireClient(player, { runId = options.runId, kind = "welcome", actor = assigned[player] })
		elseif fields.kind == "ready" and assigned[player] ~= nil then
			local ok, capabilities = pcall(strings, fields.capabilities)
			if ok then
				ready[assigned[player]] = capabilities
			end
		elseif fields.kind == "response" and type(fields.id) == "string" then
			local waiting = pending[fields.id]
			if waiting and waiting.actor == assigned[player] and waiting.response == nil then
				waiting.response = fields.response
			end
		end
	end)
	if options.armed then
		options.armed()
	end
	local deadline = options.engine.now() + math.min(options.deadlineSeconds, context:remainingSeconds())
	while true do
		local count = 0
		for actor in ready do
			assert(players[actor].Parent ~= nil, "actor disconnected during readiness: " .. actor)
			count += 1
		end
		if count == options.clients then
			break
		end
		assert(options.engine.now() < deadline, "multiplayer actor readiness timed out")
		options.sleep(0.02)
	end
	local actorContexts: { [string]: Native.Context } = { server = "server" }
	local capabilities = { "native-multiplayer" }
	for actor, caps in ready do
		actorContexts[actor] = "client"
		for _, cap in caps do
			table.insert(capabilities, actor .. ":" .. cap)
			if not table.find(capabilities, cap) then
				table.insert(capabilities, cap)
			end
		end
	end
	local function exchange(envelope: Native.Envelope): unknown
		assert(not closed, "multiplayer session is closed")
		local actor = envelope.request.actor
		local player = players[actor]
		assert(player ~= nil and ready[actor] ~= nil and player.Parent ~= nil, "actor unavailable: " .. actor)
		local limit = options.engine.now() + envelope.request.remainingSeconds
		local entry = { actor = actor, response = nil :: unknown }
		pending[envelope.id] = entry
		local ok, result = pcall(function(): unknown
			options.remote:FireClient(player, { runId = options.runId, kind = "request", envelope = envelope })
			while entry.response == nil do
				assert(player.Parent ~= nil, "actor disconnected: " .. actor)
				assert(options.engine.now() < limit, "actor response timed out: " .. actor)
				options.sleep(0.01)
			end
			return entry.response
		end)
		pending[envelope.id] = nil
		if not ok then
			error(result, 0)
		end
		return result
	end
	local host = Native.create {
		engine = options.engine,
		actor = "server",
		actors = actorContexts,
		registry = options.registry,
		capabilities = capabilities,
		sleep = options.sleep,
		transport = { exchange = exchange, close = close },
		capture = function(actor, checkpoint)
			assert(ready[actor] ~= nil and table.find(ready[actor], "capture") ~= nil, "capture unavailable: " .. actor)
			sequence += 1
			local response = record(exchange {
				id = "capture:" .. tostring(sequence),
				request = {
					actor = actor,
					kind = "query",
					name = "verify.capture",
					payload = checkpoint,
					remainingSeconds = math.max(0.001, context:remainingSeconds()),
				},
			})
			assert(
				response.id == "capture:" .. tostring(sequence)
					and response.actor == actor
					and response.kind == "query"
					and response.name == "verify.capture",
				"capture response identity mismatch"
			)
			assert(response.ok == true, tostring(response.error))
			return artifacts(response.value)
		end,
	}
	return host
end

local function client(options: ClientOptions): () -> ()
	assert(options.runId ~= "", "client requires a run identity")
	local actor: string? = nil
	local closed = false
	local connection: Connection? = nil
	local capabilities = table.clone(options.capabilities)
	local registry: Native.Registry =
		{ actions = table.clone(options.registry.actions), queries = table.clone(options.registry.queries) }
	if options.capture then
		table.insert(capabilities, "capture")
		registry.queries["verify.capture"] = Native.endpoint(function(value): string
			assert(type(value) == "string" and value ~= "", "capture requires checkpoint")
			return value
		end, function(name)
			return (options.capture :: (string) -> { Core.Artifact })(name)
		end)
	end
	local function close()
		if closed then
			return
		end
		closed = true
		if connection then
			connection:Disconnect()
		end
		if options.close then
			options.close()
		end
	end
	connection = options.remote.OnClientEvent:Connect(function(value: unknown)
		if closed or type(value) ~= "table" then
			return
		end
		local fields = record(value)
		if fields.runId ~= options.runId then
			return
		end
		if fields.kind == "welcome" then
			assert(
				type(fields.actor) == "string" and (actor == nil or actor == fields.actor),
				"client actor identity changed"
			)
			actor = fields.actor
			options.remote:FireServer { runId = options.runId, kind = "ready", capabilities = capabilities }
		elseif fields.kind == "close" then
			local ok, reason = pcall(function(): unknown
				close()
				return nil
			end)
			options.remote:FireServer {
				runId = options.runId,
				kind = "closed",
				ok = ok,
				error = if ok then nil else tostring(reason),
			}
		elseif fields.kind == "request" and actor ~= nil then
			local identity = actor :: string
			options.spawn(function()
				local envelope = record(fields.envelope)
				local response = Native.respond(registry, capabilities, options.now, identity, envelope)
				if not closed then
					options.remote:FireServer {
						runId = options.runId,
						kind = "response",
						id = envelope.id,
						response = response,
					}
				end
			end)
		end
	end)
	options.remote:FireServer { runId = options.runId, kind = "hello" }
	return close
end

return { server = server, client = client }
