--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Plan = require "../src/core/plan"
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
	local narrowed = Plan.select(planOf(files), Corpus.selection(files, query))
	local ids: { string } = {}
	for _, unit in narrowed.units do
		table.insert(ids, unit.id)
	end
	return ids
end

local REQUIRE_PATTERN = 'require%("@units/([%w%-_/%.]+)"%)'

describe("corpus discovery", function()
	it("walks a root recursively and keeps only the files a rule's pattern names", function()
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
		expect(files):toEqual { "units/Root.verify.luau", "units/nested/Deep.verify.luau" }
	end)

	it("drops a file its rule excludes, whatever the pattern says", function()
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
		expect(files):toEqual { "units/A.verify.luau" }
	end)

	it("matches a rule against the file name, so an anchored rule names exactly one file", function()
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
		expect(files):toEqual { "units/Exact.verify.luau" }
	end)

	it("deduplicates and sorts across overlapping rules, so no plan gains a duplicate", function()
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
		expect(files):toEqual { "units/Z.verify.luau", "units/nested/A.verify.luau" }
	end)

	it("refuses a rule with no root or no pattern rather than walking nothing quietly", function()
		local noRoot, rootThrown: unknown =
			pcall(Corpus.discover, { listDir = listDir {}, rules = { { root = "", pattern = "x" } } })
		expect(noRoot):toEqual(false)
		expect((tostring(rootThrown))):toContain "has no root"
		local noPattern, patternThrown: unknown =
			pcall(Corpus.discover, { listDir = listDir {}, rules = { { root = "units", pattern = "" } } })
		expect(noPattern):toEqual(false)
		expect((tostring(patternThrown))):toContain "has no pattern"
	end)
end)

describe("corpus fixture grouping", function()
	it("groups a fixture with every file that requires it", function()
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
		expect(groups):toEqual { { "Consumer.verify.luau", "Fixture.verify.luau" }, { "Standalone.verify.luau" } }
	end)

	it("merges a transitive chain into one group", function()
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
		expect(groups):toEqual { { "One.verify.luau", "Three.verify.luau", "Two.verify.luau" } }
	end)

	it("ignores a require naming something that is not one of the files", function()
		local files = { "Lonely.verify.luau" }
		local groups = Corpus.groupByRequire(
			files,
			reader { ["Lonely.verify.luau"] = 'require("@units/elsewhere/Fixture.verify")' },
			REQUIRE_PATTERN
		)
		expect(groups):toEqual { { "Lonely.verify.luau" } }
	end)

	it("gives a file it could not read no edges rather than abandoning the walk", function()
		local files = { "A.verify.luau", "B.verify.luau" }
		local groups = Corpus.groupByRequire(files, reader { ["B.verify.luau"] = "return {}" }, REQUIRE_PATTERN)
		expect(groups):toEqual { { "A.verify.luau" }, { "B.verify.luau" } }
	end)

	it("carries the affinity into partitioning at every batch count", function()
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
			local batches = Plan.partition({ id = "corpus", units = units }, batchCount)
			local home: { [string]: number } = {}
			for _, batch in batches do
				for _, unit in batch.units do
					home[unit.id] = batch.index
				end
			end
			expect(home["B.verify.luau"]):toEqual(home["A.verify.luau"])
			expect(home["C.verify.luau"]):toEqual(home["A.verify.luau"])
		end
	end)
end)

describe("corpus worker counts", function()
	it("leaves the margin free by default and never drops below one", function()
		expect((Corpus.workers(12, nil, 1000, 2, 16))):toEqual(10)
		expect((Corpus.workers(2, nil, 1000, 2, 16))):toEqual(1)
		expect((Corpus.workers(1, nil, 1000, 2, 16))):toEqual(1)
	end)

	it("honours an override, the cap and the file count", function()
		expect((Corpus.workers(12, 4, 1000, 2, 16))):toEqual(4)
		expect((Corpus.workers(128, nil, 1000, 2, 16))):toEqual(16)
		expect((Corpus.workers(12, nil, 3, 2, 16))):toEqual(3)
		expect((Corpus.workers(12, nil, 0, 2, 16))):toEqual(1)
	end)
end)

describe("corpus literal names", function()
	it("matches a hyphenated name that raw concatenation cannot match at all", function()
		local name = "check-test-corpus"
		local file = "check-test-corpus.lute.verify.luau"
		expect(string.match(file, Corpus.literal(name)) ~= nil):toEqual(true)
		expect(string.match(file, name .. ".*%.verify%.luau$") ~= nil):toEqual(false)
	end)

	it("escapes every character the matcher reads as syntax, the escape included", function()
		for _, text in { "a%b", "a^b", "a$b", "a(b)", "a.b", "a[b]", "a*b", "a+b", "a-b", "a?b" } do
			expect((string.match(text, Corpus.literal(text)))):toEqual(text)
			expect(string.match(text .. "x", "^" .. Corpus.literal(text) .. "$") == nil):toEqual(true)
		end
	end)
end)

