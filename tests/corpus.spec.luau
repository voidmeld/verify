--!strict

local test = require "@std/test"

local Corpus = require "../src/lute/corpus"
local Verify = require "../src/core"

type Tree = { [string]: { { name: string, type: string } } }

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

test.suite("corpus discovery", function(suite)
	suite:case("walks a root recursively and keeps only the files a rule's pattern names", function(assert)
		local tree: Tree = {
			["units"] = {
				{ name = "nested", type = "dir" },
				{ name = "Root.spec.luau", type = "file" },
				{ name = "Root.luau", type = "file" },
			},
			["units/nested"] = {
				{ name = "Deep.spec.luau", type = "file" },
				{ name = "helper.luau", type = "file" },
			},
		}
		local files = Corpus.discover {
			listDir = listDir(tree),
			rules = { { root = "units", pattern = "%.spec%.luau$" } },
		}
		assert.eq(files, { "units/Root.spec.luau", "units/nested/Deep.spec.luau" })
	end)

	suite:case("drops a file its rule excludes, whatever the pattern says", function(assert)
		local tree: Tree = {
			["units"] = {
				{ name = "A.spec.luau", type = "file" },
				{ name = "B.engine.spec.luau", type = "file" },
			},
		}
		local files = Corpus.discover {
			listDir = listDir(tree),
			rules = { { root = "units", pattern = "%.spec%.luau$", exclude = "%.engine%.spec%.luau$" } },
		}
		assert.eq(files, { "units/A.spec.luau" })
	end)

	suite:case("matches a rule against the file name, so an anchored rule names exactly one file", function(assert)
		local tree: Tree = {
			["units"] = {
				{ name = "Exact.spec.luau", type = "file" },
				{ name = "NotExact.spec.luau", type = "file" },
			},
		}
		local files = Corpus.discover {
			listDir = listDir(tree),
			rules = { { root = "units", pattern = "^Exact%.spec%.luau$" } },
		}
		assert.eq(files, { "units/Exact.spec.luau" })
	end)

	suite:case("deduplicates and sorts across overlapping rules, so no plan gains a duplicate", function(assert)
		local tree: Tree = {
			["units"] = { { name = "nested", type = "dir" }, { name = "Z.spec.luau", type = "file" } },
			["units/nested"] = { { name = "A.spec.luau", type = "file" } },
		}
		local files = Corpus.discover {
			listDir = listDir(tree),
			rules = {
				{ root = "units", pattern = "%.spec%.luau$" },
				{ root = "units/nested", pattern = "%.spec%.luau$" },
			},
		}
		assert.eq(files, { "units/Z.spec.luau", "units/nested/A.spec.luau" })
	end)

	suite:case("refuses a rule with no root or no pattern rather than walking nothing quietly", function(assert)
		local noRoot, rootThrown: any =
			pcall(Corpus.discover, { listDir = listDir {}, rules = { { root = "", pattern = "x" } } })
		assert.eq(noRoot, false)
		assert.strContains(tostring(rootThrown), "has no root")
		local noPattern, patternThrown: any =
			pcall(Corpus.discover, { listDir = listDir {}, rules = { { root = "units", pattern = "" } } })
		assert.eq(noPattern, false)
		assert.strContains(tostring(patternThrown), "has no pattern")
	end)
end)

