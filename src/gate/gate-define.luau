--!strict

local Benchmark = require "../benchmark"
local Capability = require "../core/capability"
local GateJob = require "./gate-job"
local GateTypes = require "./gate-types"
local Plan = require "../core/plan"
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
			local declared = ordered(draft.cases, label .. ".cases")
			cases = declared
			if #declared == 0 then
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
						return producer.collection.name
							.. ":"
							.. table.concat(members, ",")
							.. (
								if (producer.collection.calibrationAttempts or 1) > 1
									then `:calibrationAttempts={producer.collection.calibrationAttempts}`
									else ""
							)
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

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	DEFAULT_LOG_BYTES = DEFAULT_LOG_BYTES,
	define = define,
}
