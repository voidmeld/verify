--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local system = require "@std/system"
local task = require "@std/task"

local Files = require "../src/lute/files"
local Paths = require "../src/core/path"
local Lute = require "../src/lute"
local Verify = require "../src/core"

return function(suite: Verify.Harness)
	local ROOT = Files.claimDirectory ".lute/tmp/verify-files-spec"

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
			local made, thrown: unknown = pcall(Files.ensureDirectory, blocker .. "/beneath")
			check:expect(made):toEqual(false)
			check:expect((tostring(thrown))):toContain "could not be created"
			check:expect((tostring(thrown))):toContain "beneath"
		end)
	end)

	suite:suite("concurrent file removal", function()
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

	suite:suite("platform paths", function()
		suite:case("creates each parent of a drive path with either separator", function(check)
			local made: { string } = {}
			local present: { [string]: boolean } = { ["C:"] = true }
			local bound = Files.create {
				read = function(): string
					return ""
				end,
				write = function() end,
				exists = function(path: string): boolean
					return present[path] == true
				end,
				createDirectory = function(path: string)
					table.insert(made, path)
					present[path] = true
				end,
				remove = function() end,
			}
			bound.ensureDirectory "C:\\work\\run/leaf"
			check:expect(made):toEqual { "C:\\work", "C:\\work\\run", "C:\\work\\run/leaf" }
			table.clear(made)
			bound.ensureDirectory "relative\\name/leaf"
			check:expect(made):toEqual { "relative\\name", "relative\\name/leaf" }
		end)

		suite:case("resolves, names and places paths in the form of the host platform", function(check)
			check:expect(Paths.collapse "C:/work/../run/./case"):toEqual "C:/run/case"
			check:expect(Paths.collapse "/../../case"):toEqual "/case"
			check
				:expect(function()
					Paths.collapse("../case", "outside root")
				end)
				:toThrow "outside root"
			local cwd = tostring(process.cwd())
			if system.win32 then
				local slashed = string.gsub(cwd, "\\", "/")
				local temporary = string.gsub(tostring(system.tmpdir()), "\\", "/")
				check:expect(Files.absolute "C:\\work\\a"):toEqual "C:/work/a"
				check:expect(Files.absolute "rel\\a"):toEqual(slashed .. "/rel/a")
				check:expect(Files.hasScheme "C:/work/a.png"):toBe(false)
				check:expect(Files.hasScheme "C:\\work\\a.png"):toBe(false)
				check:expect(Files.temporary "verify-x"):toEqual(temporary .. "/verify-x")
			else
				check:expect(Files.absolute "/work/a"):toEqual "/work/a"
				check:expect(Files.absolute "rel/a"):toEqual(cwd .. "/rel/a")
				check:expect(Files.hasScheme "C:/work/a.png"):toBe(true)
				check:expect(Files.temporary "verify-x"):toEqual "/tmp/verify-x"
			end
			check:expect(Files.hasScheme "rbxtemp://1"):toBe(true)
			check:expect(Files.hasScheme "https://example.com/a.png"):toBe(true)
			check:expect(Files.hasScheme "artifacts/a.png"):toBe(false)
			check:expect((pcall(Files.temporary, "a/b"))):toBe(false)
		end)
	end)
end
