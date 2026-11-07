--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"
local Core = require "../src/core"
local Eval = require "../src/agent-eval"
local Consumer = require "../src/consumer"

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

return nil
