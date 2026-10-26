--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local fs = require "@std/fs"
local process = require "@std/process"
local system = require "@std/system"

local Files = require "../src/lute/files"
local Lute = require "../src/lute"
local Verify = require "../src/core"
local Gate = require "../src/gate"
local GateRuntime = require "../src/lute/gate"
local LuteRuntime = require "../src/lute/runtime"

local ROOT = ".lute/tmp/verify-gate-test"

local WINDOWS = system.win32

local NEWLINE = if WINDOWS then "\r\n" else "\n"

local CMD: { [string]: string } = {
	["echo fine"] = "echo fine",
	["echo ok"] = "echo ok",
	["echo never"] = "echo never",
	["true"] = "exit 0",
	["exit 3"] = "exit 3",
	["sleep 1"] = "ping -n 2 127.0.0.1 >nul",
	["sleep 6"] = "ping -n 7 127.0.0.1 >nul",
	["sleep 8; echo late"] = "ping -n 9 127.0.0.1 >nul&echo late",
	["echo to-out; echo to-err >&2; exit 4"] = "echo to-out&(echo to-err)1>&2&exit 4",
	['printf "not json" > "$1"'] = "exit 2",
	['test "$GATE_PROBE" = yes'] = "if %GATE_PROBE%==yes (exit 0) else (exit 1)",
	['test "$GATE_PROBE" = yes && test -n "$HOME" && test "$(basename "$(pwd)")" = cwd'] = "if %GATE_PROBE%==yes (if defined SystemRoot (cd | findstr /e cwd) else (exit 1)) else (exit 1)",
}

type ShOptions = { deadlineSeconds: number?, report: Gate.ReportExpectation? }

local function sh(id: string, script: string, extra: ShOptions?): Gate.ProducerDraft
	local more: ShOptions = extra or {}
	local argv = { "/bin/sh", "-c", script, "sh" }
	if WINDOWS then
		argv = { "cmd", "/c", (assert(CMD[script], "no Windows command for " .. script)) }
	end
	return {
		id = id,
		kind = "command",
		argv = argv,
		deadlineSeconds = more.deadlineSeconds,
		report = more.report,
	}
end

local function copy(source: string): { string }
	if WINDOWS then
		return { tostring(process.execPath()), "run", "tests/programs/copy.luau", source, "{report}" }
	end
	return { "/bin/cp", source, "{report}" }
end

type Extras = {
	isolate: boolean?,
	workers: number?,
	sourceDeadlineSeconds: number?,
	deadlineSeconds: number?,
	tier: string?,
}

local function recordOf(outcome: Gate.Outcome, id: string): Gate.Record
	for _, record in outcome.producers do
		if record.id == id then
			return record
		end
	end
	error("no record for " .. id)
end

local function reportOf(name: string, source: string?): Verify.Report
	local clock = 0
	local harness = Verify.createHarness {
		now = function()
			clock += 0.001
			return clock
		end,
		source = source,
		prefixIds = false,
	}
	harness:case(name, function(context)
		context:expect(1):toBe(1)
	end)
	return harness:run { executor = "child" }
end

local function runIn(
	label: string,
	producers: { Gate.ProducerDraft },
	policy: Gate.PolicyDraft?,
	runId: string?
): Gate.Outcome
	local gate = Gate.define { id = label, producers = producers, policy = policy }
	return Lute.gate.run(gate, { directory = ROOT, runId = runId or label })
end

local function fixture(name: string, source: string): string
	Files.ensureDirectory(ROOT .. "/modules")
	local path = ("%s/modules/%s.verify.luau"):format(ROOT, name)
	fs.writeStringToFile(path, source)
	return path
end

