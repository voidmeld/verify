--!strict

local Verify = require "../src/core"
local Network = require "../src/roblox/network"

type Dictionary = { [string]: Network.Payload }

local function packet(payload: Network.Payload): Network.Message
	return { channel = "test", payload = payload }
end

local function refusal(
	outcome: Network.SendOutcome | Network.DeliveryOutcome | Network.DisconnectOutcome
): Network.Refusal
	assert(not outcome.ok)
	return outcome
end

return function(suite: Verify.Harness)
	suite:suite("isolated network contexts", function()
		suite:case("server and clients own distinct objects, signals and virtual time", function(check)
			local network = Network.create { clients = { "first", "second" } }
			local server = network.server.environment
			local first = network.clients.first.environment
			local second = network.clients.second.environment
			check:expect(server.root ~= first.root and first.root ~= second.root):toEqual(true)
			server.createInstance("Folder", { Name = "OnlyServer", Parent = server.root })
			first.createInstance("Folder", { Name = "OnlyFirst", Parent = first.root })
			check:expect(#server.root:GetChildren()):toEqual(1)
			check:expect(#first.root:GetChildren()):toEqual(1)
			check:expect(#second.root:GetChildren()):toEqual(0)
			local fired = 0
			first.heartbeat:Connect(function()
				fired += 1
			end)
			server.step(2)
			check:expect(first.now()):toEqual(0)
			check:expect(fired):toEqual(0)
			network.advance(3)
			check:expect(network.now()):toEqual(3)
			check:expect(server.now()):toEqual(2)
			check:expect(second.now()):toEqual(0)
		end)

		suite:case(
			"queued delivery orders due time then send sequence and binds the actual client sender",
			function(check)
				local network = Network.create { clients = { "first", "second" }, latency = 1 }
				local observed: { string } = {}
				network.server.onMessage(function(sender: string, message: Network.Message)
					table.insert(observed, sender .. ":" .. tostring(message.payload))
				end)
				local first = network.clients.first
				first.id = "spoofed"
				check:expect(first.send(packet "later", 2).ok):toEqual(true)
				check:expect(network.clients.second.send(packet "earlier").ok):toEqual(true)
				check:expect(first.send(packet "tie").ok):toEqual(true)
				check:expect(#observed):toEqual(0)
				local early = network.advance(0.5)
				assert(early.ok)
				check:expect(early.delivered):toEqual(0)
				local ready = network.advance(0.5)
				assert(ready.ok)
				check:expect(ready.delivered):toEqual(2)
				check:expect(observed):toEqual { "second:earlier", "first:tie" }
				network.advance(1)
				check:expect(observed[3]):toEqual "first:later"
				check:expect(network.pending()):toEqual(0)
			end
		)

		suite:case("payloads are cloned when queued and again for each listener and destination", function(check)
			local network = Network.create { clients = { "first", "second" } }
			local nested: Dictionary = { value = "queued" }
			local payload: Dictionary = { nested = nested }
			local observed: { string } = {}
			network.server.onMessage(function(_sender: string, message: Network.Message)
				((message.payload :: Dictionary).nested :: Dictionary).value = "listener mutation"
			end)
			network.server.onMessage(function(_sender: string, message: Network.Message)
				table.insert(observed, tostring(((message.payload :: Dictionary).nested :: Dictionary).value))
			end)
			network.clients.first.send(packet(payload))
			nested.value = "source mutation"
			network.advance(0)
			check:expect(observed):toEqual { "queued" }
			check:expect(nested.value):toEqual "source mutation"
			local firstValue = ""
			local secondValue = ""
			network.clients.first.onMessage(function(message: Network.Message)
				local copy = (message.payload :: Dictionary).nested :: Dictionary
				firstValue = tostring(copy.value)
				copy.value = "first mutation"
			end)
			network.clients.second.onMessage(function(message: Network.Message)
				secondValue = tostring(((message.payload :: Dictionary).nested :: Dictionary).value)
			end)
			network.server.send("first", packet(payload))
			network.server.send("second", packet(payload))
			network.advance(0)
			check:expect(firstValue):toEqual "source mutation"
			check:expect(secondValue):toEqual "source mutation"
			check:expect(nested.value):toEqual "source mutation"
		end)

		suite:case("disconnect drops both directions, disconnects handles and refuses later sends", function(check)
			local network = Network.create { clients = { "first", "second" }, latency = 1 }
			local observed = 0
			local connection = network.clients.first.onMessage(function()
				observed += 1
			end)
			network.server.onMessage(function()
				observed += 1
			end)
			network.clients.first.send(packet "up")
			network.server.send("first", packet "down")
			network.clients.second.send(packet "retained")
			local disconnected = network.disconnect "first"
			assert(disconnected.ok)
			check:expect(disconnected.dropped):toEqual(2)
			check:expect(connection.Connected):toEqual(false)
			connection:Disconnect()
			check:expect(network.isConnected "first"):toEqual(false)
			check:expect(refusal(network.clients.first.send(packet "up")).reason):toEqual "client_disconnected"
			check:expect(refusal(network.server.send("first", packet "down")).reason):toEqual "client_disconnected"
			check:expect(refusal(network.server.send("absent", packet "down")).reason):toEqual "unknown_client"
			check:expect(refusal(network.disconnect "absent").reason):toEqual "unknown_client"
			local again = network.disconnect "first"
			assert(again.ok)
			check:expect(again.dropped):toEqual(0)
			network.advance(1)
			check:expect(observed):toEqual(1)
			local subscribed = pcall(function()
				network.clients.first.onMessage(function() end)
			end)
			check:expect(subscribed):toEqual(false)
			check:expect(network.clients.first.environment.liveConnections()):toEqual(0)
		end)

		suite:case("delivery snapshots bound callback sends and observe a disconnect during the batch", function(check)
			local network = Network.create { clients = { "first", "second" } }
			local reached = 0
			network.server.onMessage(function(sender: string)
				if sender == "first" then
					check:expect(refusal(network.advance(0)).reason):toEqual "delivery_in_progress"
					network.disconnect "second"
					network.server.send("first", packet "reply")
				end
			end)
			network.clients.first.onMessage(function()
				reached += 1
			end)
			network.clients.first.send(packet "first")
			network.clients.second.send(packet "second")
			local first = network.advance(0)
			assert(first.ok)
			check:expect(first.delivered):toEqual(1)
			check:expect(first.dropped):toEqual(1)
			check:expect(first.pending):toEqual(1)
			check:expect(reached):toEqual(0)
			network.advance(0)
			check:expect(reached):toEqual(1)
			check:expect(#network.server.environment.errors):toEqual(0)
		end)

		suite:case("invalid payloads and clocks refuse without queuing or advancing", function(check)
			local network = Network.create { clients = { "first" } }
			local invalid: { unknown } =
				{ math.huge, function() end, { [2] = "sparse" }, { [1] = "mixed", key = "mixed" } }
			local cycle: { [string]: unknown } = {}
			cycle.self = cycle
			table.insert(invalid, cycle)
			table.insert(invalid, setmetatable({}, {}))
			table.insert(invalid, network.server.environment.root)
			for _, payload in invalid do
				local outcome = network.clients.first.send(packet(payload :: Network.Payload))
				check:expect(refusal(outcome).reason):toEqual "invalid_payload"
			end
			check:expect(refusal(network.clients.first.send(packet "ok", -1)).reason):toEqual "invalid_latency"
			check
				:expect(refusal(network.clients.first.send { channel = "", payload = "ok" }).reason)
				:toEqual "invalid_channel"
			check:expect(refusal(network.advance(-1)).reason):toEqual "invalid_step"
			check:expect(refusal(network.advance(math.huge)).reason):toEqual "invalid_step"
			check:expect(network.now()):toEqual(0)
			check:expect(network.pending()):toEqual(0)
		end)

		suite:case(
			"handler failures are recorded in the receiving environment and later handlers still run",
			function(check)
				local network = Network.create { clients = { "first" } }
				local reached = false
				network.server.onMessage(function()
					error "server handler failed"
				end)
				network.server.onMessage(function()
					reached = true
				end)
				network.clients.first.send(packet(false))
				network.advance(0)
				check:expect(reached):toEqual(true)
				check:expect(#network.server.environment.errors):toEqual(1)
				check:expect(network.server.environment.errors[1]):toContain "server handler failed"
				check:expect(#network.clients.first.environment.errors):toEqual(0)
			end
		)
	end)
end
