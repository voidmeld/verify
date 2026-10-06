--!strict

local Batch = require "./batch"
local Binding = require "./binding"
local Bounded = require "./bounded"
local Files = require "./files"
local Receipt = require "./receipt"
local Verify = require "../core"
local Wire = require "./wire"

type BatchOutcome = Verify.BatchOutcome
type PlanBatch = Verify.PlanBatch

export type Options = {
	deadlineSeconds: number?,

	worker: string,
	command: { string }?,
	directory: string?,
	name: string?,
	capabilities: { string }?,
	environment: { [string]: string }?,
	maxParallelBatches: number?,
	now: (() -> number)?,
	cancelled: (() -> boolean)?,
	receipts: ("report" | "bound")?,
	arguments: { string }?,
}

local DEFAULT_CAPABILITIES = { "local-luau", "worker", Bounded.CAPABILITY }

local runSequence = 0

local function safeName(id: string): string
	return (string.gsub(id, "[^%w%-_]", "-"))
end

local function recordsLoadFailure(report: unknown): boolean
	if type(report) ~= "table" then
		return false
	end
	local results = (report :: { [string]: unknown }).results
	if type(results) ~= "table" then
		return false
	end
	for _, result in results :: { unknown } do
		if type(result) == "table" then
			local row = result :: { [string]: unknown }
			if
				type(row.id) == "string"
				and string.match(row.id :: string, "^unit:.+:load$") ~= nil
				and row.status ~= "passed"
			then
				return true
			end
		end
	end
	return false
end

local function create(runtime: Binding.Runtime, options: Options): Verify.Host
	Binding.validate(runtime)
	if type(options) ~= "table" or type(options.worker) ~= "string" or options.worker == "" then
		error("the host needs the path of a worker to start", 2)
	end
	local name = options.name or runtime.name
	local capabilities = options.capabilities or DEFAULT_CAPABILITIES
	local environment = options.environment or { runtime = runtime.name }
	local directory = options.directory or runtime.defaultDirectory
	local command = options.command or runtime.defaultCommand
	local bound = options.receipts == "bound"
	local files = Files.create(runtime.fs)
	local batches = Batch.create(runtime.json)
	local wire = Wire.create(runtime.json)

	local function runBatch(batch: PlanBatch): BatchOutcome
		files.ensureDirectory(directory)
		local stem = ("%s/%s"):format(directory, safeName(batch.id))
		local runId: string? = nil
		if bound then
			runSequence += 1
			runId = ("%d-%d-%d"):format(os.time(), math.floor(runtime.time.clock() * 1000000), runSequence)
			stem ..= "-" .. (runId :: string)
		end
		local batchPath = stem .. "-batch.json"
		local resultPath = stem .. "-result.json"
		local logPath = stem .. "-worker.log"

		files.removeIfPresent(resultPath)
		runtime.fs.write(batchPath, batches.encode(batch))

		local argv: { string } = table.clone(command)
		table.insert(argv, options.worker)
		table.insert(argv, batchPath)
		table.insert(argv, resultPath)
		if runId ~= nil then
			table.insert(argv, runId)
		end
		local extras: { string } = if options.arguments ~= nil then options.arguments else {}
		if #extras > 0 then
			table.insert(argv, "--")
			for _, extra in extras do
				table.insert(argv, extra)
			end
		end

		local started, result: unknown =
			pcall(Bounded.run, argv, batch.deadlineSeconds or options.deadlineSeconds or 60, runtime.process.run)
		if not started then
			return { status = "faulted", detail = ("the worker could not be started: %s"):format(tostring(result)) }
		end
		local outcome = result :: Bounded.Result
		if outcome.timedOut then
			return { status = "timed_out", detail = "worker process exceeded its enforced deadline" }
		end
		local diagnostics = outcome.stdout .. (if outcome.stderr ~= "" then "\n" .. outcome.stderr else "")
		local logged = ""
		if bound then
			local wrote = pcall(runtime.fs.write, logPath, diagnostics)
			logged = if wrote then (" (log: %s)"):format(logPath) else ""
		end
		if not runtime.fs.exists(resultPath) then
			return {
				status = "faulted",
				detail = ("the worker exited %d and wrote no %s%s%s"):format(
					outcome.exitcode,
					if bound then "receipt" else "report",
					logged,
					if diagnostics ~= "" then ": " .. diagnostics else ""
				),
			}
		end
		local read, encoded: unknown = pcall(runtime.fs.read, resultPath)
		if not read then
			return { status = "faulted", detail = "the worker's report could not be read: " .. tostring(encoded) }
		end

		if runId ~= nil then
			local verdict = Receipt.check(runtime.json, encoded :: string, runId, batch.id)
			if verdict.report == nil then
				return {
					status = "faulted",
					detail = ("the worker wrote a %s receipt: %s%s"):format(verdict.kind, verdict.detail, logged),
				}
			end
			if outcome.exitcode ~= 0 and not recordsLoadFailure(verdict.report) then
				return {
					status = "faulted",
					detail = ("the worker exited %d yet wrote a valid receipt%s"):format(outcome.exitcode, logged),
				}
			end
			return { status = "returned", report = verdict.report }
		end

		local parsed, payload: unknown = pcall(wire.parse, encoded :: string)
		if not parsed then
			return {
				status = "faulted",
				detail = ("the worker wrote an unreadable report: %s%s"):format(
					tostring(payload),
					if diagnostics ~= "" then "; " .. diagnostics else ""
				),
			}
		end
		return { status = "returned", report = payload }
	end

	local host = {} :: Verify.Host
	host.name = name
	host.capabilities = capabilities
	host.environment = environment
	host.now = options.now or runtime.time.clock
	host.maxParallelBatches = options.maxParallelBatches
	host.runBatch = runBatch
	host.cancelled = options.cancelled

	host.runBatches = function(pending: { PlanBatch }, deliver: (number, BatchOutcome) -> ())
		local outcomes: { [number]: BatchOutcome } = {}
		local finished = 0
		for _, batch in pending do
			runtime.time.spawn(function()
				local ok, value: unknown = pcall(runBatch, batch)
				outcomes[batch.index] = if ok
					then value :: BatchOutcome
					else {
						status = "faulted",
						detail = "the host raised while running a batch: " .. tostring(value),
					}
				finished += 1
			end)
		end
		while finished < #pending do
			runtime.time.wait(0.005)
		end

		for _, batch in pending do
			deliver(batch.index, outcomes[batch.index])
		end
	end

	return host
end

return {
	DEFAULT_CAPABILITIES = DEFAULT_CAPABILITIES,
	create = create,
}
