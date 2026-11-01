--!strict

local Capability = require "./capability"
local Harness = require "./harness"
local ReportModel = require "./report"
local Types = require "./types"
local Operations = require "./operations"

type Report = Types.Report
type Selection = Harness.Selection

export type Surface = { [string]: unknown }
export type SurfaceFactory<S = Surface> = (harness: Harness.Harness) -> S

export type ProvidedOptions<S> = {
	executor: string,
	bind: ((Harness.Context) -> Operations.Host)?,
	cancelled: (() -> boolean)?,
	environment: { [string]: string },
	capabilities: { string }?,
	now: (() -> number)?,
	surface: SurfaceFactory<S>,
	prefixCaseIds: boolean?,
	selection: Selection?,
}

export type DefaultOptions = {
	executor: string,
	bind: ((Harness.Context) -> Operations.Host)?,
	cancelled: (() -> boolean)?,
	environment: { [string]: string },
	capabilities: { string }?,
	now: (() -> number)?,
	prefixCaseIds: boolean?,
	selection: Selection?,
}

export type Session<S = Harness.Harness> = {
	open: (self: Session<S>, source: string) -> (),
	close: (self: Session<S>) -> (),
	current: (self: Session<S>) -> S,
	active: (self: Session<S>) -> S,
	harness: (self: Session<S>) -> Harness.Harness,
	adoptReport: (self: Session<S>, source: string, report: Report) -> (),
	sourceReport: (
		self: Session<S>,
		id: string,
		source: string,
		status: "failed" | "skipped",
		detail: string
	) -> Report,
	setSelection: (self: Session<S>, selection: Selection?) -> (),
	run: (self: Session<S>) -> Report,
	reset: (self: Session<S>) -> (),
}

type Registered<S> = {
	source: string,
	harness: Harness.Harness,
	surface: S,
	report: nil,
}

type Entry<S> = Registered<S> | {
	source: string,
	harness: nil,
	surface: nil,
	report: Report,
}

local function createSurface<S>(options: ProvidedOptions<S>): Session<S>
	if type(options) ~= "table" or options.executor == "" then
		error("a session needs a non-empty executor", 2)
	end
	local executor = options.executor
	local environment = options.environment
	local capabilities = Capability.sorted(options.capabilities, "session capabilities")
	local now = options.now or function(): number
		return 0
	end
	local build = options.surface
	local prefixCaseIds = options.prefixCaseIds == true
	local stack: { Registered<S> } = {}
	local pending: { Entry<S> } = {}
	local running: Entry<S>? = nil
	local runInProgress = false
	local selection: Selection? = options.selection

	local function registering(): Registered<S>
		local entry = stack[#stack]
		if entry == nil then
			error("a verification source registered outside an open session source", 3)
		end
		return entry
	end

	local function current(_self: Session<S>): S
		return registering().surface
	end

	local function active(_self: Session<S>): S
		if running ~= nil then
			local surface = running.surface
			assert(surface ~= nil)
			return surface
		end
		return registering().surface
	end

	local function harness(_self: Session<S>): Harness.Harness
		return registering().harness
	end

	local function open(_self: Session<S>, source: string)
		if source == "" then
			error("a session source must not be empty", 2)
		end
		local harness = Harness.createHarness { now = now, source = source, prefixIds = prefixCaseIds }
		table.insert(stack, { source = source, harness = harness, surface = build(harness), report = nil })
	end

	local function close(_self: Session<S>)
		local entry = table.remove(stack)
		if entry == nil then
			error("close with no open session source", 2)
		end
		table.insert(pending, entry)
	end

	local function sourceReport(
		_self: Session<S>,
		id: string,
		source: string,
		status: "failed" | "skipped",
		detail: string
	): Report
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

	local function adoptReport(_self: Session<S>, source: string, report: Report)
		table.insert(pending, { source = source, harness = nil, surface = nil, report = report })
	end

	local function setSelection(_self: Session<S>, value: Selection?)
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

	local function runQueued(queued: { Entry<S> }): Report
		local reports: { Report } = {}
		for _, entry in queued do
			local adopted = entry.report
			if adopted ~= nil then
				table.insert(reports, stamp(adopted, entry.source))
				continue
			end
			running = entry
			local ok, produced = pcall(function(): Report
				local harness = entry.harness
				assert(harness ~= nil)
				return harness:run {
					executor = executor,
					capabilities = capabilities,
					environment = environment,
					selection = selection,
					bind = options.bind,
					cancelled = options.cancelled,
				}
			end)
			running = nil
			if not ok then
				error(produced, 0)
			end
			table.insert(reports, stamp(produced, entry.source))
		end
		return ReportModel.merge(reports, executor, environment)
	end

	local function run(_self: Session<S>): Report
		if runInProgress then
			error("a session run is already in progress", 2)
		end
		runInProgress = true

		local ok, produced = pcall(runQueued, table.clone(pending))
		running = nil
		runInProgress = false
		if not ok then
			error(produced, 0)
		end
		return produced
	end

	local function reset(_self: Session<S>)
		if runInProgress then
			error("a session cannot be reset while its run is in progress", 2)
		end
		table.clear(stack)
		table.clear(pending)
		running = nil
	end

	return {
		current = current,
		active = active,
		harness = harness,
		open = open,
		close = close,
		sourceReport = sourceReport,
		adoptReport = adoptReport,
		setSelection = setSelection,
		run = run,
		reset = reset,
	}
end

local function create(options: DefaultOptions): Session<Harness.Harness>
	return createSurface {
		executor = options.executor,
		bind = options.bind,
		cancelled = options.cancelled,
		environment = options.environment,
		capabilities = options.capabilities,
		now = options.now,
		prefixCaseIds = options.prefixCaseIds,
		selection = options.selection,
		surface = function(harness: Harness.Harness): Harness.Harness
			return harness
		end,
	}
end

return { create = create, createSurface = createSurface }
