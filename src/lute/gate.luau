--!strict

local LuteRuntime = require "./runtime"
local Bounded = require "./bounded"
local Files = require "./files"
local Host = require "./host"
local Verify = require "../core"
local Cli = require "./gate-cli"
local Gate = require "../gate"
local Wire = require "./wire"

type Runtime = LuteRuntime.Runtime

export type Options = {
	runId: string?,
	directory: string?,
	build: Verify.EvidenceBuild?,
	selection: Gate.Selection?,
	reuse: { [string]: Gate.Reuse }?,
	capabilities: { string }?,
	environment: { [string]: string }?,
	name: string?,
	logBytes: number?,
	pollSeconds: number?,
	observe: ((record: Gate.Record) -> ())?,
	command: { string }?,
	now: (() -> number)?,
	wait: ((seconds: number) -> ())?,
	fixtures: { { name: string, acquire: () -> (), release: (() -> ())? } }?,
}

export type CliOptions = {
	options: Options?,
	usage: string?,
}

export type Gate = {
	DEFAULT_DIRECTORY: string,
	run: (gate: Gate.Definition, options: Options?) -> Gate.Outcome,
	writeReport: (path: string, runId: string, report: Verify.Report) -> (),
	last: (gate: Gate.Definition, options: Options?) -> (Gate.Outcome?, string?),
	cli: (draft: Gate.Draft, args: { string }, options: CliOptions?) -> number,
}

local function capabilities(runtime: Runtime?): { string }
	local declared = { "local-luau", "process" }
	for _, capability in Bounded.capabilities(if runtime ~= nil then runtime.bounded else nil) do
		table.insert(declared, capability)
	end
	return declared
end

local sequence = 0

local function safeName(id: string): string
	return (string.gsub(id, "[^%w%-_]", "-"))
end

local function substitute(argv: { string }, reportPath: string, job: Gate.Job): { string }
	local result: { string } = {}
	for _, value in argv do
		local replaced = string.gsub(value, "{report}", function()
			return reportPath
		end)
		replaced = string.gsub(replaced, "{run}", function()
			return job.runId
		end)
		replaced = string.gsub(replaced, "{tier}", function()
			return table.concat(job.tiers, ",")
		end)
		replaced = string.gsub(replaced, "{cases}", function()
			return table.concat(job.cases, ",")
		end)
		table.insert(result, replaced)
	end
	return result
end

