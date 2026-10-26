--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local fs = require "@std/fs"
local process = require "@std/process"
local parser = require "@std/syntax/parser"
local syntax = require "@std/syntax"
local Checks = require "../src/checks"

local function fixture(body: (string) -> ())
	Checks.temporaryDirectory.run(Checks.temporaryDirectory.root(), "checks-spec", function(root)
		body(root)
		return true
	end)
end

local function write(root: string, path: string, source: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent ~= nil then
		fs.createDirectory(root .. "/" .. parent, { makeParents = true })
	end
	fs.writeStringToFile(root .. "/" .. path, source)
end

local function git(root: string, args: { string })
	local argv = {
		"git",
		"-c",
		"safe.directory=*",
		"-c",
		"user.name=voidmeld",
		"-c",
		"user.email=158495725+voidmeld@users.noreply.github.com",
	}
	for _, arg in args do
		table.insert(argv, arg)
	end
	local result = process.run(argv, { cwd = root })
	assert(result.ok, result.stdout .. result.stderr)
end

it("checks walk sorts files skips subtrees and reports lines", function()
	fixture(function(root)
		write(root, "b.luau", "b")
		write(root, "a/nested.luau", "nested")
		write(root, "a/ignore.txt", "text")
		expect(#Checks.walk.files(root, { ".luau" })):toBe(2)
		expect(Checks.walk.files(root, { ".luau" })[1].contents):toBe "nested"
		expect(#Checks.walk.pathsSkipping(root, { "" }, function(relative, kind)
			return relative == "a" and kind == "dir"
		end)):toBe(1)
		expect(Checks.walk.lineOf("a\nb\nc", 5)):toBe(3)
		expect(#Checks.walk.paths(root .. "/absent", { "" })):toBe(0)
	end)
end)

it("checks temporary directory cleans exceptions and rejects traversal", function()
	local allocated = ""
	local ok, failure = pcall(function()
		fixture(function(root)
			allocated = root
			write(root, "evidence", "x")
			error("body failed", 0)
		end)
	end)
	expect(ok):toBe(false)
	expect(tostring(failure)):toContain "body failed"
	expect(fs.exists(allocated)):toBe(false)
	expect(pcall(function()
		Checks.temporaryDirectory.run(Checks.temporaryDirectory.root(), "../escape", function()
			return true
		end)
	end)):toBe(false)
end)

it("checks denylist preserves lines applies literal masks and scoped exemptions", function()
	local rules = { { pattern = "secret", why = "private" } }
	expect(#Checks.denylist.scan("a", "safe", rules)):toBe(0)
	expect(Checks.denylist.scan("a", "safe\nsecret", rules)[1]):toContain "a:2:"
	expect(#Checks.denylist.scan("a", "secret", rules, { a = { "secret" } })):toBe(0)
	expect(#Checks.denylist.scan("b", "secret", rules, { a = { "secret" } })):toBe(1)
	expect(
		#Checks.denylist.scan("a", "secret", { { pattern = "secret", why = "private", exempt = { a = "reviewed" } } })
	):toBe(0)
	expect(#Checks.denylist.scan("a", "aXb", { { pattern = "a.b", plain = true, why = "literal" } })):toBe(0)
	local scoped =
		{ { pattern = "value%d+", why = "private", allMatches = true, exempt = { ["a:value1"] = "fixture" } } }
	expect(#Checks.denylist.scan("a", "value1", scoped)):toBe(0)
	expect(#Checks.denylist.scan("a", "value1 value2 value3", scoped)):toBe(2)
	expect(#Checks.denylist.scan("b", "value1", scoped)):toBe(1)
end)

it("checks boundary rejects empty and forbidden roots with configured exclusions", function()
	fixture(function(root)
		local rules = { { pattern = "HOST", why = "host" } }
		expect(#Checks.boundary { root = root, rules = rules }):toBe(1)
		write(root, "pure.luau", "return 1")
		expect(#Checks.boundary { root = root, rules = rules }):toBe(0)
		write(root, "sample.verify.luau", "HOST")
		expect(#Checks.boundary { root = root, rules = rules }):toBe(1)
		expect(#Checks.boundary { root = root, rules = rules, exclude = "%.verify%.luau$" }):toBe(0)
		expect(#Checks.boundary { root = root .. "/absent", rules = rules, allowMissing = true }):toBe(0)
	end)
end)

it("checks manifest detects omissions duplicates order and writes discovery", function()
	fixture(function(root)
		write(root, "b.verify.luau", "return nil")
		write(root, "a.verify.luau", "return nil")
		local rules = { { root = root, pattern = "%.verify%.luau$" } }
		local entries = { root .. "/a.verify.luau", root .. "/b.verify.luau" }
		expect(#Checks.testManifest { path = root .. "/manifest.luau", rules = rules, entries = entries }):toBe(0)
		expect(#Checks.testManifest { path = "manifest", rules = rules, entries = { entries[2], entries[1] } }):toBe(2)
		expect(#Checks.testManifest { path = "manifest", rules = rules, entries = { entries[1], entries[1] } }):toBe(1)
		expect(#Checks.testManifest { path = "manifest", rules = rules, entries = {} }):toBe(2)
		expect(#Checks.testManifest { path = root .. "/manifest.luau", rules = rules, write = true }):toBe(0)
		expect(fs.readFileToString(root .. "/manifest.luau")):toContain(entries[2])
	end)
end)

it("checks public surface detects undocumented stale failed and nested exports", function()
	fixture(function(root)
		write(root, "init.luau", "export type Item = string\nreturn {}")
		write(root, "api.md", "### `Sample.run`\n")
		local packages = {
			{
				prefix = "Sample",
				entry = root .. "/init.luau",
				load = function(): unknown
					return { run = function() end }
				end,
			},
		}
		expect(#Checks.publicSurface { docs = root .. "/api.md", packages = packages }):toBe(0)
		write(root, "api.md", "### `Sample.stale`\n")
		expect(#Checks.publicSurface { docs = root .. "/api.md", packages = packages }):toBe(2)
		write(root, "api.md", "`Sample.nested.call` `Sample.Item`\n")
		packages[1].load = function(): unknown
			return { nested = { call = function() end } }
		end
		expect(#Checks.publicSurface {
			docs = root .. "/api.md",
			packages = packages,
			recursive = true,
			codeReferences = true,
			includeTypes = true,
		}):toBe(0)
		packages[1].load = function(): unknown
			error "load refused"
		end
		expect(#Checks.publicSurface { docs = root .. "/api.md", packages = packages } > 0):toBe(true)
	end)
end)

it("checks comments handle interpolation directives licenses and reversible rewriting", function()
	fixture(function(root)
		local path = root .. "/code.luau"
		write(
			root,
			"code.luau",
			"--!strict\nlocal quoted = '-- ordinary text'\nlocal value = `{(function() -- forbidden\nreturn 1 end)()}`\n-- tail\n"
		)
		local config = { files = { path }, allowed = { "^%-%-!" } }
		expect(#Checks.comments(config)):toBe(2)
		expect(#Checks.comments { files = { path }, allowed = config.allowed, write = true }):toBe(0)
		expect(#Checks.comments(config)):toBe(0)
		expect(fs.readFileToString(path)):toContain "-- ordinary text"
		write(root, "code.luau", "local text = '\u{e9}' --[[same]] --[[same]]\nreturn text\n")
		expect(#Checks.comments(config)):toBe(2)
		Checks.comments { files = { path }, write = true }
		expect(#Checks.comments(config)):toBe(0)
		write(root, "code.luau", "-- Copyright\nreturn 1\n")
		expect(#Checks.comments { files = { path }, licenseFragments = { "Copyright", "Permission" } }):toBe(1)
		write(root, "code.luau", "--[[Copyright Permission]]\nreturn 1\n")
		expect(#Checks.comments { files = { path }, licenseFragments = { "Copyright", "Permission" } }):toBe(0)
		write(root, "config.toml", "text = '# literal' # forbidden\n#! permitted only as first bytes\n")
		expect(#Checks.comments { configFiles = { root .. "/config.toml" } }):toBe(2)
		Checks.comments { configFiles = { root .. "/config.toml" }, write = true }
		expect(fs.readFileToString(root .. "/config.toml")):toContain "'# literal'"
	end)
end)

it("checks leakage and type policy honor git selection and ignored files", function()
	fixture(function(root)
		git(root, { "init", "--quiet" })
		write(root, ".gitignore", "ignored.luau\n")
		write(root, "tracked.luau", "--!strict\nreturn 1\n")
		git(root, { "add", "." })
		write(root, "fresh.luau", "--!strict\nlocal x: any = 'private'\n")
		write(root, "ignored.luau", "private")
		local rules = { { pattern = "private", why = "private" } }
		expect(#Checks.leakage { root = root, rules = rules }):toBe(0)
		expect(#Checks.leakage { root = root, rules = rules, untracked = true }):toBe(1)
		expect(#Checks.noAny { root = root }):toBe(0)
		expect(#Checks.noAny { root = root, untracked = true }):toBe(1)
		write(root, "fresh.luau", "--!nonstrict\nreturn 1\n")
		expect(#Checks.noAny { root = root, untracked = true }):toBe(2)
	end)
end)

it("checks provenance rejects missing license unmanaged notices scripts and dependency failure", function()
	fixture(function(root)
		local config = {
			forbiddenPaths = { root .. "/vendor" },
			license = root .. "/LICENSE",
			licenseFragments = { "Grant" },
		}
		expect(#Checks.provenance(config)):toBe(1)
		write(root, "LICENSE", "Grant" .. string.rep(" ", 40))
		expect(#Checks.provenance(config)):toBe(0)
		fs.createDirectory(root .. "/vendor")
		expect(#Checks.provenance(config)):toBe(1)
		write(root, "nested/NOTICE", "unreviewed")
		write(root, "nested/tool.sh", "echo")
		write(root, "nested/package.json", "{}")
		expect(#Checks.provenance {
			forbiddenPaths = {},
			license = config.license,
			licenseFragments = config.licenseFragments,
			root = root,
			noticeNames = { "LICENSE", "NOTICE" },
			expectedNotices = { LICENSE = "reviewed" },
			justifiedSuffixes = { ".sh" },
			descriptors = { "package.json" },
		}):toBe(3)
		expect(#Checks.provenance {
			forbiddenPaths = {},
			license = config.license,
			licenseFragments = {},
			dependencyCommand = { "git", "checks-nonexistent-command" },
		}):toBe(1)
	end)
end)

it("checks clean clone proves committed content gate failure and dirty refusal", function()
	fixture(function(root)
		git(root, { "init", "--quiet" })
		write(
			root,
			"gate.luau",
			"--!strict\nlocal fs = require '@std/fs'\nassert(fs.readFileToString('payload') == 'committed')\n"
		)
		write(root, "payload", "committed")
		git(root, { "add", "." })
		git(root, {
			"-c",
			"user.name=fixture",
			"-c",
			"user.email=fixture@example.invalid",
			"commit",
			"--quiet",
			"-m",
			"fixture",
		})
		expect(
			table.concat(
				Checks.cleanClone { root = root, command = { tostring(process.execPath()), "run", "gate.luau" } },
				"\n"
			)
		):toBe ""
		expect(#Checks.cleanClone { root = root, command = { "git", "checks-nonexistent-command" } }):toBe(1)
		expect(#Checks.cleanClone {
			root = root,
			command = { "git", "status" },
			requiredPaths = { root .. "/absent" },
		}):toBe(1)
		write(root, "payload", "dirty")
		expect(#Checks.cleanClone { root = root, command = { "git", "status" } }):toBe(1)
	end)
end)

it("checks lint rules reject shared globals misplaced comparisons and invalid escapes", function()
	local function parse(source: string)
		return ((parser.parse(source) :: unknown) :: { root: syntax.CstStatBlock }).root
	end
	expect(#Checks.lintRules.globalTableUsage.lint(parse "return _G.value", nil, {})):toBe(1)
	expect(#Checks.lintRules.globalTableUsage.lint(parse "local _G = {}; return _G.value", nil, {})):toBe(0)
	expect(#Checks.lintRules.typeCheckInsideCall.lint(parse "return type(value == 'table')", nil, {})):toBe(1)
	expect(#Checks.lintRules.typeCheckInsideCall.lint(parse "return type(value) == 'table'", nil, {})):toBe(0)
	expect(#Checks.lintRules.badStringEscape.lint(parse 'return "\\q"', nil, {})):toBe(1)
	expect(#Checks.lintRules.badStringEscape.lint(parse 'return "\\n"', nil, {})):toBe(0)
end)

return nil
