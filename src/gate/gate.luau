--!strict

local Benchmark = require "../benchmark"
local Capability = require "../core/capability"
local Execution = require "../core/execution"
local GateJob = require "./gate-job"
local GateTypes = require "./gate-types"
local Plan = require "../core/plan"
local ReportModel = require "../core/report"
local Types = require "../core/types"

type Producer = GateTypes.Producer
type ProducerRecord = GateTypes.ProducerRecord
type Gate = GateTypes.Gate
type Status = GateTypes.Status
type Report = Types.Report

local SCHEMA_VERSION = 1
local DEFAULT_COMMAND_DEADLINE = 300
local DEFAULT_LOG_BYTES = 65536
local ID_PATTERN = "^[%w][%w%-_%.]*$"

local function positiveWhole(value: number?, fallback: number, label: string): number
	local chosen = if value ~= nil then value else fallback
	if type(chosen) ~= "number" or chosen < 1 or chosen % 1 ~= 0 then
		error(label .. " must be a positive whole number", 3)
	end
	return chosen
end

local function positiveSeconds(value: number?, label: string): number?
	if value == nil then
		return nil
	end
	if type(value) ~= "number" or value <= 0 or value >= math.huge then
		error(label .. " must be a positive finite number of seconds", 3)
	end
	return value
end

local function strings(values: { string }?, label: string): { string }
	return Capability.sorted(values, label)
end

local function ordered(values: { string }?, label: string): { string }
	local source: { string } = if values ~= nil then values else {}
	local result: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, value in source do
		if type(value) ~= "string" or value == "" then
			error(label .. " must contain only non-empty strings", 3)
		end
		if seen[value] then
			error(("%s names %q more than once"):format(label, value), 3)
		end
		seen[value] = true
		table.insert(result, value)
	end
	return result
end

local function arguments(values: { string }?, label: string): { string }
	local result: { string } = {}
	local source: { string } = if values ~= nil then values else {}
	for _, value in source do
		if type(value) ~= "string" then
			error(label .. " must contain only strings", 3)
		end
		table.insert(result, value)
	end
	return result
end

local function normalizeProducer(draft: GateTypes.ProducerDraft, defaultDeadline: number): Producer
	local id = draft.id
	if type(id) ~= "string" or string.match(id, ID_PATTERN) == nil then
		error(
			("producer id %q must start with a letter or digit and use only letters, digits, '-', '_' and '.'"):format(
				tostring(id)
			),
			3
		)
	end
	local label = ("producer %q"):format(id)
	local kind = draft.kind
	if kind ~= "tests" and kind ~= "command" and kind ~= "build" and kind ~= "native" and kind ~= "benchmark" then
		error(label .. " has an unknown kind", 3)
	end
	if
		kind ~= "tests"
		and (
			draft.isolate ~= nil
			or draft.workers ~= nil
			or draft.sourceDeadlineSeconds ~= nil
			or draft.args ~= nil
			or draft.cases ~= nil
			or draft.command ~= nil
		)
	then
		error(
			label .. " takes isolate, workers, sourceDeadlineSeconds, args, cases and command only as a tests producer",
			3
		)
	end
	local workers = 1
	local cases: { string }? = nil
	local argv: { string } = {}
	local locators: { string } = {}
	local silent: { string } = {}
	local exit: { [number]: GateTypes.ExitClass } = {}
	if kind == "tests" then
		if type(draft.worker) ~= "string" or draft.worker == "" then
			error(label .. " needs a worker module", 3)
		end
		locators = ordered(draft.locators, label .. ".locators")
		if #locators == 0 then
			error(label .. " lists no test module", 3)
		end
		silent = ordered(draft.silent, label .. ".silent")
		if draft.workers ~= nil then
			if draft.isolate ~= true then
				error(label .. ".workers needs isolate = true", 3)
			end
			workers = positiveWhole(draft.workers, 1, label .. ".workers")
		end
		if draft.sourceDeadlineSeconds ~= nil and draft.isolate ~= true then
			error(label .. ".sourceDeadlineSeconds needs isolate = true", 3)
		end
		if draft.command ~= nil and #arguments(draft.command, label .. ".command") == 0 then
			error(label .. ".command must name the program that starts the worker", 3)
		end
		if draft.cases ~= nil then
			cases = ordered(draft.cases, label .. ".cases")
			if #(cases :: { string }) == 0 then
				error(label .. ".cases must declare at least one case", 3)
			end
		end
		for _, locator in silent do
			if table.find(locators, locator) == nil then
				error(("%s.silent names %s, which is not one of its locators"):format(label, locator), 3)
			end
		end
		if
			draft.argv ~= nil
			or draft.exit ~= nil
			or draft.report ~= nil
			or draft.benchmark ~= nil
			or draft.collection ~= nil
			or draft.env ~= nil
			or draft.cwd ~= nil
		then
			error(label .. " is a tests producer and takes only worker and locators", 3)
		end
	elseif kind == "benchmark" then
		if (draft.benchmark == nil) == (draft.collection == nil) then
			error(label .. " needs one benchmark specification or one benchmark collection", 3)
		end
		if draft.benchmark ~= nil then
			Benchmark.check(draft.benchmark)
		elseif draft.collection ~= nil then
			Benchmark.checkCollection(draft.collection)
		end
		if
			draft.argv ~= nil
			or draft.exit ~= nil
			or draft.report ~= nil
			or draft.worker ~= nil
			or draft.locators ~= nil
			or draft.silent ~= nil
			or draft.env ~= nil
			or draft.cwd ~= nil
		then
			error(label .. " is a benchmark producer and takes only a benchmark specification or collection", 3)
		end
	else
		argv = arguments(draft.argv, label .. ".argv")
		if #argv == 0 then
			error(label .. " needs a command", 3)
		end
		if
			draft.worker ~= nil
			or draft.locators ~= nil
			or draft.silent ~= nil
			or draft.benchmark ~= nil
			or draft.collection ~= nil
		then
			error(label .. " is a command producer and takes argv, env, cwd, exit and report", 3)
		end
		local declaredExit: { [number]: GateTypes.ExitClass } = if draft.exit ~= nil then draft.exit else {}
		local declaredEnv: { [string]: string } = if draft.env ~= nil then draft.env else {}
		for key, value in declaredEnv do
			if type(key) ~= "string" or key == "" or type(value) ~= "string" then
				error(label .. ".env must map non-empty names to strings", 3)
			end
		end
		if draft.cwd ~= nil and draft.cwd == "" then
			error(label .. ".cwd must not be empty", 3)
		end
		for code, class in declaredExit do
			if type(code) ~= "number" or code % 1 ~= 0 then
				error(label .. ".exit must be keyed by whole exit codes", 3)
			end
			if class ~= "passed" and class ~= "failed" and class ~= "deferred" and class ~= "unsupported" then
				error(("%s.exit[%d] must be passed, failed, deferred or unsupported"):format(label, code), 3)
			end
			exit[code] = class
		end
	end
	local expectation = draft.report
	if expectation ~= nil then
		if expectation.minimum ~= nil then
			positiveWhole(expectation.minimum, 1, label .. ".report.minimum")
		end
		if expectation.cases ~= nil then
			ordered(expectation.cases, label .. ".report.cases")
		end
		if expectation.exact == true and expectation.cases == nil then
			error(label .. ".report.exact needs report.cases", 3)
		end
	end
	local requires = strings(draft.requires, label .. ".requires")
	if kind == "native" and #requires == 0 then
		error(label .. " is native and must name the host capability it requires", 3)
	end
	if draft.why ~= nil and (type(draft.why) ~= "string" or string.find(draft.why, "%S") == nil) then
		error(label .. ".why must be a non-empty explanation", 3)
	end
	if draft.tier ~= nil and draft.tier == "" then
		error(label .. ".tier must not be empty", 3)
	end
	return {
		id = id,
		kind = kind,
		after = ordered(draft.after, label .. ".after"),
		tier = draft.tier,
		why = draft.why,
		tags = strings(draft.tags, label .. ".tags"),
		requires = requires,
		deadlineSeconds = positiveSeconds(draft.deadlineSeconds, label .. ".deadlineSeconds") or defaultDeadline,
		exclusive = if draft.exclusive ~= nil then draft.exclusive else kind == "benchmark",
		argv = argv,
		exit = exit,
		env = if draft.env ~= nil then table.clone(draft.env) else {},
		cwd = draft.cwd,
		report = expectation,
		worker = draft.worker,
		command = if draft.command ~= nil then arguments(draft.command, label .. ".command") else nil,
		locators = locators,
		silent = silent,
		isolate = draft.isolate == true,
		workers = workers,
		sourceDeadlineSeconds = positiveSeconds(draft.sourceDeadlineSeconds, label .. ".sourceDeadlineSeconds"),
		args = arguments(draft.args, label .. ".args"),
		cases = cases,
		benchmark = draft.benchmark,
		collection = draft.collection,
	}
