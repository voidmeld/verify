--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Verify = require "../src/core"
local Benchmark = require "../src/benchmark"
local Gate = require "../src/gate"

type Behavior = {
	seconds: number?,
	outcome: ((job: Gate.Job) -> Gate.JobOutcome)?,
	raises: string?,
}

type Fake = {
	executor: Gate.Executor,
	started: { string },
	deadlines: { [string]: number },
	peak: number,
}

local function exited(code: number, stdout: string?, stderr: string?): Gate.JobOutcome
	return {
		started = true,
		exitcode = code,
		timedOut = false,
		stdout = stdout or "",
		stderr = stderr or "",
	}
end

local function withReport(outcome: Gate.JobOutcome, report: unknown): Gate.JobOutcome
	outcome.report = report
	return outcome
end

local function reportOf(cases: { { name: string, pass: boolean } }, source: string?): Verify.Report
	local clock = 0
	local harness = Verify.createHarness {
		now = function()
			clock += 0.001
			return clock
		end,
		source = source,
		prefixIds = false,
	}
	for _, entry in cases do
		harness:case(entry.name, function(context)
			context:expect(entry.pass):toBe(true)
		end)
	end
	return harness:run { executor = "child" }
end

local function envelope(job: Gate.Job, report: Verify.Report): unknown
	return { runId = job.runId, report = report }
end

local function fakeExecutor(behaviors: { [string]: Behavior }): Fake
	local clock = 0
	local active = 0
	local fake: Fake = {
		started = {},
		deadlines = {},
		peak = 0,
		executor = {
			now = function()
				return clock
			end,
			wait = function(seconds: number)
				clock += seconds
			end,
			start = function(job: Gate.Job): Gate.Task
				error "replaced below"
			end,
		},
	}
	fake.executor.start = function(job: Gate.Job): Gate.Task
		table.insert(fake.started, job.id)
		fake.deadlines[job.id] = job.deadlineSeconds
		local behavior: Behavior = behaviors[job.id] or {}
		if behavior.raises ~= nil then
			error(behavior.raises, 0)
		end
		active += 1
		fake.peak = math.max(fake.peak, active)
		local finishAt = clock + (behavior.seconds or 0.05)
		return {
			poll = function(): Gate.JobOutcome?
				if clock < finishAt then
					return nil
				end
				active -= 1
				if behavior.outcome ~= nil then
					return behavior.outcome(job)
				end
				return exited(0)
			end,
		}
	end
	return fake
end

type Extra = {
	after: { string }?,
	tier: string?,
	deadlineSeconds: number?,
	exclusive: boolean?,
	argv: { string }?,
	exit: { [number]: Gate.ExitClass }?,
	report: Gate.ReportExpectation?,
}

local function command(id: string, extra: Extra?): Gate.ProducerDraft
	local more: Extra = extra or {}
	return {
		id = id,
		kind = "command",
		argv = more.argv or { "tool", id },
		after = more.after,
		tier = more.tier,
		deadlineSeconds = more.deadlineSeconds,
		exclusive = more.exclusive,
		exit = more.exit,
		report = more.report,
	}
end

local DEFER_75: { [number]: Gate.ExitClass } = { [75] = "deferred" }

local LENIENT: { [number]: Gate.ExitClass } = { [0] = "passed", [2] = "passed" }

type Go = {
	selection: Gate.Selection?,
	reuse: { [string]: Gate.Reuse }?,
	capabilities: { string }?,
}

local function go(gate: Gate.Definition, fake: Fake, options: Go?): Gate.Outcome
	local more: Go = options or {}
	return Gate.run(gate, fake.executor, {
		runId = "run-1",
		capabilities = more.capabilities or { "process" },
		pollSeconds = 0.1,
		selection = more.selection,
		reuse = more.reuse,
	})
end

type Declared = { cases: { string }?, isolate: boolean?, workers: number?, command: { string }? }

local function recordOf(outcome: Gate.Outcome, id: string): Gate.Record
	for _, record in outcome.producers do
		if record.id == id then
			return record
		end
	end
	error("no record for " .. id)
end

describe("gate definition", function()
	it("rejects duplicate ids, unknown or cyclic dependencies and malformed producers", function()
		expect(function()
			Gate.define { id = "g", producers = { command "a", command "a" } }
		end):toThrow "duplicate producer id"
		expect(function()
			Gate.define { id = "g", producers = { command("a", { after = { "ghost" } }) } }
		end):toThrow "unknown producer"
		expect(function()
			Gate.define {
				id = "g",
				producers = { command("a", { after = { "b" } }), command("b", { after = { "a" } }) },
			}
		end):toThrow "cycle"
		expect(function()
			Gate.define {
				id = "g",
				producers = { { id = "t", kind = "tests", worker = "w", locators = {} } },
			}
		end):toThrow "lists no test module"
		expect(function()
			Gate.define { id = "g", producers = { { id = "n", kind = "native", argv = { "x" } } } }
		end):toThrow "must name the host capability"
		expect(function()
			Gate.define { id = "g", producers = { { id = "c", kind = "command" } } }
		end):toThrow "needs a command"
		expect(function()
			Gate.define { id = "g", producers = { command "bad id" } }
		end):toThrow "must start with a letter"
		expect(function()
			Gate.define {
				id = "g",
				producers = { command "a" },
				policy = { deferrals = { ghost = "later" } },
			}
		end):toThrow "unknown producer"
		expect(function()
			Gate.define { id = "g", producers = { command "a" }, policy = { deferrals = { a = " " } } }
		end):toThrow "needs a reason"
	end)

	it("accepts env and cwd only on commands", function()
		local gate = Gate.define {
			id = "g",
			producers = { { id = "a", kind = "command", argv = { "x" }, env = { K = "v" }, cwd = "dir" } },
		}
		expect(gate.producers[1].env):toEqual { K = "v" }
		expect(gate.producers[1].cwd):toEqual "dir"
		expect(function()
			Gate.define {
				id = "g",
				producers = { { id = "t", kind = "tests", worker = "w", locators = { "l" }, cwd = "dir" } },
			}
		end):toThrow "takes only worker"
		expect(function()
			Gate.define {
				id = "g",
				producers = { { id = "a", kind = "command", argv = { "x" }, env = { [""] = "v" } } },
			}
		end):toThrow "env must map"
	end)

	it("hands env and cwd to the executor", function()
		local gate = Gate.define {
			id = "g",
			producers = { { id = "a", kind = "command", argv = { "x" }, env = { K = "v" }, cwd = "dir" } },
		}
		local seen: Gate.Job? = nil
		local fake = fakeExecutor {}
		local base = fake.executor.start
		fake.executor.start = function(job: Gate.Job): Gate.Task
			seen = job
			return base(job)
		end
		go(gate, fake)
		expect(seen ~= nil and seen.cwd):toEqual "dir"
		expect(seen ~= nil and seen.env.K):toEqual "v"
	end)

	it("allows repeated command arguments", function()
		local gate = Gate.define { id = "g", producers = { command("a", { argv = { "tool", "x", "x" } }) } }
		expect(gate.producers[1].argv):toEqual { "tool", "x", "x" }
	end)

	it("binds the declared definition into a digest", function()
		local first = Gate.define { id = "g", producers = { command "a" } }
		local same = Gate.define { id = "g", producers = { command "a" } }
		local changed = Gate.define { id = "g", producers = { command("a", { argv = { "other" } }) } }
		expect(first.digest):toEqual(same.digest)
		expect(first.digest == changed.digest):toEqual(false)
	end)
end)

