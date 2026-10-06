--!strict

local Core = require "../src/core"
local Native = require "../src/roblox/experience-host"
local Multi = require "../src/roblox/multiplayer"

local function identity(value: unknown): string
	assert(type(value) == "string")
	return value
end
local operation = Core.operation { kind = "query", name = "identity", input = identity, output = identity }
type Mode =
	"normal"
	| "spoof"
	| "disconnect"
	| "timeout"
	| "cleanup-failure"
	| "cleanup-timeout"
	| "readiness-timeout"
	| "wrong-identity"
	| "premature-ack"
local function exercise(mode: Mode, body: (Core.Context) -> (), count: number?): (Core.Report, number, number)
	local time, connections, cleaned = 0, 0, 0
	local requested = count or 2
	local previousId: string? = nil
	local serverListener: ((Multi.Player, unknown) -> ())? = nil
	local listeners: { [number]: (unknown) -> () } = {}
	local players: { Multi.Player } = {
		{ UserId = 1, Name = "one", Parent = true },
		{ UserId = 2, Name = "two", Parent = true },
	}
	if requested == 1 then
		table.remove(players, 2)
	elseif requested == 8 then
		for index = 3, 8 do
			table.insert(players, { UserId = index, Name = tostring(index), Parent = true })
		end
	end
	local outsider: Multi.Player = { UserId = 99, Name = "outside", Parent = true }
	local function emit(player: Multi.Player, value: unknown)
		if serverListener then
			serverListener(player, value)
		end
	end
	local function connect(disconnect: () -> ()): Multi.Connection
		connections += 1
		local closed = false
		return {
			Disconnect = function()
				if not closed then
					closed = true
					connections -= 1
					disconnect()
				end
			end,
		}
	end
	local remote: Multi.Remote
	remote = {
		OnServerEvent = {
			Connect = function(_, callback)
				serverListener = callback
				return connect(function()
					serverListener = nil
				end)
			end,
		},
		OnClientEvent = {
			Connect = function()
				error "server cannot listen as client"
			end,
		},
		FireServer = function()
			error "server cannot send as client"
		end,
		FireClient = function(_, player, value)
			local packet = value :: { [string]: unknown }
			if packet.kind == "request" then
				local envelope = packet.envelope :: Native.Envelope
				if mode == "wrong-identity" then
					emit(player, {
						runId = "run",
						kind = "response",
						id = envelope.id,
						response = {
							id = envelope.id,
							actor = "client-99",
							kind = "query",
							name = "identity",
							ok = true,
							value = "forged",
						},
					})
					return
				end
				if mode == "disconnect" then
					player.Parent = nil
					return
				end
				if mode == "timeout" then
					return
				end
				if mode == "spoof" then
					if previousId then
						emit(player, {
							runId = "run",
							kind = "response",
							id = previousId,
							response = {
								id = previousId,
								actor = envelope.request.actor,
								kind = "query",
								name = "identity",
								ok = true,
								value = "late",
							},
						})
					end
					previousId = envelope.id
					local response: Native.Response = {
						id = envelope.id,
						actor = envelope.request.actor,
						kind = "query",
						name = "identity",
						ok = true,
						value = "forged",
					}
					emit(outsider, { runId = "run", kind = "response", id = envelope.id, response = response })
					emit(
						players[if player.UserId == 1 then 2 else 1],
						{ runId = "run", kind = "response", id = envelope.id, response = response }
					)
					emit(player, { runId = "other", kind = "response", id = envelope.id, response = response })
				end
			elseif packet.kind == "close" and (mode == "cleanup-timeout" or mode == "premature-ack") then
				return
			end
			local callback = listeners[player.UserId]
			if callback then
				callback(value)
			end
		end,
	}
	local now = function()
		return time
	end
	local harness = Core.createHarness { now = now }
	harness:case("coordinated", { timeoutSeconds = 0.1, cleanupTimeoutSeconds = 0.2, run = body })
	local report = harness:run {
		executor = "mock-remote-event",
		bind = function(context)
			return Multi.server(context, {
				remote = remote,
				runId = "run",
				clients = requested,
				authorize = function(player)
					return player.UserId <= 8
				end,
				registry = {
					actions = {},
					queries = {
						identity = Native.endpoint(identity, function(value)
							return "server:" .. value
						end),
					},
				},
				engine = { studio = true, context = "server", placeId = 0, gameId = 0, version = "mock", now = now },
				sleep = function(seconds)
					time += seconds
				end,
				deadlineSeconds = 0.05,
				armed = function()
					emit(outsider, { runId = "run", kind = "hello" })
					emit(players[1], { runId = "other", kind = "hello" })
					for _, player in players do
						if mode == "readiness-timeout" and player.UserId == 2 then
							break
						end
						local clientRemote: Multi.Remote = {
							FireServer = function(_, value)
								emit(player, value)
							end,
							FireClient = remote.FireClient,
							OnServerEvent = remote.OnServerEvent,
							OnClientEvent = {
								Connect = function(_, callback)
									listeners[player.UserId] = callback
									return connect(function()
										listeners[player.UserId] = nil
									end)
								end,
							},
						}
						Multi.client {
							remote = clientRemote,
							runId = "run",
							now = now,
							spawn = function(callback)
								callback()
							end,
							registry = {
								actions = {},
								queries = {
									identity = Native.endpoint(identity, function(value)
										return player.Name .. ":" .. value
									end),
								},
							},
							capabilities = { "query:identity" },
							capture = function(name)
								return { { name = name, reference = "mock:" .. player.Name, mediaType = "image/png" } }
							end,
							close = function()
								cleaned += 1
								if mode == "cleanup-failure" and player.UserId == 1 then
									error "input release failed"
								end
							end,
						}
						if mode == "spoof" then
							emit(player, { runId = "run", kind = "hello" })
						end
						if mode == "premature-ack" then
							emit(player, { runId = "run", kind = "closed", ok = true })
						end
					end
				end,
			})
		end,
	}
	return report, connections, cleaned
