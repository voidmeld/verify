--!strict

local load = require :: (string) -> unknown
local fs = load "@lune/fs" :: { readFile: (string) -> string }

local Lune = require "../../src/lune"
local Verify = require "../../src/core"
local Gate = require "../../src/gate"

local SCRATCH = ".verify/lune-test/gate"

local function recordOf(outcome: Gate.Outcome, id: string): Gate.Record
	for _, record in outcome.producers do
		if record.id == id then
			return record
		end
	end
	error("no record for " .. id)
end

local function run(label: string, producers: { Gate.ProducerDraft }, policy: Gate.PolicyDraft?)
	local gate = Gate.define { id = label, producers = producers, policy = policy }
	return Lune.gate.run(gate, { directory = SCRATCH, runId = label })
end

return function(suite: Verify.Harness)
	suite:suite("gate on the Lune runtime (real lune subprocesses)", function()
		suite:case("classifies exits, passes environment and working directory, and keeps logs", function(check)
			local outcome = run("lune-commands", {
				{ id = "good", kind = "command", argv = { "/bin/sh", "-c", "echo ok" } },
				{ id = "bad", kind = "command", argv = { "/bin/sh", "-c", "echo oops >&2; exit 3" } },
				{
					id = "context",
					kind = "command",
					argv = { "/bin/sh", "-c", 'test "$GATE_PROBE" = yes && test "$(basename "$(pwd)")" = workers' },
					env = { GATE_PROBE = "yes" },
					cwd = "tests/lune/workers",
				},
			})
			check:expect(recordOf(outcome, "good").status):toBe "passed"
			check:expect(recordOf(outcome, "bad").status):toBe "failed"
			check:expect(recordOf(outcome, "bad").exitcode):toBe(3)
			check:expect(recordOf(outcome, "context").status):toBe "passed"
			local log = assert(recordOf(outcome, "bad").log)
			local reference = assert(log.reference)
			check:expect(fs.readFile(reference)):toContain "oops"
			check:expect(outcome.acceptance.verdict):toBe "failed"
		end)

		suite:case("bounds a command at its deadline", function(check)
			local outcome = run(
				"lune-deadline",
				{ { id = "hung", kind = "command", argv = { "/bin/sh", "-c", "sleep 8" }, deadlineSeconds = 1 } }
			)
			check:expect(recordOf(outcome, "hung").status):toBe "timed_out"
		end)

		suite:case("runs test modules in a Lune worker and accounts every module", function(check)
			local producer: Gate.ProducerDraft = {
				id = "specs",
				kind = "tests",
				worker = "tests/lune/workers/main.luau",
				locators = { "pass" },
				deadlineSeconds = 30,
			}
			local outcome = run("lune-tests", { producer })
			check:expect(recordOf(outcome, "specs").status):toBe "passed"
			check:expect(outcome.acceptance.verdict):toBe "release"
			local missing = run("lune-tests-missing", {
				{
					id = "specs",
					kind = "tests",
					worker = "tests/lune/workers/silent.luau",
					locators = { "pass" },
					deadlineSeconds = 30,
				},
			})
			check:expect(recordOf(missing, "specs").status):toBe "failed"
		end)

		suite:case("runs isolated sources as one producer and attributes each fault to its source", function(check)
			local outcome = run("lune-isolated", {
				{
					id = "specs",
					kind = "tests",
					worker = "tests/lune/workers/main.luau",
					locators = { "pass", "load-error", "fail" },
					isolate = true,
					workers = 2,
					deadlineSeconds = 60,
				},
			})
			local record = recordOf(outcome, "specs")
			check:expect(record.status):toBe "failed"
			check:expect(#outcome.producers):toBe(1)
			local cases = Gate.testCases(outcome)
			check:expect(cases.passed):toBe(3)
			check:expect(cases.failed):toBe(2)
			local sources: { string } = {}
			for _, result in cases.results do
				if result.status == "failed" then
					table.insert(sources, tostring(result.source))
				end
			end
			table.sort(sources)
			check:expect(sources):toEqual { "fail", "load-error" }
		end)

		suite:case("times a hung source out alone against its own deadline", function(check)
			local outcome = run("lune-source-deadline", {
				{
					id = "specs",
					kind = "tests",
					worker = "tests/lune/workers/main.luau",
					locators = { "hang", "pass" },
					isolate = true,
					workers = 1,
					sourceDeadlineSeconds = 1,
					deadlineSeconds = 60,
				},
			})
			local cases = Gate.testCases(outcome)
			check:expect(cases.timedOut):toBe(1)
			check:expect(cases.passed):toBe(2)
			for _, result in cases.results do
				if result.status == "timed_out" then
					check:expect(result.source):toBe "hang"
				end
			end
		end)

		suite:case("hands the selected tier to a Lune worker and keeps the run selected", function(check)
			local gate = Gate.define {
				id = "lune-tier",
				producers = {
					{
						id = "specs",
						kind = "tests",
						worker = "tests/lune/workers/main.luau",
						locators = { "pass" },
						tier = "fast",
						deadlineSeconds = 60,
					},
					{ id = "other", kind = "command", argv = { "/bin/sh", "-c", "echo ok" }, tier = "slow" },
				},
			}
			local outcome =
				Lune.gate.run(gate, { directory = SCRATCH, runId = "lune-tier", selection = { tiers = { "fast" } } })
			check:expect(recordOf(outcome, "specs").status):toBe "passed"
			check:expect(outcome.acceptance.verdict):toBe "selected"
			check:expect(outcome.acceptance.skippedByTier):toEqual { "other" }
		end)
	end)
end
