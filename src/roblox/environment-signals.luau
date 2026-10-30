--!strict

local Types = require "./environment-types"
local Scheduler = require "./scheduler"
local Names = require "./datatypes/names"
type Signal<A... = ...unknown> = Types.Signal<A...>
type Connection = Types.Connection

local function create(scheduler: Scheduler.Scheduler, errors: { string }, raising: boolean)
	local connections = 0
	local running: { [thread]: boolean } = {}
	setmetatable(running, { __mode = "k" })
	local meters: { [unknown]: { connections: () -> number, fires: () -> number } } = {}
	setmetatable(meters, { __mode = "k" })

	local function finish<R...>(thread: thread, start: number, ok: boolean, ...: R...): R...
		running[thread] = nil
		if not ok then
			error(table.pack(...)[1], 0)
		end
		if #errors > start then
			local parts: { string } = {}
			for index = start + 1, #errors do
				table.insert(parts, errors[index])
				errors[index] = nil
			end
			error(table.concat(parts, "\n"), 0)
		end
		return ...
	end

	local function operation<A..., R...>(body: (A...) -> R...): (A...) -> R...
		if not raising then
			return body
		end
		return function(...: A...): R...
			local thread = coroutine.running()
			if running[thread] then
				return body(...)
			end
			running[thread] = true
			return finish(thread, #errors, pcall(body, ...))
		end
	end

	local function newSignal<A...>(initialFires: number?): Signal<A...>
		type Record = { run: (A...) -> (), connected: boolean, connection: Connection, context: unknown }
		local live: { Record } = {}
		local fired = initialFires or 0
		local signal: Signal<A...>
		local function connect(_self: Signal<A...>, handler: (A...) -> ()): Connection
			local connection: Connection
			local record: Record
			connection = {
				Connected = true,
				Disconnect = function(_self: Connection)
					if not record.connected then
						return
					end
					record.connected = false
					connection.Connected = false
					connections -= 1
					local index = table.find(live, record)
					if index ~= nil then
						table.remove(live, index)
					end
				end,
			}
			Names.register(connection, "RBXScriptConnection")
			record = {
				run = function(...: A...)
					local ok, thrown: unknown = pcall(handler, ...)
					if not ok then
						table.insert(errors, tostring(thrown))
					end
				end,
				connected = true,
				connection = connection,
				context = scheduler.context(),
			}
			table.insert(live, record)
			connections += 1
			return connection
		end
		local function wait(_self: Signal<A...>): ...unknown
			return scheduler.block(function(waiter: thread)
				local connection: Connection?
				local function cleanup()
					if connection then
						connection:Disconnect()
						connection = nil
					end
				end
				local function resume(...: unknown)
					cleanup()
					if coroutine.status(waiter) ~= "dead" then
						scheduler.resume(waiter, ...)
					end
				end
				connection = signal:Connect((resume :: unknown) :: (A...) -> ())
				return cleanup
			end)
		end
		local function dispatch(_self: Signal<A...>, ...: A...)
			fired += 1
			if #live == 0 then
				return
			end
			if #live == 1 then
				local record = live[1]
				if record.context ~= nil then
					scheduler.spawnTagged(record.context, record.run, ...)
				else
					scheduler.spawn(record.run, ...)
				end
				return
			end
			for _, record in table.clone(live) do
				if record.connected then
					if record.context ~= nil then
						scheduler.spawnTagged(record.context, record.run, ...)
					else
						scheduler.spawn(record.run, ...)
					end
				end
			end
		end
		local function disconnectAll(_self: Signal<A...>)
			for _, record in table.clone(live) do
				record.connection:Disconnect()
			end
			table.clear(live)
		end
		signal = {
			Connect = connect,
			Wait = (wait :: unknown) :: (Signal<A...>) -> A...,
			Fire = operation(dispatch),
			DisconnectAll = disconnectAll,
		}
		Names.register(signal, "RBXScriptSignal")
		meters[signal] = {
			connections = function(): number
				return #live
			end,
			fires = function(): number
				return fired
			end,
		}
		return signal
	end

	return {
		newSignal = newSignal,
		operation = operation,
		meters = meters,
		liveConnections = function()
			return connections
		end,
	}
end

return create
