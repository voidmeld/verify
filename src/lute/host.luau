--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local task = require "@std/task"

local Batch = require "./batch"
local Files = require "./files"
local Verify = require "../core"
local Wire = require "./wire"

type BatchOutcome = Verify.BatchOutcome
type PlanBatch = Verify.PlanBatch

export type Options = {

	worker: string,
	command: { string }?,
	directory: string?,
	name: string?,
	capabilities: { string }?,
	environment: { [string]: string }?,
	maxParallelBatches: number?,
	now: (() -> number)?,
	cancelled: (() -> boolean)?,
}

local DEFAULT_COMMAND = { "lute", "run" }
local DEFAULT_DIRECTORY = ".lute/tmp/verify"
local DEFAULT_CAPABILITIES = { "local-luau", "worker" }

local function safeName(id: string): string
	return (string.gsub(id, "[^%w%-_]", "-"))
end

local function create(options: Options): Verify.Host
	if type(options) ~= "table" or type(options.worker) ~= "string" or options.worker == "" then
		error("the Lute host needs the path of a worker to start", 2)
	end
	local name = options.name or "lute"
	local capabilities = options.capabilities or DEFAULT_CAPABILITIES
	local environment = options.environment or { runtime = "lute" }
	local directory = options.directory or DEFAULT_DIRECTORY
	local command = options.command or DEFAULT_COMMAND

	local function runBatch(batch: PlanBatch): BatchOutcome
		Files.ensureDirectory(directory)
		local stem = ("%s/%s"):format(directory, safeName(batch.id))
		local batchPath = stem .. "-batch.json"
		local resultPath = stem .. "-result.json"

		Files.removeIfPresent(resultPath)
		fs.writeStringToFile(batchPath, Batch.encode(batch))

		local argv: { string } = table.clone(command)
		table.insert(argv, options.worker)
		table.insert(argv, batchPath)
		table.insert(argv, resultPath)

		local started, result: any = pcall(process.run, argv)
		if not started then
			return { status = "faulted", detail = ("the worker could not be started: %s"):format(tostring(result)) }
		end
		local outcome = result :: process.ProcessResult
		local diagnostics = outcome.stdout .. (if outcome.stderr ~= "" then "\n" .. outcome.stderr else "")
		if not fs.exists(resultPath) then
			return {
				status = "faulted",
				detail = ("the worker exited %d and wrote no report%s"):format(
					outcome.exitcode,
					if diagnostics ~= "" then ": " .. diagnostics else ""
				),
			}
		end
		local read, encoded: any = pcall(fs.readFileToString, resultPath)
		if not read then
			return { status = "faulted", detail = "the worker's report could not be read: " .. tostring(encoded) }
		end

		local parsed, payload: any = pcall(Wire.parse, encoded :: string)
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
	host.now = options.now or os.clock
	host.maxParallelBatches = options.maxParallelBatches
	host.runBatch = runBatch
	host.cancelled = options.cancelled

	host.runBatches = function(batches: { PlanBatch }, deliver: (number, BatchOutcome) -> ())
		local outcomes: { [number]: BatchOutcome } = {}
		local finished = 0
		for _, batch in batches do
			task.spawn(function()
				local ok, value: any = pcall(runBatch, batch)
				outcomes[batch.index] = if ok
					then value :: BatchOutcome
					else {
						status = "faulted",
						detail = "the host raised while running a batch: " .. tostring(value),
					}
				finished += 1
			end)
		end
		while finished < #batches do
			task.wait(0.005)
		end

		for _, batch in batches do
			deliver(batch.index, outcomes[batch.index])
		end
	end

	return host
end

return {
	DEFAULT_COMMAND = DEFAULT_COMMAND,
	DEFAULT_DIRECTORY = DEFAULT_DIRECTORY,
	DEFAULT_CAPABILITIES = DEFAULT_CAPABILITIES,
	create = create,
}
