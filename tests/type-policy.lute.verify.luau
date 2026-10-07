--!strict

local Verify = require "../src/core"
local Policy = require "../src/lute/type-policy"

return function(suite: Verify.Harness)
	suite:case("type policy rejects aliases casts fields and variadic escapes", function(check)
		local source = [[
export type Escape = any
local x: {value: any} = {} :: any
local function f(...: any): ...any return ... end
]]
		check:expect(#Policy.explicitAny(source)):toBe(5)
	end)
	suite:case("type policy permits ordinary text and unknown refinement", function(check)
		local source = [[
local any = "any"
local text = `any {any}`
local value: unknown = 1
local values: {unknown} = {}
]]
		check:expect(#Policy.explicitAny(source)):toBe(0)
	end)
	suite:case("type policy rejects compiler opt-outs but ignores quoted directives", function(check)
		check:expect(#Policy.nonStrict "--!nocheck\nlocal x = 1"):toBe(1)
		check:expect(#Policy.nonStrict "--!nonstrict\nlocal x = 1"):toBe(1)
		check:expect(#Policy.nonStrict 'local text = "--!nocheck"'):toBe(0)
	end)

	suite:case("type policy sees casts inside interpolated expressions", function(check)
		check:expect(#Policy.explicitAny "local text = `{(1 :: any)}`"):toBe(1)
	end)
end
