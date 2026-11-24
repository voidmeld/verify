--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect
local Lute = require "../src/lute"
local Identity = require "../src/lute/studio-identity"
describe("Studio place identity", function()
	it("sets both IDs in Edit and verifies their readback", function()
		local calls: { string } = {}
		local model = { PlaceId = 0, GameId = 0 }
		local source = Identity.source { placeId = 123, universeId = 456 }
		local service = setmetatable({
			GetService = function(_self: unknown, name: string)
				assert(name == "RunService")
				return {
					IsStudio = function()
						return true
					end,
				}
			end,
			SetPlaceId = function(_self: unknown, id: number)
				model.PlaceId = id
				table.insert(calls, "place")
			end,
			SetUniverseId = function(_self: unknown, id: number)
				model.GameId = id
				table.insert(calls, "universe")
			end,
		}, { __index = model })
		local environment: { [string]: unknown } = { assert = assert, game = service }
		local execute = Lute.chunk.load(source, {
			injectGlobals = false,
			environment = environment,
		})
		local result: unknown = execute()
		expect(result):toBe "verify-studio-identity-ok"
		expect(table.concat(calls, ",")):toBe "place,universe"
		expect(model.PlaceId):toBe(123)
		expect(model.GameId):toBe(456)
	end)
	it("rejects missing, extra, fractional and unsafe identity fields", function()
		local inputs: { unknown } = {
			{},
			{ placeId = 1 },
			{ placeId = 1, universeId = 2, other = true },
			{ placeId = 0, universeId = 2 },
			{ placeId = -1, universeId = 2 },
			{ placeId = 1.5, universeId = 2 },
			{ placeId = 1, universeId = math.huge },
			{ placeId = 9007199254740992, universeId = 2 },
			{ placeId = "1", universeId = 2 },
		}
		for _, value in inputs do
			local ok = pcall(Identity.read, value)
			expect(ok):toBe(false)
		end
	end)
	it("refuses identity mutation on a borrowed Studio", function()
		local ok, problem = pcall(function()
			Lute.studio.run {
				identity = { placeId = 123, universeId = 456 },
				attach = {
					studioId = "never-open",
					authorize = function()
						return { ok = false, reason = "No action" }
					end,
				},
				code = "return nil",
			}
		end)
		expect(ok):toBe(false)
		expect(string.find(tostring(problem), "launched disposable", 1, true) ~= nil):toBe(true)
	end)
end)

return nil
