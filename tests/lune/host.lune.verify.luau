--!strict

local load = require :: (string) -> unknown
local fs = load "@lune/fs" :: {
	readDir: (string) -> { string },
	readFile: (string) -> string,
	isFile: (string) -> boolean,
	writeDir: (string) -> (),
}
local task = load "@lune/task" :: { wait: (number?) -> number }

local Bounded = require "../../src/runtime/bounded"
local Lune = require "../../src/lune"
local Verify = require "../../src/core"

local WORKERS = "tests/lune/workers/"
local SCRATCH = ".verify/lune-test/"

local function unit(id: string, group: string?): Verify.PlanUnitDraft
	return { id = id, locator = id, group = group }
end

type Extra = { deadlineSeconds: number?, command: { string }? }

local function hostFor(
	worker: string,
	name: string,
	extra: { deadlineSeconds: number?, command: { string }? }?
): Verify.Host
	local settings: Extra = extra or {}
	return Lune.host {
		worker = WORKERS .. worker .. ".luau",
		directory = SCRATCH .. name,
		deadlineSeconds = settings.deadlineSeconds or 30,
		command = settings.command,
	}
end

local function batchOf(id: string, locators: { string }): Verify.PlanBatch
	local units: { Verify.PlanUnit } = {}
	for _, locator in locators do
		table.insert(units, {
			id = locator,
			locator = locator,
			group = nil,
			tags = {},
			requires = {},
			deadlineSeconds = nil,
			weight = 1,
		})
	end
	return { id = id, index = 1, units = units }
end

local function statuses(report: Verify.Report): { [string]: string }
	local result: { [string]: string } = {}
	for _, item in report.results do
		result[item.id] = item.status
	end
	return result
end

local function faultOf(worker: string, name: string): Verify.BatchOutcome
	return hostFor(worker, name).runBatch(batchOf(name, { "pass" }))
end

