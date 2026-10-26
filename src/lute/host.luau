--!strict

local Batch = require "./batch"
local Bounded = require "./bounded"
local Files = require "./files"
local LuteRuntime = require "./runtime"
local Verify = require "../core"
local Wire = require "./wire"

type BatchOutcome = Verify.BatchOutcome
type PlanBatch = Verify.PlanBatch
type Runtime = LuteRuntime.Runtime

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
	arguments: { string }?,
}

local function capabilities(runtime: Runtime?): { string }
	local declared = { "local-luau", "worker" }
	for _, capability in Bounded.capabilities(if runtime ~= nil then runtime.bounded else nil) do
		table.insert(declared, capability)
	end
	return declared
end

local function safeName(id: string): string
	return (string.gsub(id, "[^%w%-_]", "-"))
end

local function create(options: Options, runtime: Runtime?): Verify.Host
	local services: Runtime = runtime or LuteRuntime
	if type(options) ~= "table" or type(options.worker) ~= "string" or options.worker == "" then
		error("the host needs the path of a worker to start", 2)
	end
	local directory = options.directory or ".lute/tmp/verify"
	local command = options.command or { "lute", "run" }
	local files = Files.create(services.fs)

	local function runBatch(batch: PlanBatch): BatchOutcome
		files.ensureDirectory(directory)
		local stem = ("%s/%s"):format(directory, safeName(batch.id))
		local batchPath = stem .. "-batch.json"
		local resultPath = stem .. "-result.json"

		files.removeIfPresent(resultPath)
		services.fs.write(batchPath, Batch.encode(batch))

		local argv: { string } = table.clone(command)
		table.insert(argv, options.worker)
		table.insert(argv, batchPath)
		table.insert(argv, resultPath)
		local extras: { string } = if options.arguments ~= nil then options.arguments else {}
		if #extras > 0 then
			table.insert(argv, "--")
			for _, extra in extras do
				table.insert(argv, extra)
			end
		end

		local started, result = pcall(
			Bounded.runWith,
			argv,
			batch.deadlineSeconds or options.deadlineSeconds or 60,
			services.process.run,
			nil,
			services.bounded
		)
		if not started then
			return { status = "faulted", detail = ("the worker could not be started: %s"):format(tostring(result)) }
		end
		local outcome = result
		if outcome.timedOut then
			return { status = "timed_out", detail = "worker process exceeded its enforced deadline" }
		end
		local diagnostics = outcome.stdout .. (if outcome.stderr ~= "" then "\n" .. outcome.stderr else "")
		if not services.fs.exists(resultPath) then
			return {
				status = "faulted",
				detail = ("the worker exited %d and wrote no report%s"):format(
					outcome.exitcode,
					if diagnostics ~= "" then ": " .. diagnostics else ""
				),
			}
		end
		local read, encoded = pcall(services.fs.read, resultPath)
		if not read then
			return { status = "faulted", detail = "the worker's report could not be read: " .. tostring(encoded) }
		end
		local parsed, payload = pcall(Wire.parse, encoded)
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

	local host: Verify.Host = {
		name = options.name or "lute",
		capabilities = options.capabilities or capabilities(services),
		environment = options.environment or { runtime = "lute" },
		now = options.now or services.time.clock,
		maxParallelBatches = options.maxParallelBatches,
		runBatch = runBatch,
		cancelled = options.cancelled,
	}
	host.runQueue = function(parallel: number, take: () -> PlanBatch?, deliver: (number, BatchOutcome) -> ())
		local finished = 0
		local errors: { string } = {}
		for _ = 1, parallel do
			services.time.spawn(function()
				local ran, thrown = pcall(function()
					while true do
						local batch = take()
						if batch == nil then
							break
						end
						local outcome: BatchOutcome? = nil
						local _, reason = pcall(function()
							outcome = host.runBatch(batch)
						end)
						local result: BatchOutcome = outcome
							or {
								status = "faulted",
								detail = "the host raised while running a batch: " .. tostring(reason),
							}
						deliver(batch.index, result)
					end
				end)
				if not ran then
					table.insert(errors, tostring(thrown))
				end
				finished += 1
			end)
		end
		while finished < parallel do
			services.time.wait(0.005)
		end
		if #errors > 0 then
			error(table.concat(errors, "\n"), 0)
		end
	end

	host.runBatches = function(pending: { PlanBatch }, deliver: (number, BatchOutcome) -> ())
		local outcomes: { [number]: BatchOutcome } = {}
		local finished = 0
		for _, batch in pending do
			services.time.spawn(function()
				local ok, value = pcall(host.runBatch, batch)
				outcomes[batch.index] = if ok
					then value
					else {
						status = "faulted",
						detail = "the host raised while running a batch: " .. tostring(value),
					}
				finished += 1
			end)
		end
		while finished < #pending do
			services.time.wait(0.005)
		end

		for _, batch in pending do
			deliver(batch.index, outcomes[batch.index])
		end
	end

	return host
end

return {
	capabilities = capabilities,
	create = create,
}
