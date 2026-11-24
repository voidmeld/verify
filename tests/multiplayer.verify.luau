--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Core = require "../src/core"
local Shape = require "../src/core/shape"
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
			Connect = function(_: unknown, callback: (Multi.Player, unknown) -> ()): Multi.Connection
				serverListener = callback
				return connect(function()
					serverListener = nil
				end)
			end,
		},
		OnClientEvent = {
			Connect = function(_: unknown, _callback: (unknown) -> ()): Multi.Connection
				error "server cannot listen as client"
			end,
		},
		FireServer = function(_remote: Multi.Remote, _value: unknown): ()
			error "server cannot send as client"
		end,
		FireClient = function(_remote: Multi.Remote, player: Multi.Player, value: unknown): ()
			local packet = Shape.record(value, "multiplayer message")
			local kind = packet.kind
			local envelopeValue = packet.envelope
			if kind == "request" then
				local envelope = Shape.record(envelopeValue, "request envelope")
				local requestId = envelope.id
				assert(type(requestId) == "string")
				local request = Shape.record(envelope.request, "wire request")
				local actor = request.actor
				assert(type(actor) == "string")
				if mode == "wrong-identity" then
					emit(player, {
						runId = "run",
						kind = "response",
						id = requestId,
						response = {
							id = requestId,
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
								actor = actor,
								kind = "query",
								name = "identity",
								ok = true,
								value = "late",
							},
						})
					end
					previousId = requestId
					local response: Native.Response = {
						id = requestId,
						actor = actor,
						kind = "query",
						name = "identity",
						ok = true,
						value = "forged",
					}
					emit(outsider, { runId = "run", kind = "response", id = requestId, response = response })
					emit(
						players[if player.UserId == 1 then 2 else 1],
						{ runId = "run", kind = "response", id = requestId, response = response }
					)
					emit(player, { runId = "other", kind = "response", id = requestId, response = response })
				end
			elseif kind == "close" and (mode == "cleanup-timeout" or mode == "premature-ack") then
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
						identity = Native.endpoint(identity, function(value: string)
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
									identity = Native.endpoint(identity, function(value: string)
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
describe("multiplayer transport", function()
	it("supports one through eight clients and rejects invalid counts before readiness", function()
		for _, count in { 1, 8 } do
			local report, connections, cleaned = exercise("normal", function(context)
				context
					:expect(context:perform("client-" .. tostring(count), operation, "x"))
					:toBe(if count == 1 then "one:x" else "8:x")
			end, count)
			expect(report.passed):toBe(1)
			expect(connections):toBe(0)
			expect(cleaned):toBe(count)
		end
		for _, count in { 0, -1, 1.5, 9, math.huge, math.huge - math.huge } do
			local report = exercise("normal", function()
				error "must not run"
			end, count)
			expect(report.passed):toBe(0)
			expect(
				string.find(report.results[1].failures[1].message, "invalid session identity or client count", 1, true)
					~= nil
			):toBe(true)
		end
	end)

	it("routes both clients and server through one ordinary case and acknowledges cleanup", function()
		local report, connections, cleaned = exercise("normal", function(context)
			context:expect(context:perform("server", operation, "x")):toBe "server:x"
			context:expect(context:perform("client-1", operation, "x")):toBe "one:x"
			context:expect(context:perform("client-2", operation, "x")):toBe "two:x"
			context:checkpoint("client-1", "first")
			context:checkpoint("client-2", "second")
		end)
		expect(report.passed):toBe(1)
		expect(connections):toBe(0)
		expect(cleaned):toBe(2)
		local evidence = report.results[1].evidence
		assert(evidence)
		expect(evidence.checkpoints[1].artifacts[1].reference):toBe "mock:one"
		expect(evidence.checkpoints[2].artifacts[1].reference):toBe "mock:two"
	end)
	it("ignores unauthorized, wrong-run and wrong-player responses", function()
		local report, connections = exercise("spoof", function(context)
			context:expect(context:perform("client-1", operation, "x")):toBe "one:x"
			context:expect(context:perform("client-2", operation, "x")):toBe "two:x"
		end)
		expect(report.passed):toBe(1)
		expect(connections):toBe(0)
	end)
	it("fails lost actors and bounded response waits", function()
		local modes: { Mode } = { "disconnect", "timeout", "wrong-identity" }
		for _, mode in modes do
			local report = exercise(mode, function(context)
				context:perform("client-1", operation, "x")
			end)
			expect(report.passed):toBe(0)
			expect(report.failed + report.timedOut):toBe(1)
		end
	end)
	it("records cleanup failure and missing acknowledgments without passing", function()
		local modes: { Mode } = { "cleanup-failure", "cleanup-timeout", "premature-ack" }
		for _, mode in modes do
			local report = exercise(mode, function() end)
			expect(report.passed):toBe(0)
			expect(report.results[1].failures[1].phase):toBe "cleanup"
		end
	end)
	it("cleans connected clients after readiness fails", function()
		local report, connections, cleaned = exercise("readiness-timeout", function()
			error "must not run"
		end)
		expect(report.passed):toBe(0)
		expect(connections):toBe(0)
		expect(cleaned):toBe(1)
	end)
end)

describe("delivery diagnostics", function()
	it("reports an undeliverable run through the delivery channel when it exists", function()
		local received: { string } = {}
		local channel: Multi.DeliveryChannel = {
			FireServer = function(_, reason: string, detail: string)
				table.insert(received, reason .. "|" .. detail)
			end,
		}
		local present: Multi.DeliveryStorage = {
			FindFirstChild = function(_, name: string): Multi.DeliveryChannel?
				expect(name):toBe(Multi.DELIVERY_CHANNEL)
				return channel
			end,
		}
		expect(Multi.undeliverable(present, "remote_missing", "no session remote")):toBe(true)
		expect(received):toEqual { "remote_missing|no session remote" }
		local absent: Multi.DeliveryStorage = {
			FindFirstChild = function(): Multi.DeliveryChannel?
				return nil
			end,
		}
		expect(Multi.undeliverable(absent, "remote_missing", "no session remote")):toBe(false)
	end)

	it("tells the client owner once when a message belongs to another run", function()
		local reports: { string } = {}
		local listener: { callback: ((unknown) -> ())? } = {}
		local remote: Multi.Remote = {
			FireClient = function() end,
			FireServer = function() end,
			OnServerEvent = {
				Connect = function()
					return { Disconnect = function() end }
				end,
			},
			OnClientEvent = {
				Connect = function(_, callback)
					listener.callback = callback
					return { Disconnect = function() end }
				end,
			},
		}
		Multi.client {
			remote = remote,
			runId = "expected",
			now = function()
				return 0
			end,
			spawn = function(callback)
				callback()
			end,
			registry = { actions = {}, queries = {} },
			capabilities = {},
			undeliverable = function(reason, detail)
				table.insert(reports, reason .. "|" .. detail)
			end,
		}
		local callback = listener.callback
		assert(callback, "client never listened")
		callback { runId = "other", kind = "welcome", actor = "client-1" }
		callback { runId = "another", kind = "welcome", actor = "client-1" }
		expect(reports):toEqual { "run_id_mismatch|expected run expected but received other" }
	end)
end)

return nil