describe("corpus selection", function()
	local FILES = {
		"shared/BalanceLab.verify.luau",
		"tools/check-test-corpus-routing.verify.luau",
		"tools/check-test-corpus.lute.verify.luau",
		"tools/worker-setup.verify.luau",
	}

	it("narrows to the files whose name carries a literal fragment", function()
		expect((selected(FILES, { name = "worker-setup" }))):toEqual { "tools/worker-setup.verify.luau" }
	end)

	it("uses an already-complete pattern exactly as given rather than doubling it", function()
		expect((selected(FILES, { pattern = "^BalanceLab%.verify%.luau$" }))):toEqual { "shared/BalanceLab.verify.luau" }
		expect((#selected(FILES, { pattern = "%.verify%.luau$" }))):toEqual(#FILES)
	end)

	it("keeps only the files under a named root", function()
		expect((selected(FILES, { root = "shared" }))):toEqual { "shared/BalanceLab.verify.luau" }
	end)

	it("keeps every file when the query names nothing", function()
		expect((#selected(FILES, nil))):toEqual(#FILES)
		expect((#selected(FILES, {}))):toEqual(#FILES)
	end)

	it("selects nothing at all when nothing matched, rather than everything", function()
		expect((selected(FILES, { name = "no-such-unit" }))):toEqual {}
	end)

	it("refuses a query naming both a pattern and a literal name", function()
		local asked, thrown: unknown = pcall(Corpus.selection, FILES, { name = "a", pattern = "b" })
		expect(asked):toEqual(false)
		expect((tostring(thrown))):toContain "never both"
	end)
end)

describe("corpus lock bytes", function()
	it("emits a frozen module a consumer can compare byte for byte", function()
		local text = Corpus.lockText {
			{ name = "tier1", fields = { { name = "count", value = 12 }, { name = "digest", value = "abc-1" } } },
		}
		expect(text):toEqual(table.concat({
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

	it("emits sections in the order it was given them", function()
		local text = Corpus.lockText {
			{ name = "second", fields = { { name = "count", value = 2 } } },
			{ name = "first", fields = { { name = "count", value = 1 } } },
		}
		local second = string.find(text, "second", 1, true)
		local first = string.find(text, "first", 1, true)
		assert(second ~= nil and first ~= nil)
		assert(second < first)
	end)

	it("refuses a field that is neither a number nor a string", function()
		local emitted, thrown: unknown = pcall(
			Corpus.lockText,
			{ { name = "s", fields = { { name = "f", value = (true :: unknown) :: string | number } } } }
		)
		expect(emitted):toEqual(false)
		expect((tostring(thrown))):toContain "neither a number nor a string"
	end)
end)

describe("corpus discovery order", function()
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

	it("keeps the walk order when the consumer asks for it", function()
		local walked = Corpus.discover { listDir = listDir(tree), rules = rules, order = "walk" }
		expect(walked):toEqual {
			"units/a.verify.luau",
			"units/b/c.verify.luau",
			"units/b/z.verify.luau",
			"units/b.verify.luau",
		}
		local sorted = Corpus.discover { listDir = listDir(tree), rules = rules }
		expect(sorted):toEqual {
			"units/a.verify.luau",
			"units/b.verify.luau",
			"units/b/c.verify.luau",
			"units/b/z.verify.luau",
		}
	end)

	it("applies the consumer's comparison to entries and paths", function()
		local descending = function(left: string, right: string): boolean
			return left > right
		end
		local walked = Corpus.discover { listDir = listDir(tree), rules = rules, order = "walk", compare = descending }
		expect(walked):toEqual {
			"units/b.verify.luau",
			"units/b/z.verify.luau",
			"units/b/c.verify.luau",
			"units/a.verify.luau",
		}
		local sorted = Corpus.discover { listDir = listDir(tree), rules = rules, compare = descending }
		expect(sorted[1]):toEqual "units/b/z.verify.luau"
	end)

	it("does not reorder the entries that the runtime returned", function()
		local entries: { Corpus.DirEntry } =
			{ { name = "z.verify.luau", type = "file" }, { name = "a.verify.luau", type = "file" } }
		Corpus.discover {
			listDir = function()
				return entries
			end,
			rules = rules,
			order = "walk",
		}
		expect(entries[1].name):toEqual "z.verify.luau"
	end)

	it("refuses an unknown order and a comparison that is not a function", function()
		local notFunction: unknown = 3
		local unknownOrder: unknown = "random"
		local badOrder =
			pcall(Corpus.discover, { listDir = listDir(tree), rules = rules, order = unknownOrder :: Corpus.Order })
		local badCompare =
			pcall(Corpus.discover, { listDir = listDir(tree), rules = rules, compare = notFunction :: Corpus.Compare })
		expect(badOrder):toEqual(false)
		expect(badCompare):toEqual(false)
	end)
end)

return nil