describe("ordering and concurrency", function()
	it("starts a producer only after what it runs after has passed", function()
		local gate = Gate.define {
			id = "g",
			producers = { command("c", { after = { "b" } }), command("b", { after = { "a" } }), command "a" },
			policy = { concurrency = 3 },
		}
		local fake = fakeExecutor {}
		local outcome = go(gate, fake)
		expect(fake.started):toEqual { "a", "b", "c" }
		expect(fake.peak):toEqual(1)
		expect(outcome.acceptance.verdict):toEqual "release"
	end)

	it("never exceeds the concurrency bound and uses it when allowed", function()
		local producers: { Gate.ProducerDraft } = {}
		for index = 1, 6 do
			table.insert(producers, command("p" .. index))
		end
		local bounded = fakeExecutor {}
		go(Gate.define { id = "g", producers = producers, policy = { concurrency = 2 } }, bounded)
		expect(bounded.peak):toEqual(2)
		local wide = fakeExecutor {}
		go(Gate.define { id = "g", producers = producers, policy = { concurrency = 4 } }, wide)
		expect(wide.peak):toEqual(4)
		local serial = fakeExecutor {}
		go(Gate.define { id = "g", producers = producers }, serial)
		expect(serial.peak):toEqual(1)
		expect(serial.started):toEqual { "p1", "p2", "p3", "p4", "p5", "p6" }
	end)

	it("runs an exclusive producer alone", function()
		local gate = Gate.define {
			id = "g",
			producers = { command "a", command("solo", { exclusive = true }), command "b", command "c" },
			policy = { concurrency = 4 },
		}
		local fake = fakeExecutor { solo = { seconds = 1 } }
		local active = 0
		local overlapped = false
		local base = fake.executor.start
		fake.executor.start = function(job: Gate.Job): Gate.Task
			local task = base(job)
			active += 1
			if job.id == "solo" and active > 1 then
				overlapped = true
			end
			return {
				poll = function()
					local outcome = task.poll()
					if outcome ~= nil then
						active -= 1
					end
					return outcome
				end,
			}
		end
		go(gate, fake)
		expect(overlapped):toEqual(false)
		expect(fake.started[1]):toEqual "a"
		expect(table.find(fake.started, "solo")):toBeTruthy()
	end)

	it("blocks what depends on a producer that did not pass", function()
		local gate = Gate.define {
			id = "g",
			producers = { command "a", command("b", { after = { "a" } }), command "c" },
		}
		local outcome = go(
			gate,
			fakeExecutor { a = {
				outcome = function()
					return exited(1, "", "boom")
				end,
			} }
		)
		expect(recordOf(outcome, "a").status):toEqual "failed"
		expect(recordOf(outcome, "b").status):toEqual "blocked"
		expect(recordOf(outcome, "b").blockedBy):toEqual "a"
		expect(recordOf(outcome, "c").status):toEqual "passed"
		expect(outcome.acceptance.verdict):toEqual "failed"
	end)

	it("stops dispatching after the first failure under fail-fast", function()
		local gate = Gate.define {
			id = "g",
			producers = { command "a", command "b", command "c" },
			policy = { failFast = true },
		}
		local fake = fakeExecutor { a = {
			outcome = function()
				return exited(2)
			end,
		} }
		local outcome = go(gate, fake)
		expect(fake.started):toEqual { "a" }
		expect(recordOf(outcome, "b").status):toEqual "not_run"
		expect(recordOf(outcome, "c").status):toEqual "not_run"
		expect(outcome.acceptance.verdict):toEqual "failed"
	end)
end)

describe("deadlines", function()
	it("clamps a command to the remaining whole-run time and times out what cannot start", function()
		local gate = Gate.define {
			id = "g",
			producers = { command("a", { deadlineSeconds = 100 }), command "b", command "c" },
			policy = { deadlineSeconds = 5 },
		}
		local fake = fakeExecutor { a = { seconds = 6 }, b = { seconds = 1 } }
		local outcome = go(gate, fake)
		expect(fake.deadlines.a <= 5):toEqual(true)
		expect(fake.started):toEqual { "a" }
		expect(recordOf(outcome, "b").status):toEqual "timed_out"
		expect(recordOf(outcome, "c").status):toEqual "timed_out"
		expect(recordOf(outcome, "c").detail):toContain "run deadline"
		expect(outcome.acceptance.verdict):toEqual "failed"
	end)

	it("reports an enforced command timeout as timed out with its log", function()
		local gate = Gate.define { id = "g", producers = { command("slow", { deadlineSeconds = 2 }) } }
		local outcome = go(
			gate,
			fakeExecutor {
				slow = {
					outcome = function()
						local result = exited(-1, "partial output", "")
						result.timedOut = true
						result.logReference = "logs/slow.log"
						return result
					end,
				},
			}
		)
		local record = recordOf(outcome, "slow")
		expect(record.status):toEqual "timed_out"
		expect(record.timedOut):toEqual(true)
		expect(record.detail):toContain "partial output"
		expect(record.log ~= nil and record.log.reference):toEqual "logs/slow.log"
		expect(outcome.execution.report.timedOut):toEqual(1)
		expect(outcome.acceptance.releasable):toEqual(false)
	end)
end)