return function(suite: Verify.Harness)
	suite:suite("lune host (real lune subprocesses)", function()
		suite:case("returns validated reports with preserved case ids and classified load failures", function(check)
			local locators =
				{ "pass", "fail", "load-error", "not-function", "registration-error", "needs-gpu", "skip-me" }
			local outcome = hostFor("main", "mixed").runBatch(batchOf("mixed", locators))
			check:expect(outcome.status):toBe "returned"
			local report = outcome.report :: Verify.Report
			check:expect(statuses(report)):toEqual {
				["pass::fixture > first"] = "passed",
				["pass::fixture > second"] = "passed",
				["fail::fixture > first"] = "passed",
				["fail::fixture > broken"] = "failed",
				["unit:load-error:load"] = "failed",
				["unit:not-function:load"] = "failed",
				["unit:registration-error:registration"] = "failed",
				["unit:needs-gpu:load"] = "unsupported",
				["unit:skip-me:load"] = "skipped",
			}
			check:expect(report.executor):toBe "lune"
		end)

		suite:case("runs several isolated batches concurrently through the standard executor", function(check)
			local plan: Verify.PlanDraft = {
				id = "parallel",
				units = { unit("pass", "a"), unit("fail", "b"), unit("load-error", "c") },
			}
			local execution = Verify.execute(plan, hostFor("main", "parallel"), { batchCount = 3, parallel = 3 })
			local seen = statuses(execution.report)
			check:expect(seen["pass::fixture > first"]):toBe "passed"
			check:expect(seen["fail::fixture > broken"]):toBe "failed"
			check:expect(seen["unit:load-error:load"]):toBe "failed"
			check:expect(execution.report.passed < execution.report.total):toBe(true)
		end)

		suite:case("carries an inline attachment in the returned report", function(check)
			local outcome = hostFor("main", "attach").runBatch(batchOf("attach", { "attach" }))
			check:expect(outcome.status):toBe "returned"
			local artifact = (outcome.report :: Verify.Report).results[1].artifacts[1]
			check:expect(artifact.name):toBe "lune.txt"
			check:expect(artifact.content):toBe "from lune"
			check:expect(artifact.mediaType):toBe "text/plain"
		end)

		suite:case("supports self-registering workers", function(check)
			local outcome = hostFor("self-registering", "self").runBatch(batchOf("self", { "pass" }))
			check:expect(outcome.status):toBe "returned"
			check:expect(statuses(outcome.report :: Verify.Report)["pass::fixture > second"]):toBe "passed"
		end)

		suite:case("never lets empty discovery pass", function(check)
			local empty = hostFor("main", "empty").runBatch(batchOf("empty", {}))
			check:expect(empty.status):toBe "returned"
			check:expect((empty.report :: Verify.Report).total):toBe(0)
			local execution = Verify.execute({ id = "empty", units = {} }, hostFor("main", "empty-plan"))
			check:expect(statuses(execution.report)["execution:no-cases:empty"]):toBe "failed"
		end)

		suite:case("keeps worker output as a log beside the receipt", function(check)
			local outcome = hostFor("loud", "log").runBatch(batchOf("log", { "pass" }))
			check:expect(outcome.status):toBe "returned"
			local found = false
			for _, name in fs.readDir(SCRATCH .. "log") do
				if string.sub(name, -11) == "-worker.log" then
					found = string.find(fs.readFile(SCRATCH .. "log/" .. name), "worker-says-hello", 1, true) ~= nil
				end
			end
			check:expect(found):toBe(true)
		end)

		suite:case("faults rather than passes when the worker breaks the receipt contract", function(check)
			local expectations: { { worker: string, detail: string } } = {
				{ worker = "silent", detail = "wrote no receipt" },
				{ worker = "malformed", detail = "malformed receipt" },
				{ worker = "legacy-report", detail = "malformed receipt" },
				{ worker = "stale", detail = "stale receipt" },
				{ worker = "foreign", detail = "foreign receipt" },
				{ worker = "invalid", detail = "invalid receipt" },
				{ worker = "exit-nonzero", detail = "exited 3 yet wrote a valid receipt" },
			}
			for _, expected in expectations do
				local outcome = faultOf(expected.worker, "fault-" .. expected.worker)
				check:expect(outcome.status):toBe "faulted"
				check:expect(string.find(outcome.detail or "", expected.detail, 1, true) ~= nil):toBe(true)
				check:expect(outcome.report):toBe(nil)
			end
		end)

		suite:case("a faulted batch makes the standard execution fail", function(check)
			local execution =
				Verify.execute({ id = "faulted", units = { unit "pass" } }, hostFor("silent", "faulted-plan"))
			check:expect(execution.report.passed):toBe(0)
			check:expect(execution.report.failed > 0):toBe(true)
		end)

		suite:case("keeps the recorded load failure of a module that raises at require", function(check)
			local outcome =
				hostFor("require-raises", "require-raises").runBatch(batchOf("require-raises", { "raises", "pass" }))
			check:expect(outcome.status):toBe "returned"
			local report = assert(outcome.report) :: Verify.Report
			local found: { [string]: string } = statuses(report)
			check:expect(found["unit:raises:load"]):toBe "failed"
			check:expect(report.failed):toBe(1)
			check:expect(report.passed):toBe(1)
			local disagreeing = faultOf("exit-nonzero", "exit-disagrees")
			check:expect(disagreeing.status):toBe "faulted"
		end)

		suite:case("faults when the worker cannot start or does not exist", function(check)
			local missing = hostFor("absent", "absent").runBatch(batchOf("absent", { "pass" }))
			check:expect(missing.status):toBe "faulted"
			check:expect(string.find(missing.detail or "", "wrote no receipt", 1, true) ~= nil):toBe(true)
			local unstartable = hostFor("main", "unstartable", { command = { "/nonexistent/lune", "run" } }).runBatch(
				batchOf("unstartable", { "pass" })
			)
			check:expect(unstartable.status):toBe "faulted"
		end)

		suite:case("kills a hung worker and its descendants at the deadline", function(check)
			local began = os.clock()
			local outcome = hostFor("hang", "hang", { deadlineSeconds = 1 }).runBatch(batchOf("hang", { "pass" }))
			check:expect(outcome.status):toBe "timed_out"
			check:expect(os.clock() - began < 4):toBe(true)
			task.wait(4.5)
			local survived = false
			for _, name in fs.readDir(SCRATCH .. "hang") do
				if string.sub(name, -9) == ".survivor" then
					survived = true
				end
			end
			check:expect(survived):toBe(false)
		end)

		suite:case("kills descendants under dash and fails closed when no group can be made", function(check)
			fs.writeDir(SCRATCH .. "shells")
			local runs = 0
			for _, shell in { "sh", "/bin/dash" } do
				for _, mechanism in { "auto", "none" } do
					runs += 1
					local marker = ("%sshells/marker-%d"):format(SCRATCH, runs)
					local result = Bounded.run(
						{ "/bin/sh", "-c", ("(sleep 2; echo late > %s) & sleep 8"):format(marker) },
						1,
						Lune.runtime.process.run,
						nil,
						{ shell = shell, mechanism = mechanism :: Bounded.Mechanism }
					)
					check:expect(result.ok):toBe(false)
					check:expect(result.timedOut or result.unsupported):toBe(true)
					check:expect(mechanism ~= "none" or result.unsupported):toBe(true)
					task.wait(2.5)
					check:expect(fs.isFile(marker)):toBe(false)
				end
			end
		end)

		suite:case("the descendant marker is observable when nothing kills it", function(check)
			fs.writeDir(SCRATCH .. "control")
			local marker = SCRATCH .. "control/marker"
			local result = Lune.runBounded({ "/bin/sh", "-c", "(sleep 1; echo ok > " .. marker .. ") & wait" }, 10)
			check:expect(result.ok):toBe(true)
			check:expect(fs.isFile(marker)):toBe(true)
		end)
	end)
end
