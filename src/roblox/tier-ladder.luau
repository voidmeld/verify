--!strict

local Bdd = require "../bdd"
local Verify = require "../core"
local Shape = require "../core/shape"
local finite = Shape.finite
local finiteNonnegative = Shape.finiteNonnegative
local nonnegativeInteger = Shape.nonnegativeInteger
local denseRows = Shape.denseRows
local deeplyFinite = Shape.deeplyFinite
local safeId = Shape.safeId

export type Report = Verify.Report
export type Bundle = Verify.Bundle
export type ClassifyOptions = Verify.ClassifyConsoleOptions

export type Artifact = { name: string, reference: string, mediaType: string? }

export type Verbs = {
	describe: (name: string, register: () -> ()) -> (),
	it: (name: string, body: any) -> (),
	itSkip: (name: string, reason: string, body: any?) -> (),
	beforeEach: (body: any) -> (),
	afterEach: (body: any) -> (),
	expect: (value: any, ...any) -> any,
	skip: (reason: string) -> never,
}

export type Spec = (verbs: Verbs, observations: { [string]: any }?, declare: ((string) -> ())?) -> ()

export type Seal = {
	executor: string,
	environment: { [string]: any },
	capabilities: { string },
	actors: { string }?,
	artifacts: { Artifact }?,
}

export type UnsupportedRule = {
	status: string,
	reason: string,
	fromReason: string,
	whenText: { key: string, value: string }?,
	whenZero: string?,
	namedBy: string?,
	fallback: string,
}

export type Verdict = {
	status: string,
	reason: string,
	limitation: string?,
	report: Report?,
}

export type ReceiptOptions = {
	contract: string,
	verdict: Verdict,
	binding: { [string]: any }?,
	observations: { [string]: any }?,
}

local COMPLETE = "COMPLETE"
local HOLD = "HOLD"

local function numberAt(observations: { [string]: any }, key: string): number
	local value = observations[key]
	return if type(value) == "number" then value else -1
end

local function textAt(observations: { [string]: any }, key: string): string
	local value = observations[key]
	return if type(value) == "string" then value else ""
end

local function listAt(observations: { [string]: any }, key: string): { any }
	local value = observations[key]
	return if type(value) == "table" then value else {}
end

local function classify(
	status: string,
	reason: string,
	observations: { [string]: any },
	rule: UnsupportedRule?
): (string, string, string?)
	if rule == nil or status ~= HOLD or reason ~= (rule :: UnsupportedRule).fromReason then
		return status, reason, nil
	end
	local named = rule :: UnsupportedRule
	if named.whenText ~= nil and textAt(observations, named.whenText.key) ~= named.whenText.value then
		return status, reason, nil
	end
	if named.whenZero ~= nil and numberAt(observations, named.whenZero :: string) ~= 0 then
		return status, reason, nil
	end
	local limitation = named.fallback
	if named.namedBy ~= nil then
		local failures = listAt(observations, named.namedBy :: string)
		if type(failures[1]) == "string" and failures[1] ~= "" then
			limitation = failures[1] :: string
		end
	end
	return named.status, named.reason, limitation
end

local function judge(
	observations: { [string]: any },
	seal: Seal,
	source: string,
	spec: Spec,
	passReason: string,
	rule: UnsupportedRule?
): Verdict
	local bundle = Verify.sealObservations {
		executor = seal.executor,
		environment = seal.environment,
		capabilities = seal.capabilities,
		actors = seal.actors,
		artifacts = seal.artifacts,
		timeline = {},
		observations = observations,
	}
	local report = Verify.evaluateObservations(
		bundle,
		source,
		function(harness: Verify.Harness, seen: { [string]: any })
			local verbs = Bdd.create(harness) :: any
			verbs.expect = Verify.expect
			spec(verbs :: Verbs, seen)
		end,
		os.clock
	)
	local decided = Verify.observationVerdict(report, passReason)
	local status = if decided.status == "clear" then COMPLETE else HOLD
	local finalStatus, finalReason, limitation = classify(status, decided.reason, observations, rule)
	return { status = finalStatus, reason = finalReason, limitation = limitation, report = report }