describe("shared gate process slots", function()
	local function exercise(
		limit: number,
		commandFailure: boolean?,
		testDeadline: number?
	): (Gate.Outcome, number, number, number)
		local active = 0
		local peak = 0
		local workers = 0
		local workerPeak = 0
		local overlapPeak = 0
		local commandActive = false
		local runtime = table.clone(LuteRuntime)
		runtime.bounded = { mechanism = "job" }
		runtime.process = table.clone(runtime.process)
		runtime.process.run = function(argv)
			local worker = table.find(argv, "examples/worker.luau")
			active += 1
			peak = math.max(peak, active)
			if worker then
				workers += 1
				workerPeak = math.max(workerPeak, workers)
				if commandActive then
					overlapPeak = math.max(overlapPeak, workers)
				end
				runtime.time.wait(0.15)
				local batch = Lute.decodeBatch(fs.readFileToString(argv[worker + 1]))
				local unit = batch.units[1]
				fs.writeStringToFile(argv[worker + 2], Lute.encode(reportOf(unit.locator .. "::pass", unit.locator)))
				workers -= 1
			else
				commandActive = true
				runtime.time.wait(0.05)
				commandActive = false
			end
			active -= 1
			if worker == nil and commandFailure then
				error("process start failed", 0)
			end
			return { ok = true, exitcode = 0, stdout = "", stderr = "" }
		end
		local outcome = GateRuntime.create(runtime).run(
			Gate.define {
				id = "process-slots",
				producers = {
					{ id = "command", kind = "command", argv = { "probe-command" }, exclusive = false },
					{
						id = "specs",
						kind = "tests",
						worker = "examples/worker.luau",
						exclusive = false,
						locators = { "one", "two", "three", "four", "five", "six" },
						isolate = true,
						workers = 4,
						deadlineSeconds = testDeadline or 5,
					},
				},
				policy = { concurrency = 2 },
			},
			{ directory = ROOT, runId = "process-slots", processLimit = limit }
		)
		return outcome, peak, workerPeak, overlapPeak
	end

	it("shares four slots and gives the command slot back to waiting tests", function()
		local outcome, peak, workerPeak, overlapPeak = exercise(4)
		expect(outcome.acceptance.verdict):toEqual "release"
		expect(Gate.testCases(outcome).passed):toEqual(7)
		expect(peak):toEqual(4)
		expect(overlapPeak):toEqual(3)
		expect(workerPeak):toEqual(4)
	end)

	it("releases the only slot after a command cannot start", function()
		local outcome, peak = exercise(1, true)
		expect(recordOf(outcome, "command").status):toEqual "failed"
		expect(recordOf(outcome, "specs").status):toEqual "passed"
		expect(peak):toEqual(1)
	end)

	it("does not start queued tests after their producer deadline", function()
		local outcome, peak, workerPeak = exercise(1, false, 0.02)
		expect(recordOf(outcome, "command").status):toEqual "passed"
		expect(recordOf(outcome, "specs").status):toEqual "failed"
		expect(Gate.testCases(outcome).timedOut):toEqual(6)
		expect(peak):toEqual(1)
		expect(workerPeak):toEqual(0)
	end)

	it("refuses invalid process limits", function()
		for _, limit in { 0, -1, 1.5, math.huge, math.nan } do
			expect(function()
				exercise(limit)
			end):toThrow "processLimit must be a positive integer"
		end
	end)
end)