end
return function(suite: Core.Harness)
	suite:suite("multiplayer transport", function()
		suite:case("supports one through eight clients and rejects invalid counts before readiness", function(check)
			for _, count in { 1, 8 } do
				local report, connections, cleaned = exercise("normal", function(context)
					context
						:expect(context:perform("client-" .. tostring(count), operation, "x"))
						:toBe(if count == 1 then "one:x" else "8:x")
				end, count)
				check:expect(report.passed):toBe(1)
				check:expect(connections):toBe(0)
				check:expect(cleaned):toBe(count)
			end
			for _, count in { 0, -1, 1.5, 9, math.huge, math.huge - math.huge } do
				local report = exercise("normal", function()
					error "must not run"
				end, count)
				check:expect(report.passed):toBe(0)
				check
					:expect(
						string.find(
							report.results[1].failures[1].message,
							"invalid session identity or client count",
							1,
							true
						) ~= nil
					)
					:toBe(true)
			end
		end)

		suite:case("routes both clients and server through one ordinary case and acknowledges cleanup", function(check)
			local report, connections, cleaned = exercise("normal", function(context)
				context:expect(context:perform("server", operation, "x")):toBe "server:x"
				context:expect(context:perform("client-1", operation, "x")):toBe "one:x"
				context:expect(context:perform("client-2", operation, "x")):toBe "two:x"
				context:checkpoint("client-1", "first")
				context:checkpoint("client-2", "second")
			end)
			check:expect(report.passed):toBe(1)
			check:expect(connections):toBe(0)
			check:expect(cleaned):toBe(2)
			local evidence = report.results[1].evidence
			assert(evidence)
			check:expect(evidence.checkpoints[1].artifacts[1].reference):toBe "mock:one"
			check:expect(evidence.checkpoints[2].artifacts[1].reference):toBe "mock:two"
		end)
		suite:case("ignores unauthorized, wrong-run and wrong-player responses", function(check)
			local report, connections = exercise("spoof", function(context)
				context:expect(context:perform("client-1", operation, "x")):toBe "one:x"
				context:expect(context:perform("client-2", operation, "x")):toBe "two:x"
			end)
			check:expect(report.passed):toBe(1)
			check:expect(connections):toBe(0)
		end)
		suite:case("fails lost actors and bounded response waits", function(check)
			for _, mode in { "disconnect", "timeout", "wrong-identity" } do
				local report = exercise(mode :: Mode, function(context)
					context:perform("client-1", operation, "x")
				end)
				check:expect(report.passed):toBe(0)
				check:expect(report.failed + report.timedOut):toBe(1)
			end
		end)
		suite:case("records cleanup failure and missing acknowledgments without passing", function(check)
			for _, mode in { "cleanup-failure", "cleanup-timeout", "premature-ack" } do
				local report = exercise(mode :: Mode, function() end)
				check:expect(report.passed):toBe(0)
				check:expect(report.results[1].failures[1].phase):toBe "cleanup"
			end
		end)
		suite:case("cleans connected clients after readiness fails", function(check)
			local report, connections, cleaned = exercise("readiness-timeout", function()
				error "must not run"
			end)
			check:expect(report.passed):toBe(0)
			check:expect(connections):toBe(0)
			check:expect(cleaned):toBe(1)
		end)
	end)
end
