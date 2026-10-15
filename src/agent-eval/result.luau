--!strict

local Schema = require "./schema"

export type RunStatus = "completed" | "failed" | "timed_out" | "unsupported" | "blocked" | "provision_failed"

export type CaseOutcome = { id: string, status: string, detail: string? }

export type CheckResult = {
	id: string,
	check: string,
	device: string?,
	kind: string,
	required: boolean,
	status: string,
	passed: boolean,
	seconds: number?,
	detail: string?,
	cases: { CaseOutcome },
	scores: { [string]: number },
}

export type Capture = { device: string, label: string, path: string, sha256: string, size: number }

export type Audit = { device: string?, score: number, path: string, rules: { [string]: number } }

export type Metrics = {
	turns: number,
	messages: number,
	subagentMessages: number,
	inputTokens: number,
	cacheCreationTokens: number,
	cacheReadTokens: number,
	outputTokens: number,
	totalTokens: number,
	costUsd: number?,
	wallSeconds: number,
	agentSeconds: number?,
	apiSeconds: number?,
	toolSeconds: number?,
	startupSeconds: number?,
	turnLatencies: { number },
	turnIntervals: { number },
	toolCalls: number,
	toolErrors: number,
	permissionDenials: number,
}

export type Session = {
	model: string?,
	session: string?,
	version: string?,
	finish: string?,
	usageSource: string,
	tools: { string },
	mcpServers: { { name: string, status: string } },
	result: string?,
	malformed: number,
}

export type RunResult = {
	schemaVersion: number,
	id: string,
	digest: string,
	suite: string,
	task: string,
	tier: string,
	arm: string,
	agent: string,
	adapter: string,
	model: string?,
	seed: number,
	order: number,
	parent: string?,
	status: RunStatus,
	detail: string?,
	passed: boolean,
	checksPassed: boolean,
	exceeded: { string },
	metrics: Metrics,
	session: Session,
	checks: { CheckResult },
	scores: { [string]: number },
	audits: { Audit },
	captures: { Capture },
	timeToPassSeconds: number?,
	startedAt: number,
	finishedAt: number,
	directory: string,
}

export type IndexEntry = {
	id: string,
	path: string,
	task: string,
	arm: string,
	agent: string,
	seed: number,
	status: RunStatus,
	passed: boolean,
	reused: boolean,
}

export type Index = {
	schemaVersion: number,
	suite: string,
	runs: { IndexEntry },
}

local SCHEMA_VERSION = 1

local STATUSES: { [string]: RunStatus } = {
	completed = "completed",
	failed = "failed",
	timed_out = "timed_out",
	unsupported = "unsupported",
	blocked = "blocked",
	provision_failed = "provision_failed",
}

local function numbers(value: unknown, label: string): { number }
	local result: { number } = {}
	for index, item in Schema.list(value, label) do
		table.insert(result, Schema.number(item, ("%s[%d]"):format(label, index), 0))
	end
	return result
end

local function scores(value: unknown, label: string): { [string]: number }
	local result: { [string]: number } = {}
	if Schema.absent(value) then
		return result
	end
	for key, item in Schema.record(value, label) do
		result[key] = Schema.number(item, label .. "." .. key)
	end
	return result
end

local function status(value: unknown, label: string): RunStatus
	local name = Schema.text(value, label)
	local known = STATUSES[name]
	if known == nil then
		Schema.fail(label, "is not a run status")
	end
	return known :: RunStatus
end

