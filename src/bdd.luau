--!strict

local Verify = require "./core"

type Context = Verify.Context
type Expectation = Verify.Expectation
type Harness = Verify.Harness

export type Spy = Verify.Spy

export type Own = (cleanup: () -> ()) -> ()
export type Body = (own: Own, context: Context) -> ()
export type CaseDefinition = {
	timeoutSeconds: number?,
	cleanupTimeoutSeconds: number?,
	run: Body,
	id: string?,
	requires: { string }?,
	tags: { string }?,
	limitations: { string }?,
}

export type Bdd = {
	describe: (name: string, register: () -> ()) -> (),
	it: (name: string, body: Body | CaseDefinition) -> (),
	itSkip: (name: string, reason: string, body: Body?) -> (),
	beforeEach: (body: Body) -> (),
	afterEach: (body: Body) -> (),
	expect: (value: unknown) -> Expectation,
	spy: typeof(Verify.spy),
	skip: (reason: string) -> never,
}

local function create(harness: Harness): Bdd
	local bdd = {} :: Bdd
	local activeContext: Context? = nil

	local function adapt(body: Body): (Context) -> ()
		return function(context: Context)
			local previous = activeContext
			activeContext = context
			local ok, message = pcall(function(): unknown
				body(function(cleanup: () -> ())
					context:defer(cleanup)
				end, context)
				return nil
			end)
			activeContext = previous
			if not ok then
				error(message, 0)
			end
		end
	end

	function bdd.describe(name: string, register: () -> ())
		harness:suite(name, register)
	end

	function bdd.it(name: string, definition: Body | CaseDefinition)
		if type(definition) == "function" then
			harness:case(name, adapt(definition))
			return
		end
		harness:case(name, {
			id = definition.id,
			timeoutSeconds = definition.timeoutSeconds,
			cleanupTimeoutSeconds = definition.cleanupTimeoutSeconds,
			run = adapt(definition.run),
			requires = definition.requires,
			tags = definition.tags,
			limitations = definition.limitations,
		})
	end

	function bdd.itSkip(name: string, reason: string, body: Body?)
		local adapted = if body ~= nil then adapt(body) else nil
		harness:skip(name, reason, adapted)
	end

	function bdd.beforeEach(body: Body)
		harness:beforeEach(adapt(body))
	end

	function bdd.afterEach(body: Body)
		harness:afterEach(adapt(body))
	end

	function bdd.expect(value: unknown): Expectation
		return Verify.expect(value)
	end

	bdd.spy = Verify.spy

	function bdd.skip(reason: string): never
		local context = activeContext
		if context == nil then
			error("BDD skip must be called while a case or hook is running", 2)
		end
		return context:skip(reason)
	end

	return bdd
end

export type Report = Verify.Report
export type CaseResult = Verify.CaseResult

export type SurfaceOptions = {
	bind: ((Context) -> Verify.CaseHost)?,
	cancelled: (() -> boolean)?,
	executor: string,
	environment: { [string]: string },
	capabilities: { string },
	ambientSource: string,
	now: (() -> number)?,
	selection: Verify.Selection?,
}

export type Surface = {
	describe: (name: string, register: () -> ()) -> (),
	it: (name: string, body: Body | CaseDefinition) -> (),
	itSkip: (name: string, reason: string, body: Body?) -> (),
	beforeEach: (body: Body) -> (),
	afterEach: (body: Body) -> (),
	skip: (reason: string) -> never,
	expect: (value: unknown, ...unknown) -> Expectation,
	spy: typeof(Verify.spy),
	float32: (value: number) -> number,
	open: (source: string) -> (),
	close: () -> (),
	load: (source: string, register: () -> ()) -> string?,
	adoptReport: (source: string, report: Report) -> (),
	sourceReport: (id: string, source: string, status: "failed" | "skipped", detail: string) -> Report,
	run: () -> Report,
	setSelection: (selection: Verify.Selection?) -> (),
	reset: () -> (),
	useHarness: (harness: Harness, run: () -> ()) -> (),
}

local REGISTRATION_VERBS: { string } = { "describe", "it", "itSkip", "beforeEach", "afterEach" }