describe("gate commands on the Lute host", function()
	it("passes and fails by exit code and keeps the full log on disk", function()
		local outcome = runIn("exit-codes", {
			sh("good", "echo fine"),
			sh("bad", "echo to-out; echo to-err >&2; exit 4"),
		})
		expect(recordOf(outcome, "good").status):toEqual "passed"
		local bad = recordOf(outcome, "bad")
		expect(bad.status):toEqual "failed"
		expect(bad.exitcode):toEqual(4)
		expect(bad.log ~= nil and bad.log.stderr):toEqual("to-err" .. NEWLINE)
		local reference = assert(bad.log and bad.log.reference)
		local text = fs.readFileToString(reference)
		expect(text):toContain "to-out"
		expect(text):toContain "exit 4"
		expect(outcome.acceptance.verdict):toEqual "failed"
		expect(outcome.execution.report.total):toEqual(2)
	end)

	it("terminates a command and its children at its deadline", function()
		local began = os.clock()
		local outcome = runIn("deadline", { sh("hung", "sleep 8; echo late", { deadlineSeconds = 1 }) })
		expect(recordOf(outcome, "hung").status):toEqual "timed_out"
		expect(recordOf(outcome, "hung").timedOut):toEqual(true)
		expect(os.clock() - began < 5):toEqual(true)
		expect(outcome.acceptance.releasable):toEqual(false)
	end)

	it("bounds concurrency while still overlapping commands", function()
		local began = os.clock()
		local outcome = runIn(
			"concurrent",
			{ sh("a", "sleep 1"), sh("b", "sleep 1"), sh("c", "sleep 1") },
			{ concurrency = 2 }
		)
		local elapsed = os.clock() - began
		expect(outcome.acceptance.verdict):toEqual "release"
		expect(elapsed >= 1.9):toEqual(true)
		expect(elapsed < 3.0):toEqual(true)
	end)

	it("stops starting commands at the whole-run deadline", function()
		local outcome = runIn(
			"run-deadline",
			{ sh("first", "sleep 6"), sh("second", "echo never") },
			{ deadlineSeconds = 1 }
		)
		expect(recordOf(outcome, "first").status):toEqual "timed_out"
		expect(recordOf(outcome, "second").status):toEqual "timed_out"
		expect(recordOf(outcome, "second").detail):toContain "run deadline"
		expect(outcome.acceptance.verdict):toEqual "failed"
	end)

	it("passes environment variables and the working directory to the command", function()
		Files.ensureDirectory(ROOT .. "/cwd")
		local probe = sh("probe", 'test "$GATE_PROBE" = yes && test -n "$HOME" && test "$(basename "$(pwd)")" = cwd')
		probe.env = { GATE_PROBE = "yes" }
		probe.cwd = ROOT .. "/cwd"
		local wrong = sh("wrong", 'test "$GATE_PROBE" = yes')
		local outcome = runIn("context", { probe, wrong })
		expect(recordOf(outcome, "probe").status):toEqual "passed"
		expect(recordOf(outcome, "wrong").status):toEqual "failed"
	end)

	it("runs the producers in dependency order", function()
		local marker = ROOT .. "/order.txt"
		Files.ensureDirectory(ROOT)
		Files.removeIfPresent(marker)
		local function appender(id: string, after: { string }?): Gate.ProducerDraft
			return {
				id = id,
				kind = "command",
				argv = if WINDOWS
					then { "cmd", "/c", ("echo %s>>%s"):format(id, (string.gsub(marker, "/", "\\"))) }
					else { "/bin/sh", "-c", 'printf "%s " "$1" >> ' .. marker, "sh", id },
				after = after,
			}
		end
		local outcome = runIn(
			"ordered",
			{ appender("third", { "second" }), appender("second", { "first" }), appender("first", nil) }
		)
		expect(outcome.acceptance.verdict):toEqual "release"
		expect(fs.readFileToString(marker)):toEqual(
			if WINDOWS then "first\r\nsecond\r\nthird\r\n" else "first second third "
		)
	end)
end)

