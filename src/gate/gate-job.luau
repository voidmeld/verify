--!strict

local Benchmark = require "../benchmark"
local GateTypes = require "./gate-types"
local Harness = require "../core/harness"
local ReportModel = require "../core/report"
local Types = require "../core/types"

type Producer = GateTypes.Producer
type Report = Types.Report
type Status = GateTypes.Status

export type Context = {
	runId: string,
	executor: string,
	environment: { [string]: string },
	capabilities: { string },
	now: () -> number,
	deferrals: { [string]: string },
	logBytes: number,
}

export type Built = {
	report: Report,
	status: Status,
	detail: string?,
	accounted: boolean,
	caseIds: { string },
	deselected: { string },
	deferral: string?,
}

local function locator(producer: Producer): string
	return producer.kind .. ":" .. producer.id
end

local function tail(text: string, bytes: number): string
	if #text <= bytes then
		return text
	end
	return "..." .. string.sub(text, #text - bytes + 1)
end

local function bounded(text: string, limit: number): (string, boolean)
	if #text <= limit then
		return text, false
	end
	return tail(text, limit), true
end

local function synthetic(
	producer: Producer,
	ctx: Context,
	status: "failed" | "skipped" | "unsupported" | "timed_out" | "cancelled",
	message: string?,
	skipReason: string?,
	missing: { string }?
): Report
	return Harness.syntheticReport {
		executor = ctx.executor,
		environment = ctx.environment,
		capabilities = ctx.capabilities,
		id = producer.id,
		source = locator(producer),
		name = producer.id,
		status = status,
		phase = if status == "skipped" or status == "unsupported" then nil else "executor",
		message = message,
		skipReason = skipReason,
		missingCapabilities = missing,
	}
end

local function ids(report: Report): { string }
	local found: { string } = {}
	for _, result in report.results do
		table.insert(found, result.id)
	end
	return found
end

local function isDeselected(result: Types.CaseResult): boolean
	return result.status == "skipped"
		and result.skipReason ~= nil
		and string.sub(result.skipReason, 1, #Harness.DESELECTED_PREFIX) == Harness.DESELECTED_PREFIX
end

local function deselectedOf(report: Report, producer: Producer): { string }
	local found: { string } = {}
	for _, result in report.results do
		if result.id ~= producer.id and isDeselected(result) then
			table.insert(found, result.id)
		end
	end
	return found
end

local function producerResult(report: Report, producer: Producer): Types.CaseResult?
	for _, result in report.results do
		if result.id == producer.id then
			return result
		end
	end
	return nil
end

local function statusOf(report: Report, producer: Producer): (Status, string?)
	local own = producerResult(report, producer)
	if own == nil then
		return "failed", "the producer case is missing from its report"
	end
	local status: Status = "failed"
	local detail: string? = nil
	if own.status == "passed" then
		status = "passed"
	elseif own.status == "timed_out" then
		status = "timed_out"
	elseif own.status == "unsupported" then
		status = "unsupported"
	elseif own.status == "skipped" then
		status = if own.skipReason ~= nil and string.sub(own.skipReason, 1, 9) == "deferred:"
			then "deferred"
			else "failed"
	end
	if status ~= "passed" then
		detail = if #own.failures > 0 then own.failures[1].message else own.skipReason
		if detail == nil and #own.missingCapabilities > 0 then
			detail = "missing " .. table.concat(own.missingCapabilities, ", ")
		end
		return status, detail
	end
	local notPassed = 0
	local adopted = 0
	local sample: { string } = {}
	for _, result in report.results do
		if result.id ~= producer.id and not isDeselected(result) then
			adopted += 1
			if result.status ~= "passed" then
				notPassed += 1
				if #sample < 3 then
					local failure = result.failures[1]
					table.insert(
						sample,
						("%s [%s] %s%s"):format(
							result.id,
							if result.source ~= nil then result.source else producer.id,
							result.status,
							if failure ~= nil then ": " .. failure.message else ""
						)
					)
				end
			end
		end
	end
	if notPassed > 0 then
		return "failed",
			("%d of %d reported case(s) did not pass: %s%s"):format(
				notPassed,
				adopted,
				table.concat(sample, "; "),
				if notPassed > #sample then "; ..." else ""
			)
	end
	return "passed", nil
end

local function receive(producer: Producer, document: unknown, ctx: Context, bare: boolean): (Report?, string?)
	local value: unknown = document
	if not bare then
		if type(document) ~= "table" then
			return nil, "the report file is not a run-bound envelope"
		end
		local fields = document :: { [string]: unknown }
		if fields.runId ~= ctx.runId then
			return nil,
				("the report belongs to run %s, not the current run %s"):format(tostring(fields.runId), ctx.runId)
		end
		value = fields.report
	end
	local decoded, report: unknown = pcall(ReportModel.decode, value)
	if not decoded then
		return nil, "the report is invalid: " .. tostring(report)
	end
	return report :: Report, nil
end

local function census(declared: { string }, report: Report, producer: Producer): string?
	local wanted: { [string]: boolean } = {}
	for _, id in declared do
		wanted[id] = true
	end
	local present: { [string]: boolean } = {}
	local extra: { string } = {}
	for _, result in report.results do
		if present[result.id] then
			table.insert(extra, result.id .. " (duplicate)")
		end
		present[result.id] = true
		if not wanted[result.id] then
			table.insert(extra, result.id)
		end
	end
	local missing: { string } = {}
	for _, id in declared do
		if not present[id] then
			table.insert(missing, id)
		end
	end
	if #missing == 0 and #extra == 0 then
		return nil
	end
	local parts: { string } = {}
	if #missing > 0 then
		table.insert(parts, "missing case(s): " .. table.concat(missing, ", "))
	end
	if #extra > 0 then
		table.insert(parts, "unexpected case(s): " .. table.concat(extra, ", "))
	end
	return ("case census of %s does not match: %s"):format(producer.id, table.concat(parts, "; "))
end

local function accounting(producer: Producer, report: Report): string?
	if producer.kind == "tests" then
		local silent: { string } = {}
		for _, wanted in producer.locators do
			local seen = table.find(producer.silent, wanted) ~= nil
			for _, result in report.results do
				if result.source == wanted then
					seen = true
					break
				end
			end
			if not seen then
				table.insert(silent, wanted)
			end
		end
		if #silent > 0 then
			return "module(s) reported no case: " .. table.concat(silent, ", ")
		end
		if report.total == 0 then
			return "the report accounts for no case"
		end
		if producer.cases ~= nil then
			return census(producer.cases, report, producer)
		end
		return nil
	end
	local expectation = producer.report
	local minimum = if expectation ~= nil and expectation.minimum ~= nil then expectation.minimum else 1
	if report.total < minimum then
		return ("the report has %d case(s); at least %d required"):format(report.total, minimum)
	end
	if expectation ~= nil and expectation.cases ~= nil then
		if expectation.exact == true then
			return census(expectation.cases, report, producer)
		end
		local present: { [string]: boolean } = {}
		for _, result in report.results do
			present[result.id] = true
		end
		local absent: { string } = {}
		for _, wanted in expectation.cases do
			if not present[wanted] then
				table.insert(absent, wanted)
			end
		end
		if #absent > 0 then
			return "expected case(s) absent from the report: " .. table.concat(absent, ", ")
		end
	end
	return nil
end

local function harnessReport(producer: Producer, ctx: Context, limitations: { string }?, body: Harness.CaseRun): Report
	local harness = Harness.createHarness { now = ctx.now, source = locator(producer), prefixIds = false }
	harness:case(producer.id, { id = producer.id, limitations = limitations, run = body })
	return harness:run {
		executor = ctx.executor,
		environment = ctx.environment,
		capabilities = ctx.capabilities,
	}
end

local function finish(
	producer: Producer,
	ctx: Context,
	base: Report,
	adopted: Report?,
	accounted: boolean,
	deferral: string?
): Built
	local report = base
	if adopted ~= nil then
		report = ReportModel.merge({ base, adopted }, ctx.executor, ctx.environment)
	end
	local status: Status, detail: string? = statusOf(report, producer)
	return {
		report = report,
		status = status,
		detail = detail,
		accounted = accounted,
		caseIds = ids(report),
		deselected = deselectedOf(report, producer),
		deferral = if status == "deferred" then deferral else nil,
	}
end

local function benchmark(producer: Producer, ctx: Context, deadline: number?): Built
	local function bounded(spec: Benchmark.Spec): Benchmark.Spec
		local run = table.clone(spec)
		run.clock = spec.clock or ctx.now
		if deadline ~= nil then
			run.deadlineSeconds = if spec.deadlineSeconds ~= nil
				then math.min(spec.deadlineSeconds, deadline)
				else deadline
		end
		return run
	end
	local options: Harness.CaseOptions
	if producer.collection ~= nil then
		local source = producer.collection
		local members: { Benchmark.Spec } = {}
		for _, member in source.benchmarks do
			table.insert(members, bounded(member))
		end
		options = Benchmark.collection {
			name = source.name,
			yardstick = source.yardstick,
			benchmarks = members,
			clock = source.clock or ctx.now,
		}
	else
		options = Benchmark.case(bounded(producer.benchmark :: Benchmark.Spec))
	end
	local base = harnessReport(producer, ctx, nil, options.run)
	return finish(producer, ctx, base, nil, true, nil)
end

local function conclude(producer: Producer, ctx: Context, outcome: GateTypes.JobOutcome, reuse: GateTypes.Reuse?): Built
	local prefix = producer.id .. ":"
	if outcome.timedOut and reuse == nil then
		local message = ("exceeded its enforced deadline%s%s"):format(
			if outcome.logReference ~= nil then "; log " .. outcome.logReference else "",
			if outcome.stderr ~= "" or outcome.stdout ~= ""
				then "; last output: " .. tail(if outcome.stderr ~= "" then outcome.stderr else outcome.stdout, 400)
				else ""
		)
		local base = synthetic(producer, ctx, "timed_out", message, nil, nil)
		return finish(producer, ctx, base, nil, false, nil)
	end

	local class: GateTypes.ExitClass = "passed"
	if reuse == nil then
		local mapped: GateTypes.ExitClass? = producer.exit[outcome.exitcode]
		if mapped ~= nil then
			class = mapped
		elseif outcome.exitcode ~= 0 then
			class = "failed"
		end
		if not outcome.started then
			class = "failed"
		end
	end
	local deferral = ctx.deferrals[producer.id]
	local failure: string? = nil
	local skipReason: string? = nil
	local missing: string? = nil
	if reuse == nil and not outcome.started then
		failure = "could not start: " .. tostring(outcome.detail)
	elseif class == "failed" then
		local output = if outcome.stderr ~= "" then outcome.stderr else outcome.stdout
		failure = ("exited %d%s%s"):format(
			outcome.exitcode,
			if outcome.detail ~= nil then " (" .. outcome.detail .. ")" else "",
			if output ~= "" then ": " .. tail(output, 400) else ""
		)
	elseif class == "deferred" then
		if deferral ~= nil then
			skipReason = "deferred: " .. deferral
		else
			failure = ("exit %d declares a deferral, but the gate policy permits none for %s"):format(
				outcome.exitcode,
				producer.id
			)
		end
	elseif class == "unsupported" then
		missing = "host:" .. producer.id
	end

	local adopted: Report? = nil
	local accounted = false
	local reuseLimitation: { string }? = nil
	if reuse ~= nil then
		reuseLimitation = {
			("evidence reused from %s, validated by %s; not produced by this run"):format(
				reuse.reference,
				reuse.validatedBy
			),
		}
	end
	local expects = producer.kind == "tests" or producer.report ~= nil
	if failure == nil and skipReason == nil and missing == nil and expects then
		if outcome.report == nil then
			failure = ("exit %d without the expected report: %s"):format(
				outcome.exitcode,
				tostring(outcome.detail or "none was written")
			)
		else
			local bare = producer.kind == "tests" or reuse ~= nil
			local report, problem = receive(producer, outcome.report, ctx, bare)
			if report == nil then
				failure = problem
			else
				local missingAccount = accounting(producer, report)
				if missingAccount ~= nil then
					failure = missingAccount
				else
					accounted = true
					if producer.kind ~= "tests" then
						for _, result in report.results do
							result.id = prefix .. result.id
						end
					end
					adopted = report
				end
			end
		end
	end

	local base = harnessReport(producer, ctx, reuseLimitation, function(context: Harness.Context)
		if outcome.logReference ~= nil then
			context:artifact("log", outcome.logReference, "text/plain")
		end
		if failure ~= nil then
			error(failure, 0)
		end
		if skipReason ~= nil then
			context:skip(skipReason)
		end
		if missing ~= nil then
			context:unsupported(missing)
		end
	end)
	return finish(producer, ctx, base, adopted, accounted, deferral)
end

local function blocked(producer: Producer, ctx: Context, by: string, status: string): Built
	local base = synthetic(producer, ctx, "skipped", nil, ("blocked by %s (%s)"):format(by, status), nil)
	local blockedStatus: Status = "blocked"
	return {
		report = base,
		status = blockedStatus,
		detail = ("blocked by %s (%s)"):format(by, status),
		accounted = false,
		caseIds = { producer.id },
		deselected = {},
		deferral = nil,
	}
end

local function notRun(
	producer: Producer,
	ctx: Context,
	status: "timed_out" | "cancelled" | "skipped",
	reason: string
): Built
	local base = if status == "skipped"
		then synthetic(producer, ctx, "skipped", nil, reason, nil)
		else synthetic(producer, ctx, status, reason, nil, nil)
	local resulting: Status = if status == "timed_out" then "timed_out" else "not_run"
	return {
		report = base,
		status = resulting,
		detail = reason,
		accounted = false,
		caseIds = { producer.id },
		deselected = {},
		deferral = nil,
	}
end

local function refusedReuse(producer: Producer, ctx: Context, reason: string): Built
	local base = synthetic(producer, ctx, "failed", reason .. " for " .. producer.id, nil, nil)
	return {
		report = base,
		status = "failed",
		detail = reason,
		accounted = false,
		caseIds = { producer.id },
		deselected = {},
		deferral = nil,
	}
end

return {
	locator = locator,
	bounded = bounded,
	conclude = conclude,
	benchmark = benchmark,
	blocked = blocked,
	notRun = notRun,
	refusedReuse = refusedReuse,
}
