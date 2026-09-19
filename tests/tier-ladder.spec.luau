--!strict

local test = require "@std/test"

local Roblox = require "../src/roblox"

local Ladder = Roblox.tierLadder

local SESSION_CONTRACT = "adopter.session-observation.v1"
local CLIENT_CONTRACT = "adopter.client-observation.v1"
local ARMED_CONTRACT = "adopter.armed.v1"
local SUMMARY_CONTRACT = "adopter.results-summary.v1"

local function seal(): Roblox.TierLadderSeal
	return {
		executor = "adopter.ladder",
		environment = { experience = "development" },
		capabilities = { "remote-session" },
		actors = { "synthetic-actor" },
		artifacts = {},
	}
end

local function spec(verbs: any, observations: { [string]: any }?, declare: ((string) -> ())?)
	verbs.describe("ladder", function()
		if observations == nil then
			if declare ~= nil then
				declare "the run reported a boot"
			end
			return
		end
		verbs.it("the run reported a boot", function(_own: any, context: any)
			context:step("boot_refused", function()
				verbs.expect((observations :: any).booted):toEqual(true)
			end)
		end)
	end)
end

local UNSUPPORTED: Roblox.TierLadderUnsupportedRule = {
	status = "UNSUPPORTED",
	reason = "ladder_unsupported",
	fromReason = "boot_refused",
	whenText = { key = "bootRoute", value = "none" },
	whenZero = "errorLineCount",
	namedBy = "failures",
	fallback = "this target mounts nothing the ladder could boot",
}

test.suite("tier ladder classification", function(suite)
	suite:case("names an unreached capability as the caller's own limitation", function(assert)
		local status, reason, limitation = Ladder.classify("HOLD", "boot_refused", {
			bootRoute = "none",
			errorLineCount = 0,
			failures = { "no entry to require" },
		}, UNSUPPORTED)
		assert.eq(status, "UNSUPPORTED")
		assert.eq(reason, "ladder_unsupported")
		assert.eq(limitation, "no entry to require")
	end)

	suite:case("falls back to the caller's own words when the probe named nothing", function(assert)
		local _status, _reason, limitation = Ladder.classify(
			"HOLD",
			"boot_refused",
			{ bootRoute = "none", errorLineCount = 0, failures = {} },
			UNSUPPORTED
		)
		assert.eq(limitation, UNSUPPORTED.fallback)
	end)

	suite:case("keeps a hold red when the run logged an error line", function(assert)
		local status, reason, limitation = Ladder.classify("HOLD", "boot_refused", {
			bootRoute = "none",
			errorLineCount = 1,
			failures = { "no entry to require" },
		}, UNSUPPORTED)
		assert.eq(status, "HOLD")
		assert.eq(reason, "boot_refused")
		assert.eq(limitation, nil)
	end)

	suite:case("keeps a hold red when the capability was reached", function(assert)
		local status, _reason, limitation = Ladder.classify("HOLD", "boot_refused", {
			bootRoute = "entry",
			errorLineCount = 0,
			failures = { "the entry refused" },
		}, UNSUPPORTED)
		assert.eq(status, "HOLD")
		assert.eq(limitation, nil)
	end)

	suite:case("keeps a hold red when its reason is not the rule's own", function(assert)
		local status, reason = Ladder.classify("HOLD", "content_refused", {
			bootRoute = "none",
			errorLineCount = 0,
			failures = {},
		}, UNSUPPORTED)
		assert.eq(status, "HOLD")
		assert.eq(reason, "content_refused")
	end)

	suite:case("passes a clear verdict through untouched", function(assert)
		local status, reason, limitation =
			Ladder.classify("COMPLETE", "ladder_passed", { bootRoute = "none", errorLineCount = 0 }, UNSUPPORTED)
		assert.eq(status, "COMPLETE")
		assert.eq(reason, "ladder_passed")
		assert.eq(limitation, nil)
	end)

	suite:case("passes every verdict through when the caller declared no rule", function(assert)
		local status, reason = Ladder.classify("HOLD", "boot_refused", { bootRoute = "none", errorLineCount = 0 }, nil)
		assert.eq(status, "HOLD")
		assert.eq(reason, "boot_refused")
	end)
end)

