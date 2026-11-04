--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"
local Core = require "../src/core"
local Eval = require "../src/agent-eval"
local Consumer = require "../src/consumer"
local Network = require "../src/roblox/network"
local Environment = require "../src/roblox/environment"

type ConsumerTypes = {
	instance: Lute.ModelInstance?,
	gate: Lute.GateOptions?,
	launched: Lute.StudioLaunched?,
	event: Roblox.EnvironmentEvent?,
	class: Roblox.EnvironmentClass?,
	layoutOptions: Roblox.UiLayoutOptions?,
	layoutController: Roblox.UiLayoutController?,
	shard: Core.ShardPayload?,
	verdict: Eval.Verdict?,
}

describe("consumer surface", function()
	it("keeps the types and helpers that consumers import", function()
		local _types: ConsumerTypes = {}
		expect(Lute.typePolicy.explicitAny "local value: any = 1"):toEqual { 1 }
		expect(Lute.typePolicy.explicitAny "local value: number = 1"):toEqual {}
	end)
	it("refuses a scan without a ruleset", function()
		expect(pcall(Lute.chunk.load('return Consumer.scan("return nil", "case.verify.luau", {})', {
			environment = { Consumer = Consumer },
		}))):toEqual(false)
	end)

	it("refuses a call missing listDir or readFile", function()
		expect(pcall(Lute.chunk.load('return Consumer.scanTree(".", {})', {
			environment = { Consumer = Consumer },
		}))):toEqual(false)
	end)
end)

describe("matcher runtime input validation", function()
	it("requires the authored float32 number", function()
		local _, misuse: unknown =
			pcall(Lute.chunk.load('Core.expect(0.55):toBeFloat32("0.55")', { environment = { Core = Core } }))
		expect(tostring(misuse)):toContain "requires the authored number"
	end)

	it("locates runtime matcher misuse at the calling source", function()
		local ok, misuse: unknown = pcall(
			Lute.chunk.load(
				'Core.expect(1):toBeNear(1, "wide")',
				{ name = "tests/core.verify.luau", environment = { Core = Core } }
			)
		)
		expect(ok):toEqual(false)
		expect(tostring(misuse)):toContain "core.verify.luau"
	end)

	it("names an unknown matcher instead of failing as a nil call", function()
		local ok, thrown: unknown =
			pcall(Lute.chunk.load("Core.expect(true):toBeTrue()", { environment = { Core = Core } }))
		assert(not ok)
		expect(tostring(thrown)):toContain 'unknown matcher "toBeTrue"'
	end)
end)

describe("network runtime input validation", function()
	it("invalid payloads and clocks refuse without queuing or advancing", function()
		local network = Network.create { clients = { "first" } }
		local invalid: { unknown } = { math.huge, function() end, { [2] = "sparse" }, { [1] = "mixed", key = "mixed" } }
		local cycle: { [string]: unknown } = {}
		cycle.self = cycle
		table.insert(invalid, cycle)
		table.insert(invalid, setmetatable({}, {}))
		table.insert(invalid, network.server.environment.root)
		for _, payload in invalid do
			local outcome = Lute.chunk.load('return send { channel = "test", payload = payload }', {
				environment = { send = network.clients.first.send, payload = payload },
			})()
			expect(Environment.read(outcome, "ok")):toEqual(false)
			expect(Environment.read(outcome, "reason")):toEqual "invalid_payload"
		end
		expect(Environment.read(network.clients.first.send({ channel = "test", payload = "ok" }, -1), "reason")):toEqual "invalid_latency"
		expect(Environment.read(network.clients.first.send { channel = "", payload = "ok" }, "reason")):toEqual "invalid_channel"
		expect(Environment.read(network.advance(-1), "reason")):toEqual "invalid_step"
		expect(Environment.read(network.advance(math.huge), "reason")):toEqual "invalid_step"
		expect(network.now()):toEqual(0)
		expect(network.pending()):toEqual(0)
	end)
end)

return nil