end

local function checkGraph(producers: { Producer })
	local byId: { [string]: Producer } = {}
	for _, producer in producers do
		if byId[producer.id] ~= nil then
			error("duplicate producer id: " .. producer.id, 3)
		end
		byId[producer.id] = producer
	end
	for _, producer in producers do
		for _, dependency in producer.after do
			if dependency == producer.id then
				error(("producer %q cannot run after itself"):format(producer.id), 3)
			end
			if byId[dependency] == nil then
				error(("producer %q runs after unknown producer %q"):format(producer.id, dependency), 3)
			end
		end
	end
	local visiting: { [string]: boolean } = {}
	local done: { [string]: boolean } = {}
	local function visit(producer: Producer, path: { string })
		if done[producer.id] then
			return
		end
		if visiting[producer.id] then
			error("producer dependencies form a cycle: " .. table.concat(path, " -> ") .. " -> " .. producer.id, 4)
		end
		visiting[producer.id] = true
		table.insert(path, producer.id)
		for _, dependency in producer.after do
			visit(byId[dependency], path)
		end
		table.remove(path)
		visiting[producer.id] = nil
		done[producer.id] = true
	end
	for _, producer in producers do
		visit(producer, {})
	end
end

local function fingerprint(text: string): string
	local hash = 2166136261
	for index = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = bit32.band(hash * 16777619, 0xFFFFFFFF)
	end
	return ("%08x-%d"):format(hash, #text)
end

local function digestOf(id: string, producers: { Producer }, policy: GateTypes.Policy): string
	local pieces: { string } = {
		("v%d"):format(SCHEMA_VERSION),
		id,
		("concurrency=%d"):format(policy.concurrency),
		("deadline=%s"):format(tostring(policy.deadlineSeconds)),
		("commandDeadline=%d"):format(policy.commandDeadlineSeconds),
		("failFast=%s"):format(tostring(policy.failFast)),
		("reuse=%s"):format(table.concat(policy.reuse, ",")),
		("requires=%s"):format(table.concat(policy.requires, ",")),
	}
	local deferred: { string } = {}
	for key, reason in policy.deferrals do
		table.insert(deferred, key .. "=" .. reason)
	end
	table.sort(deferred)
	table.insert(pieces, "deferrals=" .. table.concat(deferred, ";"))
	for _, producer in producers do
		local codes: { string } = {}
		for code, class in producer.exit do
			table.insert(codes, ("%d=%s"):format(code, class))
		end
		table.sort(codes)
		local report = producer.report
		local spec = producer.benchmark
		local budget: Benchmark.Budget = if spec ~= nil and spec.budget ~= nil then spec.budget else {}
		table.insert(
			pieces,
			table.concat({
				producer.id,
				producer.kind,
				table.concat(producer.after, ","),
				tostring(producer.tier),
				table.concat(producer.tags, ","),
				table.concat(producer.requires, ","),
				tostring(producer.deadlineSeconds),
				tostring(producer.exclusive),
				table.concat(producer.argv, "\0"),
				(function(): string
					local entries: { string } = {}
					for key, value in producer.env do
						table.insert(entries, key .. "=" .. value)
					end
					table.sort(entries)
					return table.concat(entries, "\0") .. "@" .. tostring(producer.cwd)
				end)(),
				table.concat(codes, ","),
				if report ~= nil
					then ("%s|%s|%s"):format(
						tostring(report.minimum),
						table.concat(if report.cases ~= nil then report.cases else {}, ","),
						tostring(report.exact == true)
					)
					else "",
				("%s|%d|%s|%s|%s"):format(
					tostring(producer.isolate),
					producer.workers,
					tostring(producer.sourceDeadlineSeconds),
					table.concat(producer.args, "\0"),
					table.concat(if producer.cases ~= nil then producer.cases else {}, ",")
				),
				tostring(producer.worker),
				table.concat(if producer.command ~= nil then producer.command else {}, "\0"),
				table.concat(producer.locators, ","),
				table.concat(producer.silent, ","),
				if spec ~= nil
					then ("%s|%s|%d|%d|%s|%s"):format(
						spec.name,
						spec.unit,
						spec.warmup,
						spec.samples,
						tostring(budget.p50) .. tostring(budget.p95) .. tostring(budget.p99) .. tostring(budget.maximum),
						spec.environment.observed
					)
					elseif producer.collection ~= nil then (function(): string
						local members: { string } = {}
						for _, member in producer.collection.benchmarks do
							local limits: Benchmark.Budget = if member.budget ~= nil then member.budget else {}
							table.insert(
								members,
								("%s|%s|%d|%d|%s|%s"):format(
									member.name,
									member.unit,
									member.warmup,
									member.samples,
									tostring(limits.p50)
										.. tostring(limits.p95)
										.. tostring(limits.p99)
										.. tostring(limits.maximum),
									member.environment.observed
								)
							)
						end
						return producer.collection.name .. ":" .. table.concat(members, ",")
					end)()
					else "",
			}, "|")
		)
	end
	return fingerprint(table.concat(pieces, "\n"))
end

local function define(draft: GateTypes.GateDraft): Gate
	if type(draft) ~= "table" or type(draft.id) ~= "string" or draft.id == "" then
		error("a gate needs a non-empty id", 2)
	end
	local source: GateTypes.PolicyDraft = if draft.policy ~= nil then draft.policy else {}
	local commandDeadline = positiveSeconds(source.commandDeadlineSeconds, "gate policy commandDeadlineSeconds")
		or DEFAULT_COMMAND_DEADLINE
	local producers: { Producer } = {}
	for index, entry in draft.producers do
		if type(index) ~= "number" or index ~= #producers + 1 then
			error("gate producers must be a dense array", 2)
		end
		table.insert(producers, normalizeProducer(entry, commandDeadline))
	end
	checkGraph(producers)
	local known: { [string]: boolean } = {}
	for _, producer in producers do
		known[producer.id] = true
	end
	local deferrals: { [string]: string } = {}
	local declaredDeferrals: { [string]: string } = if source.deferrals ~= nil then source.deferrals else {}
	for id, reason in declaredDeferrals do
		if not known[id] then
			error(("gate policy defers unknown producer %q"):format(id), 2)
		end
		if type(reason) ~= "string" or string.find(reason, "%S") == nil then
			error(("gate policy deferral for %q needs a reason"):format(id), 2)
		end
		deferrals[id] = reason
	end
	local reuse = strings(source.reuse, "gate policy reuse")
	for _, id in reuse do
		if not known[id] then
			error(("gate policy allows reuse of unknown producer %q"):format(id), 2)
		end
	end
	local policy: GateTypes.Policy = {
		concurrency = positiveWhole(source.concurrency, 1, "gate policy concurrency"),
		deadlineSeconds = positiveSeconds(source.deadlineSeconds, "gate policy deadlineSeconds"),
		commandDeadlineSeconds = commandDeadline,
		failFast = source.failFast == true,
		deferrals = deferrals,
		reuse = reuse,
		requires = strings(source.requires, "gate policy requires"),
	}
	local units: { Types.PlanUnitDraft } = {}
	for _, producer in producers do
		local tags = table.clone(producer.tags)
		table.insert(tags, "kind:" .. producer.kind)
		if producer.tier ~= nil then
			table.insert(tags, "tier:" .. producer.tier)
		end
		table.insert(units, {
			id = producer.id,
			locator = GateJob.locator(producer),
			tags = tags,
			requires = producer.requires,
			deadlineSeconds = producer.deadlineSeconds,
		})
	end
	local plan = Plan.validate {
		id = draft.id,
		requires = policy.requires,
		policy = {
			maxParallelBatches = 1,
			batchCount = 1,
			runDeadlineSeconds = policy.deadlineSeconds,
		},
		units = units,
	}
	return {
		schemaVersion = SCHEMA_VERSION,
		id = draft.id,
		digest = digestOf(draft.id, producers, policy),
		producers = producers,
		policy = policy,
		plan = plan,
	}
end

local function producerOf(gate: Gate, id: string): Producer
	for _, producer in gate.producers do
		if producer.id == id then
			return producer
		end
	end
	error("unknown producer " .. id, 2)
end

type Resolved = {
	ids: { string }?,
	pulled: { [string]: boolean },
	reasons: { [string]: string },
	byTier: { [string]: boolean },
}

local function listed(values: { string }?): { string }
	return if values ~= nil then values else {}
end

local function resolve(gate: Gate, selection: GateTypes.Selection?): Resolved
	local resolved: Resolved = { ids = nil, pulled = {}, reasons = {}, byTier = {} }
	if selection == nil then
		return resolved
	end
	local askedIds = listed(selection.ids)
	local askedTiers = listed(selection.tiers)
	local askedTags = listed(selection.tags)
	local askedCases = listed(selection.cases)
	local askedSources = listed(selection.sources)
	local askedName = selection.nameContains
	if askedName ~= nil and (type(askedName) ~= "string" or askedName == "") then
		error("a gate selection name filter must be a nonempty string", 3)
	end
	local byContent = askedName ~= nil or #askedSources > 0
	if #askedIds == 0 and #askedTiers == 0 and #askedTags == 0 and #askedCases == 0 and not byContent then
		error("a gate selection must name at least one id, tier, tag, case, name filter or source", 3)
	end
	local known: { [string]: boolean } = {}
	local present: { [string]: boolean } = {}
	for _, unit in gate.plan.units do
		known[unit.id] = true
		for _, tag in unit.tags do
			present[tag] = true
		end
	end
	for _, id in askedIds do
		if not known[id] then
			error(("selection names unknown producer %q"):format(id), 3)
		end
	end
	local wanted: { string } = {}
	for _, tier in askedTiers do
		if not present["tier:" .. tier] then
			error(("selection names unknown tier %q"):format(tier), 3)
		end
		table.insert(wanted, "tier:" .. tier)
	end
	for _, tag in askedTags do
		if not present[tag] then
			error(("selection names unknown tag %q"):format(tag), 3)
		end
		table.insert(wanted, tag)
	end
	local ownerIds: { string } = {}
	if #askedIds == 0 and #wanted == 0 then
		for _, case in askedCases do
			local owned = false
			for _, producer in gate.producers do
				if producer.cases ~= nil and table.find(producer.cases, case) ~= nil then
					owned = true
					if table.find(ownerIds, producer.id) == nil then
						table.insert(ownerIds, producer.id)
					end
				end
			end
			if not owned then
				error(
					("selection names case %q, which no producer declares; name the producer with ids or declare its cases"):format(
						case
					),
					3
				)
			end
		end
	end
	if byContent and #askedIds == 0 and #wanted == 0 and #ownerIds == 0 then
		for _, producer in gate.producers do
			if producer.kind == "tests" then
				table.insert(ownerIds, producer.id)
			end
		end
		if #ownerIds == 0 then
			error("a name or source selection needs a tests producer", 3)
		end
	end
	local picked = Plan.select(gate.plan, {
		ids = if #askedIds > 0 then askedIds elseif #ownerIds > 0 then ownerIds else nil,
		tags = if #wanted > 0 then wanted else nil,
	})
	if #picked.units == 0 then
		error("the selection matches no producer", 3)
	end
	local chosen: { [string]: boolean } = {}
	local function include(id: string)
		if chosen[id] then
			return
		end
		chosen[id] = true
		for _, dependency in producerOf(gate, id).after do
			include(dependency)
		end
	end
	local direct: { [string]: boolean } = {}
	for _, unit in picked.units do
		direct[unit.id] = true
		include(unit.id)
	end
	local result: { string } = {}
	for _, producer in gate.producers do
		if chosen[producer.id] then
			table.insert(result, producer.id)
			if not direct[producer.id] then
				resolved.pulled[producer.id] = true
			end
		else
			local tier = producer.tier
			if #askedTiers > 0 and (tier == nil or table.find(askedTiers, tier) == nil) then
				resolved.reasons[producer.id] = if tier == nil
					then ("not selected: it declares no tier and the run selected tier %s"):format(
						table.concat(askedTiers, ", ")
					)
					else ("not selected: its tier %s is not among the selected tier %s"):format(
						tier,
						table.concat(askedTiers, ", ")
					)
				resolved.byTier[producer.id] = tier ~= nil
			elseif #askedIds > 0 then
				resolved.reasons[producer.id] = "not selected: the run named other producers"
			elseif #askedTags > 0 then
				resolved.reasons[producer.id] = ("not selected: it carries none of the selected tag(s) %s"):format(
					table.concat(askedTags, ", ")
				)
			elseif byContent and #askedCases == 0 then
				resolved.reasons[producer.id] =
					"not selected: the run filtered cases by name or source, which only tests producers take"
			else
				resolved.reasons[producer.id] = "not selected: it declares none of the selected cases"
			end
		end
	end
	resolved.ids = result
	return resolved
end

local function micros(seconds: number): number
	return math.max(0, math.floor(seconds * 1e6 + 0.5))
end

type Running = {
	id: string,
	handle: GateTypes.Task,
	startedAt: number,
}

local function schedule(
	gate: Gate,
	executor: GateTypes.Executor,
	options: GateTypes.RunOptions,
	ctx: GateJob.Context,
	units: { Types.PlanUnit },
	records: { [string]: ProducerRecord }
): { Report }
	local policy = gate.policy
	local logBytes = ctx.logBytes
	local pollSeconds = options.pollSeconds or 0.01
	local byId: { [string]: Producer } = {}
	local order: { string } = {}
	local waiting: { [string]: boolean } = {}
	local inBatch: { [string]: boolean } = {}
	for _, unit in units do
		byId[unit.id] = producerOf(gate, unit.id)
		table.insert(order, unit.id)
		waiting[unit.id] = true
		inBatch[unit.id] = true
	end
	local reports: { [string]: Report } = {}
	local finished: { [string]: Status } = {}
	local running: { Running } = {}
	local startedAt = executor.now()
	local stopKind: string? = nil
	local stopReason = ""

	local function record(
		producer: Producer,
		built: GateJob.Built,
		began: number,
		outcome: GateTypes.JobOutcome?,
		reuse: GateTypes.Reuse?
	)
		reports[producer.id] = built.report
		finished[producer.id] = built.status
		local log: GateTypes.Log? = nil
		if outcome ~= nil and (outcome.stdout ~= "" or outcome.stderr ~= "" or outcome.logReference ~= nil) then
			local stdout, cutOut = GateJob.bounded(outcome.stdout, logBytes)
			local stderr, cutErr = GateJob.bounded(outcome.stderr, logBytes)
			log = {
				stdout = stdout,
				stderr = stderr,
				bytes = #outcome.stdout + #outcome.stderr,
				truncated = cutOut or cutErr,
				reference = outcome.logReference,
			}
		end
		records[producer.id] = {
			id = producer.id,
			kind = producer.kind,
			tier = producer.tier,
			why = producer.why,
			status = built.status,
			selected = true,
			pulledByDependency = false,
			exitcode = if outcome ~= nil and outcome.started then outcome.exitcode else nil,
			timedOut = outcome ~= nil and outcome.timedOut,
			durationMicros = micros(executor.now() - began),
			detail = built.detail,
			log = log,
			reportAccounted = built.accounted,
			caseIds = built.caseIds,
			deselected = built.deselected,
			reused = reuse ~= nil and built.status ~= "failed",
			reuseReference = if reuse ~= nil then reuse.reference else nil,
			deferral = built.deferral,
			blockedBy = nil,
		}
		if options.observe ~= nil then
			pcall(options.observe, records[producer.id])
		end
		if
			policy.failFast
			and stopKind == nil
			and built.status ~= "passed"
			and built.status ~= "deferred"
			and built.status ~= "blocked"
		then
			stopKind = "fail-fast"
			stopReason = ("fail-fast stopped the run after %s"):format(producer.id)
		end
	end

	local function readiness(producer: Producer): ("ready" | "waiting" | "blocked", string?, string?)
		local pendingDependency = false
		for _, dependency in producer.after do
			if not inBatch[dependency] then
				return "blocked", dependency, "not run"
			end
			local status = finished[dependency]
			if status == nil then
				pendingDependency = true
			elseif status ~= "passed" then
				return "blocked", dependency, status
			end
		end
		return if pendingDependency then "waiting" else "ready", nil, nil
	end

	local function launch(producer: Producer, remaining: number?)
		local began = executor.now()
		local reuse = if options.reuse ~= nil then options.reuse[producer.id] else nil
		if reuse ~= nil then
			if table.find(policy.reuse, producer.id) == nil then
				record(
					producer,
					GateJob.refusedReuse(producer, ctx, "evidence reuse is not permitted by the gate policy"),
					began,
					nil,
					nil
				)
				return
			end
			if options.build ~= nil and (reuse.build == nil or reuse.build.digest ~= options.build.digest) then
				record(
					producer,
					GateJob.refusedReuse(producer, ctx, "the reused receipt is not bound to the build under test"),
					began,
					nil,
					nil
				)
				return
			end
			local outcome: GateTypes.JobOutcome = {
				started = true,
				exitcode = 0,
				timedOut = false,
				stdout = "",
				stderr = "",
				report = reuse.report,
			}
			record(producer, GateJob.conclude(producer, ctx, outcome, reuse), began, nil, reuse)
			return
		end
		if producer.kind == "benchmark" then
			record(producer, GateJob.benchmark(producer, ctx, remaining), began, nil, nil)
			return
		end
		local deadline = if remaining ~= nil
			then math.min(producer.deadlineSeconds, remaining)
			else producer.deadlineSeconds
		local tiers = listed(if options.selection ~= nil then options.selection.tiers else nil)
		local cases = listed(if options.selection ~= nil then options.selection.cases else nil)
		local args = table.clone(producer.args)
		if #tiers > 0 then
			table.insert(args, "--tier=" .. table.concat(tiers, ","))
		end
		for _, case in cases do
			table.insert(args, "--case=" .. case)
		end
		if producer.kind == "tests" then
			local selection = options.selection
			if selection ~= nil and selection.nameContains ~= nil then
				table.insert(args, "--name=" .. selection.nameContains)
			end
			for _, source in listed(if selection ~= nil then selection.sources else nil) do
				table.insert(args, "--source=" .. source)
			end
		end
		local job: GateTypes.Job = {
			id = producer.id,
			kind = producer.kind :: "tests" | "command" | "build" | "native",
			argv = producer.argv,
			env = producer.env,
			cwd = producer.cwd,
			worker = producer.worker,
			command = producer.command,
			locators = producer.locators,
			args = args,
			isolate = producer.isolate,
			workers = producer.workers,
			sourceDeadlineSeconds = producer.sourceDeadlineSeconds,
			tiers = tiers,
			cases = cases,
			runId = options.runId,
			expectsReport = producer.kind == "tests" or producer.report ~= nil,
			deadlineSeconds = deadline,
		}
		local started, handle: unknown = pcall(executor.start, job)
		if not started then
			local outcome: GateTypes.JobOutcome = {
				started = false,
				exitcode = -1,
				timedOut = false,
				stdout = "",
				stderr = "",
				detail = tostring(handle),
			}
			record(producer, GateJob.conclude(producer, ctx, outcome, nil), began, outcome, nil)
			return
		end
		table.insert(running, { id = producer.id, handle = handle :: GateTypes.Task, startedAt = began })
	end

	while true do
		local index = 1
		while index <= #running do
			local entry = running[index]
			local polled, outcome: unknown = pcall(entry.handle.poll)
			local result: GateTypes.JobOutcome? = nil
			if not polled then
				result = {
					started = true,
					exitcode = -1,
					timedOut = false,
					stdout = "",
					stderr = "",
					detail = "the executor raised while polling: " .. tostring(outcome),
				}
			else
				result = outcome :: GateTypes.JobOutcome?
			end
			if result ~= nil then
				table.remove(running, index)
				local producer = byId[entry.id]
				record(producer, GateJob.conclude(producer, ctx, result, nil), entry.startedAt, result, nil)
			else
				index += 1
			end
		end

		local elapsed = executor.now() - startedAt
		local limit = policy.deadlineSeconds
		if stopKind == nil and limit ~= nil and elapsed >= limit then
			stopKind = "deadline"
			stopReason = ("the run deadline of %s second(s) elapsed"):format(tostring(limit))
		end

		local progress = false
		local exclusiveRunning = false
		for _, entry in running do
			if byId[entry.id].exclusive then
				exclusiveRunning = true
			end
		end
		if stopKind == nil and not exclusiveRunning then
			for _, id in order do
				if not waiting[id] then
					continue
				end
				local producer = byId[id]
				local state, culprit, culpritStatus = readiness(producer)
				if state == "blocked" then
					waiting[id] = nil
					record(
						producer,
						GateJob.blocked(producer, ctx, culprit :: string, culpritStatus :: string),
						executor.now(),
						nil,
						nil
					)
					records[id].blockedBy = culprit
					progress = true
				elseif state == "ready" then
					if #running >= policy.concurrency or (producer.exclusive and #running > 0) then
						break
					end
					local remaining: number? = if limit ~= nil then limit - (executor.now() - startedAt) else nil
					waiting[id] = nil
					launch(producer, remaining)
					progress = true
					if producer.exclusive or stopKind ~= nil then
						break
					end
				end
			end
		end

		local remainingWaiting = false
		for _, id in order do
			if waiting[id] then
				remainingWaiting = true
			end
		end
		if #running == 0 and (not remainingWaiting or stopKind ~= nil or not progress) then
			break
		end
		if #running > 0 and not progress then
			executor.wait(pollSeconds)
		end
	end

	for _, id in order do
		if waiting[id] then
			waiting[id] = nil
			local producer = byId[id]
			local built = if stopKind == "deadline"
				then GateJob.notRun(producer, ctx, "timed_out", "not dispatched: " .. stopReason)
				elseif stopKind == "fail-fast" then GateJob.notRun(
					producer,
					ctx,
					"skipped",
					"not dispatched: " .. stopReason
				)
				else GateJob.notRun(
					producer,
					ctx,
					"skipped",
					"no producer could be scheduled; its dependencies never completed"
				)
			record(producer, built, executor.now(), nil, nil)
		end
	end

	local collected: { Report } = {}
	for _, id in order do
		table.insert(collected, reports[id])
	end
	return collected
end

local function placeholder(
	producer: Producer,
	selected: boolean,
	declared: { string },
	gate: Gate,
	execution: Types.ExecutionReport,
	reason: string?
): ProducerRecord
	local status: Status = "not_selected"
	local detail: string? = reason
	if selected then
		local negotiation = Capability.negotiate(declared, Capability.union(gate.policy.requires, producer.requires))
		if not negotiation.satisfied then
			status = "unsupported"
			detail = Capability.explain(negotiation)
		else
			status = "not_run"
			detail = if execution.batches[1] ~= nil and execution.batches[1].reason ~= nil
				then execution.batches[1].reason
				else "the run ended before this producer was dispatched"
		end
	end
	return {
		id = producer.id,
		kind = producer.kind,
		tier = producer.tier,
		why = producer.why,
		status = status,
		selected = selected,
		pulledByDependency = false,
		exitcode = nil,
		timedOut = false,
		durationMicros = 0,
		detail = detail,
		log = nil,
		reportAccounted = false,
		caseIds = {},
		deselected = {},
		reused = false,
		reuseReference = nil,
		deferral = nil,
		blockedBy = nil,
	}
end

local function accept(
	execution: Types.ExecutionReport,
	records: { ProducerRecord },
	scope: GateTypes.Scope,
	missingCases: { string }
): GateTypes.Acceptance
	local passed: { string } = {}
	local failed: { string } = {}
	local deferred: { string } = {}
	local reused: { string } = {}
	local notSelected: { string } = {}
	local reasons: { string } = {}
	for _, record in records do
		if record.reused then
			table.insert(reused, record.id)
		end
		if record.status == "not_selected" then
			table.insert(notSelected, record.id)
		elseif record.status == "passed" then
			table.insert(passed, record.id)
		elseif record.status == "deferred" then
			table.insert(deferred, record.id)
			table.insert(reasons, ("%s deferred: %s"):format(record.id, tostring(record.deferral or record.detail)))
		else
			table.insert(failed, record.id)
			table.insert(
				reasons,
				("%s %s%s"):format(record.id, record.status, if record.detail ~= nil then ": " .. record.detail else "")
			)
		end
	end
	local unaccounted = false
	if #missingCases > 0 then
		unaccounted = true
		table.insert(
			reasons,
			("selected case(s) were not found in any selected producer: %s"):format(table.concat(missingCases, ", "))
		)
	end
	for _, fact in execution.facts do
		if fact.severity == "failure" then
			unaccounted = true
			table.insert(reasons, ("%s: %s"):format(fact.code, fact.detail))
		end
	end
	local report = execution.report
	if report.total == 0 then
		unaccounted = true
		table.insert(reasons, "the gate ran no case")
	end
	if report.failed + report.timedOut + report.cancelled > 0 and #failed == 0 then
		unaccounted = true
		table.insert(reasons, "the report holds failing cases that no producer record accounts for")
	end
	if #failed == 0 and #deferred == 0 and report.passed + #scope.deselected ~= report.total then
		unaccounted = true
		table.insert(reasons, "the report holds cases that did not pass although every producer record passed")
	end
	local complete = scope.complete
	local verdict: GateTypes.Verdict
	if #failed > 0 or unaccounted then
		verdict = "failed"
	elseif not complete then
		verdict = "selected"
		table.insert(
			reasons,
			("%d of %d producer(s) were selected%s; this is not the complete gate"):format(
				#passed + #deferred,
				#records,
				if #scope.deselected > 0 then (" and %d case(s) were deselected"):format(#scope.deselected) else ""
			)
		)
	elseif #deferred > 0 then
		verdict = "deferred"
	else
		verdict = "release"
	end
	return {
		verdict = verdict,
		releasable = verdict == "release",
		complete = complete,
		reasons = reasons,
		passed = passed,
		failed = failed,
		deferred = deferred,
		reused = reused,
		notSelected = notSelected,
		skippedByTier = scope.skippedByTier,
		deselected = scope.deselected,
	}
end

local function copied(values: { string }?): { string }
	return table.clone(listed(values))
end

local function missingCases(records: { ProducerRecord }, requested: GateTypes.Selection): { string }
	local asked = listed(requested.cases)
	local found: { [string]: boolean } = {}
	for _, record in records do
		local skipped: { [string]: boolean } = {}
		for _, id in record.deselected do
			skipped[id] = true
		end
		for _, id in record.caseIds do
			if not skipped[id] and id ~= record.id then
				found[id] = true
				local prefix = record.id .. ":"
				if string.sub(id, 1, #prefix) == prefix then
					found[string.sub(id, #prefix + 1)] = true
				end
			end
		end
	end
	local missing: { string } = {}
	for _, id in asked do
		if not found[id] then
			table.insert(missing, id)
		end
	end
	if requested.nameContains ~= nil or #listed(requested.sources) > 0 then
		local ran = false
		for _, record in records do
			if record.kind == "tests" and record.status ~= "not_selected" then
				local skipped: { [string]: boolean } = {}
				for _, id in record.deselected do
					skipped[id] = true
				end
				for _, id in record.caseIds do
					if id ~= record.id and not skipped[id] then
						ran = true
					end
				end
			end
		end
		if not ran then
			local parts: { string } = {}
			if requested.nameContains ~= nil then
				table.insert(parts, ("name %q"):format(requested.nameContains))
			end
			if #listed(requested.sources) > 0 then
				table.insert(parts, "source " .. table.concat(requested.sources :: { string }, ","))
			end
			table.insert(missing, table.concat(parts, " "))
		end
	end
	return missing
end

local function scopeOf(
	gate: Gate,
	execution: Types.ExecutionReport,
	records: { ProducerRecord },
	resolved: Resolved,
	requested: GateTypes.Selection
): GateTypes.Scope
	local selected: { string } = {}
	local notSelected: { string } = {}
	local skippedByTier: { string } = {}
	local deselected: { string } = {}
	for _, record in records do
		if record.status == "not_selected" then
			table.insert(notSelected, record.id)
			if resolved.byTier[record.id] then
				table.insert(skippedByTier, record.id)
			end
		else
			table.insert(selected, record.id)
		end
		for _, id in record.deselected do
			table.insert(deselected, id)
		end
	end
	local complete = execution.provenance.complete and #deselected == 0
	local label = "complete"
	if not complete then
		local parts: { string } = {}
		local tiers = listed(requested.tiers)
		local ids = listed(requested.ids)
		local tags = listed(requested.tags)
		local cases = listed(requested.cases)
		if #tiers > 0 then
			table.insert(parts, "tier " .. table.concat(tiers, ","))
		end
		if #ids > 0 then
			table.insert(parts, "ids " .. table.concat(ids, ","))
		end
		if #tags > 0 then
			table.insert(parts, "tags " .. table.concat(tags, ","))
		end
		if #cases > 0 then
			table.insert(parts, "cases " .. table.concat(cases, ","))
		end
		if requested.nameContains ~= nil then
			table.insert(parts, ("name %q"):format(requested.nameContains))
		end
		if #listed(requested.sources) > 0 then
			table.insert(parts, "source " .. table.concat(listed(requested.sources), ","))
		end
		label = ("selected %s: %d of %d producers, %d not selected (%d by tier), %d case(s) deselected"):format(
			if #parts > 0 then table.concat(parts, "; ") else "run",
			#selected,
			#gate.producers,
			#notSelected,
			#skippedByTier,
			#deselected
		)
	end
	return {
		complete = complete,
		label = label,
		ids = copied(requested.ids),
		tiers = copied(requested.tiers),
		tags = copied(requested.tags),
		cases = copied(requested.cases),
		nameContains = requested.nameContains,
		sources = copied(requested.sources),
		selected = selected,
		notSelected = notSelected,
		skippedByTier = skippedByTier,
		deselected = deselected,
	}
end

local function run(gate: Gate, executor: GateTypes.Executor, options: GateTypes.RunOptions): GateTypes.Outcome
	if type(options) ~= "table" or type(options.runId) ~= "string" or options.runId == "" then
		error("a gate run needs a run id", 2)
	end
	if
		type(executor) ~= "table"
		or type(executor.now) ~= "function"
		or type(executor.wait) ~= "function"
		or type(executor.start) ~= "function"
	then
		error("a gate run needs an executor with now, wait and start", 2)
	end
	local offered: { [string]: GateTypes.Reuse } = if options.reuse ~= nil then options.reuse else {}
	for id in offered do
		producerOf(gate, id)
	end
	local resolved = resolve(gate, options.selection)
	local ids = resolved.ids
	local declared = Capability.sorted(options.capabilities, "gate capabilities")
	local name = options.name or "verify-gate"
	local environment: { [string]: string } = {}
	local supplied: { [string]: string } = if options.environment ~= nil then options.environment else {}
	for key, value in supplied do
		environment[key] = value
	end
	environment["verify.gate"] = gate.digest
	environment["verify.gateRun"] = options.runId
	if options.build ~= nil then
		environment["verify.build.commit"] = options.build.commit
		environment["verify.build.tree"] = options.build.tree
		environment["verify.build.clean"] = tostring(options.build.clean)
		environment["verify.build.digest"] = options.build.digest
	end
	local ctx: GateJob.Context = {
		runId = options.runId,
		executor = name,
		environment = environment,
		capabilities = declared,
		now = executor.now,
		deferrals = gate.policy.deferrals,
		logBytes = options.logBytes or DEFAULT_LOG_BYTES,
	}
	local records: { [string]: ProducerRecord } = {}
	local host: Execution.Host = {
		name = name,
		capabilities = declared,
		environment = environment,
		now = executor.now,
		runBatch = function(batch: Types.PlanBatch): Types.BatchOutcome
			local reports = schedule(gate, executor, options, ctx, batch.units, records)
			return { status = "returned", report = ReportModel.merge(reports, name, environment) }
		end,
	}
	local execution = Execution.execute(gate.plan, host, {
		selection = if ids ~= nil then { ids = ids } else nil,
		batchCount = 1,
		parallel = 1,
		fixtures = options.fixtures,
	})
	local selectedSet: { [string]: boolean } = {}
	local chosenIds: { string } = if ids ~= nil then ids else {}
	for _, id in chosenIds do
		selectedSet[id] = true
	end
	local list: { ProducerRecord } = {}
	for _, producer in gate.producers do
		local selected = ids == nil or selectedSet[producer.id] == true
		local record = records[producer.id]
		if record == nil then
			record = placeholder(producer, selected, declared, gate, execution, resolved.reasons[producer.id])
		end
		record.selected = selected
		record.pulledByDependency = resolved.pulled[producer.id] == true
		local reason = gate.policy.deferrals[producer.id]
		if record.status == "unsupported" and reason ~= nil then
			record.status = "deferred"
			record.deferral = reason
		end
		table.insert(list, record)
	end
	local requested: GateTypes.Selection = if options.selection ~= nil then options.selection else {}
	local scope = scopeOf(gate, execution, list, resolved, requested)
	return {
		schemaVersion = SCHEMA_VERSION,
		gate = gate.id,
		digest = gate.digest,
		runId = options.runId,
		build = options.build,
		scope = scope,
		execution = execution,
		producers = list,
		acceptance = accept(execution, list, scope, missingCases(list, requested)),
	}
end

local function format(outcome: GateTypes.Outcome): string
	local lines: { string } = {
		("gate %s run %s [%s]"):format(outcome.gate, outcome.runId, outcome.digest),
		"scope: " .. outcome.scope.label,
	}
	for _, record in outcome.producers do
		local flags: { string } = {}
		if record.reused then
			table.insert(flags, "reused")
		end
		if record.pulledByDependency then
			table.insert(flags, "dependency")
		end
		table.insert(
			lines,
			("  %-12s %s (%s)%s%s"):format(
				record.status,
				record.id,
				record.kind,
				if #flags > 0 then " [" .. table.concat(flags, ",") .. "]" else "",
				if record.status == "not_selected" then "" else (" %.2fs"):format(record.durationMicros / 1e6)
			)
		)
		if record.status ~= "passed" and record.status ~= "not_selected" and record.detail ~= nil then
			table.insert(lines, "      " .. record.detail)
		end
	end
	local acceptance = outcome.acceptance
	table.insert(
		lines,
		("verdict: %s%s"):format(acceptance.verdict, if acceptance.releasable then " (releasable)" else "")
	)
	if acceptance.verdict ~= "release" then
		for _, reason in acceptance.reasons do
			table.insert(lines, "  " .. reason)
		end
	end
	if #acceptance.skippedByTier > 0 then
		table.insert(
			lines,
			("skipped by tier (%d): %s"):format(#acceptance.skippedByTier, table.concat(acceptance.skippedByTier, ", "))
		)
	end
	if #acceptance.deselected > 0 then
		table.insert(
			lines,
			("deselected cases (%d): %s"):format(#acceptance.deselected, table.concat(acceptance.deselected, ", "))
		)
	end
	return table.concat(lines, "\n")
end

local function explain(outcome: GateTypes.Outcome, id: string): string?
	local lines: { string } = {}
	for _, record in outcome.producers do
		if record.id == id then
			table.insert(
				lines,
				("producer %s (%s%s): %s"):format(
					record.id,
					record.kind,
					if record.tier ~= nil then ", tier " .. record.tier else "",
					record.status
				)
			)
			if record.why ~= nil then
				table.insert(lines, "  why it exists: " .. record.why)
			end
			if not record.selected then
				table.insert(lines, "  " .. (record.detail or "not selected"))
			elseif record.pulledByDependency then
				table.insert(lines, "  selected because a selected producer runs after it")
			else
				table.insert(lines, "  selected by this run: " .. outcome.scope.label)
			end
			if record.selected and record.detail ~= nil then
				table.insert(lines, "  " .. record.detail)
			end
			if record.deferral ~= nil then
				table.insert(lines, "  deferred: " .. record.deferral)
			end
			if record.blockedBy ~= nil then
				table.insert(lines, "  blocked by " .. record.blockedBy)
			end
			if record.reused then
				table.insert(lines, "  reused from " .. tostring(record.reuseReference))
			end
			table.insert(lines, ("  %d case(s) reported, %d deselected"):format(#record.caseIds, #record.deselected))
			if record.log ~= nil and record.log.reference ~= nil then
				table.insert(lines, "  log: " .. record.log.reference)
			end
			return table.concat(lines, "\n")
		end
	end
	for _, result in outcome.execution.report.results do
		if result.id == id then
			table.insert(
				lines,
				("case %s%s: %s"):format(
					result.id,
					if result.source ~= nil then " [" .. result.source .. "]" else "",
					result.status
				)
			)
			for _, record in outcome.producers do
				if table.find(record.caseIds, id) ~= nil and record.id ~= id then
					table.insert(lines, ("  adopted by producer %s (%s)"):format(record.id, record.status))
				end
			end
			if result.skipReason ~= nil then
				table.insert(lines, "  skipped: " .. result.skipReason)
			end
			for _, failure in result.failures do
				table.insert(lines, ("  %s %s: %s"):format(failure.phase, failure.outcome, failure.message))
			end
			if #result.missingCapabilities > 0 then
				table.insert(lines, "  missing: " .. table.concat(result.missingCapabilities, ", "))
			end
			return table.concat(lines, "\n")
		end
	end
	return nil
end

local function list(gate: Gate): string
	local lines: { string } = {}
	for _, producer in gate.producers do
		table.insert(
			lines,
			("%-14s %-9s %-8s%s%s"):format(
				producer.id,
				producer.kind,
				if producer.tier ~= nil then producer.tier else "-",
				if #producer.after > 0 then " after " .. table.concat(producer.after, ",") else "",
				if producer.why ~= nil then "  " .. producer.why else ""
			)
		)
	end
	return table.concat(lines, "\n")
end

local function rerun(outcome: GateTypes.Outcome): GateTypes.Selection?
	local ids: { string } = {}
	local cases: { string } = {}
	local narrowable = true
	local byId: { [string]: Types.CaseResult } = {}
	for _, result in outcome.execution.report.results do
		byId[result.id] = result
	end
	for _, record in outcome.producers do
		if record.selected and record.status ~= "passed" and record.status ~= "deferred" then
			table.insert(ids, record.id)
			local before = #cases
			if record.kind == "tests" or record.kind == "command" then
				local prefix = if record.kind == "command" then record.id .. ":" else ""
				for _, caseId in record.caseIds do
					local result = byId[caseId]
					if
						result ~= nil
						and caseId ~= record.id
						and result.status ~= "passed"
						and result.status ~= "skipped"
					then
						table.insert(cases, string.sub(caseId, #prefix + 1))
					end
				end
			end
			if #cases == before then
				narrowable = false
			end
		end
	end
	if #ids == 0 then
		return nil
	end
	return { ids = ids, cases = if narrowable then cases else nil }
end

export type ShardOptions = {
	prefix: string,
	worker: string,
	count: number,
	mode: Types.BatchingMode?,
	silent: { string }?,
	tier: string?,
	tags: { string }?,
	requires: { string }?,
	deadlineSeconds: number?,
}

local function shard(plan: Types.PlanDraft, options: ShardOptions): { GateTypes.ProducerDraft }
	local silent: { [string]: boolean } = {}
	local declared: { string } = options.silent or {}
	for _, locator in declared do
		silent[locator] = true
	end
	local drafts: { GateTypes.ProducerDraft } = {}
	for _, batch in Plan.partition(plan, options.count, options.mode) do
		local locators: { string } = {}
		local quiet: { string } = {}
		for _, unit in batch.units do
			table.insert(locators, unit.locator)
			if silent[unit.locator] then
				table.insert(quiet, unit.locator)
			end
		end
		if #locators > 0 then
			table.insert(drafts, {
				id = ("%s-%d"):format(options.prefix, batch.index),
				kind = "tests",
				worker = options.worker,
				locators = locators,
				silent = quiet,
				tier = options.tier,
				tags = options.tags,
				requires = options.requires,
				deadlineSeconds = options.deadlineSeconds,
			})
		end
	end
	return drafts
end

local function testCases(outcome: GateTypes.Outcome): Report
	local own: { string } = {}
	for _, record in outcome.producers do
		if record.kind == "tests" then
			table.insert(own, record.id)
		end
	end
	return ReportModel.without(outcome.execution.report, own)
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	shard = shard,
	testCases = testCases,
	DEFAULT_COMMAND_DEADLINE = DEFAULT_COMMAND_DEADLINE,
	define = define,
	run = run,
	format = format,
	explain = explain,
	list = list,
	rerun = rerun,
}
