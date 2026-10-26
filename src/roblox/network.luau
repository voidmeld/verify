--!strict

local Environment = require "./environment"

export type Payload = boolean | number | string | { Payload } | { [string]: Payload }
export type Message = { channel: string, payload: Payload }
export type RefusalReason =
	"invalid_payload"
	| "invalid_channel"
	| "invalid_latency"
	| "unknown_client"
	| "client_disconnected"
	| "invalid_step"
	| "delivery_in_progress"
export type Refusal = {
	ok: false,
	reason: RefusalReason,
	detail: string,
}
export type SendOutcome = { ok: true, sequence: number, at: number } | Refusal
export type DeliveryOutcome = { ok: true, delivered: number, dropped: number, pending: number } | Refusal
export type DisconnectOutcome = { ok: true, dropped: number } | Refusal
export type Client = {
	id: string,
	environment: Environment.Environment,
	send: (message: Message, latency: number?) -> SendOutcome,
	onMessage: (handler: (message: Message) -> ()) -> Environment.Connection,
}
export type Server = {
	environment: Environment.Environment,
	send: (client: string, message: Message, latency: number?) -> SendOutcome,
	onMessage: (handler: (sender: string, message: Message) -> ()) -> Environment.Connection,
}
export type Options = {
	clients: { string },
	latency: number?,
	environment: ((role: "server" | "client", client: string?) -> Environment.Options?)?,
}
export type Network = {
	server: Server,
	clients: { [string]: Client },
	now: () -> number,
	pending: () -> number,
	advance: (seconds: number) -> DeliveryOutcome,
	disconnect: (client: string) -> DisconnectOutcome,
	isConnected: (client: string) -> boolean,
}

type Cloned = { ok: true, value: Payload } | Refusal
type Queued = { target: "server" | "client", client: string, message: Message, at: number, sequence: number }
type ClientState = { connected: boolean, signal: Environment.Signal<Message> }

local getMetatable = (getmetatable :: unknown) :: (unknown) -> unknown

local function refuse(reason: RefusalReason, detail: string): Refusal
	return { ok = false, reason = reason, detail = detail }
end

local function finite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function clonePayload(value: unknown, active: { [unknown]: boolean }, depth: number): Cloned
	if depth > 64 then
		return refuse("invalid_payload", "payload nesting exceeds 64")
	end
	if type(value) == "boolean" or type(value) == "string" then
		return { ok = true, value = value }
	elseif type(value) == "number" then
		if not finite(value) then
			return refuse("invalid_payload", "payload numbers must be finite")
		end
		return { ok = true, value = value }
	elseif type(value) ~= "table" then
		return refuse("invalid_payload", "payload supports only booleans, finite numbers, strings and plain tables")
	end
	local entries = value :: { [unknown]: unknown }
	if getMetatable(entries) ~= nil then
		return refuse("invalid_payload", "payload tables must not have metatables")
	elseif active[value] then
		return refuse("invalid_payload", "payload tables must not contain cycles")
	end
	active[value] = true
	local list: { Payload } = {}
	local dictionary: { [string]: Payload } = {}
	local count = 0
	local maximum = 0
	local numeric = false
	local named = false
	for key, item in entries do
		local copied = clonePayload(item, active, depth + 1)
		if not copied.ok then
			active[value] = nil
			return copied
		end
		if type(key) == "number" and finite(key) and key >= 1 and key % 1 == 0 then
			numeric = true
			count += 1
			maximum = math.max(maximum, key)
			list[key] = copied.value
		elseif type(key) == "string" then
			named = true
			dictionary[key] = copied.value
		else
			active[value] = nil
			return refuse("invalid_payload", "payload keys must be strings or positive integer array indexes")
		end
	end
	active[value] = nil
	if numeric and named then
		return refuse("invalid_payload", "payload tables must not mix array and dictionary keys")
	elseif numeric and maximum ~= count then
		return refuse("invalid_payload", "payload arrays must be dense")
	end
	return { ok = true, value = if numeric then list else dictionary }
end

local function copyMessage(message: Message): Message
	local copied = clonePayload(message.payload, {}, 0)
	assert(copied.ok, "queued payload lost its protocol binding")
	return { channel = message.channel, payload = copied.value }
end

