--!strict

local Roblox = require "../src/roblox"
local Core = require "../src/core"

return function(suite: Core.Harness)
	suite:suite("place source cache", function()
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