local function surface(options: SurfaceOptions): Surface
	local api = {} :: Surface
	local sessionOptions: Verify.SessionProvidedOptions<Bdd> = {
		executor = options.executor,
		bind = options.bind,
		cancelled = options.cancelled,
		environment = options.environment,
		capabilities = options.capabilities,
		now = options.now or os.clock,
		surface = create,
		runtimeVerbs = { "skip" },
		prefixCaseIds = false,
		selection = options.selection,
	}
	local session = Verify.createSession(sessionOptions)
	local depth = 0
	local ambientOpen = false
	local activeOverride: Bdd? = nil

	local function registering(): Bdd
		if activeOverride ~= nil then
			return activeOverride
		end
		if depth == 0 then
			session:open(options.ambientSource)
			depth += 1
			ambientOpen = true
		end
		return session:current()
	end
	api.describe = function(name, run)
		registering().describe(name, run)
	end
	api.it = function(name, definition)
		registering().it(name, definition)
	end
	api.itSkip = function(name, reason, run)
		registering().itSkip(name, reason, run)
	end
	api.beforeEach = function(run)
		registering().beforeEach(run)
	end
	api.afterEach = function(run)
		registering().afterEach(run)
	end

	function api.useHarness(harness: Harness, run: () -> ())
		assert(activeOverride == nil, "surface useHarness() is not reentrant")
		activeOverride = create(harness)
		local ok, thrown: unknown = pcall(run)
		activeOverride = nil
		if not ok then
			error(thrown, 0)
		end
	end

	function api.skip(reason: string): never
		return session.verbs.skip(reason)
	end

	api.expect = Verify.expect
	api.spy = Verify.spy
	api.float32 = Verify.float32

	function api.open(source: string)
		session:open(source)
		depth += 1
	end

	function api.close()
		assert(depth > 0, "surface close() with no open source")
		session:close()
		depth -= 1
	end

	function api.load(source: string, register: () -> ()): string?
		api.open(source)
		local ok, thrown: unknown = pcall(register)
		api.close()
		if ok then
			return nil
		end
		local message = tostring(thrown)
		session:adoptReport(source, session:sourceReport("source:" .. source .. ":load", source, "failed", message))
		return message
	end

	function api.adoptReport(source: string, report: Report)
		session:adoptReport(source, report)
	end

	function api.sourceReport(id: string, source: string, status: "failed" | "skipped", detail: string): Report
		return session:sourceReport(id, source, status, detail)
	end

	function api.run(): Report
		if ambientOpen then
			session:close()
			depth -= 1
			ambientOpen = false
		end
		return session:run()
	end

	function api.setSelection(selection: Verify.Selection?)
		session:setSelection(selection)
	end

	function api.reset()
		session:reset()
		depth = 0
		ambientOpen = false
	end

	return api
end

local function label(result: CaseResult): string
	local path = table.concat(result.path, " › ")
	return if path ~= "" then path .. " › " .. result.name else result.name
end

local function detailLines(result: CaseResult, lines: { string })
	if result.status == "skipped" and result.skipReason ~= nil then
		table.insert(lines, "    SKIPPED: " .. result.skipReason)
		return
	end
	if result.status == "unsupported" then
		table.insert(lines, "    UNSUPPORTED: missing " .. table.concat(result.missingCapabilities, ", "))
		return
	end
	for _, failure in result.failures do
		local prefix = if failure.phase == "case" then "" else failure.phase .. ": "
		for line in string.gmatch(prefix .. failure.message, "([^\n]+)") do
			table.insert(lines, "    " .. line)
		end
	end
end

local function counts(report: Report): (number, number, number)
	local failed = report.failed + report.unsupported + report.timedOut + report.cancelled
	return report.passed, failed, report.skipped
end

local function summary(report: Report, lines: { string })
	local passed, failed, skipped = counts(report)
	table.insert(lines, "")
	table.insert(
		lines,
		("Tests:  %d passed, %d failed, %d skipped (%d total)"):format(
			passed,
			failed,
			skipped,
			passed + failed + skipped
		)
	)
	table.insert(lines, ("Time:   %.2fms"):format(report.durationMicros / 1000))
end

local function formatResults(report: Report, title: string?): string
	local lines = { title or "Verify" }
	for _, result in report.results do
		local glyph = if result.status == "skipped" then "⊘" elseif result.status == "passed" then "✓" else "✗"
		table.insert(lines, ("%s %s (%.2fms)"):format(glyph, label(result), result.durationMicros / 1000))
		detailLines(result, lines)
	end
	summary(report, lines)
	return table.concat(lines, "\n")
end

local function formatFailures(report: Report, title: string?): string
	local lines = { title or "Verify" }
	for _, result in report.results do
		if result.status ~= "passed" then
			table.insert(lines, ("✗ %s (%.2fms)"):format(label(result), result.durationMicros / 1000))
			detailLines(result, lines)
		end
	end
	summary(report, lines)
	return table.concat(lines, "\n")
end

return {
	create = create,
	surface = surface,
	REGISTRATION_VERBS = REGISTRATION_VERBS,
	counts = counts,
	formatResults = formatResults,
	formatFailures = formatFailures,
}