local function decode(value: unknown): RunResult
	local raw = Schema.record(value, "result")
	if raw.schemaVersion ~= SCHEMA_VERSION then
		Schema.fail("result.schemaVersion", ("must be %d"):format(SCHEMA_VERSION))
	end
	local metricsRaw = Schema.record(raw.metrics, "result.metrics")
	local function count(key: string): number
		return Schema.number(metricsRaw[key], "result.metrics." .. key, 0)
	end
	local metrics: Metrics = {
		turns = count "turns",
		messages = count "messages",
		subagentMessages = count "subagentMessages",
		inputTokens = count "inputTokens",
		cacheCreationTokens = count "cacheCreationTokens",
		cacheReadTokens = count "cacheReadTokens",
		outputTokens = count "outputTokens",
		totalTokens = count "totalTokens",
		costUsd = Schema.optionalNumber(metricsRaw.costUsd, "result.metrics.costUsd", 0),
		wallSeconds = count "wallSeconds",
		agentSeconds = Schema.optionalNumber(metricsRaw.agentSeconds, "result.metrics.agentSeconds", 0),
		apiSeconds = Schema.optionalNumber(metricsRaw.apiSeconds, "result.metrics.apiSeconds", 0),
		toolSeconds = Schema.optionalNumber(metricsRaw.toolSeconds, "result.metrics.toolSeconds", 0),
		startupSeconds = Schema.optionalNumber(metricsRaw.startupSeconds, "result.metrics.startupSeconds", 0),
		turnLatencies = numbers(metricsRaw.turnLatencies, "result.metrics.turnLatencies"),
		turnIntervals = numbers(metricsRaw.turnIntervals, "result.metrics.turnIntervals"),
		toolCalls = count "toolCalls",
		toolErrors = count "toolErrors",
		permissionDenials = count "permissionDenials",
	}
	local sessionRaw: Schema.Record = if Schema.absent(raw.session)
		then {}
		else Schema.record(raw.session, "result.session")
	local servers: { { name: string, status: string } } = {}
	for index, item in Schema.list(sessionRaw.mcpServers, "result.session.mcpServers") do
		local entry = Schema.record(item, ("result.session.mcpServers[%d]"):format(index))
		table.insert(servers, {
			name = Schema.text(entry.name, "result.session.mcpServers.name"),
			status = if type(entry.status) == "string" then entry.status :: string else "",
		})
	end
	local session: Session = {
		model = Schema.optionalText(sessionRaw.model, "result.session.model"),
		session = Schema.optionalText(sessionRaw.session, "result.session.session"),
		version = Schema.optionalText(sessionRaw.version, "result.session.version"),
		finish = Schema.optionalText(sessionRaw.finish, "result.session.finish"),
		usageSource = Schema.optionalText(sessionRaw.usageSource, "result.session.usageSource") or "none",
		tools = Schema.texts(sessionRaw.tools, "result.session.tools"),
		mcpServers = servers,
		result = if type(sessionRaw.result) == "string" then sessionRaw.result :: string else nil,
		malformed = Schema.optionalNumber(sessionRaw.malformed, "result.session.malformed", 0) or 0,
	}
	local checks: { CheckResult } = {}
	for index, item in Schema.list(raw.checks, "result.checks") do
		local where = ("result.checks[%d]"):format(index)
		local entry = Schema.record(item, where)
		local cases: { CaseOutcome } = {}
		for caseIndex, caseItem in Schema.list(entry.cases, where .. ".cases") do
			local caseWhere = ("%s.cases[%d]"):format(where, caseIndex)
			local caseRaw = Schema.record(caseItem, caseWhere)
			table.insert(cases, {
				id = Schema.text(caseRaw.id, caseWhere .. ".id"),
				status = Schema.text(caseRaw.status, caseWhere .. ".status"),
				detail = Schema.optionalText(caseRaw.detail, caseWhere .. ".detail"),
			})
		end
		table.insert(checks, {
			id = Schema.text(entry.id, where .. ".id"),
			check = Schema.text(entry.check, where .. ".check"),
			device = Schema.optionalText(entry.device, where .. ".device"),
			kind = Schema.text(entry.kind, where .. ".kind"),
			required = Schema.flag(entry.required, where .. ".required", true),
			status = Schema.text(entry.status, where .. ".status"),
			passed = Schema.flag(entry.passed, where .. ".passed", false),
			seconds = Schema.optionalNumber(entry.seconds, where .. ".seconds", 0),
			detail = if type(entry.detail) == "string" then entry.detail :: string else nil,
			cases = cases,
			scores = scores(entry.scores, where .. ".scores"),
		})
	end
	local audits: { Audit } = {}
	for index, item in Schema.list(raw.audits, "result.audits") do
		local where = ("result.audits[%d]"):format(index)
		local entry = Schema.record(item, where)
		table.insert(audits, {
			device = Schema.optionalText(entry.device, where .. ".device"),
			score = Schema.number(entry.score, where .. ".score", 0),
			path = Schema.text(entry.path, where .. ".path"),
			rules = scores(entry.rules, where .. ".rules"),
		})
	end
	local captures: { Capture } = {}
	for index, item in Schema.list(raw.captures, "result.captures") do
		local where = ("result.captures[%d]"):format(index)
		local entry = Schema.record(item, where)
		table.insert(captures, {
			device = Schema.text(entry.device, where .. ".device"),
			label = Schema.text(entry.label, where .. ".label"),
			path = Schema.text(entry.path, where .. ".path"),
			sha256 = Schema.text(entry.sha256, where .. ".sha256"),
			size = Schema.number(entry.size, where .. ".size", 0, true),
		})
	end
	return {
		schemaVersion = SCHEMA_VERSION,
		id = Schema.text(raw.id, "result.id"),
		digest = Schema.text(raw.digest, "result.digest"),
		suite = Schema.text(raw.suite, "result.suite"),
		task = Schema.text(raw.task, "result.task"),
		tier = Schema.text(raw.tier, "result.tier"),
		arm = Schema.text(raw.arm, "result.arm"),
		agent = Schema.text(raw.agent, "result.agent"),
		adapter = Schema.text(raw.adapter, "result.adapter"),
		model = Schema.optionalText(raw.model, "result.model"),
		seed = Schema.number(raw.seed, "result.seed", 0, true),
		order = Schema.number(raw.order, "result.order", 0, true),
		parent = Schema.optionalText(raw.parent, "result.parent"),
		status = status(raw.status, "result.status"),
		detail = if type(raw.detail) == "string" then raw.detail :: string else nil,
		passed = Schema.flag(raw.passed, "result.passed", false),
		checksPassed = Schema.flag(raw.checksPassed, "result.checksPassed", false),
		exceeded = Schema.texts(raw.exceeded, "result.exceeded"),
		metrics = metrics,
		session = session,
		checks = checks,
		scores = scores(raw.scores, "result.scores"),
		audits = audits,
		captures = captures,
		timeToPassSeconds = Schema.optionalNumber(raw.timeToPassSeconds, "result.timeToPassSeconds", 0),
		startedAt = Schema.number(raw.startedAt, "result.startedAt"),
		finishedAt = Schema.number(raw.finishedAt, "result.finishedAt"),
		directory = Schema.text(raw.directory, "result.directory"),
	}
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	decode = decode,
}
