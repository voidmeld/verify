--!strict

local Roblox = require "../src/roblox"
local Core = require "../src/core"
local Lute = require "../src/lute"

return function(suite: Core.Harness)
	suite:suite("place source cache", function()
		suite:case("loads Lute bytecode in isolated environments and refuses malformed JSON", function(check)
			local host = table.clone(Lute.fixture.host)
			host.readFile = function(): string
				return "return subject"
			end
			local cache = Roblox.createPlaceCache(host)
			check:expect(cache.load("module.luau", { subject = "first" })()):toBe "first"
			check:expect(cache.load("module.luau", { subject = "second" })()):toBe "second"
			check
				:expect(host.decodeJson(host.encodeJson { active = false, count = 2 }))
				:toEqual { active = false, count = 2 }
			check:expect((pcall(host.decodeJson, "{"))):toBe(false)
		end)
		suite:case("shares compiled bytes while keeping loaded environments distinct", function(check)
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
			check:expect(cache.load("module.luau", { subject = "first" })()):toBe "first"
			check:expect(cache.load("module.luau", { subject = "second" })()):toBe "second"
			check:expect(reads):toBe(1)
			check:expect(compiled):toBe(1)
		end)
	end)
end
