--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local parser = require "@std/syntax/parser"
local syntax = require "@std/syntax"
local Checks = require "../src/checks"
local Verify = require "../src/core"

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

return function(suite: Verify.Harness)
	suite:case("checks walk sorts files skips subtrees and reports lines", function(check)
		fixture(function(root)
			write(root, "b.luau", "b")
			write(root, "a/nested.luau", "nested")
			write(root, "a/ignore.txt", "text")
			check:expect(#Checks.walk.files(root, { ".luau" })):toBe(2)
			check:expect(Checks.walk.files(root, { ".luau" })[1].contents):toBe "nested"
			check
				:expect(#Checks.walk.pathsSkipping(root, { "" }, function(relative, kind)
					return relative == "a" and kind == "dir"
				end))
				:toBe(1)
			check:expect(Checks.walk.lineOf("a\nb\nc", 5)):toBe(3)
			check:expect(#Checks.walk.paths(root .. "/absent", { "" })):toBe(0)
		end)
	end)

	suite:case("checks temporary directory cleans exceptions and rejects traversal", function(check)
		local allocated = ""
		local ok, failure = pcall(function()
			fixture(function(root)
				allocated = root
				write(root, "evidence", "x")
				error("body failed", 0)
			end)
		end)
		check:expect(ok):toBe(false)
		check:expect(tostring(failure)):toContain "body failed"
		check:expect(fs.exists(allocated)):toBe(false)
		check
			:expect(pcall(function()
				Checks.temporaryDirectory.run(Checks.temporaryDirectory.root(), "../escape", function()
					return true
				end)
			end))
			:toBe(false)
	end)

	suite:case("checks denylist preserves lines applies literal masks and scoped exemptions", function(check)
		local rules = { { pattern = "secret", why = "private" } }
		check:expect(#Checks.denylist.scan("a", "safe", rules)):toBe(0)
		check:expect(Checks.denylist.scan("a", "safe\nsecret", rules)[1]):toContain "a:2:"
		check:expect(#Checks.denylist.scan("a", "secret", rules, { a = { "secret" } })):toBe(0)
		check:expect(#Checks.denylist.scan("b", "secret", rules, { a = { "secret" } })):toBe(1)
		check
			:expect(
				#Checks.denylist.scan(
					"a",
					"secret",
					{ { pattern = "secret", why = "private", exempt = { a = "reviewed" } } }
				)
			)
			:toBe(0)
		check:expect(#Checks.denylist.scan("a", "aXb", { { pattern = "a.b", plain = true, why = "literal" } })):toBe(0)
		local scoped =
			{ { pattern = "value%d+", why = "private", allMatches = true, exempt = { ["a:value1"] = "fixture" } } }
		check:expect(#Checks.denylist.scan("a", "value1", scoped)):toBe(0)
		check:expect(#Checks.denylist.scan("a", "value1 value2 value3", scoped)):toBe(2)
		check:expect(#Checks.denylist.scan("b", "value1", scoped)):toBe(1)
	end)

	suite:case("checks boundary rejects empty and forbidden roots with configured exclusions", function(check)
		fixture(function(root)
			local rules = { { pattern = "HOST", why = "host" } }
			check:expect(#Checks.boundary { root = root, rules = rules }):toBe(1)
			write(root, "pure.luau", "return 1")
			check:expect(#Checks.boundary { root = root, rules = rules }):toBe(0)
			write(root, "sample.verify.luau", "HOST")
			check:expect(#Checks.boundary { root = root, rules = rules }):toBe(1)
			check:expect(#Checks.boundary { root = root, rules = rules, exclude = "%.verify%.luau$" }):toBe(0)
			check:expect(#Checks.boundary { root = root .. "/absent", rules = rules, allowMissing = true }):toBe(0)
		end)
	end)

	suite:case("checks manifest detects omissions duplicates order and writes discovery", function(check)
		fixture(function(root)
			write(root, "b.verify.luau", "return nil")
			write(root, "a.verify.luau", "return nil")
			local rules = { { root = root, pattern = "%.verify%.luau$" } }
			local entries = { root .. "/a.verify.luau", root .. "/b.verify.luau" }
			check
				:expect(#Checks.testManifest { path = root .. "/manifest.luau", rules = rules, entries = entries })
				:toBe(0)
			check
				:expect(#Checks.testManifest { path = "manifest", rules = rules, entries = { entries[2], entries[1] } })
				:toBe(2)
			check
				:expect(#Checks.testManifest { path = "manifest", rules = rules, entries = { entries[1], entries[1] } })
				:toBe(1)
			check:expect(#Checks.testManifest { path = "manifest", rules = rules, entries = {} }):toBe(2)
			check:expect(#Checks.testManifest { path = root .. "/manifest.luau", rules = rules, write = true }):toBe(0)
			check:expect(fs.readFileToString(root .. "/manifest.luau")):toContain(entries[2])
		end)
	end)

	suite:case("checks public surface detects undocumented stale failed and nested exports", function(check)
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
			check:expect(#Checks.publicSurface { docs = root .. "/api.md", packages = packages }):toBe(0)
			write(root, "api.md", "### `Sample.stale`\n")
			check:expect(#Checks.publicSurface { docs = root .. "/api.md", packages = packages }):toBe(2)
			write(root, "api.md", "`Sample.nested.call` `Sample.Item`\n")
			packages[1].load = function(): unknown
				return { nested = { call = function() end } }
			end
			check
				:expect(#Checks.publicSurface {
					docs = root .. "/api.md",
					packages = packages,
					recursive = true,
					codeReferences = true,
					includeTypes = true,
				})
				:toBe(0)
			packages[1].load = function(): unknown
				error "load refused"
			end
			check:expect(#Checks.publicSurface { docs = root .. "/api.md", packages = packages } > 0):toBe(true)
		end)
	end)

	suite:case("checks comments handle interpolation directives licenses and reversible rewriting", function(check)
		fixture(function(root)
			local path = root .. "/code.luau"
			write(
				root,
				"code.luau",
				"--!strict\nlocal quoted = '-- ordinary text'\nlocal value = `{(function() -- forbidden\nreturn 1 end)()}`\n-- tail\n"
			)
			local config = { files = { path }, allowed = { "^%-%-!" } }
			check:expect(#Checks.comments(config)):toBe(2)
			check:expect(#Checks.comments { files = { path }, allowed = config.allowed, write = true }):toBe(0)
			check:expect(#Checks.comments(config)):toBe(0)
			check:expect(fs.readFileToString(path)):toContain "-- ordinary text"
			write(root, "code.luau", "local text = '\u{e9}' --[[same]] --[[same]]\nreturn text\n")
			check:expect(#Checks.comments(config)):toBe(2)
			Checks.comments { files = { path }, write = true }
			check:expect(#Checks.comments(config)):toBe(0)
			write(root, "code.luau", "-- Copyright\nreturn 1\n")
			check
				:expect(#Checks.comments { files = { path }, licenseFragments = { "Copyright", "Permission" } })
				:toBe(1)
			write(root, "code.luau", "--[[Copyright Permission]]\nreturn 1\n")
			check
				:expect(#Checks.comments { files = { path }, licenseFragments = { "Copyright", "Permission" } })
				:toBe(0)
			write(root, "config.toml", "text = '# literal' # forbidden\n#! permitted only as first bytes\n")
			check:expect(#Checks.comments { configFiles = { root .. "/config.toml" } }):toBe(2)
			Checks.comments { configFiles = { root .. "/config.toml" }, write = true }
			check:expect(fs.readFileToString(root .. "/config.toml")):toContain "'# literal'"
		end)
	end)

	suite:case("checks leakage and type policy honor git selection and ignored files", function(check)
		fixture(function(root)
			git(root, { "init", "--quiet" })
			write(root, ".gitignore", "ignored.luau\n")
			write(root, "tracked.luau", "--!strict\nreturn 1\n")
			git(root, { "add", "." })
			write(root, "fresh.luau", "--!strict\nlocal x: any = 'private'\n")
			write(root, "ignored.luau", "private")
			local rules = { { pattern = "private", why = "private" } }
			check:expect(#Checks.leakage { root = root, rules = rules }):toBe(0)
			check:expect(#Checks.leakage { root = root, rules = rules, untracked = true }):toBe(1)
			check:expect(#Checks.noAny { root = root }):toBe(0)
			check:expect(#Checks.noAny { root = root, untracked = true }):toBe(1)
			write(root, "fresh.luau", "--!nonstrict\nreturn 1\n")
			check:expect(#Checks.noAny { root = root, untracked = true }):toBe(2)
		end)
	end)

	suite:case(
		"checks provenance rejects missing license unmanaged notices scripts and dependency failure",
		function(check)
			fixture(function(root)
				local config = {
					forbiddenPaths = { root .. "/vendor" },
					license = root .. "/LICENSE",
					licenseFragments = { "Grant" },
				}
				check:expect(#Checks.provenance(config)):toBe(1)
				write(root, "LICENSE", "Grant" .. string.rep(" ", 40))
				check:expect(#Checks.provenance(config)):toBe(0)
				fs.createDirectory(root .. "/vendor")
				check:expect(#Checks.provenance(config)):toBe(1)
				write(root, "nested/NOTICE", "unreviewed")
				write(root, "nested/tool.sh", "echo")
				write(root, "nested/package.json", "{}")
				check
					:expect(#Checks.provenance {
						forbiddenPaths = {},
						license = config.license,
						licenseFragments = config.licenseFragments,
						root = root,
						noticeNames = { "LICENSE", "NOTICE" },
						expectedNotices = { LICENSE = "reviewed" },
						justifiedSuffixes = { ".sh" },
						descriptors = { "package.json" },
					})
					:toBe(3)
				check
					:expect(#Checks.provenance {
						forbiddenPaths = {},
						license = config.license,
						licenseFragments = {},
						dependencyCommand = { "git", "checks-nonexistent-command" },
					})
					:toBe(1)
			end)
		end
	)

	suite:case("checks clean clone proves committed content gate failure and dirty refusal", function(check)
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
			check
				:expect(
					table.concat(
						Checks.cleanClone { root = root, command = { tostring(process.execPath()), "run", "gate.luau" } },
						"\n"
					)
				)
				:toBe ""
			check:expect(#Checks.cleanClone { root = root, command = { "git", "checks-nonexistent-command" } }):toBe(1)
			check
				:expect(#Checks.cleanClone {
					root = root,
					command = { "git", "status" },
					requiredPaths = { root .. "/absent" },
				})
				:toBe(1)
			write(root, "payload", "dirty")
			check:expect(#Checks.cleanClone { root = root, command = { "git", "status" } }):toBe(1)
		end)
	end)

	suite:case("checks lint rules reject shared globals misplaced comparisons and invalid escapes", function(check)
		local function parse(source: string)
			return ((parser.parse(source) :: unknown) :: { root: syntax.CstStatBlock }).root
		end
		check:expect(#Checks.lintRules.globalTableUsage.lint(parse "return _G.value", nil, {})):toBe(1)
		check:expect(#Checks.lintRules.globalTableUsage.lint(parse "local _G = {}; return _G.value", nil, {})):toBe(0)
		check:expect(#Checks.lintRules.typeCheckInsideCall.lint(parse "return type(value == 'table')", nil, {})):toBe(1)
		check:expect(#Checks.lintRules.typeCheckInsideCall.lint(parse "return type(value) == 'table'", nil, {})):toBe(0)
		check:expect(#Checks.lintRules.badStringEscape.lint(parse 'return "\\q"', nil, {})):toBe(1)
		check:expect(#Checks.lintRules.badStringEscape.lint(parse 'return "\\n"', nil, {})):toBe(0)
	end)
end