describe("exit codes and run-bound reports", function()
	it("fails a nonzero exit and keeps the captured output", function()
		local gate = Gate.define { id = "g", producers = { command "build" } }
		local outcome = go(
			gate,
			fakeExecutor {
				build = {
					outcome = function()
						return exited(3, "out", "err text")
					end,
				},
			}
		)
		local record = recordOf(outcome, "build")
		expect(record.status):toEqual "failed"
		expect(record.exitcode):toEqual(3)
		expect(record.detail):toContain "exited 3"
		expect(record.log ~= nil and record.log.stderr):toEqual "err text"
		expect(outcome.acceptance.verdict):toEqual "failed"
	end)

	it("classifies declared exit codes as the producer states", function()
		local gate = Gate.define {
			id = "g",
			producers = { command("lenient", { exit = LENIENT }) },
		}
		local outcome = go(
			gate,
			fakeExecutor { lenient = {
				outcome = function()
					return exited(2)
				end,
			} }
		)
		expect(recordOf(outcome, "lenient").status):toEqual "passed"
		expect(outcome.acceptance.verdict):toEqual "release"
	end)

	it("fails when the command could not be started", function()
		local gate = Gate.define { id = "g", producers = { command "ghost" } }
		local outcome = go(gate, fakeExecutor { ghost = { raises = "no such tool" } })
		expect(recordOf(outcome, "ghost").status):toEqual "failed"
		expect(recordOf(outcome, "ghost").detail):toContain "could not start"
	end)

	it("adopts a valid current-run report and accounts its cases", function()
		local gate = Gate.define {
			id = "g",
			producers = { command("probe", { report = { cases = { "one", "two" } } }) },
		}
		local outcome = go(
			gate,
			fakeExecutor {
				probe = {
					outcome = function(job)
						return withReport(
							exited(0),
							envelope(job, reportOf { { name = "one", pass = true }, { name = "two", pass = true } })
						)
					end,
				},
			}
		)
		local record = recordOf(outcome, "probe")
		expect(record.status):toEqual "passed"
		expect(record.reportAccounted):toEqual(true)
		local caseIds = table.clone(record.caseIds)
		table.sort(caseIds)
		expect(caseIds):toEqual { "probe", "probe:one", "probe:two" }
		expect(outcome.execution.report.total):toEqual(3)
		expect(outcome.acceptance.verdict):toEqual "release"
	end)

	it("fails an exit-zero command that produced no report", function()
		local gate = Gate.define { id = "g", producers = { command("probe", { report = {} }) } }
		local outcome = go(gate, fakeExecutor {})
		expect(recordOf(outcome, "probe").status):toEqual "failed"
		expect(recordOf(outcome, "probe").detail):toContain "without the expected report"
		expect(outcome.acceptance.verdict):toEqual "failed"
	end)

	it("refuses a stale or other-run report", function()
		local gate = Gate.define { id = "g", producers = { command("probe", { report = {} }) } }
		local outcome = go(
			gate,
			fakeExecutor {
				probe = {
					outcome = function()
						return withReport(
							exited(0),
							{ runId = "an-earlier-run", report = reportOf { { name = "one", pass = true } } }
						)
					end,
				},
			}
		)
		expect(recordOf(outcome, "probe").status):toEqual "failed"
		expect(recordOf(outcome, "probe").detail):toContain "not the current run"
		expect(outcome.acceptance.releasable):toEqual(false)
	end)

	it("refuses a malformed report and a report lacking an expected case", function()
		local gate = Gate.define {
			id = "g",
			producers = { command("probe", { report = { cases = { "one", "missing" } } }) },
		}
		local malformed = go(
			gate,
			fakeExecutor {
				probe = {
					outcome = function(job)
						return withReport(exited(0), { runId = job.runId, report = "x" })
					end,
				},
			}
		)
		expect(recordOf(malformed, "probe").detail):toContain "invalid"
		local partial = go(
			gate,
			fakeExecutor {
				probe = {
					outcome = function(job)
						return withReport(exited(0), envelope(job, reportOf { { name = "one", pass = true } }))
					end,
				},
			}
		)
		expect(recordOf(partial, "probe").detail):toContain "absent from the report"
		expect(partial.acceptance.verdict):toEqual "failed"
	end)

	it("fails when exit and report disagree in either direction", function()
		local gate = Gate.define { id = "g", producers = { command("probe", { report = {} }) } }
		local failingReport = go(
			gate,
			fakeExecutor {
				probe = {
					outcome = function(job)
						return withReport(exited(0), envelope(job, reportOf { { name = "one", pass = false } }))
					end,
				},
			}
		)
		expect(recordOf(failingReport, "probe").status):toEqual "failed"
		expect(recordOf(failingReport, "probe").detail):toContain "did not pass"
		local failingExit = go(
			gate,
			fakeExecutor {
				probe = {
					outcome = function(job)
						return withReport(exited(1), envelope(job, reportOf { { name = "one", pass = true } }))
					end,
				},
			}
		)
		expect(recordOf(failingExit, "probe").status):toEqual "failed"
		expect(failingExit.acceptance.verdict):toEqual "failed"
		expect(recordOf(failingExit, "probe").reportAccounted):toEqual(true)
		expect(failingExit.execution.report.total):toEqual(2)
	end)
end)

