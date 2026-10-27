--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"
local Core = require "../src/core"
local Eval = require "../src/agent-eval"

type ConsumerTypes = {
	instance: Lute.ModelInstance?,
	gate: Lute.GateOptions?,
	launched: Lute.StudioLaunched?,
	event: Roblox.EnvironmentEvent?,
	class: Roblox.EnvironmentClass?,
	shard: Core.ShardPayload?,
	verdict: Eval.Verdict?,
}

describe("consumer surface", function()
	it("keeps the types and helpers that consumers import", function()
		local types: ConsumerTypes = {}
		expect(next(types)):toBeNil()
		expect(Lute.typePolicy.explicitAny "local value: any = 1"):toEqual { 1 }
		expect(Lute.typePolicy.explicitAny "local value: number = 1"):toEqual {}
	end)
end)

return nil