local function create(runtime: Runtime): Gate
	local defaults = capabilities(runtime)
	local files = Files.create(runtime.fs)

	local function newRunId(): string
		sequence += 1
		return ("gate-%d-%d-%d"):format(os.time(), math.floor(runtime.time.clock() * 1e6) % 1000000, sequence)
	end

	local function writeReport(path: string, runId: string, report: Verify.Report)
		assert(runId ~= "", "a gate report needs the run id it was started with")
		runtime.fs.write(path, Wire.encode { runId = runId, report = Verify.decode(report) })
	end

	local function executor(options: Options, directory: string, runId: string): Gate.Executor
		local now = options.now or runtime.time.clock
		local wait = options.wait or runtime.time.wait
		files.ensureDirectory(directory)

		local function start(job: Gate.Job): Gate.Task
			local stem = ("%s/%s"):format(directory, safeName(job.id))
			local result: Gate.JobOutcome? = nil
			local poll = function(): Gate.JobOutcome?
				return result
			end
			if job.kind == "tests" then
				local units: { Verify.PlanUnitDraft } = {}
				for _, locator in job.locators do
					table.insert(units, { id = job.id .. ":" .. locator, locator = locator })
				end
				local host = Host.create({
					worker = job.worker :: string,
					command = job.command or options.command,
					directory = stem .. "-worker",
					deadlineSeconds = job.deadlineSeconds,
					name = "verify-gate-tests",
					arguments = job.args,
				}, runtime)
				local started = runtime.time.clock()
				local reports: { Verify.Report } = {}
				local runBatch = host.runBatch
				host.runBatch = function(batch)
					local remaining = job.deadlineSeconds - (runtime.time.clock() - started)
					if remaining <= 0 then
						return { status = "timed_out", detail = "not started: the producer deadline elapsed" }
					end
					local bounded = table.clone(batch)
					bounded.deadlineSeconds = math.min(remaining, batch.deadlineSeconds or remaining)
					local outcome = runBatch(bounded)
					if job.isolate and outcome.status == "returned" and outcome.report ~= nil then
						table.insert(reports, Verify.decode(outcome.report))
					end
					return outcome
				end
				runtime.time.spawn(function()
					local plan: Verify.PlanDraft = {
						id = job.id,
						units = units,
						policy = {
							batchCount = if job.isolate then #units else 1,
							maxParallelBatches = if job.isolate then job.workers else 1,
							deadlineSeconds = if job.isolate
								then job.sourceDeadlineSeconds or job.deadlineSeconds
								else job.deadlineSeconds,
							runDeadlineSeconds = job.deadlineSeconds,
							caseIdStyle = "bare",
						},
					}
					local ran, execution: unknown = pcall(function()
						local execution = Verify.execute(plan, host)
						if job.isolate then
							Verify.merge(reports, host.name, host.environment)
						end
						return execution
					end)
					result = {
						started = ran,
						exitcode = if ran then 0 else -1,
						timedOut = false,
						stdout = "",
						stderr = "",
						report = if ran then (execution :: Verify.ExecutionReport).report else nil,
						detail = if ran then nil else tostring(execution),
					}
				end)
				return { poll = poll }
			end

			local reportPath = stem .. ".report.json"
			local logPath = stem .. ".log"
			files.removeIfPresent(reportPath)
			files.removeIfPresent(logPath)
			local argv = substitute(job.argv, reportPath, job)
			runtime.time.spawn(function()
				local ran = Bounded.runWith(
					argv,
					job.deadlineSeconds,
					runtime.process.run,
					{ env = job.env, cwd = job.cwd },
					runtime.bounded
				)
				local started = ran.exitcode ~= -1 or ran.stderr == ""
				local document: unknown = nil
				local detail: string? = if started then nil else ran.stderr
				if started and not ran.timedOut and runtime.fs.exists(reportPath) then
					local read, text: unknown = pcall(runtime.fs.read, reportPath)
					if read then
						local parsed, value: unknown = pcall(Wire.parse, text :: string)
						if parsed then
							document = value
						else
							detail = "the report file is unreadable: " .. tostring(value)
						end
					else
						detail = "the report file could not be read: " .. tostring(text)
					end
				elseif started and job.expectsReport and not ran.timedOut then
					detail = "no report file was written"
				end
				local logged = pcall(
					runtime.fs.write,
					logPath,
					("$ %s\nexit %d%s\n--- stdout ---\n%s\n--- stderr ---\n%s\n"):format(
						table.concat(argv, " "),
						ran.exitcode,
						if ran.timedOut then " (deadline exceeded)" else "",
						ran.stdout,
						ran.stderr
					)
				)
				result = {
					started = started,
					exitcode = ran.exitcode,
					timedOut = ran.timedOut,
					stdout = ran.stdout,
					stderr = if started then ran.stderr else "",
					report = document,
					detail = detail,
					logReference = if logged then logPath else nil,
				}
			end)
			return { poll = poll }
		end

		return { now = now, wait = wait, start = start }
	end

	local function baseOf(settings: Options): string
		return settings.directory or ".lute/tmp/verify/gate"
	end

	local function run(gate: Gate.Definition, options: Options?): Gate.Outcome
		local settings: Options = if options ~= nil then options else {}
		local runId = settings.runId or newRunId()
		local directory = ("%s/%s"):format(baseOf(settings), safeName(runId))
		local declared: { string } = table.clone(defaults)
		local extra: { string } = if settings.capabilities ~= nil then settings.capabilities else {}
		for _, capability in extra do
			table.insert(declared, capability)
		end
		local environment: { [string]: string } = { runtime = "lute" }
		local supplied: { [string]: string } = if settings.environment ~= nil then settings.environment else {}
		for key, value in supplied do
			environment[key] = value
		end
		local outcome = Gate.run(gate, executor(settings, directory, runId), {
			runId = runId,
			build = settings.build,
			selection = settings.selection,
			reuse = settings.reuse,
			capabilities = declared,
			environment = environment,
			name = settings.name,
			logBytes = settings.logBytes,
			pollSeconds = settings.pollSeconds,
			observe = settings.observe,
			fixtures = settings.fixtures,
		})
		local encoded = Wire.encode(outcome)
		runtime.fs.write(directory .. "/outcome.json", encoded)
		runtime.fs.write(baseOf(settings) .. "/latest.json", encoded)
		return outcome
	end

	local function last(gate: Gate.Definition, options: Options?): (Gate.Outcome?, string?)
		local path = baseOf(if options ~= nil then options else {}) .. "/latest.json"
		if not runtime.fs.exists(path) then
			return nil, "no earlier outcome at " .. path
		end
		local parsed, value: unknown = pcall(function(): unknown
			return Wire.parse(runtime.fs.read(path))
		end)
		if not parsed or type(value) ~= "table" then
			return nil, "the earlier outcome is unreadable"
		end
		local outcome = value :: Gate.Outcome
		if outcome.gate ~= gate.id or outcome.digest ~= gate.digest then
			return nil, "the earlier outcome belongs to another gate definition"
		end
		local decoded, report: unknown = pcall(Verify.decode, outcome.execution.report)
		if not decoded then
			return nil, "the earlier outcome holds an invalid report: " .. tostring(report)
		end
		outcome.execution.report = report :: Verify.Report
		return outcome, nil
	end

	local function cli(draft: Gate.Draft, args: { string }, cliOptions: CliOptions?): number
		local settings: CliOptions = if cliOptions ~= nil then cliOptions else {}
		local base: Options = if settings.options ~= nil then table.clone(settings.options) else {}
		local say = runtime.stdio.print
		local command, problem = Cli.parse(args)
		if command == nil then
			say(tostring(problem))
			say(settings.usage or Cli.USAGE)
			return 2
		end
		local only = table.clone(command.only)
		local narrowed, absent = Cli.narrow(draft, command.files, only)
		if narrowed == nil then
			say(tostring(absent))
			return 2
		end
		local gate = Gate.define(narrowed)
		if command.list then
			say(Gate.list(gate))
			return 0
		end
		local previous, missing = last(gate, base)
		if command.explain ~= nil then
			if previous == nil then
				say(tostring(missing))
				return 1
			end
			say(
				Gate.explain(previous, command.explain)
					or ("nothing named " .. command.explain .. " in the last outcome")
			)
			return 0
		end
		local selection: Gate.Selection? = nil
		if command.rerun then
			if previous == nil then
				say(tostring(missing))
				return 1
			end
			selection = Gate.rerun(previous)
			if selection == nil then
				say "gate: the last outcome has nothing to rerun"
				return 0
			end
		elseif #only > 0 or #command.tiers > 0 or #command.cases > 0 or command.name ~= nil then
			selection = {
				ids = if #only > 0 then only else nil,
				tiers = if #command.tiers > 0 then command.tiers else nil,
				cases = if #command.cases > 0 then command.cases else nil,
				nameContains = command.name,
			}
		end
		base.selection = selection
		if base.observe == nil then
			base.observe = function(record: Gate.Record)
				say(("-> %-12s %s"):format(record.status, record.id))
			end
		end
		local outcome = run(gate, base)
		for _, record in outcome.producers do
			if record.status ~= "passed" and record.status ~= "not_selected" and record.status ~= "deferred" then
				say(("\n== %s: %s"):format(record.id, record.status))
				if record.detail ~= nil then
					say(record.detail)
				end
				if record.log ~= nil then
					say(record.log.stdout)
					say(record.log.stderr)
				end
			end
		end
		for _, result in outcome.execution.report.results do
			if result.status ~= "passed" and result.status ~= "skipped" and result.status ~= "unsupported" then
				say(
					("case %s: %s %s"):format(
						result.id,
						result.status,
						if result.failures[1] ~= nil then result.failures[1].message else ""
					)
				)
			end
		end
		say(Gate.format(outcome))
		local verdict = outcome.acceptance.verdict
		if verdict == "failed" then
			say(("gate: FAILED (%d producer(s))"):format(#outcome.acceptance.failed))
			return 1
		elseif verdict == "selected" then
			say(("gate: NARROWED run passed (%d producer(s)); this is not the gate"):format(#outcome.acceptance.passed))
		elseif verdict == "deferred" then
			say(
				("gate: PASSED (%d producer(s); deferred: %s)"):format(
					#outcome.acceptance.passed,
					table.concat(outcome.acceptance.deferred, ", ")
				)
			)
		else
			say(("gate: PASSED (%d producer(s))"):format(#outcome.acceptance.passed))
		end
		return 0
	end

	return {
		cli = cli,
		DEFAULT_DIRECTORY = baseOf {},
		run = run,
		writeReport = writeReport,
		last = last,
	}
end

local bound = create(LuteRuntime)

return {
	create = create,
	cli = bound.cli,
	DEFAULT_DIRECTORY = bound.DEFAULT_DIRECTORY,
	run = bound.run,
	writeReport = bound.writeReport,
	last = bound.last,
}
