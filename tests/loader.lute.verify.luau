--!strict

local fs = require "@std/fs"

local Datatypes = require "../src/roblox/datatypes"
local Files = require "../src/lute/files"
local Lute = require "../src/lute"
local Verify = require "../src/core"

local ROOT = ".lute/tmp/verify-loader-test"

local function write(path: string, source: string)
	Files.ensureDirectory(assert(string.match(path, "^(.*)/[^/]+$")))
	fs.writeStringToFile(path, "--!strict\n" .. source)
end

local function failure(run: () -> ()): string
	local ok, problem: unknown = pcall(run)
	assert(not ok, "the call must fail")
	return tostring(problem)
end

return function(suite: Verify.Harness)
	suite:suite("loader", function()
		suite:case("loads an in-memory module tree without host filesystem access", function(check)
			local sources: { [string]: string } = {
				["memory/app/init.luau"] = 'return { child = require("@self/child"), shared = require("@shared/value") }',
				["memory/app/child.luau"] = 'return require("../shared/value")',
				["memory/shared/value.luau"] = "return {}",
			}
			local reads: { string } = {}
			local loader = Lute.loader.new {
				aliases = { shared = "memory/shared" },
				files = {
					exists = function(path: string): boolean
						return sources[path] ~= nil
					end,
					readFile = function(path: string): string
						table.insert(reads, path)
						return assert(sources[path])
					end,
				},
			}
			local app = loader.require "memory/app" :: { child: unknown, shared: unknown }
			check:expect(app.child == app.shared):toBe(true)
			check:expect(loader.require "memory/app/init.luau" == app):toBe(true)
			check:expect(#reads):toBe(3)
			check
				:expect(failure(function()
					loader.require "memory/absent"
				end))
				:toContain "no module at memory/absent"
		end)

		suite:case("propagates file host errors and permits a later retry", function(check)
			local ready = false
			local loader = Lute.loader.new {
				files = {
					exists = function(): boolean
						return true
					end,
					readFile = function(): string
						assert(ready, "source unavailable")
						return "return 42"
					end,
				},
			}
			check
				:expect(failure(function()
					loader.require "memory/value"
				end))
				:toContain "source unavailable"
			ready = true
			check:expect(loader.require "memory/value"):toBe(42)
		end)

		suite:case("resolves relative, self and alias requires and loads each module once", function(check)
			local root = ROOT .. "/graph"
			write(
				root .. "/app/init.luau",
				[[
local Child = require("@self/child")
local Shared = require("@shared/value")
local Sibling = require("./sibling")
return { child = Child, shared = Shared, sibling = Sibling }
]]
			)
			write(root .. "/app/child.luau", 'return { shared = require("../shared/value") }\n')
			write(root .. "/shared/value.luau", "return { count = 1 }\n")
			write(root .. "/sibling.luau", 'return "sibling"\n')
			local loader = Lute.loader.new { aliases = { shared = root .. "/shared" } }
			local app =
				loader.require(root .. "/app") :: { child: { shared: unknown }, shared: unknown, sibling: string }
			check:expect(app.sibling):toBe "sibling"
			check:expect(app.child.shared == app.shared):toBe(true)
			check:expect(loader.require(root .. "/app/init.luau") == app):toBe(true)
			check:expect(Lute.loader.new().require(root .. "/shared/value") == app.shared):toBe(false)
		end)

		suite:case("gives each module the engine typeof, warn and its own environment", function(check)
			local root = ROOT .. "/engine"
			write(
				root .. "/probe.luau",
				[[
local kind = function(value: unknown): string
	return typeof(value)
end
warn("loaded", 1)
return { kind = kind, environment = getfenv(0), own = getfenv(kind) }
]]
			)
			local probe = Lute.loader.new().require(root .. "/probe") :: {
				kind: (unknown) -> string,
				environment: { [string]: unknown },
				own: { [string]: unknown },
			}
			check:expect(probe.kind(Datatypes.Vector2.new(1, 2))):toBe "Vector2"
			check:expect(probe.kind(1)):toBe "number"
			check:expect(probe.environment.typeof == Datatypes.typeof):toBe(true)
			check:expect(type(probe.environment.require)):toBe "function"
			check:expect(probe.own == probe.environment):toBe(true)
			check:expect(rawget(_G, "require") == probe.environment.require):toBe(false)
		end)

		suite:case("loads host paths through the host require", function(check)
			local root = ROOT .. "/host"
			write(root .. "/native/thing.luau", 'return "unused"\n')
			write(root .. "/app.luau", 'return require("./native/thing")\n')
			local seen: { string } = {}
			local loader = Lute.loader.new {
				hostPaths = { root .. "/native/" },
				requireHost = function(module: string): unknown
					table.insert(seen, module)
					return "host value"
				end,
			}
			check:expect(loader.require(root .. "/app")):toBe "host value"
			check:expect(seen):toEqual { root .. "/native/thing" }
		end)

		suite:case("names a cycle, a missing module and an unknown alias", function(check)
			local root = ROOT .. "/refusals"
			write(root .. "/a.luau", 'return require("./b")\n')
			write(root .. "/b.luau", 'return require("./a")\n')
			write(root .. "/alias.luau", 'return require("@nowhere/x")\n')
			local loader = Lute.loader.new()
			check
				:expect(failure(function()
					loader.require(root .. "/a")
				end))
				:toContain "requires itself through a cycle"
			check
				:expect(failure(function()
					loader.require(root .. "/absent")
				end))
				:toContain "no module at"
			check
				:expect(failure(function()
					loader.require(root .. "/alias")
				end))
				:toContain "unknown alias"
		end)

		suite:case("requires a module through an instance-path reference", function(check)
			local root = ROOT .. "/references"
			write(root .. "/shared/rules/score.luau", "return { points = 3 }\n")
			write(root .. "/client.luau", "return require(game.ReplicatedStorage.shared.rules.score)\n")
			local holder: { [string]: unknown } = {}
			local loader = Lute.loader.new { globals = holder }
			holder.game = { ReplicatedStorage = { shared = loader.reference(root .. "/shared") } }
			local score = loader.require(root .. "/client") :: { points: number }
			check:expect(score.points):toBe(3)
			check:expect(loader.require(root .. "/shared/rules/score") == score):toBe(true)
		end)

		suite:case("gives every module the caller's globals and the transformed source", function(check)
			local root = ROOT .. "/globals"
			write(root .. "/game.luau", 'return { service = game:GetService("Players"), size = SIZE }\n')
			local requested: { string } = {}
			local players = { name = "Players" }
			local fakeGame = {
				GetService = function(_self: unknown, name: string): unknown
					table.insert(requested, name)
					return players
				end,
			}
			local globals: { [string]: unknown } = { game = fakeGame, SIZE = 1 }
			local loader = Lute.loader.new {
				globals = globals,
				transform = function(path: string, source: string): string
					return if string.find(path, "game.luau", 1, true)
						then string.gsub(source, "SIZE", "SIZE + 1")
						else source
				end,
			}
			local result = loader.require(root .. "/game") :: { service: unknown, size: number }
			check:expect(result.service == players):toBe(true)
			check:expect(result.size):toBe(2)
			check:expect(requested[1]):toBe "Players"
		end)
	end)
end