end

local function receipt(options: ReceiptOptions): { [string]: any }
	local row: { [string]: any } = {}
	for key, value in (if options.binding ~= nil then options.binding else {}) :: { [string]: any } do
		row[key] = value
	end
	row.contract = options.contract
	row.status = options.verdict.status
	row.reason = options.verdict.reason
	row.limitation = options.verdict.limitation
	if options.observations ~= nil then
		row.observations = options.observations
	end
	if options.verdict.report ~= nil then
		row.report = options.verdict.report
	end
	return row
end

export type Decoder = (payload: string) -> any

export type SessionObservationOptions = {
	contract: string,
	errorLines: { string }?,
	decode: Decoder?,
}

local function sessionObservations(results: { any }?, options: SessionObservationOptions): ({ [string]: any }?, string?)
	local first = if type(results) == "table" then (results :: { any })[1] else nil
	if type(first) == "string" and options.decode ~= nil then
		local decoded, value = pcall(options.decode :: Decoder, first :: string)
		first = if decoded then value else nil
	end
	if type(first) ~= "table" then
		return nil, "the execution session returned no observation table"
	end
	local observed = first :: any
	if observed.contract ~= options.contract then
		return nil, "the execution session returned " .. tostring(observed.contract)
	end
	local merged: { [string]: any } = {}
	for key, value in observed do
		merged[key] = value
	end
	merged.observationContract = observed.contract
	local red: { any } = if type(observed.errorLines) == "table" then observed.errorLines else {}
	for _, line in (if options.errorLines ~= nil then options.errorLines else {}) :: { string } do
		table.insert(red, line)
	end
	merged.errorLines = red
	merged.errorLineCount = #red
	return merged, nil
end

export type ChunkedProbe = {
	deadlineSeconds: number,
	chunkSeconds: number,
	maxChunks: number,
}

export type Marker = { field: string, marker: string }

export type CallPlanOptions = {
	document: string,
	probe: string,
	contract: string,
	chunk: ChunkedProbe,
}

local function chunkedCallPlan(options: CallPlanOptions): { any }
	local chunk = options.chunk
	return {
		{
			tool = "list_roblox_studios",
			input = {},
			expect = ("one instance whose name carries %s; that instance's id is <studio_id> below"):format(
				options.document
			),
		},
		{
			tool = "start_stop_play",
			input = { studio_id = "<studio_id>", is_start = true },
			expect = "the instance enters Play and a Client datamodel appears",
		},
		{
			tool = "execute_luau",
			input = { studio_id = "<studio_id>", datamodel_type = "Client", code = options.probe },
			repeatUntil = "the returned table carries pending=false",
			maxAttempts = chunk.maxChunks,
			expect = ("a table under contract %s; the probe waits at most %d seconds per call and answers pending=true while its %d second deadline still has room, so repeat this exact call, at most %d times in all, until pending is false"):format(
				options.contract,
				chunk.chunkSeconds,
				chunk.deadlineSeconds,
				chunk.maxChunks
			),
		},
		{
			tool = "get_console_output",
			input = { studio_id = "<studio_id>" },
			expect = "the whole Play console, banked verbatim as `console`",
		},
		{
			tool = "start_stop_play",
			input = { studio_id = "<studio_id>", is_start = false },
			expect = "the instance leaves Play",
		},
	}
end

local function countMarker(console: string, marker: string): number
	local seen = 0
	for line in string.gmatch(console, "[^\n]+") do
		if string.find(line, marker, 1, true) ~= nil then
			seen += 1
		end
	end
	return seen
end

export type ClientObservationOptions = {
	contract: string,
	chunk: ChunkedProbe,
	classify: ClassifyOptions?,
	markers: { Marker }?,
}

