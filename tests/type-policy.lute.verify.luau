--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Policy = require "../src/lute/type-policy"

it("type policy rejects aliases casts fields and variadic escapes", function()
	local source = [[
export type Escape = any
local x: {value: any} = {} :: any
local function f(...: any): ...any return ... end
]]
	expect(#Policy.explicitAny(source)):toBe(5)
end)
it("type policy permits ordinary text and unknown refinement", function()
	local source = [[
local any = "any"
local text = `any {any}`
local value: unknown = 1
local values: {unknown} = {}
]]
	expect(#Policy.explicitAny(source)):toBe(0)
end)
it("type policy rejects compiler opt-outs but ignores quoted directives", function()
	expect(#Policy.nonStrict "--!nocheck\nlocal x = 1"):toBe(1)
	expect(#Policy.nonStrict "--!nonstrict\nlocal x = 1"):toBe(1)
	expect(#Policy.nonStrict 'local text = "--!nocheck"'):toBe(0)
end)

it("type policy sees casts inside interpolated expressions", function()
	expect(#Policy.explicitAny "local text = `{(1 :: any)}`"):toBe(1)
end)

return nil
