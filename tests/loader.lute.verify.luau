--!strict

local fs = require "@std/fs"

local Datatypes = require "../src/roblox/datatypes"
local Files = require "../src/lute/files"
local Lute = require "../src/lute"
local Verify = require "../src/core"

local ROOT = ".lute/tmp/verify-loader-test"

local function write(path: string, source: string)
	Files.ensureDirectory(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeStringToFile(path, "--!strict\n" .. source)
end

local function failure(run: () -> ()): string
	local ok, problem: unknown = pcall(run)
	assert(not ok, "the call must fail")
	return tostring(problem)
end

return function(suite: Verify.Harness)
	suite:suite("loader", function()
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
			check:expect(rawget(_G :: { [string]: unknown }, "require") == probe.environment.require):toBe(false)
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
	end)
end
