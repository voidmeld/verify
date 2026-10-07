--!strict

local Corpus = require "../src/lute/corpus"
local Verify = require "../src/core"

type Tree = { [string]: { Corpus.DirEntry } }

local function listDir(tree: Tree): Corpus.ListDir
	return function(path: string)
		local entries = tree[path]
		if entries == nil then
			return {}
		end
		return entries
	end
end

local function reader(sources: { [string]: string }): Corpus.ReadFile
	return function(path: string): string
		local source = sources[path]
		if source == nil then
			error("no such file: " .. path)
		end
		return source
	end
end

local function planOf(files: { string }): Verify.PlanDraft
	local units: { Verify.PlanUnitDraft } = {}
	for _, file in files do
		table.insert(units, { id = file, locator = file })
	end
	return { id = "corpus", units = units }
end

local function selected(files: { string }, query: Corpus.Query?): { string }
	local narrowed = Verify.selectPlan(planOf(files), Corpus.selection(files, query))
	local ids: { string } = {}
	for _, unit in narrowed.units do
		table.insert(ids, unit.id)
	end
	return ids
end

local REQUIRE_PATTERN = 'require%("@units/([%w%-_/%.]+)"%)'

return function(suite: Verify.Harness)
	suite:suite("corpus discovery", function()
		suite:case("walks a root recursively and keeps only the files a rule's pattern names", function(check)
			local tree: Tree = {
				["units"] = {
					{ name = "nested", type = "dir" },
					{ name = "Root.verify.luau", type = "file" },
					{ name = "Root.luau", type = "file" },
				},
				["units/nested"] = {
					{ name = "Deep.verify.luau", type = "file" },
					{ name = "helper.luau", type = "file" },
				},
			}
			local files = Corpus.discover {
				listDir = listDir(tree),
				rules = { { root = "units", pattern = "%.verify%.luau$" } },
			}
			check:expect(files):toEqual { "units/Root.verify.luau", "units/nested/Deep.verify.luau" }
		end)

		suite:case("drops a file its rule excludes, whatever the pattern says", function(check)
			local tree: Tree = {
				["units"] = {
					{ name = "A.verify.luau", type = "file" },
					{ name = "B.engine.verify.luau", type = "file" },
				},
			}
			local files = Corpus.discover {
				listDir = listDir(tree),
				rules = { { root = "units", pattern = "%.verify%.luau$", exclude = "%.engine%.verify%.luau$" } },
			}
			check:expect(files):toEqual { "units/A.verify.luau" }
		end)

		suite:case("matches a rule against the file name, so an anchored rule names exactly one file", function(check)
			local tree: Tree = {
				["units"] = {
					{ name = "Exact.verify.luau", type = "file" },
					{ name = "NotExact.verify.luau", type = "file" },
				},
			}
			local files = Corpus.discover {
				listDir = listDir(tree),
				rules = { { root = "units", pattern = "^Exact%.verify%.luau$" } },
			}
			check:expect(files):toEqual { "units/Exact.verify.luau" }
		end)

		suite:case("deduplicates and sorts across overlapping rules, so no plan gains a duplicate", function(check)
			local tree: Tree = {
				["units"] = { { name = "nested", type = "dir" }, { name = "Z.verify.luau", type = "file" } },
				["units/nested"] = { { name = "A.verify.luau", type = "file" } },
			}
			local files = Corpus.discover {
				listDir = listDir(tree),
				rules = {
					{ root = "units", pattern = "%.verify%.luau$" },
					{ root = "units/nested", pattern = "%.verify%.luau$" },
				},
			}
			check:expect(files):toEqual { "units/Z.verify.luau", "units/nested/A.verify.luau" }
		end)

		suite:case("refuses a rule with no root or no pattern rather than walking nothing quietly", function(check)
			local noRoot, rootThrown: unknown =
				pcall(Corpus.discover, { listDir = listDir {}, rules = { { root = "", pattern = "x" } } })
			check:expect(noRoot):toEqual(false)
			check:expect((tostring(rootThrown))):toContain "has no root"
			local noPattern, patternThrown: unknown =
				pcall(Corpus.discover, { listDir = listDir {}, rules = { { root = "units", pattern = "" } } })
			check:expect(noPattern):toEqual(false)
			check:expect((tostring(patternThrown))):toContain "has no pattern"
		end)
	end)

	suite:suite("corpus fixture grouping", function()
		suite:case("groups a fixture with every file that requires it", function(check)
			local files = { "Consumer.verify.luau", "Fixture.verify.luau", "Standalone.verify.luau" }
			local groups = Corpus.groupByRequire(
				files,
				reader {
					["Consumer.verify.luau"] = 'require("@units/Fixture.verify")',
					["Fixture.verify.luau"] = "return {}",
					["Standalone.verify.luau"] = "return {}",
				},
				REQUIRE_PATTERN
			)
			check
				:expect(groups)
				:toEqual { { "Consumer.verify.luau", "Fixture.verify.luau" }, { "Standalone.verify.luau" } }
		end)

		suite:case("merges a transitive chain into one group", function(check)
			local files = { "One.verify.luau", "Three.verify.luau", "Two.verify.luau" }
			local groups = Corpus.groupByRequire(
				files,
				reader {
					["One.verify.luau"] = 'require("@units/Two.verify")',
					["Two.verify.luau"] = 'require("@units/Three.verify")',
					["Three.verify.luau"] = "return {}",
				},
				REQUIRE_PATTERN
			)
			check:expect(groups):toEqual { { "One.verify.luau", "Three.verify.luau", "Two.verify.luau" } }
		end)

		suite:case("ignores a require naming something that is not one of the files", function(check)
			local files = { "Lonely.verify.luau" }
			local groups = Corpus.groupByRequire(
				files,
				reader { ["Lonely.verify.luau"] = 'require("@units/elsewhere/Fixture.verify")' },
				REQUIRE_PATTERN
			)
			check:expect(groups):toEqual { { "Lonely.verify.luau" } }
		end)

		suite:case("gives a file it could not read no edges rather than abandoning the walk", function(check)
			local files = { "A.verify.luau", "B.verify.luau" }
			local groups = Corpus.groupByRequire(files, reader { ["B.verify.luau"] = "return {}" }, REQUIRE_PATTERN)
			check:expect(groups):toEqual { { "A.verify.luau" }, { "B.verify.luau" } }
		end)

		suite:case("carries the affinity into partitioning at every batch count", function(check)
			local files = { "A.verify.luau", "B.verify.luau", "C.verify.luau", "D.verify.luau" }
			local groups = Corpus.groupByRequire(
				files,
				reader {
					["A.verify.luau"] = "return {}",
					["B.verify.luau"] = 'require("@units/A.verify")',
					["C.verify.luau"] = 'require("@units/A.verify")',
					["D.verify.luau"] = "return {}",
				},
				REQUIRE_PATTERN
			)
			local groupOf: { [string]: string } = {}
			for _, group in groups do
				for _, file in group do
					groupOf[file] = group[1]
				end
			end
			local units: { Verify.PlanUnitDraft } = {}
			for _, file in files do
				table.insert(units, { id = file, locator = file, group = groupOf[file] })
			end
			for batchCount = 1, 5 do
				local batches = Verify.partitionPlan({ id = "corpus", units = units }, batchCount)
				local home: { [string]: number } = {}
				for _, batch in batches do
					for _, unit in batch.units do
						home[unit.id] = batch.index
					end
				end
				check:expect(home["B.verify.luau"]):toEqual(home["A.verify.luau"])
				check:expect(home["C.verify.luau"]):toEqual(home["A.verify.luau"])
			end
		end)
	end)

	suite:suite("corpus worker counts", function()
		suite:case("leaves the margin free by default and never drops below one", function(check)
			check:expect((Corpus.workers(12, nil, 1000, 2, 16))):toEqual(10)
			check:expect((Corpus.workers(2, nil, 1000, 2, 16))):toEqual(1)
			check:expect((Corpus.workers(1, nil, 1000, 2, 16))):toEqual(1)
		end)

		suite:case("honours an override, the cap and the file count", function(check)
			check:expect((Corpus.workers(12, 4, 1000, 2, 16))):toEqual(4)
			check:expect((Corpus.workers(128, nil, 1000, 2, 16))):toEqual(16)
			check:expect((Corpus.workers(12, nil, 3, 2, 16))):toEqual(3)
			check:expect((Corpus.workers(12, nil, 0, 2, 16))):toEqual(1)
		end)
	end)

	suite:suite("corpus literal names", function()
		suite:case("matches a hyphenated name that raw concatenation cannot match at all", function(check)
			local name = "check-test-corpus"
			local file = "check-test-corpus.lute.verify.luau"
			check:expect(string.match(file, Corpus.literal(name)) ~= nil):toEqual(true)
			check:expect(string.match(file, name .. ".*%.verify%.luau$") ~= nil):toEqual(false)
		end)

		suite:case("escapes every character the matcher reads as syntax, the escape included", function(check)
			for _, text in { "a%b", "a^b", "a$b", "a(b)", "a.b", "a[b]", "a*b", "a+b", "a-b", "a?b" } do
				check:expect((string.match(text, Corpus.literal(text)))):toEqual(text)
				check:expect(string.match(text .. "x", "^" .. Corpus.literal(text) .. "$") == nil):toEqual(true)
			end
		end)
	end)

	suite:suite("corpus selection", function()
		local FILES = {
			"shared/BalanceLab.verify.luau",
			"tools/check-test-corpus-routing.verify.luau",
			"tools/check-test-corpus.lute.verify.luau",
			"tools/worker-setup.verify.luau",
		}

		suite:case("narrows to the files whose name carries a literal fragment", function(check)
			check:expect((selected(FILES, { name = "worker-setup" }))):toEqual { "tools/worker-setup.verify.luau" }
		end)

		suite:case("uses an already-complete pattern exactly as given rather than doubling it", function(check)
			check
				:expect((selected(FILES, { pattern = "^BalanceLab%.verify%.luau$" })))
				:toEqual { "shared/BalanceLab.verify.luau" }
			check:expect((#selected(FILES, { pattern = "%.verify%.luau$" }))):toEqual(#FILES)
		end)

		suite:case("keeps only the files under a named root", function(check)
			check:expect((selected(FILES, { root = "shared" }))):toEqual { "shared/BalanceLab.verify.luau" }
		end)

		suite:case("keeps every file when the query names nothing", function(check)
			check:expect((#selected(FILES, nil))):toEqual(#FILES)
			check:expect((#selected(FILES, {}))):toEqual(#FILES)
		end)

		suite:case("selects nothing at all when nothing matched, rather than everything", function(check)
			check:expect((selected(FILES, { name = "no-such-unit" }))):toEqual {}
		end)

		suite:case("refuses a query naming both a pattern and a literal name", function(check)
			local asked, thrown: unknown = pcall(Corpus.selection, FILES, { name = "a", pattern = "b" })
			check:expect(asked):toEqual(false)
			check:expect((tostring(thrown))):toContain "never both"
		end)
	end)

	suite:suite("corpus lock bytes", function()
		suite:case("emits a frozen module a consumer can compare byte for byte", function(check)
			local text = Corpus.lockText {
				{ name = "tier1", fields = { { name = "count", value = 12 }, { name = "digest", value = "abc-1" } } },
			}
			check:expect(text):toEqual(table.concat({
				"--!strict",
				"",
				"return table.freeze({",
				"	schemaVersion = 1,",
				"	tier1 = table.freeze({",
				"		count = 12,",
				'		digest = "abc-1",',
				"	}),",
				"})",
				"",
			}, "\n"))
		end)

		suite:case("emits sections in the order it was given them", function(check)
			local text = Corpus.lockText {
				{ name = "second", fields = { { name = "count", value = 2 } } },
				{ name = "first", fields = { { name = "count", value = 1 } } },
			}
			assert((string.find(text, "second", 1, true) :: number) < (string.find(text, "first", 1, true) :: number))
		end)

		suite:case("refuses a field that is neither a number nor a string", function(check)
			local emitted, thrown: unknown = pcall(
				Corpus.lockText,
				{ { name = "s", fields = { { name = "f", value = (true :: unknown) :: string | number } } } }
			)
			check:expect(emitted):toEqual(false)
			check:expect((tostring(thrown))):toContain "neither a number nor a string"
		end)
	end)

	suite:suite("corpus discovery order", function()
		local tree: Tree = {
			["units"] = {
				{ name = "b", type = "dir" },
				{ name = "a.verify.luau", type = "file" },
				{ name = "b.verify.luau", type = "file" },
			},
			["units/b"] = {
				{ name = "z.verify.luau", type = "file" },
				{ name = "c.verify.luau", type = "file" },
			},
		}
		local rules: { Corpus.Rule } = { { root = "units", pattern = "%.verify%.luau$" } }

		suite:case("keeps the walk order when the consumer asks for it", function(check)
			local walked = Corpus.discover { listDir = listDir(tree), rules = rules, order = "walk" }
			check:expect(walked):toEqual {
				"units/a.verify.luau",
				"units/b/c.verify.luau",
				"units/b/z.verify.luau",
				"units/b.verify.luau",
			}
			local sorted = Corpus.discover { listDir = listDir(tree), rules = rules }
			check:expect(sorted):toEqual {
				"units/a.verify.luau",
				"units/b.verify.luau",
				"units/b/c.verify.luau",
				"units/b/z.verify.luau",
			}
		end)

		suite:case("applies the consumer's comparison to entries and paths", function(check)
			local descending = function(left: string, right: string): boolean
				return left > right
			end
			local walked =
				Corpus.discover { listDir = listDir(tree), rules = rules, order = "walk", compare = descending }
			check:expect(walked):toEqual {
				"units/b.verify.luau",
				"units/b/z.verify.luau",
				"units/b/c.verify.luau",
				"units/a.verify.luau",
			}
			local sorted = Corpus.discover { listDir = listDir(tree), rules = rules, compare = descending }
			check:expect(sorted[1]):toEqual "units/b/z.verify.luau"
		end)

		suite:case("does not reorder the entries that the runtime returned", function(check)
			local entries: { Corpus.DirEntry } =
				{ { name = "z.verify.luau", type = "file" }, { name = "a.verify.luau", type = "file" } }
			Corpus.discover {
				listDir = function()
					return entries
				end,
				rules = rules,
				order = "walk",
			}
			check:expect(entries[1].name):toEqual "z.verify.luau"
		end)

		suite:case("refuses an unknown order and a comparison that is not a function", function(check)
			local notFunction: unknown = 3
			local unknownOrder: unknown = "random"
			local badOrder =
				pcall(Corpus.discover, { listDir = listDir(tree), rules = rules, order = unknownOrder :: Corpus.Order })
			local badCompare = pcall(
				Corpus.discover,
				{ listDir = listDir(tree), rules = rules, compare = notFunction :: Corpus.Compare }
			)
			check:expect(badOrder):toEqual(false)
			check:expect(badCompare):toEqual(false)
		end)
	end)
end