describe("test modules", function()
	local function gateOf(): Gate.Definition
		return Gate.define {
			id = "g",
			producers = {
				{
					id = "specs",
					kind = "tests",
					worker = "worker.luau",
					locators = { "a.verify.luau", "b.verify.luau" },
				},
			},
		}
	end

	local function moduleReport(sources: { string }): unknown
		local cases: { { name: string, pass: boolean } } = {}
		for _, source in sources do
			table.insert(cases, { name = source, pass = true })
		end
		local report = reportOf(cases)
		for index, source in sources do
			report.results[index].source = source
		end
		return report
	end

	it("passes when every module reports a case", function()
		local outcome = go(
			gateOf(),
			fakeExecutor {
				specs = {
					outcome = function()
						return withReport(exited(0), moduleReport { "a.verify.luau", "b.verify.luau" })
					end,
				},
			}
		)
		expect(recordOf(outcome, "specs").status):toEqual "passed"
		expect(recordOf(outcome, "specs").reportAccounted):toEqual(true)
		expect(outcome.acceptance.verdict):toEqual "release"
	end)

	it("fails a module that reported no case", function()
		local outcome = go(
			gateOf(),
			fakeExecutor {
				specs = {
					outcome = function()
						return withReport(exited(0), moduleReport { "a.verify.luau" })
					end,
				},
			}
		)
		expect(recordOf(outcome, "specs").status):toEqual "failed"
		expect(recordOf(outcome, "specs").detail):toContain "b.verify.luau"
	end)

	it("fails a clean exit without a report", function()
		local outcome = go(gateOf(), fakeExecutor {})
		expect(recordOf(outcome, "specs").status):toEqual "failed"
		expect(recordOf(outcome, "specs").detail):toContain "without the expected report"
	end)

	it("accepts a module declared silent and still fails an undeclared one", function()
		local function silentGate(silent: { string }): Gate.Definition
			return Gate.define {
				id = "g",
				producers = {
					{
						id = "specs",
						kind = "tests",
						worker = "worker.luau",
						locators = { "a.verify.luau", "b.verify.luau" },
						silent = silent,
					},
				},
			}
		end
		local only = fakeExecutor {
			specs = {
				outcome = function()
					return withReport(exited(0), moduleReport { "a.verify.luau" })
				end,
			},
		}
		expect(recordOf(go(silentGate { "b.verify.luau" }, only), "specs").status):toEqual "passed"
		local undeclared = go(silentGate {}, only)
		expect(recordOf(undeclared, "specs").status):toEqual "failed"
		expect(recordOf(undeclared, "specs").detail):toContain "b.verify.luau"
		expect((pcall(silentGate, { "c.verify.luau" }))):toEqual(false)
	end)

	it("reports only the modules' own cases without the producer-level case", function()
		local outcome = go(
			gateOf(),
			fakeExecutor {
				specs = {
					outcome = function()
						return withReport(exited(0), moduleReport { "a.verify.luau", "b.verify.luau" })
					end,
				},
			}
		)
		expect(outcome.execution.report.total):toEqual(3)
		local cases = Gate.testCases(outcome)
		expect(cases.total):toEqual(2)
		expect(cases.passed):toEqual(2)
	end)
end)

describe("hosts and deferral", function()
	local native: Gate.Draft = {
		id = "g",
		producers = {
			command "portable",
			{ id = "studio", kind = "native", argv = { "run-native" }, requires = { "native-studio" } },
		},
	}

	it("treats an unsupported required host as a failure, never a pass", function()
		local outcome = go(Gate.define(native), fakeExecutor {})
		expect(recordOf(outcome, "studio").status):toEqual "unsupported"
		expect(outcome.acceptance.verdict):toEqual "failed"
		expect(outcome.acceptance.releasable):toEqual(false)
		expect(outcome.execution.report.unsupported):toEqual(1)
	end)

	it("runs the native producer when the host declares the capability", function()
		local outcome = go(Gate.define(native), fakeExecutor {}, { capabilities = { "native-studio" } })
		expect(recordOf(outcome, "studio").status):toEqual "passed"
		expect(outcome.acceptance.verdict):toEqual "release"
	end)

	it("defers only what the policy names, and a deferral is not a release", function()
		local deferring = table.clone(native)
		deferring.policy = { deferrals = { studio = "needs an interactive session" } }
		local outcome = go(Gate.define(deferring), fakeExecutor {})
		expect(recordOf(outcome, "studio").status):toEqual "deferred"
		expect(recordOf(outcome, "studio").deferral):toEqual "needs an interactive session"
		expect(outcome.acceptance.verdict):toEqual "deferred"
		expect(outcome.acceptance.releasable):toEqual(false)
		expect(outcome.acceptance.deferred):toEqual { "studio" }
		expect(outcome.execution.report.unsupported):toEqual(1)
	end)

	it("fails an exit-code deferral the policy does not permit", function()
		local gate = Gate.define { id = "g", producers = { command("probe", { exit = DEFER_75 }) } }
		local outcome = go(
			gate,
			fakeExecutor { probe = {
				outcome = function()
					return exited(75)
				end,
			} }
		)
		expect(recordOf(outcome, "probe").status):toEqual "failed"
		expect(recordOf(outcome, "probe").detail):toContain "permits none"
		local permitted = Gate.define {
			id = "g",
			producers = { command("probe", { exit = DEFER_75 }) },
			policy = { deferrals = { probe = "tool unavailable here" } },
		}
		local deferred = go(
			permitted,
			fakeExecutor { probe = {
				outcome = function()
					return exited(75)
				end,
			} }
		)
		expect(recordOf(deferred, "probe").status):toEqual "deferred"
		expect(deferred.acceptance.verdict):toEqual "deferred"
		expect(deferred.execution.report.skipped):toEqual(1)
	end)
end)

