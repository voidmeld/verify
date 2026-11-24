--!strict

local Test = require "./harness"
local Lute = require "../src/lute"
local Vm = require "../src/roblox/value"
local expect, it = Test.expect, Test.it

local function field(value: unknown, name: string): unknown
	assert(type(value) == "table")
	for key, child in value do
		if key == name then
			return child
		end
	end
	return nil
end

it("messaging defers isolated payloads to current topic subscribers", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local env = engine.environment
	local service = engine.service "MessagingService"
	local subscribe, publish = env.method(service, "SubscribeAsync"), env.method(service, "PublishAsync")
	local received: { unknown } = {}
	local first = subscribe(service, "updates", function(message: unknown)
		table.insert(received, message)
		local data = field(message, "Data")
		assert(type(data) == "table")
		table.clear(data)
	end)
	local other: { unknown } = {}
	local second = subscribe(service, "updates", function(message: unknown)
		table.insert(other, message)
	end)
	local absent = subscribe(service, "other", function()
		error "wrong topic"
	end)
	local payload = { nested = { value = 1 } }
	env.step(3.5)
	publish(service, "updates", payload)
	payload.nested.value = 2
	expect(received):toEqual {}
	local late = subscribe(service, "updates", function()
		error "late subscription received old message"
	end)
	env.scheduler.drain(8)
	expect(#received):toBe(1)
	expect(other):toEqual { { Data = { nested = { value = 1 } }, Sent = 3 } }
	for _, value in { first, second, absent, late } do
		assert(type(value) == "table")
		local disconnect = field(value, "Disconnect")
		assert(type(disconnect) == "function")
		Vm.invoke(Vm.value(disconnect), value)
	end
	publish(service, "updates", false)
	env.scheduler.drain(8)
	expect(#received):toBe(1)
	expect(env.errors):toEqual {}
	expect(env.liveConnections()):toBe(0)
end)

it("messaging rejects invalid topics and payloads and cancels queued delivery", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local env, service = engine.environment, engine.service "MessagingService"
	local publish, subscribe = env.method(service, "PublishAsync"), env.method(service, "SubscribeAsync")
	for _, topic in { "", string.rep("x", 81) } do
		expect(pcall(publish, service, topic, {})):toBe(false)
	end
	local cyclic: { [string]: unknown } = {}
	cyclic.self = cyclic
	for _, payload in
		{ cyclic, { object = engine.newInstance "Part" }, { callback = function() end }, { number = math.huge } }
	do
		expect(pcall(publish, service, "updates", payload)):toBe(false)
	end
	local called = 0
	local connection = subscribe(service, "updates", function()
		called += 1
	end)
	assert(type(connection) == "table")
	local disconnect = field(connection, "Disconnect")
	assert(type(disconnect) == "function")
	publish(service, "updates", true)
	Vm.invoke(Vm.value(disconnect), connection)
	env.scheduler.drain(8)
	expect(called):toBe(0)
	subscribe(service, "updates", function()
		called += 1
	end)
	publish(service, "updates", true)
	service:Destroy()
	env.scheduler.drain(8)
	expect(called):toBe(0)
	expect(env.liveConnections()):toBe(0)
	local isolated = Lute.fixture.bridge().placeEngine()
	isolated.environment.method(isolated.service "MessagingService", "PublishAsync")(
		isolated.service "MessagingService",
		"updates",
		{}
	)
	expect(called):toBe(0)
end)

return nil