test.suite("tier ladder judgement", function(suite)
	suite:case("clears a run whose only case passed", function(assert)
		local verdict = Ladder.judge({ booted = true }, seal(), "ladder.spec", spec, "ladder_passed", UNSUPPORTED)
		assert.eq(verdict.status, "COMPLETE")
		assert.eq(verdict.reason, "ladder_passed")
		assert.eq(verdict.limitation, nil)
		assert.eq((verdict.report :: any).passed, 1)
	end)

	suite:case("holds a run whose case failed and reports the step that named it", function(assert)
		local verdict = Ladder.judge(
			{ booted = false, bootRoute = "entry", errorLineCount = 0 },
			seal(),
			"ladder.spec",
			spec,
			"ladder_passed",
			UNSUPPORTED
		)
		assert.eq(verdict.status, "HOLD")
		assert.eq(verdict.reason, "boot_refused")
		assert.eq((verdict.report :: any).failed, 1)
	end)

	suite:case("softens a hold the rule recognises into an unsupported limitation", function(assert)
		local verdict = Ladder.judge(
			{ booted = false, bootRoute = "none", errorLineCount = 0, failures = { "no entry to require" } },
			seal(),
			"ladder.spec",
			spec,
			"ladder_passed",
			UNSUPPORTED
		)
		assert.eq(verdict.status, "UNSUPPORTED")
		assert.eq(verdict.reason, "ladder_unsupported")
		assert.eq(verdict.limitation, "no entry to require")
	end)
end)

test.suite("tier ladder receipts", function(suite)
	suite:case("carries the caller's binding beside the verdict it banks", function(assert)
		local row = Ladder.receipt {
			contract = "adopter.ladder-run.v1",
			verdict = { status = "COMPLETE", reason = "ladder_passed", limitation = nil, report = nil },
			binding = { target = "one", placeId = "7" },
			observations = { booted = true },
		}
		assert.eq(row.contract, "adopter.ladder-run.v1")
		assert.eq(row.status, "COMPLETE")
		assert.eq(row.target, "one")
		assert.eq(row.placeId, "7")
		assert.eq((row.observations :: any).booted, true)
		assert.eq(row.report, nil)
	end)

	suite:case("never lets a binding restate the judgment", function(assert)
		local row = Ladder.receipt {
			contract = "adopter.ladder-run.v1",
			verdict = { status = "HOLD", reason = "boot_refused", limitation = nil, report = nil },
			binding = { status = "COMPLETE", reason = "ladder_passed" },
		}
		assert.eq(row.status, "HOLD")
		assert.eq(row.reason, "boot_refused")
		assert.eq(row.observations, nil)
	end)
end)

test.suite("tier ladder session observations", function(suite)
	suite:case("folds session and log error lines into one count", function(assert)
		local observations = Ladder.sessionObservations({
			{ contract = SESSION_CONTRACT, errorLines = { "probe line" } },
		}, { contract = SESSION_CONTRACT, errorLines = { "log line" } })
		assert.eq((observations :: any).errorLineCount, 2)
		assert.eq((observations :: any).observationContract, SESSION_CONTRACT)
	end)

	suite:case("refuses a result carrying another contract", function(assert)
		local observations, problem = Ladder.sessionObservations(
			{ { contract = "other.v1" } },
			{ contract = SESSION_CONTRACT }
		)
		assert.eq(observations, nil)
		assert.eq(problem, "the execution session returned other.v1")
	end)

	suite:case("refuses an empty result list", function(assert)
		local observations, problem = Ladder.sessionObservations({}, { contract = SESSION_CONTRACT })
		assert.eq(observations, nil)
		assert.eq(problem, "the execution session returned no observation table")
	end)

	suite:case("decodes a result the session returned as text", function(assert)
		local observations = Ladder.sessionObservations({ "encoded" }, {
			contract = SESSION_CONTRACT,
			decode = function(_payload: string): any
				return { contract = SESSION_CONTRACT, booted = true }
			end,
		})
		assert.eq((observations :: any).booted, true)
	end)

	suite:case("refuses text when the caller supplied no decoder", function(assert)
		local observations, problem = Ladder.sessionObservations({ "encoded" }, { contract = SESSION_CONTRACT })
		assert.eq(observations, nil)
		assert.eq(problem, "the execution session returned no observation table")
	end)

	suite:case("refuses text a decoder could not read", function(assert)
		local observations = Ladder.sessionObservations({ "encoded" }, {
			contract = SESSION_CONTRACT,
			decode = function(_payload: string): any
				return error "unreadable"
			end,
		})
		assert.eq(observations, nil)
	end)
end)