describe("run-bound reports from commands", function()
	local function stage(runId: string, id: string, bound: string, name: string): string
		local directory = ("%s/%s"):format(ROOT, runId)
		Files.ensureDirectory(directory)
		local source = ("%s/%s-source.json"):format(directory, id)
		Lute.gate.writeReport(source, bound, reportOf(name, "probe"))
		return source
	end

	it("accepts the current run's report and refuses every other one", function()
		local runId = "bound-1"
		local current = stage(runId, "current", runId, "check-one")
		local foreign = stage(runId, "foreign", "another-run", "check-one")
		local outcome = runIn("bound", {
			sh("silent", "true", { report = {} }),
			{
				id = "current",
				kind = "command",
				argv = copy(current),
				report = { cases = { "check-one" } },
			},
			{ id = "foreign", kind = "command", argv = copy(foreign), report = {} },
			sh("garbage", 'printf "not json" > "$1"', { report = {} }),
		}, nil, runId)
		expect(recordOf(outcome, "silent").status):toEqual "failed"
		expect(recordOf(outcome, "silent").detail):toContain "without the expected report"
		expect(recordOf(outcome, "current").status):toEqual "passed"
		expect(recordOf(outcome, "current").reportAccounted):toEqual(true)
		expect(recordOf(outcome, "foreign").status):toEqual "failed"
		expect(recordOf(outcome, "foreign").detail):toContain "not the current run"
		expect(recordOf(outcome, "garbage").status):toEqual "failed"
		expect(outcome.acceptance.verdict):toEqual "failed"
	end)

	it("does not let a stale file at the report path stand in for this run", function()
		local runId = "stale-1"
		local directory = ("%s/%s"):format(ROOT, runId)
		Files.ensureDirectory(directory)
		Lute.gate.writeReport(directory .. "/probe.report.json", runId, reportOf("old", "probe"))
		local outcome = runIn("stale", { sh("probe", "true", { report = {} }) }, nil, runId)
		expect(recordOf(outcome, "probe").status):toEqual "failed"
		expect(recordOf(outcome, "probe").detail):toContain "no report file was written"
	end)
end)

describe("test modules on the Lute host", function()
	local function modules(locators: { string }): Gate.ProducerDraft
		return {
			id = "specs",
			kind = "tests",
			worker = "examples/worker.luau",
			locators = locators,
			deadlineSeconds = 60,
		}
	end

	it("runs ordinary spec modules and accounts every one", function()
		local good = fixture(
			"good",
			'return function(harness) harness:case("fine", function(context) context:expect(1):toBe(1) end) end'
		)
		local outcome = runIn("modules-ok", { modules { good } })
		expect(recordOf(outcome, "specs").status):toEqual "passed"
		expect(recordOf(outcome, "specs").reportAccounted):toEqual(true)
		expect(outcome.acceptance.verdict):toEqual "release"
	end)

	it("fails a module that registers no case, one that breaks and one that cannot load", function()
		local empty = fixture("empty", "return function(harness) end")
		local broken = fixture("broken", 'return function(harness) error("registration broke", 0) end')
		local missing = ROOT .. "/modules/absent.verify.luau"
		local emptyOutcome = runIn("modules-empty", { modules { empty } })
		expect(recordOf(emptyOutcome, "specs").status):toEqual "failed"
		expect(recordOf(emptyOutcome, "specs").detail):toContain "reported no case"
		local brokenOutcome = runIn("modules-broken", { modules { broken } })
		expect(recordOf(brokenOutcome, "specs").status):toEqual "failed"
		expect(brokenOutcome.acceptance.verdict):toEqual "failed"
		local missingOutcome = runIn("modules-missing", { modules { missing } })
		expect(recordOf(missingOutcome, "specs").status):toEqual "failed"
		expect(missingOutcome.execution.report.failed >= 1):toEqual(true)
	end)

	it("fails when the worker cannot run at all", function()
		local gate = Gate.define {
			id = "no-worker",
			producers = {
				{ id = "specs", kind = "tests", worker = "examples/none.luau", locators = { "x.verify.luau" } },
			},
		}
		local outcome = Lute.gate.run(gate, { directory = ROOT, runId = "no-worker" })
		expect(recordOf(outcome, "specs").status):toEqual "failed"
		expect(outcome.acceptance.releasable):toEqual(false)
	end)
end)

