--!strict

local fs = require "@std/fs"
local task = require "@std/task"

local Files = require "../src/lute/files"
local Lute = require "../src/lute"
local Verify = require "../src/core"

return function(suite: Verify.Harness)
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

	suite:suite("concurrent directory creation", function()
		suite:case("exists-then-create loses under contention", function(check)
			local raised = 0
			for round = 1, ROUNDS do
				local tree = freshTree("falsifier", round)
				raised += race(function()
					if not fs.exists(tree) then
						fs.createDirectory(tree, { makeParents = true })
					end
				end)
			end

			check:expect(raised > 0):toEqual(true)
		end)

		suite:case("ten callers asking for one absent tree at once all succeed", function(check)
			for round = 1, ROUNDS do
				local tree = freshTree("shared", round)
				check
					:expect((race(function()
						Files.ensureDirectory(tree)
					end)))
					:toEqual(0)
				check:expect((fs.exists(tree))):toEqual(true)
			end
		end)

		suite:case("an existing tree is not created again and is not an error", function(check)
			local tree = freshTree("warm", 1)
			Files.ensureDirectory(tree)
			check
				:expect((race(function()
					Files.ensureDirectory(tree)
				end)))
				:toEqual(0)
			check:expect((fs.exists(tree))):toEqual(true)
		end)

		suite:case("names the directory when it genuinely cannot be created", function(check)
			Files.ensureDirectory(ROOT)
			local blocker = ROOT .. "/blocker"
			fs.writeStringToFile(blocker, "not a directory")
			local made, thrown: any = pcall(Files.ensureDirectory, blocker .. "/beneath")
			check:expect(made):toEqual(false)
			check:expect((tostring(thrown))):toContain "could not be created"
			check:expect((tostring(thrown))):toContain "beneath"
		end)
	end)

	suite:suite("concurrent file removal and listing", function()
		suite:case("ten callers removing one file at once all succeed", function(check)
			Files.ensureDirectory(ROOT)
			local path = ROOT .. "/contended.json"
			fs.writeStringToFile(path, "{}")
			check
				:expect((race(function()
					Files.removeIfPresent(path)
				end)))
				:toEqual(0)
			check:expect((fs.exists(path))):toEqual(false)
		end)

		suite:case("removing what was never there is not an error", function(check)
			Files.ensureDirectory(ROOT)
			check:expect((pcall(Files.removeIfPresent, ROOT .. "/never-written.json"))):toEqual(true)
		end)

		suite:case("listing a directory that is not there yields nothing", function(check)
			check:expect((#Files.listFileNames(ROOT .. "/never-created"))):toEqual(0)
		end)

		suite:case("lists the files in a directory and not its subdirectories", function(check)
			local directory = ROOT .. "/listing"
			Files.ensureDirectory(directory .. "/nested")
			fs.writeStringToFile(directory .. "/one.json", "1")
			local names = Files.listFileNames(directory)
			check:expect(#names):toEqual(1)
			check:expect(names[1]):toEqual "one.json"
		end)
	end)

	suite:suite("host filesystem concurrency", function()
		suite:case("dispatches ten parallel batches into a directory nothing created first", function(check)
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
			check:expect((table.concat(faulted, "; "))):toEqual ""
			check:expect(execution.report.passed):toEqual(CALLERS)
			check:expect(execution.report.failed):toEqual(0)
		end)
	end)
end
