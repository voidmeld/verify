--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

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

describe("isolated network contexts", function()
	it("server and clients own distinct objects, signals and virtual time", function()
		local network = Network.create { clients = { "first", "second" } }
		local server = network.server.environment
		local first = network.clients.first.environment
		local second = network.clients.second.environment
		expect(server.root ~= first.root and first.root ~= second.root):toEqual(true)
		server.createInstance("Folder", { Name = "OnlyServer", Parent = server.root })
		first.createInstance("Folder", { Name = "OnlyFirst", Parent = first.root })
		expect(#server.root:GetChildren()):toEqual(1)
		expect(#first.root:GetChildren()):toEqual(1)
		expect(#second.root:GetChildren()):toEqual(0)
		local fired = 0
		first.heartbeat:Connect(function()
			fired += 1
		end)
		server.step(2)
		expect(first.now()):toEqual(0)
		expect(fired):toEqual(0)
		network.advance(3)
		expect(network.now()):toEqual(3)
		expect(server.now()):toEqual(2)
		expect(second.now()):toEqual(0)
	end)

	it("queued delivery orders due time then send sequence and binds the actual client sender", function()
		local network = Network.create { clients = { "first", "second" }, latency = 1 }
		local observed: { string } = {}
		network.server.onMessage(function(sender: string, message: Network.Message)
			table.insert(observed, sender .. ":" .. tostring(message.payload))
		end)
		local first = network.clients.first
		first.id = "spoofed"
		expect(first.send(packet "later", 2).ok):toEqual(true)
		expect(network.clients.second.send(packet "earlier").ok):toEqual(true)
		expect(first.send(packet "tie").ok):toEqual(true)
		expect(#observed):toEqual(0)
		local early = network.advance(0.5)
		assert(early.ok)
		expect(early.delivered):toEqual(0)
		local ready = network.advance(0.5)
		assert(ready.ok)
		expect(ready.delivered):toEqual(2)
		expect(observed):toEqual { "second:earlier", "first:tie" }
		network.advance(1)
		expect(observed[3]):toEqual "first:later"
		expect(network.pending()):toEqual(0)
	end)

	it("payloads are cloned when queued and again for each listener and destination", function()
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
		expect(observed):toEqual { "queued" }
		expect(nested.value):toEqual "source mutation"
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
		expect(firstValue):toEqual "source mutation"
		expect(secondValue):toEqual "source mutation"
		expect(nested.value):toEqual "source mutation"
	end)

	it("disconnect drops both directions, disconnects handles and refuses later sends", function()
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
		expect(disconnected.dropped):toEqual(2)
		expect(connection.Connected):toEqual(false)
		connection:Disconnect()
		expect(network.isConnected "first"):toEqual(false)
		expect(refusal(network.clients.first.send(packet "up")).reason):toEqual "client_disconnected"
		expect(refusal(network.server.send("first", packet "down")).reason):toEqual "client_disconnected"
		expect(refusal(network.server.send("absent", packet "down")).reason):toEqual "unknown_client"
		expect(refusal(network.disconnect "absent").reason):toEqual "unknown_client"
		local again = network.disconnect "first"
		assert(again.ok)
		expect(again.dropped):toEqual(0)
		network.advance(1)
		expect(observed):toEqual(1)
		local subscribed = pcall(function()
			network.clients.first.onMessage(function() end)
		end)
		expect(subscribed):toEqual(false)
		expect(network.clients.first.environment.liveConnections()):toEqual(0)
	end)

	it("delivery snapshots bound callback sends and observe a disconnect during the batch", function()
		local network = Network.create { clients = { "first", "second" } }
		local reached = 0
		network.server.onMessage(function(sender: string)
			if sender == "first" then
				expect(refusal(network.advance(0)).reason):toEqual "delivery_in_progress"
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
		expect(first.delivered):toEqual(1)
		expect(first.dropped):toEqual(1)
		expect(first.pending):toEqual(1)
		expect(reached):toEqual(0)
		network.advance(0)
		expect(reached):toEqual(1)
		expect(#network.server.environment.errors):toEqual(0)
	end)

	it("invalid payloads and clocks refuse without queuing or advancing", function()
		local network = Network.create { clients = { "first" } }
		local invalid: { unknown } = { math.huge, function() end, { [2] = "sparse" }, { [1] = "mixed", key = "mixed" } }
		local cycle: { [string]: unknown } = {}
		cycle.self = cycle
		table.insert(invalid, cycle)
		table.insert(invalid, setmetatable({}, {}))
		table.insert(invalid, network.server.environment.root)
		for _, payload in invalid do
			local outcome = network.clients.first.send(packet(payload :: Network.Payload))
			expect(refusal(outcome).reason):toEqual "invalid_payload"
		end
		expect(refusal(network.clients.first.send(packet "ok", -1)).reason):toEqual "invalid_latency"
		expect(refusal(network.clients.first.send { channel = "", payload = "ok" }).reason):toEqual "invalid_channel"
		expect(refusal(network.advance(-1)).reason):toEqual "invalid_step"
		expect(refusal(network.advance(math.huge)).reason):toEqual "invalid_step"
		expect(network.now()):toEqual(0)
		expect(network.pending()):toEqual(0)
	end)

	it("handler failures are recorded in the receiving environment and later handlers still run", function()
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
		expect(reached):toEqual(true)
		expect(#network.server.environment.errors):toEqual(1)
		expect(network.server.environment.errors[1]):toContain "server handler failed"
		expect(#network.clients.first.environment.errors):toEqual(0)
	end)
end)

return nil
