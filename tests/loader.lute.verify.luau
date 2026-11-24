--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local fs = require "@std/fs"

local Datatypes = require "../src/roblox/datatypes"
local Files = require "../src/lute/files"
local Lute = require "../src/lute"
local Shape = require "../src/core/shape"

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

describe("loader", function()
	it("loads an in-memory module tree without host filesystem access", function()
		local sources: { [string]: string } = {
			["memory/app/init.luau"] = 'return { child = require("@self/child"), shared = require("@shared/value") }',
			["memory/app/child.luau"] = 'return require("../shared/value")',
			["memory/shared/value.luau"] = "return {}",
		}
		local reads: { string } = {}
		local loader = Lute.loader.new {
			aliases = { shared = "memory/shared", ["self/child"] = "memory/shared" },
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
		local app = loader.require "memory/app"
		local appFields = Shape.record(app, "app")
		expect(appFields.child == appFields.shared):toBe(true)
		expect(loader.require "memory/app/init.luau" == app):toBe(true)
		expect(#reads):toBe(3)
		expect(failure(function()
			loader.require "memory/absent"
		end)):toContain "no module at memory/absent"
	end)

	it("propagates file host errors and permits a later retry", function()
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
		expect(failure(function()
			loader.require "memory/value"
		end)):toContain "source unavailable"
		ready = true
		expect(loader.require "memory/value"):toBe(42)
	end)

	it("resolves the longest alias at a path boundary, including the alias root", function()
		local sources: { [string]: string } = {
			["memory/app.luau"] = [[return {
root = require("@packages/ui"),
child = require("@packages/ui/child"),
deep = require("@packages/ui/components/leaf"),
sibling = require("@packages/ui-extra"),
}]],
			["memory/ui/init.luau"] = 'return "root"',
			["memory/ui/child.luau"] = 'return "child"',
			["memory/components/leaf.luau"] = 'return "deep"',
			["memory/packages/ui-extra.luau"] = 'return "sibling"',
		}
		local loader = Lute.loader.new {
			aliases = {
				packages = "memory/packages",
				["packages/ui"] = "memory/ui",
				["packages/ui/components"] = "memory/components",
			},
			files = {
				exists = function(path: string): boolean
					return sources[path] ~= nil
				end,
				readFile = function(path: string): string
					return assert(sources[path])
				end,
			},
		}
		local result = loader.require "memory/app"
		local resultFields = Shape.record(result, "result")
		expect(resultFields.root):toBe "root"
		expect(resultFields.child):toBe "child"
		expect(resultFields.deep):toBe "deep"
		expect(resultFields.sibling):toBe "sibling"
	end)

	it("shares module identity across full aliases, short aliases and relative paths", function()
		local sources: { [string]: string } = {
			["memory/app.luau"] = [[local first = require("@packages/ui")
return first == require("@shared") and first == require("./ui")]],
			["memory/ui/init.luau"] = "loaded()\nreturn {}",
		}
		local loads = 0
		local loader = Lute.loader.new {
			aliases = { ["packages/ui"] = "memory/./ui", shared = "memory/ui" },
			globals = {
				loaded = function()
					loads += 1
				end,
			},
			files = {
				exists = function(path: string): boolean
					return sources[path] ~= nil
				end,
				readFile = function(path: string): string
					return assert(sources[path])
				end,
			},
		}
		expect(loader.require "memory/app"):toBe(true)
		expect(loads):toBe(1)
		local first = loader.require "memory/ui"
		expect(first == loader.require "memory/ui/init.luau"):toBe(true)
		expect(loads):toBe(1)
	end)

	it("resolves relative, self and alias requires and loads each module once", function()
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
		local app = loader.require(root .. "/app")
		local appFields = Shape.record(app, "app")
		local child = Shape.record(appFields.child, "child")
		expect(appFields.sibling):toBe "sibling"
		expect(child.shared == appFields.shared):toBe(true)
		expect(loader.require(root .. "/app/init.luau") == app):toBe(true)
		expect(Lute.loader.new().require(root .. "/shared/value") == appFields.shared):toBe(false)
	end)

	it("requires a module on first use without yielding the caller", function()
		local root = ROOT .. "/deferred"
		write(root .. "/app.luau", 'capture(function()\n\treturn require("./later")\nend)\nreturn true\n')
		write(root .. "/later.luau", 'return "later"\n')
		local deferred: (() -> unknown)? = nil
		local loader = Lute.loader.new {
			globals = {
				capture = function(callback: () -> unknown)
					deferred = callback
				end,
			},
		}
		loader.require(root .. "/app")
		local thread = coroutine.create(assert(deferred))
		local ok, value = coroutine.resume(thread)
		expect(ok):toBe(true)
		expect(coroutine.status(thread)):toBe "dead"
		expect(value):toBe "later"
	end)

	it("reads a nested dependency's directory before its deferred require", function()
		local root = ROOT .. "/nested"
		write(root .. "/app/main.luau", 'return require("../lib/entry")\n')
		write(root .. "/lib/entry.luau", 'capture(function()\n\treturn require("./later")\nend)\nreturn true\n')
		write(root .. "/lib/later.luau", 'return "later"\n')
		local deferred: (() -> unknown)? = nil
		local loader = Lute.loader.new {
			globals = {
				capture = function(callback: () -> unknown)
					deferred = callback
				end,
			},
		}
		loader.require(root .. "/app/main")
		local thread = coroutine.create(assert(deferred))
		local ok, value = coroutine.resume(thread)
		expect(ok):toBe(true)
		expect(coroutine.status(thread)):toBe "dead"
		expect(value):toBe "later"
	end)

	it("gives each module the engine typeof, warn and its own environment", function()
		local root = ROOT .. "/engine"
		write(
			root .. "/probe.luau",
			[[
local kind = function(value: unknown): string
	return typeof(value)
end
warn("loaded", 1)
local environment = getfenv(0)
return { vectorKind = kind(vector), numberKind = kind(1), environment = environment,
 own = getfenv(kind), engineTypeof = environment.typeof, moduleRequire = environment.require }
]]
		)
		local probe = Lute.loader.new({ globals = { vector = Datatypes.Vector2.new(1, 2) } }).require(root .. "/probe")
		local probeFields = Shape.record(probe, "probe")
		expect(probeFields.vectorKind):toBe "Vector2"
		expect(probeFields.numberKind):toBe "number"
		expect(probeFields.engineTypeof == Datatypes.typeof):toBe(true)
		expect(type(probeFields.moduleRequire)):toBe "function"
		expect(probeFields.own == probeFields.environment):toBe(true)
		expect(rawget(_G, "require") == probeFields.moduleRequire):toBe(false)
	end)

	it("loads host paths through the host require", function()
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
		expect(loader.require(root .. "/app")):toBe "host value"
		expect(seen):toEqual { root .. "/native/thing" }
	end)

	it("names a cycle, a missing module and an unknown alias", function()
		local root = ROOT .. "/refusals"
		write(root .. "/a.luau", 'return require("./b")\n')
		write(root .. "/b.luau", 'return require("./a")\n')
		write(root .. "/alias.luau", 'return require("@nowhere/x")\n')
		local loader = Lute.loader.new()
		expect(failure(function()
			loader.require(root .. "/a")
		end)):toContain "requires itself through a cycle"
		expect(failure(function()
			loader.require(root .. "/absent")
		end)):toContain "no module at"
		expect(failure(function()
			loader.require(root .. "/alias")
		end)):toContain "unknown alias"
	end)

	it("requires a module through an instance-path reference", function()
		local root = ROOT .. "/references"
		write(root .. "/shared/rules/score.luau", "return { points = 3 }\n")
		write(root .. "/client.luau", "return require(game.ReplicatedStorage.shared.rules.score)\n")
		local holder: { [string]: unknown } = {}
		local loader = Lute.loader.new { globals = holder }
		holder.game = { ReplicatedStorage = { shared = loader.reference(root .. "/shared") } }
		local score = loader.require(root .. "/client")
		local scoreFields = Shape.record(score, "score")
		expect(scoreFields.points):toBe(3)
		expect(loader.require(root .. "/shared/rules/score") == score):toBe(true)
	end)

	it("gives every module the caller's globals and the transformed source", function()
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
		local result = loader.require(root .. "/game")
		local resultFields = Shape.record(result, "result")
		expect(resultFields.service == players):toBe(true)
		expect(resultFields.size):toBe(2)
		expect(requested[1]):toBe "Players"
	end)
end)

return nil
