--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

describe("place source cache", function()
	it("loads Lute bytecode in isolated environments and refuses malformed JSON", function()
		local host = table.clone(Lute.fixture.host)
		host.readFile = function(): string
			return "return subject"
		end
		local cache = Roblox.createPlaceCache(host)
		expect(cache.load("module.luau", { subject = "first" })()):toBe "first"
		expect(cache.load("module.luau", { subject = "second" })()):toBe "second"
		expect(host.decodeJson(host.encodeJson { active = false, count = 2 })):toEqual { active = false, count = 2 }
		expect((pcall(host.decodeJson, "{"))):toBe(false)
	end)
	it("shares compiled bytes while keeping loaded environments distinct", function()
		local reads, compiled = 0, 0
		local cache = Roblox.createPlaceCache {
			readFile = function(path: string): string
				assert(path == "module.luau")
				reads += 1
				return "subject"
			end,
			compile = function(source: string): string
				compiled += 1
				return source
			end,
			load = function(source: string, name: string, environment: { [string]: unknown }): () -> unknown
				assert(source == "subject" and name == "@module.luau")
				return function(): unknown
					return environment.subject
				end
			end,
			encodeJson = function(): string
				error "unused"
			end,
			decodeJson = function(): unknown
				error "unused"
			end,
		}
		expect(cache.load("module.luau", { subject = "first" })()):toBe "first"
		expect(cache.load("module.luau", { subject = "second" })()):toBe "second"
		expect(reads):toBe(1)
		expect(compiled):toBe(1)
	end)
end)

return nil
