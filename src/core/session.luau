--!strict

local Capability = require "./capability"
local Harness = require "./harness"
local ReportModel = require "./report"
local Types = require "./types"

type Report = Types.Report
type Selection = Harness.Selection

export type Surface = { [string]: any }
export type SurfaceFactory = (harness: Harness.Harness) -> Surface

export type Options = {
	executor: string,
	environment: { [string]: string },
	capabilities: { string }?,
	now: (() -> number)?,
	surface: SurfaceFactory?,

	runtimeVerbs: { string }?,
	prefixCaseIds: boolean?,
	selection: Selection?,
}

export type Session = {
	verbs: Surface,
	open: (self: Session, source: string) -> (),
	close: (self: Session) -> (),
	current: (self: Session) -> Surface,
	harness: (self: Session) -> Harness.Harness,
	adoptReport: (self: Session, source: string, report: Report) -> (),
	sourceReport: (
		self: Session,
		id: string,
		source: string,
		status: "failed" | "skipped",
		detail: string
	) -> Report,
	setSelection: (self: Session, selection: Selection?) -> (),
	run: (self: Session) -> Report,
	reset: (self: Session) -> (),
}

type Entry = {
	source: string,
	harness: Harness.Harness?,
	surface: Surface?,
	report: Report?,
}

local DEFAULT_RUNTIME_VERBS: { string } = { "skip" }

local function create(options: Options): Session
	if type(options) ~= "table" or options.executor == "" then
		error("a session needs a non-empty executor", 2)
	end
	local executor = options.executor
	local environment = options.environment
	local capabilities = Capability.sorted(options.capabilities, "session capabilities")
	local now = options.now or function(): number
		return 0
	end
	local build: SurfaceFactory = options.surface
		or function(harness: Harness.Harness): Surface
			return harness :: any
		end
	local prefixCaseIds = options.prefixCaseIds == true
	local runtimeVerbs: { [string]: boolean } = {}
	for _, verb in options.runtimeVerbs or DEFAULT_RUNTIME_VERBS do
		runtimeVerbs[verb] = true
	end

	local session = {} :: Session
	local stack: { Entry } = {}
	local pending: { Entry } = {}
	local running: Entry? = nil
	local runInProgress = false
	local selection: Selection? = options.selection

	local function registering(): Entry
		local entry = stack[#stack]
		if entry == nil then
			error("a verification source registered outside an open session source", 3)
		end
		return entry
	end

	function session:current(): Surface
		return registering().surface :: Surface
	end

	function session:harness(): Harness.Harness
		return registering().harness :: Harness.Harness
	end

	session.verbs = setmetatable({}, {
		__index = function(_, verb: string): any
			return function(...): ...any
				local entry = if runtimeVerbs[verb] then (running or registering()) else registering()
				local surface = entry.surface :: Surface
				local callable = surface[verb]
				if type(callable) ~= "function" then
					error(("the session surface has no verb %q"):format(verb), 2)
				end
				return callable(...)
			end
		end,
	}) :: any

	function session:open(source: string)
		if source == "" then
			error("a session source must not be empty", 2)
		end
		local harness = Harness.createHarness { now = now, source = source, prefixIds = prefixCaseIds }
		table.insert(stack, { source = source, harness = harness, surface = build(harness), report = nil })
	end

	function session:close()
		local entry = table.remove(stack)
		if entry == nil then
			error("close with no open session source", 2)
		end
		table.insert(pending, entry)
	end

	function session:sourceReport(id: string, source: string, status: "failed" | "skipped", detail: string): Report
		if status == "skipped" then
			return Harness.syntheticReport {
				executor = executor,
				environment = environment,
				capabilities = capabilities,
				id = id,
				source = source,
				name = source,
				status = "skipped",
				skipReason = detail,
			}
		end
		return Harness.syntheticReport {
			executor = executor,
			environment = environment,
			capabilities = capabilities,
			id = id,
			source = source,
			name = source,
			status = "failed",
			phase = "load",
			message = detail,
		}
	end

	function session:adoptReport(source: string, report: Report)
		table.insert(pending, { source = source, harness = nil, surface = nil, report = report })
	end

	function session:setSelection(value: Selection?)
		selection = value
	end

	local function stamp(report: Report, source: string): Report
		for _, result in report.results do
			if result.source == nil then
				result.source = source
			end
		end
		return report
	end

	local function runQueued(queued: { Entry }): Report
		local reports: { Report } = {}
		for _, entry in queued do
			local adopted = entry.report
			if adopted ~= nil then
				table.insert(reports, stamp(adopted, entry.source))
				continue
			end
			running = entry
			local ok, produced: any = pcall(function(): Report
				return (entry.harness :: Harness.Harness):run {
					executor = executor,
					capabilities = capabilities,
					environment = environment,
					selection = selection,
				}
			end)
			running = nil
			if not ok then
				error(produced, 0)
			end
			table.insert(reports, stamp(produced :: Report, entry.source))
		end
		return ReportModel.merge(reports, executor, environment)
	end

	function session:run(): Report
		if runInProgress then
			error("a session run is already in progress", 2)
		end
		runInProgress = true

		local ok, produced: any = pcall(runQueued, table.clone(pending))
		running = nil
		runInProgress = false
		if not ok then
			error(produced, 0)
		end
		return produced :: Report
	end

	function session:reset()
		if runInProgress then
			error("a session cannot be reset while its run is in progress", 2)
		end
		table.clear(stack)
		table.clear(pending)
		running = nil
	end

	return session
end

return {
	create = create,
	DEFAULT_RUNTIME_VERBS = DEFAULT_RUNTIME_VERBS,
}
