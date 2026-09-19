--!strict

local fs = require "@std/fs"
local task = require "@std/task"
local test = require "@std/test"

local Files = require "../src/lute/files"
local Lute = require "../src/lute"
local Verify = require "../src/core"

local ROOT: string
do
	local slot = 1
	while true do
		local candidate = (".lute/tmp/verify-files-spec-%d"):format(slot)
		local asked, answer = pcall(function()
			local fs = require "@std/fs"
			return fs.exists(candidate)
		end)
		if not (asked and answer == true) then
			ROOT = candidate
			break
		end
		slot += 1
	end
end

local CALLERS = 10
local ROUNDS = 5

local function freshTree(label: string, round: number): string
	local tree = ("%s/%s-%d"):format(ROOT, label, round)
	return tree .. "/a/b/leaf"
end

local function fixture(index: number): string
	local directory = ROOT .. "/units"
	Files.ensureDirectory(directory)
	local locator = ("%s/unit%d.luau"):format(directory, index)
	fs.writeStringToFile(
		locator,
		table.concat({
			"--!strict",
			"return function(harness)",
			'\tharness:suite("parallel", function()',
			('\t\tharness:case("unit %d passes", function(context)'):format(index),
			"\t\t\tcontext:expect(true):toBe(true)",
			"\t\tend)",
			"\tend)",
			"end",
			"",
		}, "\n")
	)
	return locator
end

local function race(body: (number) -> ()): number
	local raised = 0
	local finished = 0
	for index = 1, CALLERS do
		task.spawn(function()
			if not pcall(body, index) then
				raised += 1
			end
			finished += 1
		end)
	end
	while finished < CALLERS do
		task.wait(0.002)
	end
	return raised
end

test.suite("concurrent directory creation", function(suite)
	suite:case("exists-then-create loses under contention", function(assert)
		local raised = 0
		for round = 1, ROUNDS do
			local tree = freshTree("falsifier", round)
			raised += race(function()
				if not fs.exists(tree) then
					fs.createDirectory(tree, { makeParents = true })
				end
			end)
		end

		assert.eq(raised > 0, true)
	end)

	suite:case("ten callers asking for one absent tree at once all succeed", function(assert)
		for round = 1, ROUNDS do
			local tree = freshTree("shared", round)
			assert.eq(
				race(function()
					Files.ensureDirectory(tree)
				end),
				0
			)
			assert.eq(fs.exists(tree), true)
		end
	end)

	suite:case("an existing tree is not created again and is not an error", function(assert)
		local tree = freshTree("warm", 1)
		Files.ensureDirectory(tree)
		assert.eq(
			race(function()
				Files.ensureDirectory(tree)
			end),
			0
		)
		assert.eq(fs.exists(tree), true)
	end)

	suite:case("names the directory when it genuinely cannot be created", function(assert)
		Files.ensureDirectory(ROOT)
		local blocker = ROOT .. "/blocker"
		fs.writeStringToFile(blocker, "not a directory")
		local made, thrown: any = pcall(Files.ensureDirectory, blocker .. "/beneath")
		assert.eq(made, false)
		assert.strContains(tostring(thrown), "could not be created")
		assert.strContains(tostring(thrown), "beneath")
	end)
end)

test.suite("concurrent file removal and listing", function(suite)
	suite:case("ten callers removing one file at once all succeed", function(assert)
		Files.ensureDirectory(ROOT)
		local path = ROOT .. "/contended.json"
		fs.writeStringToFile(path, "{}")
		assert.eq(
			race(function()
				Files.removeIfPresent(path)
			end),
			0
		)
		assert.eq(fs.exists(path), false)
	end)

	suite:case("removing what was never there is not an error", function(assert)
		Files.ensureDirectory(ROOT)
		assert.eq(pcall(Files.removeIfPresent, ROOT .. "/never-written.json"), true)
	end)

	suite:case("listing a directory that is not there yields nothing", function(assert)
		assert.eq(#Files.listFileNames(ROOT .. "/never-created"), 0)
	end)

	suite:case("lists the files in a directory and not its subdirectories", function(assert)
		local directory = ROOT .. "/listing"
		Files.ensureDirectory(directory .. "/nested")
		fs.writeStringToFile(directory .. "/one.json", "1")
		local names = Files.listFileNames(directory)
		assert.eq(#names, 1)
		assert.eq(names[1], "one.json")
	end)
end)

test.suite("host filesystem concurrency", function(suite)
	suite:case("dispatches ten parallel batches into a directory nothing created first", function(assert)
		local units: { Verify.PlanUnitDraft } = {}
		for index = 1, CALLERS do
			table.insert(units, { id = ("u%d"):format(index), locator = fixture(index) })
		end
		local plan: Verify.PlanDraft = { id = "parallel-scratch", units = units }
		local execution = Verify.execute(
			plan,
			Lute.host { worker = "examples/worker.luau", directory = ROOT .. "/host/fresh/tree" },
			{ batchCount = CALLERS, parallel = CALLERS }
		)
		local faulted: { string } = {}
		for _, attempt in execution.attempts do
			if attempt.status ~= "returned" then
				table.insert(faulted, tostring(attempt.detail))
			end
		end
		assert.eq(table.concat(faulted, "; "), "")
		assert.eq(execution.report.passed, CALLERS)
		assert.eq(execution.report.failed, 0)
	end)
end)