test.suite("tier ladder chunked client probe", function(suite)
	local chunk: Roblox.ChunkedProbe = { deadlineSeconds = 90, chunkSeconds = 25, maxChunks = 4 }

	suite:case("plans one resumable probe call bounded by its own chunk count", function(assert)
		local plan = Ladder.chunkedCallPlan {
			document = "/tmp/place.rbxl",
			probe = "return {}",
			contract = CLIENT_CONTRACT,
			chunk = chunk,
		}
		assert.eq(#plan, 5)
		assert.eq((plan[3] :: any).tool, "execute_luau")
		assert.eq((plan[3] :: any).maxAttempts, 4)
		assert.strContains((plan[3] :: any).expect, CLIENT_CONTRACT)
		assert.strContains((plan[1] :: any).expect, "/tmp/place.rbxl")
		assert.eq((plan[5] :: any).input.is_start, false)
	end)

	suite:case("counts each console line carrying a marker", function(assert)
		assert.eq(Ladder.countMarker("a\nMARK|one\nb\nMARK|two\n", "MARK|"), 2)
		assert.eq(Ladder.countMarker("a\nb\n", "MARK|"), 0)
	end)

	suite:case("classifies the console and counts the markers the caller named", function(assert)
		local observations = Ladder.clientObservations(
			{ contract = CLIENT_CONTRACT, hudPresent = true },
			"ordinary line\nMARK|one\nstack begin",
			{
				contract = CLIENT_CONTRACT,
				chunk = chunk,
				classify = { errorPatterns = { "stack begin" } },
				markers = { { field = "markerCount", marker = "MARK|" } },
			}
		)
		assert.eq((observations :: any).hudPresent, true)
		assert.eq((observations :: any).errorLineCount, 1)
		assert.eq((observations :: any).markerCount, 1)
		assert.eq((observations :: any).consoleBytes, #"ordinary line\nMARK|one\nstack begin")
	end)

	suite:case("refuses a probe still inside its own deadline", function(assert)
		local observations, problem = Ladder.clientObservations(
			{ contract = CLIENT_CONTRACT, pending = true },
			"",
			{ contract = CLIENT_CONTRACT, chunk = chunk }
		)
		assert.eq(observations, nil)
		assert.strContains(problem :: string, "90 second deadline")
	end)

	suite:case("refuses a table under another contract", function(assert)
		local observations, problem = Ladder.clientObservations(
			{ contract = "other.v1" },
			"",
			{ contract = CLIENT_CONTRACT, chunk = chunk }
		)
		assert.eq(observations, nil)
		assert.eq(problem, "the bridge returned other.v1")
	end)

	suite:case("refuses a bridge answer that is not a table", function(assert)
		local observations, problem =
			Ladder.clientObservations("nothing", "", { contract = CLIENT_CONTRACT, chunk = chunk })
		assert.eq(observations, nil)
		assert.eq(problem, "the bridge returned no observation table")
	end)
end)

test.suite("tier ladder value predicates", function(suite)
	suite:case("accepts only a dense list of the exact length", function(assert)
		assert.eq(Ladder.denseRows({ 1, 2, 3 }, 3), true)
		assert.eq(Ladder.denseRows({ 1, 2 }, 3), false)
		assert.eq(Ladder.denseRows({ 1, 2, 3, extra = true }, 3), false)
		assert.eq(Ladder.denseRows(setmetatable({ 1 }, {}), 1), false)
		assert.eq(Ladder.denseRows("rows", 1), false)
	end)

	suite:case("accepts only a finite number", function(assert)
		assert.eq(Ladder.finite(1.5), true)
		assert.eq(Ladder.finite(math.huge), false)
		assert.eq(Ladder.finite(math.nan), false)
		assert.eq(Ladder.finiteNonnegative(-1), false)
		assert.eq(Ladder.nonnegativeInteger(1.5), false)
		assert.eq(Ladder.nonnegativeInteger(2), true)
	end)

	suite:case("refuses a table holding an infinity at any depth", function(assert)
		assert.eq(Ladder.deeplyFinite { a = { b = { 1, 2 } } }, true)
		assert.eq(Ladder.deeplyFinite { a = { b = { math.huge } } }, false)
	end)

	suite:case("accepts only an identifier safe to name a path", function(assert)
		assert.eq(Ladder.safeId "run-1.a", true)
		assert.eq(Ladder.safeId "-run", false)
		assert.eq(Ladder.safeId "run/1", false)
		assert.eq(Ladder.safeId "", false)
		assert.eq(Ladder.safeId(string.rep("a", 65)), false)
		assert.eq(Ladder.safeId(7), false)
	end)

	suite:case("decodes one record and refuses everything else", function(assert)
		local decoder = function(payload: string): any
			if payload == "object" then
				return { runId = "one" }
			end
			if payload == "scalar" then
				return 7
			end
			return error "unreadable"
		end
		assert.eq((Ladder.decodeObject("object", decoder) :: any).runId, "one")
		assert.eq(Ladder.decodeObject("scalar", decoder), nil)
		assert.eq(Ladder.decodeObject("broken", decoder), nil)
		assert.eq(Ladder.decodeObject(nil, decoder), nil)
	end)

	suite:case("reads a row's name from either spelling", function(assert)
		assert.eq(Ladder.rowName { name = "first" }, "first")
		assert.eq(Ladder.rowName { n = "second" }, "second")
		assert.eq(Ladder.rowName { n = "" }, nil)
		assert.eq(Ladder.rowName "row", nil)
	end)
end)

test.suite("tier ladder frame sampling", function(suite)
	local function summary(overrides: { [string]: any }?): { [string]: any }
		local row: { [string]: any } = {
			signal = "route",
			sampleCount = 4,
			elapsedSec = 1,
			p50Ms = 10,
			p95Ms = 20,
			p99Ms = 30,
			maxMs = 40,
			over50MsCount = 1,
			over50MsRatio = 0.25,
		}
		for key, value in (if overrides ~= nil then overrides else {}) :: { [string]: any } do
			row[key] = value
		end
		return row
	end

	local function report(nested: boolean): { [string]: any }
		local row = summary()
		row.phases = { setup = summary() }
		row.longFrames = { { phase = "setup", phaseElapsedSec = 0.1, routeElapsedSec = 0.2, dtMs = 60 } }
		row.longFrameThresholdMs = 50
		row.longFrameCap = 8
		row.longFrameDropped = 0
		if nested then
			local nestedRow = report(false)
			nestedRow.signal = "render"
			row.render = nestedRow
		end
		return row
	end

	local function health(): { [string]: any }
		return {
			ok = true,
			reason = "within",
			detail = "",
			signal = "render",
			sampleCount = 4,
			p50Ms = 10,
			p95Ms = 20,
			p99Ms = 30,
			maxMs = 40,
			over50MsRatio = 0.25,
		}
	end

	local function sampling(): { [string]: any }
		local timing = report(true)
		return {
			clientFrameTiming = timing,
			clientFrameBudget = {
				ok = true,
				detail = "",
				signal = timing.signal,
				environmentUnhealthy = false,
				minimumSamples = 1,
				p95LimitMs = 50,
				p99LimitMs = 60,
				maxLimitMs = 70,
				over50MsRatioLimit = 0.5,
				setupP50LimitMs = 30,
				setupMinimumSamples = 1,
				renderFrameHealth = health(),
			},
			renderFrameHealth = health(),
		}
	end

	suite:case("accepts a summary whose percentiles are ordered and whose ratio is the quotient", function(assert)
		assert.eq(Ladder.frameSummary(summary()), true)
		assert.eq(Ladder.frameSummary(summary { p95Ms = 5 }), false)
		assert.eq(Ladder.frameSummary(summary { over50MsRatio = 0.5 }), false)
		assert.eq(Ladder.frameSummary(summary { over50MsCount = 9 }), false)
	end)

	suite:case("accepts a report only with a nested render report at the outer level", function(assert)
		assert.eq(Ladder.frameReport(report(true), true), true)
		assert.eq(Ladder.frameReport(report(false), true), false)
		assert.eq(Ladder.frameReport(report(true), false), false)
	end)

	suite:case("refuses a report whose long frames overflow their own cap", function(assert)
		local row = report(true)
		row.longFrameCap = 0
		assert.eq(Ladder.frameReport(row, true), false)
	end)

	suite:case("accepts a sampling record whose health agrees with report and budget", function(assert)
		assert.eq(Ladder.frameSamplingComplete(sampling()), true)
	end)

	suite:case("refuses a sampling record whose health disagrees with its budget", function(assert)
		local row = sampling()
		local drifted = health()
		drifted.p95Ms = 21
		row.renderFrameHealth = drifted
		assert.eq(Ladder.frameSamplingComplete(row), false)
	end)

	suite:case("refuses a sampling record carrying an infinity", function(assert)
		local row = sampling()
		local budget = row.clientFrameBudget :: any
		budget.p95LimitMs = math.huge
		assert.eq(Ladder.frameSamplingComplete(row), false)
	end)

	suite:case("refuses a sampling record whose budget names another signal", function(assert)
		local row = sampling()
		local budget = row.clientFrameBudget :: any
		budget.signal = "other"
		assert.eq(Ladder.frameSamplingComplete(row), false)
	end)
end)

test.suite("tier ladder record binding", function(suite)
	suite:case("matches exact fields by value and coerced fields by text", function(assert)
		local record = { contract = ARMED_CONTRACT, placeId = 7, placeVersion = "12" }
		assert.eq(Ladder.boundRecord(record, { contract = ARMED_CONTRACT }, { placeId = "7", placeVersion = 12 }), true)
		assert.eq(Ladder.boundRecord(record, { contract = SUMMARY_CONTRACT }, nil), false)
		assert.eq(Ladder.boundRecord(record, {}, { placeId = "8" }), false)
		assert.eq(Ladder.boundRecord("record", {}, nil), false)
	end)

	suite:case("accepts exactly the expected predicates, each named once and green", function(assert)
		local rows = { { n = "one", ok = true }, { n = "two", ok = true } }
		assert.eq(Ladder.exactGreenRows(rows, 2, { "one", "two" }), true)
		assert.eq(Ladder.exactGreenRows(rows, 2, { "one", "three" }), false)
		assert.eq(Ladder.exactGreenRows(rows, 2, { "one" }), false)
		assert.eq(Ladder.exactGreenRows(rows, 3, { "one", "two", "three" }), false)
		assert.eq(Ladder.exactGreenRows(rows, 2, nil), true)
	end)

	suite:case("refuses rows that repeat one name or report a failure", function(assert)
		assert.eq(Ladder.exactGreenRows({ { n = "one", ok = true }, { n = "one", ok = true } }, 2, nil), false)
		assert.eq(Ladder.exactGreenRows({ { n = "one", ok = true }, { n = "two", ok = false } }, 2, nil), false)
		assert.eq(Ladder.exactGreenRows({ { n = "", ok = true } }, 1, nil), false)
	end)

	suite:case("refuses an expected name list that repeats or is empty", function(assert)
		assert.eq(
			Ladder.exactGreenRows({ { n = "one", ok = true }, { n = "two", ok = true } }, 2, { "one", "one" }),
			false
		)
		assert.eq(Ladder.exactGreenRows({ { n = "one", ok = true } }, 1, { "" }), false)
	end)
end)

test.suite("tier ladder transcript salvage", function(suite)
	suite:case("names the failed rows a truncated transcript still spells", function(assert)
		local names = Ladder.failedRowNames '{"ok":false,"name":"first","detail":"x"} {"ok":false,"n":"second"}'
		assert.eq(#names, 2)
		assert.eq(names[1], "first")
		assert.eq(names[2], "second")
	end)

	suite:case("names each failed row once", function(assert)
		local names = Ladder.failedRowNames '{"ok":false,"n":"first"}{"ok":false,"n":"first"}'
		assert.eq(#names, 1)
	end)

	suite:case("collects the distinct console lines that read as a refusal", function(assert)
		local lines = Ladder.refusalLines(table.concat({
			"ordinary boot line",
			"Foo:12: attempt to index nil with 'Bar'",
			"RequestX refused: not authorized for this actor",
			"ordinary boot line",
			"Foo:12: attempt to index nil with 'Bar'",
		}, "\n"))
		assert.eq(#lines, 2)
		assert.strContains(lines[1], "attempt to index")
		assert.strContains(lines[2], "not authorized")
	end)

	suite:case("collects nothing from a clean transcript", function(assert)
		assert.eq(#Ladder.refusalLines "ordinary boot line\nall clear\n", 0)
	end)

	suite:case("caps a flooded transcript and honours the caller's own vocabulary", function(assert)
		local flood: { string } = {}
		for index = 1, 40 do
			table.insert(flood, ("refused %d"):format(index))
		end
		assert.eq(#Ladder.refusalLines(table.concat(flood, "\n")), Ladder.DEFAULT_REFUSAL_LIMIT)
		assert.eq(#Ladder.refusalLines("blocked here\nrefused there", { "blocked" }, 5), 1)
	end)

	suite:case("reports one predicate row per name, in order and never twice", function(assert)
		local rows = Ladder.predicateRows({
			{ name = "first", ok = true },
			{ n = "second", ok = false },
			{ name = "first", ok = false },
			{ ok = false },
		}, "no detail")
		assert.eq(#rows, 2)
		assert.eq(rows[1].name, "first")
		assert.eq(rows[1].ok, true)
		assert.eq(rows[2].ok, false)
		assert.eq(rows[2].detail, "no detail")
	end)
end)

local NAMES: Roblox.JourneyNames = {
	armedContract = ARMED_CONTRACT,
	summaryContract = SUMMARY_CONTRACT,
	configurationBound = "configuration_bound",
	publishCurrent = "publish_current",
	launched = "driver_launched",
	logBound = "log_bound",
	recordMismatch = "record_mismatch",
	acceptanceOrder = "acceptance_order",
	acceptanceIncomplete = "acceptance_incomplete",
	receiptMissing = "receipt_missing",
	receiptTruncated = "receipt_truncated",
	failed = "scenario_failed",
	driverActor = "driver",
	hostActor = "scenario-host",
	acceptanceActor = "acceptance",
	publishArtifact = "publish-receipt",
	baselineArtifact = "baseline-log",
	logArtifact = "run-log",
}

local function payloads(): { [string]: any }
	return {
		armed = { contract = ARMED_CONTRACT, runId = "run1", placeId = 7 },
		summary = {
			contract = SUMMARY_CONTRACT,
			runId = "run1",
			placeId = 7,
			passed = 2,
			failed = 0,
			skipped = 0,
			results = { { n = "one", ok = true }, { n = "two", ok = true } },
		},
	}
end

local function journeyOptions(overrides: { [string]: any }?): Roblox.JourneyOptions
	local decoded = payloads()
	local settings: Roblox.JourneyOptions = {
		names = NAMES,
		decode = function(payload: string): any
			return decoded[payload]
		end,
		bind = function(_seen: { [string]: any }, contract: string, runId: string)
			return { contract = contract, runId = runId }, { placeId = "7" }
		end,
		acceptance = function(_start: any, _finish: any, _summary: any): (any?, string?)
			return { accepted = true }, nil
		end,
	}
	local fields = settings :: any
	for key, value in (if overrides ~= nil then overrides else {}) :: { [string]: any } do
		fields[key] = value
	end
	return settings
end

local function journeyObservations(overrides: { [string]: any }?): { [string]: any }
	local seen: { [string]: any } = {
		logBound = true,
		logFile = "/tmp/run.log",
		publishReceiptPath = "/tmp/publish.json",
		baselineLogs = {},
		requireBoundRecords = true,
		requireAcceptance = false,
		armedPayloads = { "armed" },
		summaryPayloads = { "summary" },
		armedPayload = "armed",
		summaryPayload = "summary",
		expectedPassed = 2,
		expectedPredicateNames = { "one", "two" },
		consoleRefusalLines = {},
		rows = { { n = "one", ok = true }, { n = "two", ok = true } },
		summaryFailed = 0,
	}
	for key, value in (if overrides ~= nil then overrides else {}) :: { [string]: any } do
		seen[key] = value
	end
	return seen
end

local function journeySeal(): Roblox.TierLadderSeal
	return {
		executor = "adopter.journey",
		environment = { experience = "development" },
		capabilities = { "runtime-log" },
		actors = { "driver" },
		artifacts = {},
	}
end

local function journeyVerdict(seen: { [string]: any }, options: Roblox.JourneyOptions): Roblox.TierLadderVerdict
	return Ladder.judge(seen, journeySeal(), "journey.spec", function(verbs, observations, declare)
		Ladder.journeySpec(verbs, observations, options, declare)
	end, "scenario_passed", nil)
end

test.suite("tier ladder journey declaration", function(suite)
	suite:case("declares every unbound case without registering a verdict", function(assert)
		local declared: { string } = {}
		local ran = 0
		Ladder.journeySpec(
			{
				describe = function(_name: string, register: () -> ())
					register()
				end,
				it = function()
					ran += 1
				end,
				itSkip = function() end,
				beforeEach = function() end,
				afterEach = function() end,
				expect = function(): any
					return error "unreachable"
				end,
				skip = function(): never
					return error "unreachable"
				end,
			} :: any,
			nil,
			journeyOptions(),
			function(name: string)
				table.insert(declared, name)
			end
		)
		assert.eq(ran, 0)
		assert.eq(#declared, 9)
		assert.strContains(declared[9], "scenario predicate")
	end)
end)

test.suite("tier ladder journey judgement", function(suite)
	suite:case("clears a run whose records bind and whose predicates are all green", function(assert)
		local verdict = journeyVerdict(journeyObservations(), journeyOptions())
		assert.eq(verdict.status, "COMPLETE")
		assert.eq(verdict.reason, "scenario_passed")
		assert.eq((verdict.report :: any).failed, 0)
		assert.eq((verdict.report :: any).results[1].path[1], Ladder.DEFAULT_TITLE)
	end)

	suite:case("names the suite with the caller's own title", function(assert)
		local verdict = journeyVerdict(journeyObservations(), journeyOptions { title = "tier three: the journey" })
		assert.eq(verdict.status, "COMPLETE")
		assert.eq((verdict.report :: any).results[1].path[1], "tier three: the journey")
	end)

	suite:case("holds a run that never bound a transcript", function(assert)
		local verdict = journeyVerdict(journeyObservations { logBound = false }, journeyOptions())
		assert.eq(verdict.status, "HOLD")
	end)

	suite:case("holds a run whose summary does not bind this run", function(assert)
		local verdict = journeyVerdict(
			journeyObservations(),
			journeyOptions {
				bind = function(_seen: { [string]: any }, contract: string, _runId: string)
					return { contract = contract, runId = "other" }, nil
				end,
			}
		)
		assert.eq(verdict.status, "HOLD")
		assert.eq(verdict.reason, "record_mismatch")
	end)

	suite:case("holds a run whose rows are not the expected predicates", function(assert)
		local verdict =
			journeyVerdict(journeyObservations { expectedPredicateNames = { "one", "three" } }, journeyOptions())
		assert.eq(verdict.status, "HOLD")
		assert.eq(verdict.reason, "scenario_failed")
	end)

	suite:case("holds a run that declared no expected pass count", function(assert)
		local verdict = journeyVerdict(journeyObservations { expectedPassed = 0 }, journeyOptions())
		assert.eq(verdict.status, "HOLD")
		assert.eq(verdict.reason, "record_mismatch")
	end)

	suite:case("holds a run whose console carried a refusal line", function(assert)
		local verdict =
			journeyVerdict(journeyObservations { consoleRefusalLines = { "not authorized" } }, journeyOptions())
		assert.eq(verdict.status, "HOLD")
		assert.eq(verdict.reason, "scenario_failed")
	end)

	suite:case("holds a run whose transcript never reassembled", function(assert)
		local verdict = journeyVerdict(journeyObservations { wireDefect = "truncated" }, journeyOptions())
		assert.eq(verdict.status, "HOLD")
		assert.eq(verdict.reason, "receipt_truncated")
	end)

	suite:case("holds a run whose named predicate failed", function(assert)
		local verdict = journeyVerdict(
			journeyObservations { rows = { { n = "one", ok = true }, { n = "two", ok = false, detail = "no gate" } } },
			journeyOptions()
		)
		assert.eq(verdict.status, "HOLD")
		assert.eq(verdict.reason, "scenario_failed")
	end)

	suite:case("holds a run that reported no predicate row at all", function(assert)
		local verdict = journeyVerdict(
			journeyObservations { rows = {}, failedRows = { "one" }, summaryFailed = 1 },
			journeyOptions()
		)
		assert.eq(verdict.status, "HOLD")
		assert.eq(verdict.reason, "scenario_failed")
	end)

	suite:case("holds a run whose acceptance pair arrived out of order", function(assert)
		local verdict = journeyVerdict(
			journeyObservations {
				requireAcceptance = true,
				summaryRecords = { { ordinal = 1, payload = "summary" } },
				acceptanceStartRecords = { { ordinal = 2, payload = "armed" } },
				acceptanceFinishRecords = { { ordinal = 3, payload = "armed" } },
			},
			journeyOptions()
		)
		assert.eq(verdict.status, "HOLD")
		assert.eq(verdict.reason, "acceptance_order")
	end)

	suite:case("holds a run whose acceptance validator rejected the pair", function(assert)
		local verdict = journeyVerdict(
			journeyObservations {
				requireAcceptance = true,
				summaryRecords = { { ordinal = 3, payload = "summary" } },
				acceptanceStartRecords = { { ordinal = 1, payload = "armed" } },
				acceptanceFinishRecords = { { ordinal = 2, payload = "armed" } },
			},
			journeyOptions {
				acceptance = function(_start: any, _finish: any, _summary: any): (any?, string?)
					return nil, "finish.nodes"
				end,
			}
		)
		assert.eq(verdict.status, "HOLD")
		assert.eq(verdict.reason, "acceptance_incomplete")
	end)

	suite:case("clears a run whose acceptance pair arrived in order and was accepted", function(assert)
		local verdict = journeyVerdict(
			journeyObservations {
				requireAcceptance = true,
				summaryRecords = { { ordinal = 3, payload = "summary" } },
				acceptanceStartRecords = { { ordinal = 1, payload = "armed" } },
				acceptanceFinishRecords = { { ordinal = 2, payload = "armed" } },
			},
			journeyOptions()
		)
		assert.eq(verdict.status, "COMPLETE")
	end)

	suite:case("holds a run whose configuration never bound", function(assert)
		local verdict = journeyVerdict(journeyObservations { configurationFault = "unknown_channel" }, journeyOptions())
		assert.eq(verdict.status, "HOLD")
		assert.eq(verdict.reason, "unknown_channel")
	end)
end)
