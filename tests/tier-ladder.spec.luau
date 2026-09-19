--!strict

local Verify = require "../src/core"

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

return function(suite: Verify.Harness)
	suite:suite("tier ladder classification", function()
		suite:case("names an unreached capability as the caller's own limitation", function(check)
			local status, reason, limitation = Ladder.classify("HOLD", "boot_refused", {
				bootRoute = "none",
				errorLineCount = 0,
				failures = { "no entry to require" },
			}, UNSUPPORTED)
			check:expect(status):toEqual "UNSUPPORTED"
			check:expect(reason):toEqual "ladder_unsupported"
			check:expect(limitation):toEqual "no entry to require"
		end)

		suite:case("falls back to the caller's own words when the probe named nothing", function(check)
			local _status, _reason, limitation = Ladder.classify(
				"HOLD",
				"boot_refused",
				{ bootRoute = "none", errorLineCount = 0, failures = {} },
				UNSUPPORTED
			)
			check:expect(limitation):toEqual(UNSUPPORTED.fallback)
		end)

		suite:case("keeps a hold red when the run logged an error line", function(check)
			local status, reason, limitation = Ladder.classify("HOLD", "boot_refused", {
				bootRoute = "none",
				errorLineCount = 1,
				failures = { "no entry to require" },
			}, UNSUPPORTED)
			check:expect(status):toEqual "HOLD"
			check:expect(reason):toEqual "boot_refused"
			check:expect(limitation):toEqual(nil)
		end)

		suite:case("keeps a hold red when the capability was reached", function(check)
			local status, _reason, limitation = Ladder.classify("HOLD", "boot_refused", {
				bootRoute = "entry",
				errorLineCount = 0,
				failures = { "the entry refused" },
			}, UNSUPPORTED)
			check:expect(status):toEqual "HOLD"
			check:expect(limitation):toEqual(nil)
		end)

		suite:case("keeps a hold red when its reason is not the rule's own", function(check)
			local status, reason = Ladder.classify("HOLD", "content_refused", {
				bootRoute = "none",
				errorLineCount = 0,
				failures = {},
			}, UNSUPPORTED)
			check:expect(status):toEqual "HOLD"
			check:expect(reason):toEqual "content_refused"
		end)

		suite:case("passes a clear verdict through untouched", function(check)
			local status, reason, limitation =
				Ladder.classify("COMPLETE", "ladder_passed", { bootRoute = "none", errorLineCount = 0 }, UNSUPPORTED)
			check:expect(status):toEqual "COMPLETE"
			check:expect(reason):toEqual "ladder_passed"
			check:expect(limitation):toEqual(nil)
		end)

		suite:case("passes every verdict through when the caller declared no rule", function(check)
			local status, reason =
				Ladder.classify("HOLD", "boot_refused", { bootRoute = "none", errorLineCount = 0 }, nil)
			check:expect(status):toEqual "HOLD"
			check:expect(reason):toEqual "boot_refused"
		end)
	end)

	suite:suite("tier ladder judgement", function()
		suite:case("clears a run whose only case passed", function(check)
			local verdict = Ladder.judge({ booted = true }, seal(), "ladder.spec", spec, "ladder_passed", UNSUPPORTED)
			check:expect(verdict.status):toEqual "COMPLETE"
			check:expect(verdict.reason):toEqual "ladder_passed"
			check:expect(verdict.limitation):toEqual(nil)
			check:expect((verdict.report :: any).passed):toEqual(1)
		end)

		suite:case("holds a run whose case failed and reports the step that named it", function(check)
			local verdict = Ladder.judge(
				{ booted = false, bootRoute = "entry", errorLineCount = 0 },
				seal(),
				"ladder.spec",
				spec,
				"ladder_passed",
				UNSUPPORTED
			)
			check:expect(verdict.status):toEqual "HOLD"
			check:expect(verdict.reason):toEqual "boot_refused"
			check:expect((verdict.report :: any).failed):toEqual(1)
		end)

		suite:case("softens a hold the rule recognises into an unsupported limitation", function(check)
			local verdict = Ladder.judge(
				{ booted = false, bootRoute = "none", errorLineCount = 0, failures = { "no entry to require" } },
				seal(),
				"ladder.spec",
				spec,
				"ladder_passed",
				UNSUPPORTED
			)
			check:expect(verdict.status):toEqual "UNSUPPORTED"
			check:expect(verdict.reason):toEqual "ladder_unsupported"
			check:expect(verdict.limitation):toEqual "no entry to require"
		end)
	end)

	suite:suite("tier ladder receipts", function()
		suite:case("carries the caller's binding beside the verdict it banks", function(check)
			local row = Ladder.receipt {
				contract = "adopter.ladder-run.v1",
				verdict = { status = "COMPLETE", reason = "ladder_passed", limitation = nil, report = nil },
				binding = { target = "one", placeId = "7" },
				observations = { booted = true },
			}
			check:expect(row.contract):toEqual "adopter.ladder-run.v1"
			check:expect(row.status):toEqual "COMPLETE"
			check:expect(row.target):toEqual "one"
			check:expect(row.placeId):toEqual "7"
			check:expect((row.observations :: any).booted):toEqual(true)
			check:expect(row.report):toEqual(nil)
		end)

		suite:case("never lets a binding restate the judgment", function(check)
			local row = Ladder.receipt {
				contract = "adopter.ladder-run.v1",
				verdict = { status = "HOLD", reason = "boot_refused", limitation = nil, report = nil },
				binding = { status = "COMPLETE", reason = "ladder_passed" },
			}
			check:expect(row.status):toEqual "HOLD"
			check:expect(row.reason):toEqual "boot_refused"
			check:expect(row.observations):toEqual(nil)
		end)
	end)

	suite:suite("tier ladder session observations", function()
		suite:case("folds session and log error lines into one count", function(check)
			local observations = Ladder.sessionObservations({
				{ contract = SESSION_CONTRACT, errorLines = { "probe line" } },
			}, { contract = SESSION_CONTRACT, errorLines = { "log line" } })
			check:expect((observations :: any).errorLineCount):toEqual(2)
			check:expect((observations :: any).observationContract):toEqual(SESSION_CONTRACT)
		end)

		suite:case("refuses a result carrying another contract", function(check)
			local observations, problem = Ladder.sessionObservations(
				{ { contract = "other.v1" } },
				{ contract = SESSION_CONTRACT }
			)
			check:expect(observations):toEqual(nil)
			check:expect(problem):toEqual "the execution session returned other.v1"
		end)

		suite:case("refuses an empty result list", function(check)
			local observations, problem = Ladder.sessionObservations({}, { contract = SESSION_CONTRACT })
			check:expect(observations):toEqual(nil)
			check:expect(problem):toEqual "the execution session returned no observation table"
		end)

		suite:case("decodes a result the session returned as text", function(check)
			local observations = Ladder.sessionObservations({ "encoded" }, {
				contract = SESSION_CONTRACT,
				decode = function(_payload: string): any
					return { contract = SESSION_CONTRACT, booted = true }
				end,
			})
			check:expect((observations :: any).booted):toEqual(true)
		end)

		suite:case("refuses text when the caller supplied no decoder", function(check)
			local observations, problem = Ladder.sessionObservations({ "encoded" }, { contract = SESSION_CONTRACT })
			check:expect(observations):toEqual(nil)
			check:expect(problem):toEqual "the execution session returned no observation table"
		end)

		suite:case("refuses text a decoder could not read", function(check)
			local observations = Ladder.sessionObservations({ "encoded" }, {
				contract = SESSION_CONTRACT,
				decode = function(_payload: string): any
					return error "unreadable"
				end,
			})
			check:expect(observations):toEqual(nil)
		end)
	end)

	suite:suite("tier ladder chunked client probe", function()
		local chunk: Roblox.ChunkedProbe = { deadlineSeconds = 90, chunkSeconds = 25, maxChunks = 4 }

		suite:case("plans one resumable probe call bounded by its own chunk count", function(check)
			local plan = Ladder.chunkedCallPlan {
				document = "/tmp/place.rbxl",
				probe = "return {}",
				contract = CLIENT_CONTRACT,
				chunk = chunk,
			}
			check:expect(#plan):toEqual(5)
			check:expect((plan[3] :: any).tool):toEqual "execute_luau"
			check:expect((plan[3] :: any).maxAttempts):toEqual(4)
			check:expect((plan[3] :: any).expect):toContain(CLIENT_CONTRACT)
			check:expect((plan[1] :: any).expect):toContain "/tmp/place.rbxl"
			check:expect((plan[5] :: any).input.is_start):toEqual(false)
		end)

		suite:case("counts each console line carrying a marker", function(check)
			check:expect((Ladder.countMarker("a\nMARK|one\nb\nMARK|two\n", "MARK|"))):toEqual(2)
			check:expect((Ladder.countMarker("a\nb\n", "MARK|"))):toEqual(0)
		end)

		suite:case("classifies the console and counts the markers the caller named", function(check)
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
			check:expect((observations :: any).hudPresent):toEqual(true)
			check:expect((observations :: any).errorLineCount):toEqual(1)
			check:expect((observations :: any).markerCount):toEqual(1)
			check:expect((observations :: any).consoleBytes):toEqual(#"ordinary line\nMARK|one\nstack begin")
		end)

		suite:case("refuses a probe still inside its own deadline", function(check)
			local observations, problem = Ladder.clientObservations(
				{ contract = CLIENT_CONTRACT, pending = true },
				"",
				{ contract = CLIENT_CONTRACT, chunk = chunk }
			)
			check:expect(observations):toEqual(nil)
			check:expect(problem :: string):toContain "90 second deadline"
		end)

		suite:case("refuses a table under another contract", function(check)
			local observations, problem = Ladder.clientObservations(
				{ contract = "other.v1" },
				"",
				{ contract = CLIENT_CONTRACT, chunk = chunk }
			)
			check:expect(observations):toEqual(nil)
			check:expect(problem):toEqual "the bridge returned other.v1"
		end)

		suite:case("refuses a bridge answer that is not a table", function(check)
			local observations, problem =
				Ladder.clientObservations("nothing", "", { contract = CLIENT_CONTRACT, chunk = chunk })
			check:expect(observations):toEqual(nil)
			check:expect(problem):toEqual "the bridge returned no observation table"
		end)
	end)

	suite:suite("tier ladder value predicates", function()
		suite:case("accepts only a dense list of the exact length", function(check)
			check:expect((Ladder.denseRows({ 1, 2, 3 }, 3))):toEqual(true)
			check:expect((Ladder.denseRows({ 1, 2 }, 3))):toEqual(false)
			check:expect((Ladder.denseRows({ 1, 2, 3, extra = true }, 3))):toEqual(false)
			check:expect((Ladder.denseRows(setmetatable({ 1 }, {}), 1))):toEqual(false)
			check:expect((Ladder.denseRows("rows", 1))):toEqual(false)
		end)

		suite:case("accepts only a finite number", function(check)
			check:expect((Ladder.finite(1.5))):toEqual(true)
			check:expect((Ladder.finite(math.huge))):toEqual(false)
			check:expect((Ladder.finite(math.nan))):toEqual(false)
			check:expect((Ladder.finiteNonnegative(-1))):toEqual(false)
			check:expect((Ladder.nonnegativeInteger(1.5))):toEqual(false)
			check:expect((Ladder.nonnegativeInteger(2))):toEqual(true)
		end)

		suite:case("refuses a table holding an infinity at any depth", function(check)
			check:expect(Ladder.deeplyFinite { a = { b = { 1, 2 } } }):toEqual(true)
			check:expect(Ladder.deeplyFinite { a = { b = { math.huge } } }):toEqual(false)
		end)

		suite:case("accepts only an identifier safe to name a path", function(check)
			check:expect(Ladder.safeId "run-1.a"):toEqual(true)
			check:expect(Ladder.safeId "-run"):toEqual(false)
			check:expect(Ladder.safeId "run/1"):toEqual(false)
			check:expect(Ladder.safeId ""):toEqual(false)
			check:expect((Ladder.safeId(string.rep("a", 65)))):toEqual(false)
			check:expect((Ladder.safeId(7))):toEqual(false)
		end)

		suite:case("decodes one record and refuses everything else", function(check)
			local decoder = function(payload: string): any
				if payload == "object" then
					return { runId = "one" }
				end
				if payload == "scalar" then
					return 7
				end
				return error "unreadable"
			end
			check:expect((Ladder.decodeObject("object", decoder) :: any).runId):toEqual "one"
			check:expect((Ladder.decodeObject("scalar", decoder))):toEqual(nil)
			check:expect((Ladder.decodeObject("broken", decoder))):toEqual(nil)
			check:expect((Ladder.decodeObject(nil, decoder))):toEqual(nil)
		end)

		suite:case("reads a row's name from either spelling", function(check)
			check:expect(Ladder.rowName { name = "first" }):toEqual "first"
			check:expect(Ladder.rowName { n = "second" }):toEqual "second"
			check:expect(Ladder.rowName { n = "" }):toEqual(nil)
			check:expect(Ladder.rowName "row"):toEqual(nil)
		end)
	end)

	suite:suite("tier ladder frame sampling", function()
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

		suite:case("accepts a summary whose percentiles are ordered and whose ratio is the quotient", function(check)
			check:expect((Ladder.frameSummary(summary()))):toEqual(true)
			check:expect((Ladder.frameSummary(summary { p95Ms = 5 }))):toEqual(false)
			check:expect((Ladder.frameSummary(summary { over50MsRatio = 0.5 }))):toEqual(false)
			check:expect((Ladder.frameSummary(summary { over50MsCount = 9 }))):toEqual(false)
		end)

		suite:case("accepts a report only with a nested render report at the outer level", function(check)
			check:expect((Ladder.frameReport(report(true), true))):toEqual(true)
			check:expect((Ladder.frameReport(report(false), true))):toEqual(false)
			check:expect((Ladder.frameReport(report(true), false))):toEqual(false)
		end)

		suite:case("refuses a report whose long frames overflow their own cap", function(check)
			local row = report(true)
			row.longFrameCap = 0
			check:expect((Ladder.frameReport(row, true))):toEqual(false)
		end)

		suite:case("accepts a sampling record whose health agrees with report and budget", function(check)
			check:expect((Ladder.frameSamplingComplete(sampling()))):toEqual(true)
		end)

		suite:case("refuses a sampling record whose health disagrees with its budget", function(check)
			local row = sampling()
			local drifted = health()
			drifted.p95Ms = 21
			row.renderFrameHealth = drifted
			check:expect((Ladder.frameSamplingComplete(row))):toEqual(false)
		end)

		suite:case("refuses a sampling record carrying an infinity", function(check)
			local row = sampling()
			local budget = row.clientFrameBudget :: any
			budget.p95LimitMs = math.huge
			check:expect((Ladder.frameSamplingComplete(row))):toEqual(false)
		end)

		suite:case("refuses a sampling record whose budget names another signal", function(check)
			local row = sampling()
			local budget = row.clientFrameBudget :: any
			budget.signal = "other"
			check:expect((Ladder.frameSamplingComplete(row))):toEqual(false)
		end)
	end)

	suite:suite("tier ladder record binding", function()
		suite:case("matches exact fields by value and coerced fields by text", function(check)
			local record = { contract = ARMED_CONTRACT, placeId = 7, placeVersion = "12" }
			check
				:expect(
					(Ladder.boundRecord(record, { contract = ARMED_CONTRACT }, { placeId = "7", placeVersion = 12 }))
				)
				:toEqual(true)
			check:expect((Ladder.boundRecord(record, { contract = SUMMARY_CONTRACT }, nil))):toEqual(false)
			check:expect((Ladder.boundRecord(record, {}, { placeId = "8" }))):toEqual(false)
			check:expect((Ladder.boundRecord("record", {}, nil))):toEqual(false)
		end)

		suite:case("accepts exactly the expected predicates, each named once and green", function(check)
			local rows = { { n = "one", ok = true }, { n = "two", ok = true } }
			check:expect((Ladder.exactGreenRows(rows, 2, { "one", "two" }))):toEqual(true)
			check:expect((Ladder.exactGreenRows(rows, 2, { "one", "three" }))):toEqual(false)
			check:expect((Ladder.exactGreenRows(rows, 2, { "one" }))):toEqual(false)
			check:expect((Ladder.exactGreenRows(rows, 3, { "one", "two", "three" }))):toEqual(false)
			check:expect((Ladder.exactGreenRows(rows, 2, nil))):toEqual(true)
		end)

		suite:case("refuses rows that repeat one name or report a failure", function(check)
			check
				:expect((Ladder.exactGreenRows({ { n = "one", ok = true }, { n = "one", ok = true } }, 2, nil)))
				:toEqual(false)
			check
				:expect((Ladder.exactGreenRows({ { n = "one", ok = true }, { n = "two", ok = false } }, 2, nil)))
				:toEqual(false)
			check:expect((Ladder.exactGreenRows({ { n = "", ok = true } }, 1, nil))):toEqual(false)
		end)

		suite:case("refuses an expected name list that repeats or is empty", function(check)
			check
				:expect(
					(Ladder.exactGreenRows({ { n = "one", ok = true }, { n = "two", ok = true } }, 2, { "one", "one" }))
				)
				:toEqual(false)
			check:expect((Ladder.exactGreenRows({ { n = "one", ok = true } }, 1, { "" }))):toEqual(false)
		end)
	end)

	suite:suite("tier ladder transcript salvage", function()
		suite:case("names the failed rows a truncated transcript still spells", function(check)
			local names = Ladder.failedRowNames '{"ok":false,"name":"first","detail":"x"} {"ok":false,"n":"second"}'
			check:expect(#names):toEqual(2)
			check:expect(names[1]):toEqual "first"
			check:expect(names[2]):toEqual "second"
		end)

		suite:case("names each failed row once", function(check)
			local names = Ladder.failedRowNames '{"ok":false,"n":"first"}{"ok":false,"n":"first"}'
			check:expect(#names):toEqual(1)
		end)

		suite:case("collects the distinct console lines that read as a refusal", function(check)
			local lines = Ladder.refusalLines(table.concat({
				"ordinary boot line",
				"Foo:12: attempt to index nil with 'Bar'",
				"RequestX refused: not authorized for this actor",
				"ordinary boot line",
				"Foo:12: attempt to index nil with 'Bar'",
			}, "\n"))
			check:expect(#lines):toEqual(2)
			check:expect(lines[1]):toContain "attempt to index"
			check:expect(lines[2]):toContain "not authorized"
		end)

		suite:case("collects nothing from a clean transcript", function(check)
			check:expect(#Ladder.refusalLines "ordinary boot line\nall clear\n"):toEqual(0)
		end)

		suite:case("caps a flooded transcript and honours the caller's own vocabulary", function(check)
			local flood: { string } = {}
			for index = 1, 40 do
				table.insert(flood, ("refused %d"):format(index))
			end
			check:expect((#Ladder.refusalLines(table.concat(flood, "\n")))):toEqual(Ladder.DEFAULT_REFUSAL_LIMIT)
			check:expect((#Ladder.refusalLines("blocked here\nrefused there", { "blocked" }, 5))):toEqual(1)
		end)

		suite:case("reports one predicate row per name, in order and never twice", function(check)
			local rows = Ladder.predicateRows({
				{ name = "first", ok = true },
				{ n = "second", ok = false },
				{ name = "first", ok = false },
				{ ok = false },
			}, "no detail")
			check:expect(#rows):toEqual(2)
			check:expect(rows[1].name):toEqual "first"
			check:expect(rows[1].ok):toEqual(true)
			check:expect(rows[2].ok):toEqual(false)
			check:expect(rows[2].detail):toEqual "no detail"
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

	suite:suite("tier ladder journey declaration", function()
		suite:case("declares every unbound case without registering a verdict", function(check)
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
			check:expect(ran):toEqual(0)
			check:expect(#declared):toEqual(10)
			check:expect(declared[10]):toContain "scenario predicate"
		end)
	end)

	suite:suite("tier ladder journey judgement", function()
		suite:case("clears a run whose records bind and whose predicates are all green", function(check)
			local verdict = journeyVerdict(journeyObservations(), journeyOptions())
			check:expect(verdict.status):toEqual "COMPLETE"
			check:expect(verdict.reason):toEqual "scenario_passed"
			check:expect((verdict.report :: any).failed):toEqual(0)
			check:expect((verdict.report :: any).results[1].path[1]):toEqual(Ladder.DEFAULT_TITLE)
		end)

		suite:case("names the suite with the caller's own title", function(check)
			local verdict = journeyVerdict(journeyObservations(), journeyOptions { title = "tier three: the journey" })
			check:expect(verdict.status):toEqual "COMPLETE"
			check:expect((verdict.report :: any).results[1].path[1]):toEqual "tier three: the journey"
		end)

		suite:case("holds a run that never bound a transcript", function(check)
			local verdict = journeyVerdict(journeyObservations { logBound = false }, journeyOptions())
			check:expect(verdict.status):toEqual "HOLD"
		end)

		suite:case("holds a run whose summary does not bind this run", function(check)
			local verdict = journeyVerdict(
				journeyObservations(),
				journeyOptions {
					bind = function(_seen: { [string]: any }, contract: string, _runId: string)
						return { contract = contract, runId = "other" }, nil
					end,
				}
			)
			check:expect(verdict.status):toEqual "HOLD"
			check:expect(verdict.reason):toEqual "record_mismatch"
		end)

		suite:case("holds a run whose rows are not the expected predicates", function(check)
			local verdict =
				journeyVerdict(journeyObservations { expectedPredicateNames = { "one", "three" } }, journeyOptions())
			check:expect(verdict.status):toEqual "HOLD"
			check:expect(verdict.reason):toEqual "scenario_failed"
		end)

		suite:case("holds a run that declared no expected pass count", function(check)
			local verdict = journeyVerdict(journeyObservations { expectedPassed = 0 }, journeyOptions())
			check:expect(verdict.status):toEqual "HOLD"
			check:expect(verdict.reason):toEqual "record_mismatch"
		end)

		suite:case("holds a run whose console carried a refusal line", function(check)
			local verdict =
				journeyVerdict(journeyObservations { consoleRefusalLines = { "not authorized" } }, journeyOptions())
			check:expect(verdict.status):toEqual "HOLD"
			check:expect(verdict.reason):toEqual "scenario_failed"
		end)

		suite:case("holds a run whose transcript never reassembled", function(check)
			local verdict = journeyVerdict(journeyObservations { wireDefect = "truncated" }, journeyOptions())
			check:expect(verdict.status):toEqual "HOLD"
			check:expect(verdict.reason):toEqual "receipt_truncated"
		end)

		suite:case("holds a run whose named predicate failed", function(check)
			local verdict = journeyVerdict(
				journeyObservations { rows = { { n = "one", ok = true }, { n = "two", ok = false, detail = "no gate" } } },
				journeyOptions()
			)
			check:expect(verdict.status):toEqual "HOLD"
			check:expect(verdict.reason):toEqual "scenario_failed"
		end)

		suite:case("holds a run that reported no predicate row at all", function(check)
			local verdict = journeyVerdict(
				journeyObservations { rows = {}, failedRows = { "one" }, summaryFailed = 1 },
				journeyOptions()
			)
			check:expect(verdict.status):toEqual "HOLD"
			check:expect(verdict.reason):toEqual "scenario_failed"
		end)

		suite:case("holds a run whose acceptance pair arrived out of order", function(check)
			local verdict = journeyVerdict(
				journeyObservations {
					requireAcceptance = true,
					summaryRecords = { { ordinal = 1, payload = "summary" } },
					acceptanceStartRecords = { { ordinal = 2, payload = "armed" } },
					acceptanceFinishRecords = { { ordinal = 3, payload = "armed" } },
				},
				journeyOptions()
			)
			check:expect(verdict.status):toEqual "HOLD"
			check:expect(verdict.reason):toEqual "acceptance_order"
		end)

		suite:case("holds a run whose acceptance validator rejected the pair", function(check)
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
			check:expect(verdict.status):toEqual "HOLD"
			check:expect(verdict.reason):toEqual "acceptance_incomplete"
		end)

		suite:case("clears a run whose acceptance pair arrived in order and was accepted", function(check)
			local verdict = journeyVerdict(
				journeyObservations {
					requireAcceptance = true,
					summaryRecords = { { ordinal = 3, payload = "summary" } },
					acceptanceStartRecords = { { ordinal = 1, payload = "armed" } },
					acceptanceFinishRecords = { { ordinal = 2, payload = "armed" } },
				},
				journeyOptions()
			)
			check:expect(verdict.status):toEqual "COMPLETE"
		end)

		suite:case("holds a run whose configuration never bound", function(check)
			local verdict =
				journeyVerdict(journeyObservations { configurationFault = "unknown_channel" }, journeyOptions())
			check:expect(verdict.status):toEqual "HOLD"
			check:expect(verdict.reason):toEqual "unknown_channel"
		end)
	end)
end