local function clientObservations(
	banked: any,
	console: string,
	options: ClientObservationOptions
): ({ [string]: any }?, string?)
	if type(banked) ~= "table" then
		return nil, "the bridge returned no observation table"
	end
	local observed = banked :: any
	if observed.contract ~= options.contract then
		return nil, "the bridge returned " .. tostring(observed.contract)
	end
	if observed.pending == true then
		return nil,
			("the probe is still inside its %d second deadline; run the same execute_luau call again"):format(
				options.chunk.deadlineSeconds
			)
	end
	local merged: { [string]: any } = {}
	for key, value in observed do
		merged[key] = value
	end
	local red = Verify.classifyConsoleText(console, options.classify)
	merged.errorLines = red
	merged.errorLineCount = #red
	merged.consoleBytes = #console
	for _, row in (if options.markers ~= nil then options.markers else {}) :: { Marker } do
		merged[row.field] = countMarker(console, row.marker)
	end
	return merged, nil
end

local function decodeObject(payload: string?, decode: Decoder): { [string]: any }?
	if payload == nil then
		return nil
	end
	local ok, decoded = pcall(decode, payload :: string)
	if not ok or type(decoded) ~= "table" then
		return nil
	end
	return decoded :: { [string]: any }
end

local function frameSummary(value: any): boolean
	return type(value) == "table"
		and nonnegativeInteger(value.sampleCount)
		and finiteNonnegative(value.elapsedSec)
		and finiteNonnegative(value.p50Ms)
		and finiteNonnegative(value.p95Ms)
		and finiteNonnegative(value.p99Ms)
		and finiteNonnegative(value.maxMs)
		and nonnegativeInteger(value.over50MsCount)
		and value.over50MsCount <= value.sampleCount
		and finiteNonnegative(value.over50MsRatio)
		and value.over50MsRatio <= 1
		and value.p50Ms <= value.p95Ms
		and value.p95Ms <= value.p99Ms
		and value.p99Ms <= value.maxMs
		and value.over50MsRatio == if value.sampleCount == 0 then 0 else value.over50MsCount / value.sampleCount
end

local FRAME_HEALTH_FIELDS = {
	"ok",
	"reason",
	"detail",
	"signal",
	"sampleCount",
	"p50Ms",
	"p95Ms",
	"p99Ms",
	"maxMs",
	"over50MsRatio",
}

local function frameHealth(value: any): boolean
	return type(value) == "table"
		and type(value.ok) == "boolean"
		and type(value.reason) == "string"
		and type(value.detail) == "string"
		and type(value.signal) == "string"
		and value.signal ~= ""
		and nonnegativeInteger(value.sampleCount)
		and finiteNonnegative(value.p50Ms)
		and finiteNonnegative(value.p95Ms)
		and finiteNonnegative(value.p99Ms)
		and finiteNonnegative(value.maxMs)
		and finiteNonnegative(value.over50MsRatio)
		and value.over50MsRatio <= 1
end

local function sameFrameHealth(left: any, right: any): boolean
	if not frameHealth(left) or not frameHealth(right) then
		return false
	end
	for _, key in FRAME_HEALTH_FIELDS do
		if left[key] ~= right[key] then
			return false
		end
	end
	return true
end

local function frameHealthMatchesSummary(health: any, summary: any): boolean
	return frameHealth(health)
		and frameSummary(summary)
		and health.signal == summary.signal
		and health.sampleCount == summary.sampleCount
		and health.p50Ms == summary.p50Ms
		and health.p95Ms == summary.p95Ms
		and health.p99Ms == summary.p99Ms
		and health.maxMs == summary.maxMs
		and health.over50MsRatio == summary.over50MsRatio
end