describe("selected and complete coverage", function()
	local gate = Gate.define {
		id = "g",
		producers = {
			command("lint", { tier = "fast" }),
			command("build", { tier = "slow" }),
			command("test", { tier = "slow", after = { "build" } }),
		},
	}

	it("reports a full pass as complete and releasable", function()
		local outcome = go(gate, fakeExecutor {})
		expect(outcome.acceptance.verdict):toEqual "release"
		expect(outcome.acceptance.complete):toEqual(true)
		expect(outcome.acceptance.releasable):toEqual(true)
		expect(#outcome.producers):toEqual(3)
	end)

	it("never lets a selected pass report as complete", function()
		local fake = fakeExecutor {}
		local outcome = go(gate, fake, { selection = { ids = { "lint" } } })
		expect(fake.started):toEqual { "lint" }
		expect(outcome.acceptance.verdict):toEqual "selected"
		expect(outcome.acceptance.releasable):toEqual(false)
		expect(outcome.acceptance.complete):toEqual(false)
		expect(outcome.acceptance.notSelected):toEqual { "build", "test" }
		expect(recordOf(outcome, "build").status):toEqual "not_selected"
		expect(outcome.execution.provenance.complete):toEqual(false)
	end)

	it("selects by tier and pulls in what the selection depends on", function()
		local fake = fakeExecutor {}
		local outcome = go(gate, fake, { selection = { ids = { "test" } } })
		expect(fake.started):toEqual { "build", "test" }
		expect(recordOf(outcome, "build").pulledByDependency):toEqual(true)
		expect(recordOf(outcome, "test").pulledByDependency):toEqual(false)
		local tier = go(gate, fakeExecutor {}, { selection = { tiers = { "slow" } } })
		expect(tier.acceptance.passed):toEqual { "build", "test" }
		expect(tier.acceptance.verdict):toEqual "selected"
	end)

	it("a selection that names everything is the complete gate", function()
		local outcome = go(gate, fakeExecutor {}, { selection = { ids = { "lint", "build", "test" } } })
		expect(outcome.acceptance.verdict):toEqual "release"
	end)

	it("fails an unknown, empty or non-matching selection", function()
		expect(function()
			go(gate, fakeExecutor {}, { selection = { ids = { "ghost" } } })
		end):toThrow "unknown producer"
		expect(function()
			go(gate, fakeExecutor {}, { selection = { tiers = { "nowhere" } } })
		end):toThrow "unknown tier"
		expect(function()
			go(gate, fakeExecutor {}, { selection = {} })
		end):toThrow "must name at least one"
		expect(function()
			go(gate, fakeExecutor {}, { selection = { ids = { "lint" }, tiers = { "slow" } } })
		end):toThrow "matches no producer"
	end)

	it("keeps a failed selected run from reporting as a selected pass", function()
		local outcome = go(
			gate,
			fakeExecutor { lint = {
				outcome = function()
					return exited(1)
				end,
			} },
			{ selection = { ids = { "lint" } } }
		)
		expect(outcome.acceptance.verdict):toEqual "failed"
	end)

	it("a gate with no producer proves nothing", function()
		local empty = Gate.define { id = "empty", producers = {} }
		local outcome = go(empty, fakeExecutor {})
		expect(outcome.acceptance.verdict):toEqual "failed"
		expect(outcome.acceptance.reasons[1]):toContain "no-cases"
	end)
end)

describe("evidence reuse", function()
	local gate = Gate.define {
		id = "g",
		producers = { command("probe", { report = {} }), command "other" },
		policy = { reuse = { "probe" } },
	}

	it("satisfies a producer from a caller-validated receipt when policy allows it", function()
		local fake = fakeExecutor {}
		local outcome = go(gate, fake, {
			reuse = {
				probe = {
					report = reportOf { { name = "one", pass = true } },
					reference = "receipts/probe.json",
					validatedBy = "caller",
				},
			},
		})
		expect(fake.started):toEqual { "other" }
		expect(recordOf(outcome, "probe").reused):toEqual(true)
		expect(recordOf(outcome, "probe").reuseReference):toEqual "receipts/probe.json"
		expect(outcome.acceptance.reused):toEqual { "probe" }
		expect(outcome.acceptance.verdict):toEqual "release"
		local limitation = outcome.execution.report.results[1].limitations[1]
		expect(limitation):toContain "not produced by this run"
	end)

	it("fails a reuse the policy does not permit and a reused report that is invalid", function()
		local denied = Gate.define { id = "g", producers = { command("probe", { report = {} }) } }
		local refused = go(denied, fakeExecutor {}, {
			reuse = {
				probe = { report = reportOf { { name = "one", pass = true } }, reference = "r", validatedBy = "c" },
			},
		})
		expect(recordOf(refused, "probe").status):toEqual "failed"
		expect(recordOf(refused, "probe").reused):toEqual(false)
		local invalid = go(gate, fakeExecutor {}, {
			reuse = { probe = { report = "garbage", reference = "r", validatedBy = "c" } },
		})
		expect(recordOf(invalid, "probe").status):toEqual "failed"
		expect(invalid.acceptance.verdict):toEqual "failed"
	end)

	it("binds reuse to the build under test", function()
		local build: Verify.EvidenceBuild = { commit = "c1", tree = "t1", clean = true, digest = "d1" }
		local other: Verify.EvidenceBuild = { commit = "c2", tree = "t2", clean = true, digest = "d2" }
		local function offer(bound: Verify.EvidenceBuild?): Gate.Outcome
			local settings: Gate.RunOptions = {
				runId = "run-1",
				capabilities = { "process" },
				build = build,
				reuse = {
					probe = {
						report = reportOf { { name = "one", pass = true } },
						reference = "r",
						validatedBy = "c",
						build = bound,
					},
				},
			}
			return Gate.run(gate, fakeExecutor({}).executor, settings)
		end
		expect(recordOf(offer(build), "probe").reused):toEqual(true)
		expect(recordOf(offer(other), "probe").status):toEqual "failed"
		expect(recordOf(offer(nil), "probe").detail):toContain "not bound to the build"
		local outcome = offer(build)
		expect(outcome.build and outcome.build.digest):toEqual "d1"
		expect(outcome.execution.report.environment["verify.build.commit"]):toEqual "c1"
	end)

	it("rejects reuse offered for an unknown producer", function()
		expect(function()
			go(gate, fakeExecutor {}, { reuse = { ghost = { report = {}, reference = "r", validatedBy = "c" } } })
		end):toThrow "unknown producer"
	end)
end)

describe("benchmark producers", function()
	it("runs a benchmark with the injected clock, alone and accounted", function()
		local now = 0
		local spec: Benchmark.Spec = {
			name = "tick",
			unit = "milliseconds",
			warmup = 1,
			samples = 4,
			workload = function()
				now += 0.002
			end,
			budget = { p95 = 5 },
			environment = { observed = "lab" },
			clock = function()
				return now
			end,
		}
		local gate = Gate.define {
			id = "g",
			producers = {
				command "build",
				{ id = "speed", kind = "benchmark", benchmark = spec, after = { "build" } },
			},
		}
		local outcome = go(gate, fakeExecutor {})
		expect(recordOf(outcome, "speed").status):toEqual "passed"
		local result = outcome.execution.report.results[2]
		expect(result.id):toEqual "speed"
		expect(result.evidence ~= nil and #result.evidence.measurements):toEqual(1)
	end)

	it("fails a gate whose benchmark exceeds its budget", function()
		local now = 0
		local spec: Benchmark.Spec = {
			name = "slow",
			unit = "milliseconds",
			warmup = 0,
			samples = 3,
			workload = function()
				now += 0.1
			end,
			budget = { p95 = 5 },
			environment = { observed = "lab" },
			clock = function()
				return now
			end,
		}
		local gate = Gate.define { id = "g", producers = { { id = "speed", kind = "benchmark", benchmark = spec } } }
		local outcome = go(gate, fakeExecutor {})
		expect(recordOf(outcome, "speed").status):toEqual "failed"
		expect(outcome.acceptance.verdict):toEqual "failed"
	end)
end)

describe("scope, census and explanation", function()
	local function testsGate(extra: Declared?): Gate.Definition
		local more: Declared = extra or {}
		return Gate.define {
			id = "g",
			producers = {
				{
					id = "specs",
					kind = "tests",
					worker = "worker.luau",
					locators = { "a.verify.luau" },
					tier = "fast",
					cases = more.cases,
					isolate = more.isolate,
					workers = more.workers,
					command = more.command,
				},
				command("slow-check", { tier = "slow" }),
				command "untiered",
			},
		}
	end

	local function sourced(names: { string }, selection: Verify.Selection?): Verify.Report
		local clock = 0
		local harness = Verify.createHarness {
			now = function()
				clock += 0.001
				return clock
			end,
			prefixIds = false,
		}
		for _, name in names do
			harness:case(name, { id = name, run = function() end })
		end
		local report = harness:run { executor = "child", selection = selection }
		for _, result in report.results do
			result.source = "a.verify.luau"
		end
		return report
	end

	local function answering(report: Verify.Report): Fake
		return fakeExecutor {
			specs = {
				outcome = function()
					return withReport(exited(0), report)
				end,
			},
		}
	end

	it("hands a tests producer's own worker command to the executor", function()
		local seen: { string }? = nil
		local fake = fakeExecutor {
			specs = {
				outcome = function(job)
					seen = job.command
					return withReport(exited(0), sourced { "one" })
				end,
			},
		}
		go(testsGate { command = { "lune", "run" } }, fake)
		expect(seen):toEqual { "lune", "run" }
	end)

	it("lists tier skips and states the selection that ran", function()
		local outcome = go(testsGate(), answering(sourced { "one" }), { selection = { tiers = { "fast" } } })
		expect(outcome.acceptance.verdict):toEqual "selected"
		expect(outcome.scope.complete):toEqual(false)
		expect(outcome.scope.tiers):toEqual { "fast" }
		expect(outcome.scope.selected):toEqual { "specs" }
		expect(outcome.acceptance.skippedByTier):toEqual { "slow-check" }
		expect(outcome.acceptance.notSelected):toEqual { "slow-check", "untiered" }
		expect(recordOf(outcome, "slow-check").detail):toContain "tier slow is not among the selected tier fast"
		expect(recordOf(outcome, "untiered").detail):toContain "declares no tier"
		expect(Gate.format(outcome)):toContain "skipped by tier (1): slow-check"
		expect(Gate.format(outcome)):toContain "scope: selected tier fast"
		local complete = go(testsGate(), answering(sourced { "one" }))
		expect(complete.scope.complete):toEqual(true)
		expect(complete.scope.label):toEqual "complete"
		expect(#complete.acceptance.skippedByTier):toEqual(0)
	end)

	it("hands the selected tier and cases to workers", function()
		local jobs: { Gate.Job } = {}
		local fake = fakeExecutor {
			specs = {
				outcome = function(job)
					table.insert(jobs, job)
					return withReport(exited(0), sourced { "one" })
				end,
			},
		}
		go(testsGate(), fake, { selection = { tiers = { "fast" }, cases = { "one" } } })
		expect(jobs[1].tiers):toEqual { "fast" }
		expect(jobs[1].args):toEqual { "--tier=fast", "--case=one" }
		local plain = fakeExecutor {
			specs = {
				outcome = function(job)
					table.insert(jobs, job)
					return withReport(exited(0), sourced { "one" })
				end,
			},
		}
		go(testsGate(), plain)
		expect(jobs[2].args):toEqual {}
	end)

	it("hands a name filter and sources to tests workers only and states them", function()
		local jobs: { Gate.Job } = {}
		local fake = fakeExecutor {
			specs = {
				outcome = function(job)
					table.insert(jobs, job)
					return withReport(exited(0), sourced({ "one", "two" }, { nameContains = "on", account = true }))
				end,
			},
		}
		local outcome = go(testsGate(), fake, { selection = { nameContains = "on", sources = { "a.verify.luau" } } })
		expect(jobs[1].args):toEqual { "--name=on", "--source=a.verify.luau" }
		expect(outcome.acceptance.verdict):toEqual "selected"
		expect(outcome.scope.complete):toEqual(false)
		expect(outcome.scope.nameContains):toEqual "on"
		expect(outcome.scope.selected):toEqual { "specs" }
		expect(outcome.acceptance.notSelected):toEqual { "slow-check", "untiered" }
		expect(outcome.scope.label):toContain 'name "on"'
		expect(recordOf(outcome, "slow-check").detail):toContain "only tests producers"
	end)

	it("fails a name filter that matches no case and refuses a malformed one", function()
		local empty = go(
			testsGate(),
			answering(sourced({ "one" }, { nameContains = "zzz", account = true })),
			{ selection = { nameContains = "zzz" } }
		)
		expect(empty.acceptance.verdict):toEqual "failed"
		expect(empty.acceptance.reasons[1]):toContain "were not found"
		expect(empty.acceptance.reasons[1]):toContain "zzz"
		expect(function()
			go(testsGate(), answering(sourced { "one" }), { selection = { nameContains = "" } })
		end):toThrow "nonempty string"
		local commandOnly = Gate.define { id = "g", producers = { command "build" } }
		expect(function()
			go(commandOnly, fakeExecutor {}, { selection = { nameContains = "x" } })
		end):toThrow "needs a tests producer"
	end)

	it("counts deselected cases as such and never as passes or failures", function()
		local narrowed = sourced({ "one", "two" }, { ids = { "one" }, account = true })
		expect(narrowed.skipped):toEqual(1)
		local outcome = go(testsGate(), answering(narrowed), { selection = { ids = { "specs" } } })
		expect(recordOf(outcome, "specs").status):toEqual "passed"
		expect(recordOf(outcome, "specs").deselected):toEqual { "two" }
		expect(outcome.acceptance.deselected):toEqual { "two" }
		expect(outcome.acceptance.verdict):toEqual "selected"
		expect(outcome.scope.complete):toEqual(false)
		local unaccounted = sourced({ "one", "two" }, { ids = { "one" } })
		expect(unaccounted.total):toEqual(1)
		local deliberate = Verify.createHarness {
			now = function()
				return 0
			end,
			prefixIds = false,
		}
		deliberate:skip("later", "needs a device")
		local skipped = deliberate:run { executor = "child" }
		skipped.results[1].source = "a.verify.luau"
		local refused = go(testsGate(), answering(skipped), { selection = { ids = { "specs" } } })
		expect(recordOf(refused, "specs").status):toEqual "failed"
		expect(recordOf(refused, "specs").deselected):toEqual {}
	end)

	it("rejects missing and extra cases against the declared census", function()
		local exact = go(testsGate { cases = { "one", "two" } }, answering(sourced { "one", "two" }))
		expect(recordOf(exact, "specs").status):toEqual "passed"
		local missing = go(testsGate { cases = { "one", "two" } }, answering(sourced { "one" }))
		expect(recordOf(missing, "specs").status):toEqual "failed"
		expect(recordOf(missing, "specs").detail):toContain "missing case(s): two"
		local extra = go(testsGate { cases = { "one" } }, answering(sourced { "one", "stray" }))
		expect(recordOf(extra, "specs").status):toEqual "failed"
		expect(recordOf(extra, "specs").detail):toContain "unexpected case(s): stray"
		local both = go(testsGate { cases = { "one", "two" } }, answering(sourced { "one", "stray" }))
		expect(recordOf(both, "specs").detail):toContain "missing case(s): two; unexpected case(s): stray"
		local narrowed = sourced({ "one", "two" }, { ids = { "one" }, account = true })
		local still = go(testsGate { cases = { "one", "two" } }, answering(narrowed))
		expect(recordOf(still, "specs").status):toEqual "passed"
	end)

	it("applies an exact census to a command report and tolerates extras otherwise", function()
		local function commandGate(exact: boolean): Gate.Definition
			return Gate.define {
				id = "g",
				producers = { command("probe", { report = { cases = { "one" }, exact = exact } }) },
			}
		end
		local function fake(): Fake
			return fakeExecutor {
				probe = {
					outcome = function(job)
						return withReport(
							exited(0),
							envelope(job, reportOf { { name = "one", pass = true }, { name = "two", pass = true } })
						)
					end,
				},
			}
		end
		expect(recordOf(go(commandGate(false), fake()), "probe").status):toEqual "passed"
		local strict = go(commandGate(true), fake())
		expect(recordOf(strict, "probe").status):toEqual "failed"
		expect(recordOf(strict, "probe").detail):toContain "unexpected case(s): two"
	end)

	it("fails a run that names a case no selected producer reported", function()
		local outcome =
			go(testsGate(), answering(sourced { "one" }), { selection = { ids = { "specs" }, cases = { "ghost" } } })
		expect(outcome.acceptance.verdict):toEqual "failed"
		expect(outcome.acceptance.reasons[1]):toContain "ghost"
		local found = go(
			testsGate(),
			answering(sourced({ "one", "two" }, { ids = { "one" }, account = true })),
			{ selection = { ids = { "specs" }, cases = { "one" } } }
		)
		expect(found.acceptance.verdict):toEqual "selected"
		local owned =
			go(testsGate { cases = { "one" } }, answering(sourced { "one" }), { selection = { cases = { "one" } } })
		expect(owned.scope.selected):toEqual { "specs" }
		expect(function()
			go(testsGate(), answering(sourced { "one" }), { selection = { cases = { "one" } } })
		end):toThrow "which no producer declares"
	end)

	it("explains why a producer or case ran, was skipped or failed", function()
		local outcome = go(testsGate(), answering(sourced { "one" }), { selection = { tiers = { "fast" } } })
		expect(Gate.explain(outcome, "slow-check")):toContain "tier slow is not among"
		expect(Gate.explain(outcome, "specs")):toContain "selected by this run: selected tier fast"
		expect(Gate.explain(outcome, "one")):toContain "adopted by producer specs (passed)"
		expect(Gate.explain(outcome, "nothing")):toEqual(nil)
		local failing = go(testsGate(), answering(sourced { "one" }), { selection = { ids = { "untiered" } } })
		expect(Gate.explain(failing, "specs")):toContain "not selected"
	end)

	it("lists producers with why they exist and refuses an empty reason", function()
		local gate = Gate.define {
			id = "g",
			producers = {
				{ id = "lint", kind = "command", argv = { "lint" }, tier = "fast", why = "catches style drift" },
				command("test", { after = { "lint" } }),
			},
		}
		local listing = Gate.list(gate)
		expect(listing):toContain "catches style drift"
		expect(listing):toContain "after lint"
		local outcome = go(gate, fakeExecutor {})
		expect(Gate.explain(outcome, "lint")):toContain "why it exists: catches style drift"
		expect(recordOf(outcome, "lint").why):toEqual "catches style drift"
		expect(function()
			Gate.define { id = "g", producers = { { id = "a", kind = "command", argv = { "x" }, why = " " } } }
		end):toThrow "non-empty explanation"
	end)

	it("proposes a rerun of exactly the failed producers and cases", function()
		local broken = reportOf { { name = "good", pass = true }, { name = "bad", pass = false } }
		for _, result in broken.results do
			result.source = "a.verify.luau"
		end
		local outcome = go(testsGate(), answering(broken))
		local again = Gate.rerun(outcome)
		expect(again ~= nil and again.ids):toEqual { "specs" }
		expect(again ~= nil and again.cases):toEqual { "bad" }
		local clean = go(testsGate(), answering(sourced { "one" }))
		expect(Gate.rerun(clean)):toEqual(nil)
		local crashed = go(
			testsGate(),
			fakeExecutor { specs = {
				outcome = function()
					return exited(3)
				end,
			} }
		)
		local whole = Gate.rerun(crashed)
		expect(whole ~= nil and whole.cases):toEqual(nil)
		expect(whole ~= nil and whole.ids):toEqual { "specs" }
	end)

	it("rejects tests-only fields elsewhere and incoherent declarations", function()
		expect(function()
			Gate.define {
				id = "g",
				producers = { { id = "c", kind = "command", argv = { "x" }, isolate = true } },
			}
		end):toThrow "only as a tests producer"
		expect(function()
			testsGate { workers = 2 }
		end):toThrow "needs isolate = true"
		expect(function()
			testsGate { cases = {} }
		end):toThrow "at least one case"
		expect(function()
			testsGate { command = {} }
		end):toThrow "must name the program"
		expect(function()
			Gate.define {
				id = "g",
				producers = { { id = "c", kind = "command", argv = { "x" }, command = { "lune", "run" } } },
			}
		end):toThrow "only as a tests producer"
		expect(function()
			Gate.define { id = "g", producers = { command("c", { report = { exact = true } }) } }
		end):toThrow "needs report.cases"
	end)
end)

describe("benchmark collection producers", function()
	local function member(name: string, line: { now: number }, step: number, budget: number): Benchmark.Spec
		return {
			name = name,
			unit = "milliseconds",
			warmup = 0,
			samples = 3,
			workload = function()
				line.now += step / 1000
			end,
			budget = { p95 = budget },
			environment = { observed = "lab" },
			clock = function()
				return line.now
			end,
		}
	end

	local function collectionOf(line: { now: number }, slowStep: number, slowBudget: number?): Benchmark.Collection
		return {
			name = "group",
			yardstick = {
				run = function()
					line.now += 0.001
				end,
				samples = 2,
				maxSpread = 1,
				maxDrift = 1,
			},
			benchmarks = { member("quick", line, 1, 5), member("lazy", line, slowStep, slowBudget or 5) },
		}
	end

	it("runs a collection as one accounted benchmark producer", function()
		local line = { now = 0 }
		local gate = Gate.define {
			id = "g",
			producers = { { id = "speed", kind = "benchmark", collection = collectionOf(line, 2) } },
		}
		local outcome = go(gate, fakeExecutor {})
		expect(recordOf(outcome, "speed").status):toEqual "passed"
		local result = outcome.execution.report.results[1]
		expect(result.id):toEqual "speed"
		expect(result.evidence ~= nil and #result.evidence.measurements):toEqual(2)
		expect(outcome.acceptance.verdict):toEqual "release"
	end)

	it("fails the gate when one member of the collection exceeds its budget", function()
		local line = { now = 0 }
		local gate = Gate.define {
			id = "g",
			producers = { { id = "speed", kind = "benchmark", collection = collectionOf(line, 50) } },
		}
		local outcome = go(gate, fakeExecutor {})
		expect(recordOf(outcome, "speed").status):toEqual "failed"
		expect(outcome.acceptance.verdict):toEqual "failed"
	end)

	it("refuses a benchmark producer that names both, neither or a malformed collection", function()
		local line = { now = 0 }
		local collection = collectionOf(line, 2)
		expect(function()
			Gate.define {
				id = "g",
				producers = {
					{
						id = "speed",
						kind = "benchmark",
						collection = collection,
						benchmark = member("x", line, 1, 5),
					},
				},
			}
		end):toThrow "one benchmark specification or one benchmark collection"
		expect(function()
			Gate.define { id = "g", producers = { { id = "speed", kind = "benchmark" } } }
		end):toThrow "one benchmark specification or one benchmark collection"
		local empty = collectionOf(line, 2)
		empty.benchmarks = {}
		expect(function()
			Gate.define { id = "g", producers = { { id = "speed", kind = "benchmark", collection = empty } } }
		end):toThrow "at least one benchmark"
		expect(function()
			Gate.define {
				id = "g",
				producers = { { id = "cmd", kind = "command", argv = { "x" }, collection = collection } },
			}
		end):toThrow "command producer"
	end)

	it("changes the gate fingerprint when a member changes", function()
		local line = { now = 0 }
		local first = Gate.define {
			id = "g",
			producers = { { id = "speed", kind = "benchmark", collection = collectionOf(line, 2) } },
		}
		local second = Gate.define {
			id = "g",
			producers = { { id = "speed", kind = "benchmark", collection = collectionOf(line, 2, 6) } },
		}
		local sameAgain = Gate.define {
			id = "g",
			producers = { { id = "speed", kind = "benchmark", collection = collectionOf(line, 2) } },
		}
		expect(first.digest):toEqual(sameAgain.digest)
		expect(first.digest ~= second.digest):toEqual(true)
	end)
end)

return nil
