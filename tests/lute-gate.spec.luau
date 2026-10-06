--!strict

local fs = require "@std/fs"

local Files = require "../src/lute/files"
local Lute = require "../src/lute"
local Verify = require "../src/core"
local Gate = require "../src/gate"
local GateRuntime = require "../src/runtime/gate"
local LuteRuntime = require "../src/lute/runtime"

local ROOT = ".lute/tmp/verify-gate-test"

type ShOptions = { deadlineSeconds: number?, report: Gate.ReportExpectation? }

local function sh(id: string, script: string, extra: ShOptions?): Gate.ProducerDraft
	local more: ShOptions = extra or {}
	return {
		id = id,
		kind = "command",
		argv = { "/bin/sh", "-c", script, "sh" },
		deadlineSeconds = more.deadlineSeconds,
		report = more.report,
	}
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
	local path = ("%s/modules/%s.spec.luau"):format(ROOT, name)
	fs.writeStringToFile(path, source)
	return path
end

return function(suite: Verify.Harness)
	suite:suite("gate commands on the Lute host", function()
		suite:case("passes and fails by exit code and keeps the full log on disk", function(check)
			local outcome = runIn("exit-codes", {
				sh("good", "echo fine"),
				sh("bad", "echo to-out; echo to-err >&2; exit 4"),
			})
			check:expect(recordOf(outcome, "good").status):toEqual "passed"
			local bad = recordOf(outcome, "bad")
			check:expect(bad.status):toEqual "failed"
			check:expect(bad.exitcode):toEqual(4)
			check:expect(bad.log ~= nil and bad.log.stderr):toEqual "to-err\n"
			local reference = assert(bad.log and bad.log.reference)
			local text = fs.readFileToString(reference)
			check:expect(text):toContain "to-out"
			check:expect(text):toContain "exit 4"
			check:expect(outcome.acceptance.verdict):toEqual "failed"
			check:expect(outcome.execution.report.total):toEqual(2)
		end)

		suite:case("terminates a command and its children at its deadline", function(check)
			local began = os.clock()
			local outcome = runIn("deadline", { sh("hung", "sleep 8; echo late", { deadlineSeconds = 1 }) })
			check:expect(recordOf(outcome, "hung").status):toEqual "timed_out"
			check:expect(recordOf(outcome, "hung").timedOut):toEqual(true)
			check:expect(os.clock() - began < 5):toEqual(true)
			check:expect(outcome.acceptance.releasable):toEqual(false)
		end)

		suite:case("bounds concurrency while still overlapping commands", function(check)
			local began = os.clock()
			local outcome = runIn(
				"concurrent",
				{ sh("a", "sleep 1"), sh("b", "sleep 1"), sh("c", "sleep 1") },
				{ concurrency = 2 }
			)
			local elapsed = os.clock() - began
			check:expect(outcome.acceptance.verdict):toEqual "release"
			check:expect(elapsed >= 1.9):toEqual(true)
			check:expect(elapsed < 3.0):toEqual(true)
		end)

		suite:case("stops starting commands at the whole-run deadline", function(check)
			local outcome = runIn(
				"run-deadline",
				{ sh("first", "sleep 6"), sh("second", "echo never") },
				{ deadlineSeconds = 1 }
			)
			check:expect(recordOf(outcome, "first").status):toEqual "timed_out"
			check:expect(recordOf(outcome, "second").status):toEqual "timed_out"
			check:expect(recordOf(outcome, "second").detail):toContain "run deadline"
			check:expect(outcome.acceptance.verdict):toEqual "failed"
		end)

		suite:case("passes environment variables and the working directory to the command", function(check)
			Files.ensureDirectory(ROOT .. "/cwd")
			local probe =
				sh("probe", 'test "$GATE_PROBE" = yes && test -n "$HOME" && test "$(basename "$(pwd)")" = cwd')
			probe.env = { GATE_PROBE = "yes" }
			probe.cwd = ROOT .. "/cwd"
			local wrong = sh("wrong", 'test "$GATE_PROBE" = yes')
			local outcome = runIn("context", { probe, wrong })
			check:expect(recordOf(outcome, "probe").status):toEqual "passed"
			check:expect(recordOf(outcome, "wrong").status):toEqual "failed"
		end)

		suite:case("runs the producers in dependency order", function(check)
			local marker = ROOT .. "/order.txt"
			Files.ensureDirectory(ROOT)
			Files.removeIfPresent(marker)
			local function appender(id: string, after: { string }?): Gate.ProducerDraft
				return {
					id = id,
					kind = "command",
					argv = { "/bin/sh", "-c", 'printf "%s " "$1" >> ' .. marker, "sh", id },
					after = after,
				}
			end
			local outcome = runIn(
				"ordered",
				{ appender("third", { "second" }), appender("second", { "first" }), appender("first", nil) }
			)
			check:expect(outcome.acceptance.verdict):toEqual "release"
			check:expect(fs.readFileToString(marker)):toEqual "first second third "
		end)
	end)

	suite:suite("run-bound reports from commands", function()
		local function stage(runId: string, id: string, bound: string, name: string): string
			local directory = ("%s/%s"):format(ROOT, runId)
			Files.ensureDirectory(directory)
			local source = ("%s/%s-source.json"):format(directory, id)
			Lute.gate.writeReport(source, bound, reportOf(name, "probe"))
			return source
		end

		suite:case("accepts the current run's report and refuses every other one", function(check)
			local runId = "bound-1"
			local current = stage(runId, "current", runId, "check-one")
			local foreign = stage(runId, "foreign", "another-run", "check-one")
			local outcome = runIn("bound", {
				sh("silent", "true", { report = {} }),
				{
					id = "current",
					kind = "command",
					argv = { "/bin/cp", current, "{report}" },
					report = { cases = { "check-one" } },
				},
				{ id = "foreign", kind = "command", argv = { "/bin/cp", foreign, "{report}" }, report = {} },
				sh("garbage", 'printf "not json" > "$1"', { report = {} }),
			}, nil, runId)
			check:expect(recordOf(outcome, "silent").status):toEqual "failed"
			check:expect(recordOf(outcome, "silent").detail):toContain "without the expected report"
			check:expect(recordOf(outcome, "current").status):toEqual "passed"
			check:expect(recordOf(outcome, "current").reportAccounted):toEqual(true)
			check:expect(recordOf(outcome, "foreign").status):toEqual "failed"
			check:expect(recordOf(outcome, "foreign").detail):toContain "not the current run"
			check:expect(recordOf(outcome, "garbage").status):toEqual "failed"
			check:expect(outcome.acceptance.verdict):toEqual "failed"
		end)

		suite:case("does not let a stale file at the report path stand in for this run", function(check)
			local runId = "stale-1"
			local directory = ("%s/%s"):format(ROOT, runId)
			Files.ensureDirectory(directory)
			Lute.gate.writeReport(directory .. "/probe.report.json", runId, reportOf("old", "probe"))
			local outcome = runIn("stale", { sh("probe", "true", { report = {} }) }, nil, runId)
			check:expect(recordOf(outcome, "probe").status):toEqual "failed"
			check:expect(recordOf(outcome, "probe").detail):toContain "no report file was written"
		end)
	end)

	suite:suite("test modules on the Lute host", function()
		local function modules(locators: { string }): Gate.ProducerDraft
			return {
				id = "specs",
				kind = "tests",
				worker = "examples/worker.luau",
				locators = locators,
				deadlineSeconds = 60,
			}
		end

		suite:case("runs ordinary spec modules and accounts every one", function(check)
			local good = fixture(
				"good",
				'return function(harness) harness:case("fine", function(context) context:expect(1):toBe(1) end) end'
			)
			local outcome = runIn("modules-ok", { modules { good } })
			check:expect(recordOf(outcome, "specs").status):toEqual "passed"
			check:expect(recordOf(outcome, "specs").reportAccounted):toEqual(true)
			check:expect(outcome.acceptance.verdict):toEqual "release"
		end)

		suite:case("fails a module that registers no case, one that breaks and one that cannot load", function(check)
			local empty = fixture("empty", "return function(harness) end")
			local broken = fixture("broken", 'return function(harness) error("registration broke", 0) end')
			local missing = ROOT .. "/modules/absent.spec.luau"
			local emptyOutcome = runIn("modules-empty", { modules { empty } })
			check:expect(recordOf(emptyOutcome, "specs").status):toEqual "failed"
			check:expect(recordOf(emptyOutcome, "specs").detail):toContain "reported no case"
			local brokenOutcome = runIn("modules-broken", { modules { broken } })
			check:expect(recordOf(brokenOutcome, "specs").status):toEqual "failed"
			check:expect(brokenOutcome.acceptance.verdict):toEqual "failed"
			local missingOutcome = runIn("modules-missing", { modules { missing } })
			check:expect(recordOf(missingOutcome, "specs").status):toEqual "failed"
			check:expect(missingOutcome.execution.report.failed >= 1):toEqual(true)
		end)

		suite:case("fails when the worker cannot run at all", function(check)
			local gate = Gate.define {
				id = "no-worker",
				producers = {
					{ id = "specs", kind = "tests", worker = "examples/none.luau", locators = { "x.spec.luau" } },
				},
			}
			local outcome = Lute.gate.run(gate, { directory = ROOT, runId = "no-worker" })
			check:expect(recordOf(outcome, "specs").status):toEqual "failed"
			check:expect(outcome.acceptance.releasable):toEqual(false)
		end)
	end)

	suite:suite("isolated sources, selection and the last outcome", function()
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
				'local state = require("./leak-state.spec") return function(harness) harness:case("pollutes", function(context) state.leaked = true end) end'
			)
		end

		local function observer(): string
			return fixture(
				"observer",
				'local state = require("./leak-state.spec") return function(harness) harness:case("clean", function(context) context:expect(state.leaked):toBe(false) end) end'
			)
		end

		suite:case("runs each source in its own worker process under one producer", function(check)
			local shared = runIn("shared-process", { specs { polluter(), observer() } })
			check:expect(recordOf(shared, "specs").status):toEqual "failed"
			check:expect(recordOf(shared, "specs").detail):toContain "observer.spec.luau::clean"
			local isolated =
				runIn("isolated-process", { specs({ polluter(), observer() }, { isolate = true, workers = 2 }) })
			check:expect(recordOf(isolated, "specs").status):toEqual "passed"
			check:expect(#isolated.producers):toEqual(1)
			check:expect(Gate.testCases(isolated).total):toEqual(2)
			check:expect(isolated.acceptance.verdict):toEqual "release"
		end)

		suite:case("attributes a load error, a registration error and a hang to their own source", function(check)
			local good = fixture(
				"isolated-good",
				'return function(harness) harness:case("fine", function(context) context:expect(1):toBe(1) end) end'
			)
			local broken = fixture("isolated-broken", 'return function(harness) error("registration broke", 0) end')
			local hung = fixture("isolated-hung", "while true do end")
			local missing = ROOT .. "/modules/isolated-absent.spec.luau"
			local outcome = runIn(
				"isolated-faults",
				{ specs({ good, broken, missing, hung }, { isolate = true, workers = 4, deadlineSeconds = 3 }) }
			)
			local record = recordOf(outcome, "specs")
			check:expect(record.status):toEqual "failed"
			local cases = Gate.testCases(outcome)
			check:expect(cases.total):toEqual(4)
			check:expect(cases.passed):toEqual(1)
			check:expect(cases.failed + cases.timedOut):toEqual(3)
			local sources: { string } = {}
			for _, result in cases.results do
				if result.status ~= "passed" then
					table.insert(sources, tostring(result.source))
				end
			end
			table.sort(sources)
			local expected = { broken, hung, missing }
			table.sort(expected)
			check:expect(sources):toEqual(expected)
			check:expect(record.detail):toContain "3 of 4 reported case(s) did not pass"
			check:expect(outcome.acceptance.failed):toEqual { "specs" }
		end)

		suite:case("times a hung source out alone against its own deadline", function(check)
			local good = fixture(
				"budget-good",
				'return function(harness) harness:case("fine", function(context) context:expect(1):toBe(1) end) end'
			)
			local hung = fixture("budget-hung", "while true do end")
			local began = os.clock()
			local outcome = runIn("source-deadline", {
				specs({ hung, good }, { isolate = true, workers = 1, sourceDeadlineSeconds = 1, deadlineSeconds = 60 }),
			})
			check:expect(os.clock() - began < 20):toEqual(true)
			local cases = Gate.testCases(outcome)
			check:expect(cases.passed):toEqual(1)
			check:expect(cases.timedOut):toEqual(1)
			for _, result in cases.results do
				if result.status == "timed_out" then
					check:expect(result.source):toEqual(hung)
				end
			end
			check
				:expect(function()
					Gate.define {
						id = "g",
						producers = {
							{ id = "t", kind = "tests", worker = "w", locators = { "a" }, sourceDeadlineSeconds = 1 },
						},
					}
				end)
				:toThrow "needs isolate = true"
		end)

		suite:case("passes the selected tier and cases to the worker and states the selection", function(check)
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
			check:expect(record.status):toEqual "passed"
			check:expect(#record.deselected):toEqual(1)
			check:expect(record.deselected[1]):toContain "long"
			check:expect(outcome.acceptance.verdict):toEqual "selected"
			check:expect(outcome.scope.deselected):toEqual(record.deselected)
			check:expect(outcome.acceptance.skippedByTier):toEqual {}
			check:expect(outcome.acceptance.notSelected):toEqual { "other" }
			local named = Lute.gate.run(
				gate,
				{ directory = ROOT, runId = "named-case", selection = { ids = { "specs" }, cases = { "x" } } }
			)
			check:expect(named.acceptance.verdict):toEqual "failed"
			check:expect(named.acceptance.reasons[1]):toContain "were not found"
		end)

		suite:case("filters real worker cases by name and fails when the name matches nothing", function(check)
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
			check:expect(recordOf(narrowed, "specs").status):toEqual "passed"
			check:expect(#recordOf(narrowed, "specs").deselected):toEqual(1)
			check:expect(narrowed.acceptance.verdict):toEqual "selected"
			check:expect(narrowed.acceptance.notSelected):toEqual { "other" }
			local missed =
				Lute.gate.run(gate, { directory = ROOT, runId = "name-miss", selection = { nameContains = "garage" } })
			check:expect(missed.acceptance.verdict):toEqual "failed"
		end)

		suite:case("substitutes the selected tier into a command", function(check)
			local gate = Gate.define {
				id = "tier-command",
				producers = {
					{
						id = "probe",
						kind = "command",
						argv = { "/bin/sh", "-c", 'test "$1" = fast', "sh", "{tier}" },
						tier = "fast",
					},
					sh("other", "echo ok"),
				},
			}
			local outcome =
				Lute.gate.run(gate, { directory = ROOT, runId = "tier-command", selection = { tiers = { "fast" } } })
			check:expect(recordOf(outcome, "probe").status):toEqual "passed"
			local wrong = Lute.gate.run(gate, { directory = ROOT, runId = "tier-command-none" })
			check:expect(recordOf(wrong, "probe").status):toEqual "failed"
		end)

		suite:case("keeps the last outcome for a rerun and refuses another gate's", function(check)
			local bad = fixture(
				"rerun-bad",
				'return function(harness) harness:case("fails", function(context) context:expect(1):toBe(2) end) harness:case("holds", function(context) context:expect(1):toBe(1) end) end'
			)
			local gate = Gate.define { id = "rerun-gate", producers = { specs { bad } } }
			local first = Lute.gate.run(gate, { directory = ROOT .. "/rerun", runId = "rerun-1" })
			check:expect(first.acceptance.verdict):toEqual "failed"
			local last = assert(Lute.gate.last(gate, { directory = ROOT .. "/rerun" }))
			check:expect(last.runId):toEqual "rerun-1"
			local selection = assert(Gate.rerun(last))
			check:expect(selection.ids):toEqual { "specs" }
			check:expect(#(selection.cases :: { string })):toEqual(1)
			local again =
				Lute.gate.run(gate, { directory = ROOT .. "/rerun", runId = "rerun-2", selection = selection })
			check:expect(recordOf(again, "specs").status):toEqual "failed"
			check:expect(#recordOf(again, "specs").deselected):toEqual(1)
			check:expect(again.acceptance.verdict):toEqual "failed"
			local other = Gate.define { id = "other-gate", producers = { specs { bad } } }
			local refused, reason = Lute.gate.last(other, { directory = ROOT .. "/rerun" })
			check:expect(refused):toEqual(nil)
			check:expect(reason):toContain "another gate"
			local none, absent = Lute.gate.last(gate, { directory = ROOT .. "/never" })
			check:expect(none):toEqual(nil)
			check:expect(absent):toContain "no earlier outcome"
		end)
	end)

	suite:suite("the gate command line", function()
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

		suite:case("runs a draft, lists producers and returns the exit code", function(check)
			local named = fixture(
				"cli-named",
				'return function(harness) harness:case("opens the door", function() end) harness:case("closes the window", function() end) end'
			)
			local lines, cli = talk()
			local options = { options = { directory = ROOT .. "/cli" } }
			check:expect(cli.cli(draft { named }, { "--list" }, options)):toEqual(0)
			check:expect(joined(lines)):toContain "alpha"
			check:expect(cli.cli(draft { named }, {}, options)):toEqual(0)
			check:expect(joined(lines)):toContain "gate: PASSED"
			check:expect(cli.cli(draft { named }, { "--only", "alpha" }, options)):toEqual(0)
			check:expect(joined(lines)):toContain "NARROWED"
			check:expect(cli.cli(draft { named }, { "--name", "door" }, options)):toEqual(0)
			check:expect(joined(lines)):toContain 'name "door"'
			check:expect(cli.cli(draft { named }, { "--explain", "alpha" }, options)):toEqual(0)
			check:expect(cli.cli(draft { named }, { "--only", "alpha", "--rerun" }, options)):toEqual(0)
		end)

		suite:case("narrows the silent modules with the spec file", function(check)
			local first = fixture("cli-silent-a", 'return function(harness) harness:case("opens", function() end) end')
			local quiet = fixture("cli-silent-b", "return function(harness) end")
			local base = draft { first, quiet }
			base.producers[2].silent = { quiet }
			local _, cli = talk()
			local options = { options = { directory = ROOT .. "/cli-silent" } }
			check:expect(cli.cli(base, {}, options)):toEqual(0)
			check:expect(cli.cli(base, { "--file", first }, options)):toEqual(0)
		end)

		suite:case("narrows a declared census with the spec file and still enforces it", function(check)
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
			check:expect(cli.cli(census(), {}, options)):toEqual(0)
			check:expect(cli.cli(census(), { "--file", first }, options)):toEqual(0)
			check:expect(cli.cli(census(), { "--file", second }, options)):toEqual(0)
			check:expect(cli.cli(census(), { "--name", "lone" }, options)):toEqual(0)
			check:expect(cli.cli(census(), { "--only", "specs", "--case", second .. "::lone" }, options)):toEqual(0)
			check:expect(cli.cli(census(second .. "::absent"), { "--file", first }, options)):toEqual(0)
			check:expect(cli.cli(census(first .. "::absent"), { "--file", first }, options)):toEqual(1)
			check:expect(joined(lines)):toContain "missing case(s)"
			check:expect(cli.cli(census(second .. "::absent"), {}, options)):toEqual(1)
			local loose = census()
			loose.producers[2].cases = { "opens", "closes", "lone" }
			check:expect(cli.cli(loose, { "--file", first }, options)):toEqual(0)
		end)

		suite:case("narrows to a spec file and fails on a miss, a bad flag or a missing outcome", function(check)
			local named =
				fixture("cli-file", 'return function(harness) harness:case("opens the door", function() end) end')
			local other = fixture("cli-other", 'return function(harness) harness:case("lone", function() end) end')
			local lines, cli = talk()
			local options = { options = { directory = ROOT .. "/cli-file" } }
			check:expect(cli.cli(draft { named, other }, { "--file", named }, options)):toEqual(0)
			check:expect(joined(lines)):toContain "NARROWED"
			check:expect(cli.cli(draft { named }, { "--file", "nowhere.spec.luau" }, options)):toEqual(2)
			check:expect(joined(lines)):toContain "no spec file named nowhere.spec.luau"
			check:expect(cli.cli(draft { named }, { "--name", "garage" }, options)):toEqual(1)
			check:expect(joined(lines)):toContain "gate: FAILED"
			check:expect(cli.cli(draft { named }, { "--bogus" }, options)):toEqual(2)
			check:expect(cli.cli(draft { named }, { "--tier" }, options)):toEqual(2)
			check:expect(cli.cli(draft { named }, { "--name", "" }, options)):toEqual(2)
			check:expect(joined(lines)):toContain "usage:"
			local fresh = { options = { directory = ROOT .. "/cli-none" } }
			check:expect(cli.cli(draft { named }, { "--rerun" }, fresh)):toEqual(1)
			check:expect(cli.cli(draft { named }, { "--explain", "alpha" }, fresh)):toEqual(1)
			local failing = draft { named }
			table.insert(failing.producers, sh("broken", "exit 3"))
			check:expect(cli.cli(failing, {}, options)):toEqual(1)
		end)
	end)
end