local function create(options: Options): Network
	local defaultLatency = options.latency or 0
	assert(finite(defaultLatency) and defaultLatency >= 0, "network latency must be finite and nonnegative")
	local function environment(role: "server" | "client", client: string?): Environment.Environment
		return Environment.create(if options.environment ~= nil then options.environment(role, client) else nil)
	end
	local serverEnvironment = environment("server", nil)
	local serverSignal: Environment.Signal<string, Message> = serverEnvironment.newSignal()
	local states: { [string]: ClientState } = {}
	local clients: { [string]: Client } = {}
	local queue: { Queued } = {}
	local now = 0
	local sequence = 0
	local advancing = false

	local function send(target: "server" | "client", client: string, message: Message, latency: number?): SendOutcome
		local state = states[client]
		if state == nil then
			return refuse("unknown_client", "client is not declared: " .. client)
		elseif not state.connected then
			return refuse("client_disconnected", "client is disconnected: " .. client)
		end
		if type(message) ~= "table" or getMetatable(message) ~= nil then
			return refuse("invalid_payload", "message must be a plain table")
		end
		local delay = if latency ~= nil then latency else defaultLatency
		if not finite(delay) or delay < 0 or not finite(now + delay) then
			return refuse("invalid_latency", "message latency must be finite and nonnegative")
		elseif type(message.channel) ~= "string" or message.channel == "" then
			return refuse("invalid_channel", "message channel must be a non-empty string")
		end
		local copied = clonePayload(message.payload, {}, 0)
		if not copied.ok then
			return copied
		end
		sequence += 1
		local packet: Queued = {
			target = target,
			client = client,
			message = { channel = message.channel, payload = copied.value },
			at = now + delay,
			sequence = sequence,
		}
		table.insert(queue, packet)
		return { ok = true, sequence = sequence, at = packet.at }
	end

	for _, id in options.clients do
		assert(type(id) == "string" and id ~= "", "client ids must be non-empty strings")
		assert(states[id] == nil, "duplicate client id: " .. id)
		local clientEnvironment = environment("client", id)
		local signal: Environment.Signal<Message> = clientEnvironment.newSignal()
		states[id] = { connected = true, signal = signal }
		clients[id] = {
			id = id,
			environment = clientEnvironment,
			send = function(message: Message, latency: number?): SendOutcome
				return send("server", id, message, latency)
			end,
			onMessage = function(handler: (Message) -> ()): Environment.Connection
				assert(states[id].connected, "client is disconnected: " .. id)
				return signal:Connect(function(message: Message)
					handler(copyMessage(message))
				end)
			end,
		}
	end

	local server: Server = {
		environment = serverEnvironment,
		send = function(client: string, message: Message, latency: number?): SendOutcome
			return send("client", client, message, latency)
		end,
		onMessage = function(handler: (string, Message) -> ()): Environment.Connection
			return serverSignal:Connect(function(sender: string, message: Message)
				handler(sender, copyMessage(message))
			end)
		end,
	}
	return {
		server = server,
		clients = clients,
		now = function(): number
			return now
		end,
		pending = function(): number
			return #queue
		end,
		isConnected = function(client: string): boolean
			local state = states[client]
			return state ~= nil and state.connected
		end,
		disconnect = function(client: string): DisconnectOutcome
			local state = states[client]
			if state == nil then
				return refuse("unknown_client", "client is not declared: " .. client)
			end
			state.connected = false
			state.signal:DisconnectAll()
			local retained: { Queued } = {}
			local dropped = 0
			for _, packet in queue do
				if packet.client == client then
					dropped += 1
				else
					table.insert(retained, packet)
				end
			end
			queue = retained
			return { ok = true, dropped = dropped }
		end,
		advance = function(seconds: number): DeliveryOutcome
			if advancing then
				return refuse("delivery_in_progress", "message delivery cannot advance recursively")
			elseif not finite(seconds) or seconds < 0 or not finite(now + seconds) then
				return refuse("invalid_step", "network step must be finite and nonnegative")
			end
			advancing = true
			now += seconds
			local ready: { Queued } = {}
			local future: { Queued } = {}
			for _, packet in queue do
				table.insert(if packet.at <= now then ready else future, packet)
			end
			queue = future
			table.sort(ready, function(left: Queued, right: Queued): boolean
				return left.at < right.at or (left.at == right.at and left.sequence < right.sequence)
			end)
			local delivered = 0
			local dropped = 0
			for _, packet in ready do
				local state = states[packet.client]
				if not state.connected then
					dropped += 1
				elseif packet.target == "server" then
					serverSignal:Fire(packet.client, packet.message)
					delivered += 1
				else
					state.signal:Fire(packet.message)
					delivered += 1
				end
			end
			advancing = false
			return { ok = true, delivered = delivered, dropped = dropped, pending = #queue }
		end,
	}
end

return { create = create }