describe("isolated sources, selection and the last outcome", function()
	local function specs(locators: { string }, extra: Extras?): Gate.ProducerDraft
		local more: Extras = extra or {}
		return {
			id = "specs",
			kind = "tests",
			worker = "examples/worker.luau",
			locators = locators,
			deadlineSeconds = more.deadlineSeconds or 30,
			isolate = more.isolate,
			workers = more.workers,
			sourceDeadlineSeconds = more.sourceDeadlineSeconds,
			tier = more.tier,
		}
	end

	local function polluter(): string
		fixture("leak-state", "return { leaked = false }")
		return fixture(
			"polluter",
			'local state = require("./leak-state.verify") return function(harness) harness:case("pollutes", function(context) state.leaked = true end) end'
		)
	end

	local function observer(): string
		return fixture(
			"observer",
			'local state = require("./leak-state.verify") return function(harness) harness:case("clean", function(context) context:expect(state.leaked):toBe(false) end) end'
		)
	end

	it("runs each source in its own worker process under one producer", function()
		local shared = runIn("shared-process", { specs { polluter(), observer() } })
		expect(recordOf(shared, "specs").status):toEqual "failed"
		expect(recordOf(shared, "specs").detail):toContain "observer.verify.luau::clean"
		local isolated =
			runIn("isolated-process", { specs({ polluter(), observer() }, { isolate = true, workers = 2 }) })
		expect(recordOf(isolated, "specs").status):toEqual "passed"
		expect(#isolated.producers):toEqual(1)
		expect(Gate.testCases(isolated).total):toEqual(2)
		expect(isolated.acceptance.verdict):toEqual "release"
	end)

	it("attributes a load error, a registration error and a hang to their own source", function()
		local good = fixture(
			"isolated-good",
			'return function(harness) harness:case("fine", function(context) context:expect(1):toBe(1) end) end'
		)
		local broken = fixture("isolated-broken", 'return function(harness) error("registration broke", 0) end')
		local hung = fixture("isolated-hung", "while true do end")
		local missing = ROOT .. "/modules/isolated-absent.verify.luau"
		local outcome = runIn(
			"isolated-faults",
			{ specs({ good, broken, missing, hung }, { isolate = true, workers = 4, deadlineSeconds = 3 }) }
		)
		local record = recordOf(outcome, "specs")
		expect(record.status):toEqual "failed"
		local cases = Gate.testCases(outcome)
		expect(cases.total):toEqual(4)
		expect(cases.passed):toEqual(1)
		expect(cases.failed + cases.timedOut):toEqual(3)
		local sources: { string } = {}
		for _, result in cases.results do
			if result.status ~= "passed" then
				table.insert(sources, tostring(result.source))
			end
		end
		table.sort(sources)
		local expected = { broken, hung, missing }
		table.sort(expected)
		expect(sources):toEqual(expected)
		expect(record.detail):toContain "3 of 4 reported case(s) did not pass"
		expect(outcome.acceptance.failed):toEqual { "specs" }
	end)

	it("returns an isolated report merge refusal as a terminal failure", function()
		local first = fixture("duplicate-first", 'return function(h) h:case("collision", function() end) end')
		local second = fixture("duplicate-second", 'return function(h) h:case("collision", function() end) end')
		local worker = fixture(
			"duplicate-worker",
			table.concat({
				'local Lute = require("../../../../src/lute")',
				"Lute.worker({ load = function(locator)",
				'  return require("../../../../" .. string.sub(locator, 1, -6))',
				'end }, { caseIdStyle = "bare" })',
			}, "\n")
		)
		local controller = fixture(
			"duplicate-controller",
			table.concat({
				'local Lute = require("../../../../src/lute")',
				'local Gate = require("../../../../src/gate")',
				string.format(
					'local outcome = Lute.gate.run(Gate.define({ id = "duplicate-terminal", producers = {{ id = "specs", kind = "tests", worker = %q, locators = {%q, %q}, isolate = true, workers = 2, deadlineSeconds = 6 }} }), {directory = %q})',
					worker,
					first,
					second,
					ROOT .. "/duplicate-terminal"
				),
				'assert(outcome.producers[1].status == "failed", "merge was not a failed producer")',
				'assert(string.find(outcome.producers[1].detail or "", "duplicate result id", 1, true))',
				'assert(outcome.acceptance.verdict == "failed")',
			}, "\n")
		)
		local result = require("../src/lute/bounded").run({ tostring(process.execPath()), "run", controller }, 8)
		expect(result.timedOut):toEqual(false)
		expect(result.exitcode):toEqual(0)
	end)

	it("times a hung source out alone against its own deadline", function(_, caseContext)
		local good = fixture(
			"budget-good",
			'return function(harness) harness:case("fine", function(context) context:expect(1):toBe(1) end) end'
		)
		local hung = fixture("budget-hung", "while true do end")
		local began = os.clock()
		local outcome = runIn("source-deadline", {
			specs({ hung, good }, { isolate = true, workers = 1, sourceDeadlineSeconds = 1, deadlineSeconds = 60 }),
		})
		caseContext:attach("source-deadline-outcome.json", "application/json", Lute.encode(outcome))
		expect(os.clock() - began < 20):toEqual(true)
		local cases = Gate.testCases(outcome)
		expect(cases.passed):toEqual(1)
		expect(cases.timedOut):toEqual(1)
		for _, result in cases.results do
			if result.status == "timed_out" then
				expect(result.source):toEqual(hung)
			end
		end
		expect(function()
			Gate.define {
				id = "g",
				producers = {
					{ id = "t", kind = "tests", worker = "w", locators = { "a" }, sourceDeadlineSeconds = 1 },
				},
			}
		end):toThrow "needs isolate = true"
	end)

	it("passes the selected tier and cases to the worker and states the selection", function()
		local tiered = fixture(
			"tiered",
			'return function(harness) harness:case("quick", {tags = {"tier:fast"}, run = function() end}) harness:case("long", {tags = {"tier:slow"}, run = function() end}) harness:case("always", function() end) end'
		)
		local gate = Gate.define {
			id = "tier-args",
			producers = { specs({ tiered }, { tier = "fast" }), sh("other", "echo ok") },
		}
		local outcome =
			Lute.gate.run(gate, { directory = ROOT, runId = "tier-args", selection = { tiers = { "fast" } } })
		local record = recordOf(outcome, "specs")
		expect(record.status):toEqual "passed"
		expect(#record.deselected):toEqual(1)
		expect(record.deselected[1]):toContain "long"
		expect(outcome.acceptance.verdict):toEqual "selected"
		expect(outcome.scope.deselected):toEqual(record.deselected)
		expect(outcome.acceptance.skippedByTier):toEqual {}
		expect(outcome.acceptance.notSelected):toEqual { "other" }
		local named = Lute.gate.run(
			gate,
			{ directory = ROOT, runId = "named-case", selection = { ids = { "specs" }, cases = { "x" } } }
		)
		expect(named.acceptance.verdict):toEqual "failed"
		expect(named.acceptance.reasons[1]):toContain "were not found"
	end)

	it("filters real worker cases by name and fails when the name matches nothing", function()
		local named = fixture(
			"named",
			'return function(harness) harness:case("opens the door", function() end) harness:case("closes the window", function() end) end'
		)
		local gate = Gate.define {
			id = "name-args",
			producers = { specs({ named }, {}), sh("other", "echo ok") },
		}
		local narrowed =
			Lute.gate.run(gate, { directory = ROOT, runId = "name-hit", selection = { nameContains = "the door" } })
		expect(recordOf(narrowed, "specs").status):toEqual "passed"
		expect(#recordOf(narrowed, "specs").deselected):toEqual(1)
		expect(narrowed.acceptance.verdict):toEqual "selected"
		expect(narrowed.acceptance.notSelected):toEqual { "other" }
		local missed =
			Lute.gate.run(gate, { directory = ROOT, runId = "name-miss", selection = { nameContains = "garage" } })
		expect(missed.acceptance.verdict):toEqual "failed"
	end)

	it("substitutes the selected tier into a command", function()
		local gate = Gate.define {
			id = "tier-command",
			producers = {
				{
					id = "probe",
					kind = "command",
					argv = if WINDOWS
						then { "cmd", "/c", "if x{tier}==xfast (exit 0) else (exit 1)" }
						else { "/bin/sh", "-c", 'test "$1" = fast', "sh", "{tier}" },
					tier = "fast",
				},
				sh("other", "echo ok"),
			},
		}
		local outcome =
			Lute.gate.run(gate, { directory = ROOT, runId = "tier-command", selection = { tiers = { "fast" } } })
		expect(recordOf(outcome, "probe").status):toEqual "passed"
		local wrong = Lute.gate.run(gate, { directory = ROOT, runId = "tier-command-none" })
		expect(recordOf(wrong, "probe").status):toEqual "failed"
	end)

	it("keeps the last outcome for a rerun and refuses another gate's", function()
		local bad = fixture(
			"rerun-bad",
			'return function(harness) harness:case("fails", function(context) context:expect(1):toBe(2) end) harness:case("holds", function(context) context:expect(1):toBe(1) end) end'
		)
		local gate = Gate.define { id = "rerun-gate", producers = { specs { bad } } }
		local first = Lute.gate.run(gate, { directory = ROOT .. "/rerun", runId = "rerun-1" })
		expect(first.acceptance.verdict):toEqual "failed"
		local last = assert(Lute.gate.last(gate, { directory = ROOT .. "/rerun" }))
		expect(last.runId):toEqual "rerun-1"
		local selection = assert(Gate.rerun(last))
		expect(selection.ids):toEqual { "specs" }
		expect(#(assert(selection.cases))):toEqual(1)
		local again = Lute.gate.run(gate, { directory = ROOT .. "/rerun", runId = "rerun-2", selection = selection })
		expect(recordOf(again, "specs").status):toEqual "failed"
		expect(#recordOf(again, "specs").deselected):toEqual(1)
		expect(again.acceptance.verdict):toEqual "failed"
		local other = Gate.define { id = "other-gate", producers = { specs { bad } } }
		local refused, reason = Lute.gate.last(other, { directory = ROOT .. "/rerun" })
		expect(refused):toEqual(nil)
		expect(reason):toContain "another gate"
		local none, absent = Lute.gate.last(gate, { directory = ROOT .. "/never" })
		expect(none):toEqual(nil)
		expect(absent):toContain "no earlier outcome"
	end)
end)

describe("the gate command line", function()
	local function talk(): ({ string }, GateRuntime.Gate)
		local lines: { string } = {}
		local runtime = table.clone(LuteRuntime)
		runtime.stdio = {
			print = function(line: string)
				table.insert(lines, line)
			end,
		}
		return lines, GateRuntime.create(runtime)
	end

	local function draft(modules: { string }): Gate.Draft
		return {
			id = "cli-gate",
			producers = {
				sh("alpha", "echo ok"),
				{
					id = "specs",
					kind = "tests",
					worker = "examples/worker.luau",
					locators = modules,
					deadlineSeconds = 30,
				},
			},
		}
	end

	local function joined(lines: { string }): string
		return table.concat(lines, "\n")
	end

	it("runs a draft, lists producers and returns the exit code", function()
		local named = fixture(
			"cli-named",
			'return function(harness) harness:case("opens the door", function() end) harness:case("closes the window", function() end) end'
		)
		local lines, cli = talk()
		local options = { options = { directory = ROOT .. "/cli" } }
		expect(cli.cli(draft { named }, { "--list" }, options)):toEqual(0)
		expect(joined(lines)):toContain "alpha"
		expect(cli.cli(draft { named }, {}, options)):toEqual(0)
		expect(joined(lines)):toContain "gate: PASSED"
		expect(cli.cli(draft { named }, { "--only", "alpha" }, options)):toEqual(0)
		expect(joined(lines)):toContain "NARROWED"
		expect(cli.cli(draft { named }, { "--name", "door" }, options)):toEqual(0)
		expect(joined(lines)):toContain 'name "door"'
		expect(cli.cli(draft { named }, { "--explain", "alpha" }, options)):toEqual(0)
		expect(cli.cli(draft { named }, { "--only", "alpha", "--rerun" }, options)):toEqual(0)
	end)

	it("narrows the silent modules with the spec file", function()
		local first = fixture("cli-silent-a", 'return function(harness) harness:case("opens", function() end) end')
		local quiet = fixture("cli-silent-b", "return function(harness) end")
		local base = draft { first, quiet }
		base.producers[2].silent = { quiet }
		local _, cli = talk()
		local options = { options = { directory = ROOT .. "/cli-silent" } }
		expect(cli.cli(base, {}, options)):toEqual(0)
		expect(cli.cli(base, { "--file", first }, options)):toEqual(0)
	end)

	it("narrows a declared census with the spec file and still enforces it", function()
		local first = fixture(
			"cli-census-a",
			'return function(harness) harness:case("opens", function() end) harness:case("closes", function() end) end'
		)
		local second = fixture("cli-census-b", 'return function(harness) harness:case("lone", function() end) end')
		local function census(missing: string?): Gate.Draft
			local base = draft { first, second }
			local producer = base.producers[2]
			local ids = { first .. "::opens", first .. "::closes", second .. "::lone" }
			if missing ~= nil then
				table.insert(ids, missing)
			end
			producer.cases = ids
			return base
		end
		local lines, cli = talk()
		local options = { options = { directory = ROOT .. "/cli-census" } }
		expect(cli.cli(census(), {}, options)):toEqual(0)
		expect(cli.cli(census(), { "--file", first }, options)):toEqual(0)
		expect(cli.cli(census(), { "--file", second }, options)):toEqual(0)
		expect(cli.cli(census(), { "--name", "lone" }, options)):toEqual(0)
		expect(cli.cli(census(), { "--only", "specs", "--case", second .. "::lone" }, options)):toEqual(0)
		expect(cli.cli(census(second .. "::absent"), { "--file", first }, options)):toEqual(0)
		expect(cli.cli(census(first .. "::absent"), { "--file", first }, options)):toEqual(1)
		expect(joined(lines)):toContain "missing case(s)"
		expect(cli.cli(census(second .. "::absent"), {}, options)):toEqual(1)
		local loose = census()
		loose.producers[2].cases = { "opens", "closes", "lone" }
		expect(cli.cli(loose, { "--file", first }, options)):toEqual(0)
	end)

	it("narrows to a spec file and fails on a miss, a bad flag or a missing outcome", function()
		local named = fixture("cli-file", 'return function(harness) harness:case("opens the door", function() end) end')
		local other = fixture("cli-other", 'return function(harness) harness:case("lone", function() end) end')
		local lines, cli = talk()
		local options = { options = { directory = ROOT .. "/cli-file" } }
		expect(cli.cli(draft { named, other }, { "--file", named }, options)):toEqual(0)
		expect(joined(lines)):toContain "NARROWED"
		expect(cli.cli(draft { named }, { "--file", "nowhere.verify.luau" }, options)):toEqual(2)
		expect(joined(lines)):toContain "no spec file named nowhere.verify.luau"
		expect(cli.cli(draft { named }, { "--name", "garage" }, options)):toEqual(1)
		expect(joined(lines)):toContain "gate: FAILED"
		expect(cli.cli(draft { named }, { "--bogus" }, options)):toEqual(2)
		expect(cli.cli(draft { named }, { "--tier" }, options)):toEqual(2)
		expect(cli.cli(draft { named }, { "--name", "" }, options)):toEqual(2)
		expect(joined(lines)):toContain "usage:"
		local fresh = { options = { directory = ROOT .. "/cli-none" } }
		expect(cli.cli(draft { named }, { "--rerun" }, fresh)):toEqual(1)
		expect(cli.cli(draft { named }, { "--explain", "alpha" }, fresh)):toEqual(1)
		local failing = draft { named }
		table.insert(failing.producers, sh("broken", "exit 3"))
		expect(cli.cli(failing, {}, options)):toEqual(1)
	end)
end)

return nil