test.suite("corpus fixture grouping", function(suite)
	suite:case("groups a fixture with every file that requires it", function(assert)
		local files = { "Consumer.spec.luau", "Fixture.spec.luau", "Standalone.spec.luau" }
		local groups = Corpus.groupByRequire(
			files,
			reader {
				["Consumer.spec.luau"] = 'require("@units/Fixture.spec")',
				["Fixture.spec.luau"] = "return {}",
				["Standalone.spec.luau"] = "return {}",
			},
			REQUIRE_PATTERN
		)
		assert.eq(groups, { { "Consumer.spec.luau", "Fixture.spec.luau" }, { "Standalone.spec.luau" } })
	end)

	suite:case("merges a transitive chain into one group", function(assert)
		local files = { "One.spec.luau", "Three.spec.luau", "Two.spec.luau" }
		local groups = Corpus.groupByRequire(
			files,
			reader {
				["One.spec.luau"] = 'require("@units/Two.spec")',
				["Two.spec.luau"] = 'require("@units/Three.spec")',
				["Three.spec.luau"] = "return {}",
			},
			REQUIRE_PATTERN
		)
		assert.eq(groups, { { "One.spec.luau", "Three.spec.luau", "Two.spec.luau" } })
	end)

	suite:case("ignores a require naming something that is not one of the files", function(assert)
		local files = { "Lonely.spec.luau" }
		local groups = Corpus.groupByRequire(
			files,
			reader { ["Lonely.spec.luau"] = 'require("@units/elsewhere/Fixture.spec")' },
			REQUIRE_PATTERN
		)
		assert.eq(groups, { { "Lonely.spec.luau" } })
	end)

	suite:case("gives a file it could not read no edges rather than abandoning the walk", function(assert)
		local files = { "A.spec.luau", "B.spec.luau" }
		local groups = Corpus.groupByRequire(files, reader { ["B.spec.luau"] = "return {}" }, REQUIRE_PATTERN)
		assert.eq(groups, { { "A.spec.luau" }, { "B.spec.luau" } })
	end)

	suite:case("carries the affinity into partitioning at every batch count", function(assert)
		local files = { "A.spec.luau", "B.spec.luau", "C.spec.luau", "D.spec.luau" }
		local groups = Corpus.groupByRequire(
			files,
			reader {
				["A.spec.luau"] = "return {}",
				["B.spec.luau"] = 'require("@units/A.spec")',
				["C.spec.luau"] = 'require("@units/A.spec")',
				["D.spec.luau"] = "return {}",
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
			assert.eq(home["B.spec.luau"], home["A.spec.luau"])
			assert.eq(home["C.spec.luau"], home["A.spec.luau"])
		end
	end)
end)

test.suite("corpus worker counts", function(suite)
	suite:case("leaves the margin free by default and never drops below one", function(assert)
		assert.eq(Corpus.workers(12, nil, 1000, 2, 16), 10)
		assert.eq(Corpus.workers(2, nil, 1000, 2, 16), 1)
		assert.eq(Corpus.workers(1, nil, 1000, 2, 16), 1)
	end)

	suite:case("honours an override, the cap and the file count", function(assert)
		assert.eq(Corpus.workers(12, 4, 1000, 2, 16), 4)
		assert.eq(Corpus.workers(128, nil, 1000, 2, 16), 16)
		assert.eq(Corpus.workers(12, nil, 3, 2, 16), 3)
		assert.eq(Corpus.workers(12, nil, 0, 2, 16), 1)
	end)
end)

test.suite("corpus literal names", function(suite)
	suite:case("matches a hyphenated name that raw concatenation cannot match at all", function(assert)
		local name = "check-test-corpus"
		local file = "check-test-corpus.spec.luau"
		assert.eq(string.match(file, Corpus.literal(name)) ~= nil, true)
		assert.eq(string.match(file, name .. ".*%.spec%.luau$") ~= nil, false)
	end)

	suite:case("escapes every character the matcher reads as syntax, the escape included", function(assert)
		for _, text in { "a%b", "a^b", "a$b", "a(b)", "a.b", "a[b]", "a*b", "a+b", "a-b", "a?b" } do
			assert.eq(string.match(text, Corpus.literal(text)), text)
			assert.eq(string.match(text .. "x", "^" .. Corpus.literal(text) .. "$") == nil, true)
		end
	end)
end)

test.suite("corpus selection", function(suite)
	local FILES = {
		"shared/BalanceLab.spec.luau",
		"tools/check-test-corpus-routing.spec.luau",
		"tools/check-test-corpus.spec.luau",
		"tools/worker-setup.spec.luau",
	}

	suite:case("narrows to the files whose name carries a literal fragment", function(assert)
		assert.eq(selected(FILES, { name = "worker-setup" }), { "tools/worker-setup.spec.luau" })
	end)

	suite:case("uses an already-complete pattern exactly as given rather than doubling it", function(assert)
		assert.eq(selected(FILES, { pattern = "^BalanceLab%.spec%.luau$" }), { "shared/BalanceLab.spec.luau" })
		assert.eq(#selected(FILES, { pattern = "%.spec%.luau$" }), #FILES)
	end)

	suite:case("keeps only the files under a named root", function(assert)
		assert.eq(selected(FILES, { root = "shared" }), { "shared/BalanceLab.spec.luau" })
	end)

	suite:case("keeps every file when the query names nothing", function(assert)
		assert.eq(#selected(FILES, nil), #FILES)
		assert.eq(#selected(FILES, {}), #FILES)
	end)

	suite:case("selects nothing at all when nothing matched, rather than everything", function(assert)
		assert.eq(selected(FILES, { name = "no-such-unit" }), {})
	end)

	suite:case("refuses a query naming both a pattern and a literal name", function(assert)
		local asked, thrown: any = pcall(Corpus.selection, FILES, { name = "a", pattern = "b" })
		assert.eq(asked, false)
		assert.strContains(tostring(thrown), "never both")
	end)
end)

test.suite("corpus lock bytes", function(suite)
	suite:case("emits a frozen module a consumer can compare byte for byte", function(assert)
		local text = Corpus.lockText {
			{ name = "tier1", fields = { { name = "count", value = 12 }, { name = "digest", value = "abc-1" } } },
		}
		assert.eq(
			text,
			table.concat({
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
			}, "\n")
		)
	end)

	suite:case("emits sections in the order it was given them", function(assert)
		local text = Corpus.lockText {
			{ name = "second", fields = { { name = "count", value = 2 } } },
			{ name = "first", fields = { { name = "count", value = 1 } } },
		}
		assert.that((string.find(text, "second", 1, true) :: number) < (string.find(text, "first", 1, true) :: number))
	end)

	suite:case("refuses a field that is neither a number nor a string", function(assert)
		local emitted, thrown: any =
			pcall(Corpus.lockText, { { name = "s", fields = { { name = "f", value = true :: any } } } })
		assert.eq(emitted, false)
		assert.strContains(tostring(thrown), "neither a number nor a string")
	end)
end)