local function frameReport(value: any, requireRender: boolean): boolean
	if
		not frameSummary(value)
		or type(value.signal) ~= "string"
		or value.signal == ""
		or type(value.phases) ~= "table"
		or getmetatable(value.phases) ~= nil
		or type(value.longFrames) ~= "table"
		or not denseRows(value.longFrames, #(value.longFrames or {}))
		or not finiteNonnegative(value.longFrameThresholdMs)
		or not nonnegativeInteger(value.longFrameCap)
		or not nonnegativeInteger(value.longFrameDropped)
		or #value.longFrames > value.longFrameCap
	then
		return false
	end
	for name, phase in value.phases do
		if type(name) == "userdata" then
			continue
		end
		if type(name) ~= "string" or name == "" or not frameSummary(phase) then
			return false
		end
	end
	for index, frame in value.longFrames do
		if type(index) == "userdata" then
			continue
		end
		if
			type(frame) ~= "table"
			or type(frame.phase) ~= "string"
			or frame.phase == ""
			or not finiteNonnegative(frame.phaseElapsedSec)
			or not finiteNonnegative(frame.routeElapsedSec)
			or not finiteNonnegative(frame.dtMs)
		then
			return false
		end
	end
	if requireRender then
		return frameReport(value.render, false)
	end
	return value.render == nil
end

local function frameSamplingComplete(sampling: any): boolean
	if type(sampling) ~= "table" or not deeplyFinite(sampling) then
		return false
	end
	local timing = sampling.clientFrameTiming
	local budget = sampling.clientFrameBudget
	local health = sampling.renderFrameHealth
	return frameReport(timing, true)
		and type(budget) == "table"
		and type(budget.ok) == "boolean"
		and type(budget.detail) == "string"
		and type(budget.signal) == "string"
		and budget.signal == timing.signal
		and type(budget.environmentUnhealthy) == "boolean"
		and nonnegativeInteger(budget.minimumSamples)
		and finiteNonnegative(budget.p95LimitMs)
		and finiteNonnegative(budget.p99LimitMs)
		and finiteNonnegative(budget.maxLimitMs)
		and finiteNonnegative(budget.over50MsRatioLimit)
		and budget.over50MsRatioLimit <= 1
		and finiteNonnegative(budget.setupP50LimitMs)
		and nonnegativeInteger(budget.setupMinimumSamples)
		and sameFrameHealth(health, budget.renderFrameHealth)
		and frameHealthMatchesSummary(health, timing.render)
end

local function boundRecord(record: any, exact: { [string]: any }, coerced: { [string]: any }?): boolean
	if type(record) ~= "table" then
		return false
	end
	for field, expected in exact do
		if (record :: any)[field] ~= expected then
			return false
		end
	end
	for field, expected in (if coerced ~= nil then coerced else {}) :: { [string]: any } do
		if tostring((record :: any)[field]) ~= tostring(expected) then
			return false
		end
	end
	return true
end

local function exactGreenRows(summaryRows: any, count: number, expectedNames: { string }?): boolean
	if not denseRows(summaryRows, count) then
		return false
	end
	local seen: { [string]: boolean } = {}
	local expected: { [string]: boolean }? = nil
	if expectedNames ~= nil then
		if #(expectedNames :: { string }) ~= count then
			return false
		end
		local names: { [string]: boolean } = {}
		for _, name in expectedNames :: { string } do
			if name == "" or names[name] then
				return false
			end
			names[name] = true
		end
		expected = names
	end
	for index = 1, count do
		local row = summaryRows[index]
		if
			type(row) ~= "table"
			or type(row.n) ~= "string"
			or row.n == ""
			or row.ok ~= true
			or seen[row.n]
			or (expected ~= nil and (expected :: { [string]: boolean })[row.n] ~= true)
		then
			return false
		end
		seen[row.n] = true
	end
	return true
end

local DEFAULT_REFUSAL_PATTERNS = table.freeze {
	"attempt to index",
	"not authorized",
	"unauthorized",
	"refused",
	"refusal",
}

local DEFAULT_REFUSAL_LIMIT = 20

local function failedRowNames(bytes: string): { string }
	local names: { string } = {}
	local seen: { [string]: boolean } = {}
	local function collect(pattern: string)
		for name in string.gmatch(bytes, pattern) do
			if not seen[name] then
				seen[name] = true
				table.insert(names, name)
			end
		end
	end
	collect '{"ok":false,"name":"([^"]+)"[^{}]*}'
	collect '{"ok":false,"n":"([^"]+)"}'
	return names
end

local function refusalLines(bytes: string, patterns: { string }?, limit: number?): { string }
	local vocabulary: { string } = if patterns ~= nil then patterns else DEFAULT_REFUSAL_PATTERNS
	local cap = if limit ~= nil then limit else DEFAULT_REFUSAL_LIMIT
	local lines: { string } = {}
	local seen: { [string]: boolean } = {}
	for line in string.gmatch(string.gsub(bytes, "\r\n", "\n") .. "\n", "(.-)\n") do
		if #lines >= cap then
			break
		end
		local lower = string.lower(line)
		for _, pattern in vocabulary do
			if string.find(lower, pattern, 1, true) ~= nil then
				if not seen[line] then
					seen[line] = true
					table.insert(lines, line)
				end
				break
			end
		end
	end
	return lines
end

local function rowName(row: any): string?
	if type(row) ~= "table" then
		return nil
	end
	if type(row.name) == "string" and row.name ~= "" then
		return row.name
	end
	if type(row.n) == "string" and row.n ~= "" then
		return row.n
	end
	return nil
end

export type PredicateRow = { name: string, ok: boolean, detail: string }

local function predicateRows(rows: { any }, missingDetail: string): { PredicateRow }
	local resolved: { PredicateRow } = {}
	local seen: { [string]: boolean } = {}
	for _, row in rows do
		local name = rowName(row)
		if name == nil or seen[name :: string] then
			continue
		end
		seen[name :: string] = true
		local detail = if type((row :: any).detail) == "string" then (row :: any).detail else missingDetail
		table.insert(resolved, { name = name :: string, ok = (row :: any).ok == true, detail = detail })
	end
	return resolved
end

export type JourneyNames = {
	armedContract: string,
	summaryContract: string,
	configurationBound: string,
	publishCurrent: string,
	launched: string,
	logBound: string,
	recordMismatch: string,
	acceptanceOrder: string,
	acceptanceIncomplete: string,
	receiptMissing: string,
	receiptTruncated: string,
	failed: string,
	driverActor: string,
	hostActor: string,
	acceptanceActor: string,
	publishArtifact: string,
	baselineArtifact: string,
	logArtifact: string,
}

export type JourneyBinding = (
	seen: { [string]: any },
	contract: string,
	runId: string
) -> ({ [string]: any }, { [string]: any }?)

export type JourneyAcceptance = (start: any, finish: any, summary: any) -> (any?, string?)

export type JourneyOptions = {
	title: string?,
	names: JourneyNames,
	decode: Decoder,
	bind: JourneyBinding?,
	acceptance: JourneyAcceptance?,
	missingDetail: string?,
}

local DEFAULT_TITLE = "the scenario journey"
local DEFAULT_MISSING_DETAIL = "the scenario host reported this predicate as failed"

local function step(context: any, name: string, actor: string, run: () -> ())
	context:step(name, { actor = actor, run = run })
end

local function journeySpec(
	verbs: Verbs,
	observations: { [string]: any }?,
	options: JourneyOptions,
	declare: ((string) -> ())?
)
	local describe, it, expect = verbs.describe, verbs.it, verbs.expect
	local names = options.names
	local missingDetail = if options.missingDetail ~= nil then options.missingDetail else DEFAULT_MISSING_DETAIL
	local function record(payload: string?): { [string]: any }?
		return decodeObject(payload, options.decode)
	end

	describe(if options.title ~= nil then options.title else DEFAULT_TITLE, function()
		local function case(
			name: string,
			body: (any, { [string]: any }) -> (),
			applicable: (({ [string]: any }) -> boolean)?
		)
			if observations == nil then
				if declare ~= nil then
					declare(name)
				end
				return
			end
			if applicable ~= nil and not applicable(observations :: { [string]: any }) then
				return
			end
			it(name, function(_own: any, context: any)
				body(context, observations :: { [string]: any })
			end)
		end

		local function requireLog(seen: { [string]: any })
			expect(seen.logBound):toBeTrueWith "the executor did not bind a runtime log for this run"
		end

		case("reaches a bound runtime log against a current publish", function(context, seen)
			context:artifact(names.publishArtifact, tostring(seen.publishReceiptPath), "application/json")
			for _, path in listAt(seen, "baselineLogs") do
				context:artifact(names.baselineArtifact, tostring(path), "text/plain")
			end
			context:step(seen.configurationFault or names.configurationBound, function()
				expect(seen.configurationFault):toBeNil()
			end)
			context:step(seen.publishFault or names.publishCurrent, function()
				expect(seen.publishFault):toBeNil()
			end)
			step(context, seen.launchFault or names.launched, names.driverActor, function()
				expect(seen.launchFault):toBeNil()
			end)
			step(context, seen.selectionFault or names.logBound, names.driverActor, function()
				expect(seen.selectionFault):toBeNil()
			end)
			if seen.logBound == true then
				context:artifact(names.logArtifact, tostring(seen.logFile), "text/plain")
			end
		end)

		case("prints exactly one armed record and one results summary it can bind", function(context, seen)
			requireLog(seen)
			step(context, names.recordMismatch, names.hostActor, function()
				expect(#listAt(seen, "armedPayloads")):toBe(1)
				expect(#listAt(seen, "summaryPayloads")):toBe(1)
			end)
		end, function(seen)
			return seen.requireBoundRecords == true
		end)

		case("prints its acceptance pair before the summary that closes the run", function(context, seen)
			requireLog(seen)
			step(context, names.acceptanceOrder, names.hostActor, function()
				local summaries = listAt(seen, "summaryRecords")
				local starts = listAt(seen, "acceptanceStartRecords")
				local finishes = listAt(seen, "acceptanceFinishRecords")
				expect(#summaries):toBe(1)
				expect(#starts):toBe(1)
				expect(#finishes):toBe(1)
				expect(starts[1].ordinal):toBeLessThan(finishes[1].ordinal)
				expect(finishes[1].ordinal):toBeLessThan(summaries[1].ordinal)
			end)
		end, function(seen)
			return seen.requireAcceptance == true
		end)

		case("prints a results summary that decodes and names a safe run id", function(context, seen)
			requireLog(seen)
			local summary = record(seen.summaryPayload)
			local valid = summary ~= nil
				and summary.contract == names.summaryContract
				and safeId(summary.runId)
				and type(summary.passed) == "number"
				and type(summary.failed) == "number"
				and summary.passed >= 0
				and summary.failed >= 0
				and summary.passed % 1 == 0
				and summary.failed % 1 == 0
			if seen.requireBoundRecords == true then
				step(context, names.recordMismatch, names.hostActor, function()
					expect(valid):toBeTrueWith "the results summary must decode and bind a safe run id"
				end)
				return
			end
			step(context, names.receiptMissing, names.hostActor, function()
				expect(valid):toBeTrueWith "the results summary must decode and name a safe run id"
			end)
		end)

		case("reassembles every framed record the scenario host printed", function(context, seen)
			requireLog(seen)
			step(context, names.receiptTruncated, names.hostActor, function()
				expect(seen.wireDefect):toBeNil()
			end)
		end)

		case("carries no refusal, attempt-to-index, or not-authorized console lines", function(context, seen)
			requireLog(seen)
			step(context, names.failed, names.hostActor, function()
				local lines = listAt(seen, "consoleRefusalLines")
				expect(#lines == 0):toBeTrueWith(table.concat(lines, "; "))
			end)
		end)

		case("binds its armed and summary records to this run, place and version", function(context, seen)
			requireLog(seen)
			local summary = record(seen.summaryPayload)
			local armed = record(seen.armedPayload)
			local expectedPassed = seen.expectedPassed
			step(context, names.recordMismatch, names.hostActor, function()
				expect(summary).never:toBeNil()
				local runId = (summary :: any).runId
				local bind = options.bind
				expect(bind ~= nil):toBeTrueWith "the caller declared no record binding for this run"
				local armedExact, armedCoerced = (bind :: JourneyBinding)(seen, names.armedContract, runId)
				local summaryExact, summaryCoerced = (bind :: JourneyBinding)(seen, names.summaryContract, runId)
				expect(boundRecord(armed, armedExact, armedCoerced)):toBeTrueWith "the armed record must bind this run, place and version"
				expect(boundRecord(summary, summaryExact, summaryCoerced)):toBeTrueWith "the results summary must bind this run, place and version"
				expect(type(expectedPassed) == "number" and expectedPassed > 0 and expectedPassed % 1 == 0):toBeTrueWith "the caller must declare a positive integral expected pass count"
			end)
			step(context, names.failed, names.hostActor, function()
				local expected = expectedPassed :: number
				expect(
					(summary :: any).passed == expected
						and (summary :: any).failed == 0
						and (summary :: any).skipped == 0
				):toBeTrueWith "the summary must report exactly the expected passes and nothing else"
				local expectedNames = seen.expectedPredicateNames
				expect(
					exactGreenRows(
						(summary :: any).results,
						expected,
						if type(expectedNames) == "table" then expectedNames :: { string } else nil
					)
				):toBeTrueWith "the summary rows must be exactly the expected predicates, all green"
			end)
		end, function(seen)
			return seen.requireBoundRecords == true
		end)

		case("carries a complete acceptance record for the run it closes", function(context, seen)
			requireLog(seen)
			local summary = record(seen.summaryPayload)
			step(context, names.acceptanceOrder, names.acceptanceActor, function()
				expect(seen.wireDefect):toBeNil()
			end)
			step(context, names.acceptanceIncomplete, names.acceptanceActor, function()
				local starts = listAt(seen, "acceptanceStartRecords")
				local finishes = listAt(seen, "acceptanceFinishRecords")
				expect(summary).never:toBeNil()
				local validate = options.acceptance
				expect(validate ~= nil):toBeTrueWith "the caller declared no acceptance validator"
				local accepted, reason = (validate :: JourneyAcceptance)(
					record(starts[1].payload),
					record(finishes[1].payload),
					summary
				)
				expect(accepted ~= nil):toBeTrueWith("acceptance rejected " .. tostring(reason))
			end)
		end, function(seen)
			return seen.requireAcceptance == true
		end)

		if observations == nil then
			if declare ~= nil then
				declare "scenario predicate: <named by the scenario host at run time>"
			end
			return
		end

		local seen = observations :: { [string]: any }
		local rows = predicateRows(listAt(seen, "rows"), missingDetail)
		for _, row in rows do
			case(("scenario predicate: %s"):format(row.name), function(context, _seen)
				step(context, names.failed, names.hostActor, function()
					expect(row.ok):toBeTrueWith(row.name .. ": " .. row.detail)
				end)
			end)
		end
		if #rows == 0 and seen.logBound == true then
			case("reports predicate rows for the run it closed", function(context, own)
				for _, failedName in listAt(own, "failedRows") do
					step(context, names.failed, names.hostActor, function()
						expect(false):toBeTrueWith(tostring(failedName) .. ": named by a summary line")
					end)
				end
				step(context, names.failed, names.hostActor, function()
					expect(own.summaryFailed):toBe(0)
				end)
			end)
		end
	end)
end

return {
	COMPLETE = COMPLETE,
	HOLD = HOLD,
	DEFAULT_REFUSAL_PATTERNS = DEFAULT_REFUSAL_PATTERNS,
	DEFAULT_REFUSAL_LIMIT = DEFAULT_REFUSAL_LIMIT,
	DEFAULT_TITLE = DEFAULT_TITLE,
	DEFAULT_MISSING_DETAIL = DEFAULT_MISSING_DETAIL,
	classify = classify,
	judge = judge,
	receipt = receipt,
	sessionObservations = sessionObservations,
	chunkedCallPlan = chunkedCallPlan,
	countMarker = countMarker,
	clientObservations = clientObservations,
	finite = finite,
	finiteNonnegative = finiteNonnegative,
	nonnegativeInteger = nonnegativeInteger,
	denseRows = denseRows,
	deeplyFinite = deeplyFinite,
	safeId = safeId,
	decodeObject = decodeObject,
	frameSummary = frameSummary,
	frameHealth = frameHealth,
	sameFrameHealth = sameFrameHealth,
	frameHealthMatchesSummary = frameHealthMatchesSummary,
	frameReport = frameReport,
	frameSamplingComplete = frameSamplingComplete,
	boundRecord = boundRecord,
	exactGreenRows = exactGreenRows,
	failedRowNames = failedRowNames,
	refusalLines = refusalLines,
	rowName = rowName,
	predicateRows = predicateRows,
	journeySpec = journeySpec,
}
