--!strict

local Verify = require "../src/core"
local Experience = require "../src/core/operations"
local RobloxHost = require "../src/roblox/experience-host"

local function engine(now: (() -> number)?): RobloxHost.Engine
	return {
		studio = true,
		context = "server",
		placeId = 0,
		gameId = 0,
		version = "test-engine",
		now = now or function(): number
			return 0
		end,
	}
end

local function wire(actor: string, name: string, payload: unknown): RobloxHost.WireRequest
	return { kind = "action", actor = actor, name = name, payload = payload, remainingSeconds = 1 }
end

local function invocation(actor: string, name: string, payload: unknown): Experience.Request
	return { kind = "action", actor = actor, name = name, payload = payload, deadline = 1 }
end

return function(suite: Verify.Harness)
	suite:suite("Roblox experience reference host", function()
		suite:case("dispatches decoded endpoints and validates engine identity", function(check)
			local visible = true
			local registry: RobloxHost.Registry = {
				actions = {
					visible = RobloxHost.endpoint(function(value: unknown): boolean
						assert(type(value) == "boolean", "expected boolean")
						return value
					end, function(value: boolean): unknown
						visible = value
						return nil
					end, { "native-state" }),
				},
				queries = {
					visible = RobloxHost.endpoint(function(value: unknown): nil
						assert(value == nil, "query takes no payload")
						return nil
					end, function(): unknown
						return visible
					end),
				},
			}
			local host = RobloxHost.create {
				engine = engine(),
				actor = "server",
				actors = { server = "server" },
				registry = registry,
				capabilities = { "native-state" },
			}
			host.invoke(invocation("server", "visible", false))
			check
				:expect(host.invoke { kind = "query", actor = "server", name = "visible", payload = nil, deadline = 1 })
				:toBe(false)
			check:expect(host.environment["roblox.version"]):toBe "test-engine"
			check
				:expect(function()
					host.invoke(invocation("server", "visible", "false"))
				end)
				:toThrow "expected boolean"
			check
				:expect(function()
					RobloxHost.create {
						engine = engine(),
						actor = "client",
						actors = { client = "client" },
						registry = registry,
					}
				end)
				:toThrow "does not match"
		end)

		suite:case("refuses undeclared actors, unavailable operations and capabilities", function(check)
			local host = RobloxHost.create {
				engine = engine(),
				actor = "server",
				actors = { server = "server", client = "client" },
				registry = {
					actions = {
						reserved = RobloxHost.endpoint(function(value: unknown): unknown
							return value
						end, function(value: unknown): unknown
							return value
						end, { "unavailable" }),
					},
					queries = {},
				},
			}
			check
				:expect(function()
					host.invoke(invocation("stranger", "missing", nil))
				end)
				:toThrow "unknown actor"
			check
				:expect(function()
					host.invoke(invocation("server", "missing", nil))
				end)
				:toThrow "unavailable action"
			check
				:expect(function()
					host.invoke(invocation("server", "reserved", nil))
				end)
				:toThrow "unavailable capability"
			check
				:expect(function()
					host.invoke(invocation("client", "reserved", nil))
				end)
				:toThrow "supplied transport"
			check:expect(host.capture):toBe(nil)
			check:expect(host.judge):toBe(nil)
		end)

		suite:case("correlates remote replies and releases transport once", function(check)
			local closed = 0
			local wrong = false
			local host = RobloxHost.create {
				engine = engine(),
				actor = "server",
				actors = { server = "server", client = "client" },
				registry = { actions = {}, queries = {} },
				transport = {
					exchange = function(envelope: RobloxHost.Envelope): unknown
						return {
							id = if wrong then "other" else envelope.id,
							actor = "client",
							kind = envelope.request.kind,
							name = envelope.request.name,
							ok = true,
							value = 7,
						}
					end,
					close = function()
						closed += 1
					end,
				},
			}
			check:expect(host.invoke(invocation("client", "answer", nil))):toBe(7)
			wrong = true
			check
				:expect(function()
					host.invoke(invocation("client", "answer", nil))
				end)
				:toThrow "correlation mismatch"
			assert(host.close ~= nil)
			host.close()
			host.close()
			check:expect(closed):toBe(1)
			check
				:expect(function()
					host.invoke(invocation("client", "answer", nil))
				end)
				:toThrow "host is closed"
		end)

		suite:case("rejects stale work and late responses", function(check)
			local clock = 1
			local called = 0
			local host = RobloxHost.create {
				engine = engine(function(): number
					return clock
				end),
				actor = "server",
				actors = { server = "server" },
				registry = {
					actions = {
						advance = RobloxHost.endpoint(function(value: unknown): unknown
							return value
						end, function(): unknown
							called += 1
							clock = 1
							return nil
						end),
					},
					queries = {},
				},
			}
			check
				:expect(function()
					host.invoke(invocation("server", "advance", nil))
				end)
				:toThrow "deadline expired"
			check:expect(called):toBe(0)
			clock = 0
			check
				:expect(function()
					host.invoke(invocation("server", "advance", nil))
				end)
				:toThrow "exceeded its deadline"
			check:expect(called):toBe(1)
		end)

		suite:case("binds remote caller authority separately from request fields", function(check)
			local trusted = {}
			local calls = 0
			local responder = RobloxHost.remoteResponder(
				{
					actions = {
						act = RobloxHost.endpoint(function(value: unknown): unknown
							return value
						end, function(): unknown
							calls += 1
							return "done"
						end),
					},
					queries = {},
				},
				{},
				function(): number
					return 0
				end,
				"server",
				function(caller: unknown): boolean
					return caller == trusted
				end
			)
			local envelope: RobloxHost.Envelope = { id = "client:1", request = wire("server", "act", nil) }
			check
				:expect(function()
					responder({ caller = trusted }, envelope)
				end)
				:toThrow "unauthorized"
			check:expect(calls):toBe(0)
			check:expect(responder(trusted, envelope).value):toBe "done"
			envelope.request.actor = "client"
			check
				:expect(function()
					responder(trusted, envelope)
				end)
				:toThrow "wrong actor"
			check:expect(calls):toBe(1)
		end)

		suite:case("uses a receiver-local budget and bounds nested requests", function(check)
			local registry: RobloxHost.Registry = {
				actions = {
					act = RobloxHost.endpoint(function(value: unknown): unknown
						return value
					end, function(): unknown
						return "done"
					end),
				},
				queries = {},
			}
			local reply = RobloxHost.respond(registry, {}, function(): number
				return 1000
			end, "server", { id = "client:1", request = wire("server", "act", nil) })
			check:expect(reply.value):toBe "done"
			local host: Experience.Host? = nil
			registry.actions.nested = RobloxHost.endpoint(function(value: unknown): unknown
				return value
			end, function(): unknown
				return (host :: Experience.Host).invoke(invocation("server", "act", nil))
			end)
			host = RobloxHost.create {
				engine = engine(),
				actor = "server",
				actors = { server = "server" },
				registry = registry,
				maxInFlight = 1,
			}
			check
				:expect(function()
					(host :: Experience.Host).invoke(invocation("server", "nested", nil))
				end)
				:toThrow "in-flight"
			check:expect((host :: Experience.Host).invoke(invocation("server", "act", nil))):toBe "done"
			check:expect(table.find((host :: Experience.Host).capabilities, "action:act") ~= nil):toBe(true)
		end)

		suite:case("routes RemoteFunction calls by actual server/client direction", function(check)
			local chosen: unknown = nil
			local remote: RobloxHost.Remote = {
				InvokeServer = function(_: RobloxHost.Remote, envelope: RobloxHost.Envelope): unknown
					return envelope.id
				end,
				InvokeClient = function(_: RobloxHost.Remote, player: unknown, envelope: RobloxHost.Envelope): unknown
					chosen = player
					return envelope.id
				end,
			}
			local actors: { [string]: RobloxHost.Context } = { server = "server", client = "client" }
			local client = RobloxHost.remoteTransport("client", remote, actors)
			check:expect(client.exchange { id = "client:1", request = wire("server", "act", nil) }):toBe "client:1"
			check
				:expect(function()
					client.exchange { id = "client:2", request = wire("client", "act", nil) }
				end)
				:toThrow "only routes to the server"
			local player = {}
			local server = RobloxHost.remoteTransport("server", remote, actors, function(): unknown
				return player
			end)
			check:expect(server.exchange { id = "server:1", request = wire("client", "act", nil) }):toBe "server:1"
			check:expect(chosen):toBe(player)
		end)
	end)
end
