--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local task = require "@std/task"

local Batch = require "./batch"
local Files = require "./files"
local Mailbox = require "./mailbox"
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

	size: number?,
	now: (() -> number)?,
	cancelled: (() -> boolean)?,
	batchTimeoutSeconds: number?,

	startTimeoutSeconds: number?,
	maxRestarts: number?,

	recycleAfter: number?,
	pollSeconds: number?,
}

local DEFAULT_COMMAND = { "lute", "run" }
local DEFAULT_DIRECTORY = ".lute/tmp/verify-pool"
local DEFAULT_CAPABILITIES = { "local-luau", "worker", "pooled-worker" }
local DEFAULT_SIZE = 4
local DEFAULT_BATCH_TIMEOUT = 600
local DEFAULT_START_TIMEOUT = 30
local DEFAULT_MAX_RESTARTS = 2
local DEFAULT_POLL = 0.002

export type Stats = {
	started: number,
	restarted: number,
	batches: number,
	faults: number,
}

export type Pool = Verify.Host & {
	close: (Pool) -> (),
	statistics: (Pool) -> Stats,
}

type Slot = {
	index: number,

	sequence: number,
	running: boolean,
	exited: boolean,
	starts: number,
	handled: number,
	dead: string?,
}

local removeIfPresent = Files.removeIfPresent

local function create(options: Options): Pool
	if type(options) ~= "table" or type(options.worker) ~= "string" or options.worker == "" then
		error("the Lute worker pool needs the path of a worker to start", 2)
	end
	local size = math.max(1, math.floor(options.size or DEFAULT_SIZE))
	local directory = Files.claimDirectory(options.directory or DEFAULT_DIRECTORY)
	local command = options.command or DEFAULT_COMMAND
	local timeout = options.batchTimeoutSeconds or DEFAULT_BATCH_TIMEOUT
	local startTimeout = options.startTimeoutSeconds or DEFAULT_START_TIMEOUT
	local maxRestarts = if options.maxRestarts ~= nil then options.maxRestarts else DEFAULT_MAX_RESTARTS
	local poll = options.pollSeconds or DEFAULT_POLL
	local recycleAfter = options.recycleAfter
	local clock = options.now or os.clock

	local slots: { Slot } = {}
	for index = 1, size do
		table.insert(slots, {
			index = index,
			sequence = 0,
			running = false,
			exited = false,
			starts = 0,
			handled = 0,
			dead = nil,
		})
	end

	local statistics: Stats = { started = 0, restarted = 0, batches = 0, faults = 0 }
	local closed = false

	local function start(slot: Slot): boolean
		if closed or slot.dead ~= nil then
			return false
		end
		removeIfPresent(Mailbox.readyPath(directory, slot.index))
		local argv: { string } = table.clone(command)
		table.insert(argv, options.worker)
		table.insert(argv, "--pool")
		table.insert(argv, directory)
		table.insert(argv, tostring(slot.index))

		slot.running = true
		slot.exited = false
		slot.starts += 1
		slot.handled = 0
		statistics.started += 1

		task.spawn(function()
			pcall(process.run, argv)
			slot.running = false
			slot.exited = true
		end)
		return true
	end

	local function retire(slot: Slot)
		slot.running = false
		slot.exited = true
	end

	local function healthy(slot: Slot): boolean
		return slot.dead == nil and not closed
	end

	local function ready(slot: Slot): string?
		if closed then
			return "the worker pool is closed"
		end
		if slot.dead ~= nil then
			return slot.dead
		end
		if slot.running and not slot.exited then
			return nil
		end
		local readyFile = Mailbox.readyPath(directory, slot.index)
		while true do
			if slot.starts > 0 then
				if slot.starts > maxRestarts then
					slot.dead = ("worker %d was replaced %d time(s) and is not trusted again"):format(
						slot.index,
						slot.starts - 1
					)
					return slot.dead
				end
				statistics.restarted += 1
			end
			if not start(slot) then
				slot.dead = ("worker %d could not be started"):format(slot.index)
				return slot.dead
			end
			local waitedFrom = clock()
			while not fs.exists(readyFile) do
				if slot.exited then
					break
				end
				if clock() - waitedFrom >= startTimeout then
					retire(slot)
					break
				end
				task.wait(poll)
			end
			if fs.exists(readyFile) then
				return nil
			end
		end
	end

	local function dispatch(slot: Slot, batch: PlanBatch): BatchOutcome
		local blocked = ready(slot)
		if blocked ~= nil then
			statistics.faults += 1
			return { status = "faulted", detail = blocked }
		end

		slot.sequence += 1
		local names = Mailbox.names(directory, slot.index, slot.sequence)
		removeIfPresent(names.response)
		removeIfPresent(names.sentinel)

		local written, thrown: any = pcall(fs.writeStringToFile, names.request, Batch.encode(batch))
		if not written then
			statistics.faults += 1
			return { status = "faulted", detail = "the batch could not be handed to a worker: " .. tostring(thrown) }
		end

		local published, publishError: any = pcall(fs.writeStringToFile, names.requestReady, "")
		if not published then
			removeIfPresent(names.request)
			statistics.faults += 1
			return {
				status = "faulted",
				detail = "the batch could not be handed to a worker: " .. tostring(publishError),
			}
		end

		local started = clock()
		while not fs.exists(names.sentinel) do
			if slot.exited and not fs.exists(names.sentinel) then
				task.wait(poll)
				if not fs.exists(names.sentinel) then
					statistics.faults += 1
					removeIfPresent(names.requestReady)
					removeIfPresent(names.request)
					retire(slot)
					return {
						status = "faulted",
						detail = ("worker %d exited without answering batch %s"):format(slot.index, batch.id),
					}
				end
				break
			end
			if clock() - started >= timeout then
				statistics.faults += 1
				removeIfPresent(names.requestReady)
				removeIfPresent(names.request)

				retire(slot)
				return {
					status = "faulted",
					detail = ("worker %d did not answer batch %s within %s second(s)"):format(
						slot.index,
						batch.id,
						tostring(timeout)
					),
				}
			end
			task.wait(poll)
		end

		local read, encoded: any = pcall(fs.readFileToString, names.response)
		removeIfPresent(names.response)
		removeIfPresent(names.sentinel)
		removeIfPresent(names.requestReady)
		removeIfPresent(names.request)
		if not read then
			statistics.faults += 1
			retire(slot)
			return { status = "faulted", detail = "the worker's report could not be read: " .. tostring(encoded) }
		end
		local bytes = encoded :: string
		if string.sub(bytes, 1, #Mailbox.RAISED_PREFIX) == Mailbox.RAISED_PREFIX then
			statistics.faults += 1
			retire(slot)
			return {
				status = "faulted",
				detail = ("worker %d raised while running batch %s: %s"):format(
					slot.index,
					batch.id,
					string.sub(bytes, #Mailbox.RAISED_PREFIX + 1)
				),
			}
		end

		local parsed, payload: any = pcall(Wire.parse, bytes)
		if not parsed then
			statistics.faults += 1
			retire(slot)
			return { status = "faulted", detail = "the worker wrote an unreadable report: " .. tostring(payload) }
		end

		statistics.batches += 1
		slot.handled += 1
		if recycleAfter ~= nil and slot.handled >= recycleAfter then
			retire(slot)
		end
		return { status = "returned", report = payload }
	end

	local function slotFor(position: number): Slot?
		local preferred = slots[((position - 1) % size) + 1]
		if healthy(preferred) then
			return preferred
		end
		for _, slot in slots do
			if healthy(slot) then
				return slot
			end
		end
		return nil
	end

	local function runBatch(batch: PlanBatch): BatchOutcome
		local slot = slotFor(1)
		if slot == nil then
			statistics.faults += 1
			return { status = "faulted", detail = "the worker pool has no usable worker left" }
		end
		return dispatch(slot :: Slot, batch)
	end

	local pool = {} :: Pool
	pool.name = options.name or "lute-pool"
	pool.capabilities = options.capabilities or DEFAULT_CAPABILITIES
	pool.environment = options.environment or { runtime = "lute", workers = tostring(size) }
	pool.now = clock
	pool.maxParallelBatches = size
	pool.runBatch = runBatch
	pool.cancelled = options.cancelled

	pool.runBatches = function(batches: { PlanBatch }, deliver: (number, BatchOutcome) -> ())
		local outcomes: { [number]: BatchOutcome } = {}
		local finished = 0
		for position, batch in batches do
			local slot = slotFor(position)
			if slot == nil then
				outcomes[batch.index] = {
					status = "faulted",
					detail = "the worker pool has no usable worker left",
				}
				statistics.faults += 1
				finished += 1
				continue
			end
			task.spawn(function()
				local ok, value: any = pcall(dispatch, slot :: Slot, batch)
				outcomes[batch.index] = if ok
					then value :: BatchOutcome
					else {
						status = "faulted",
						detail = "the pool raised while running a batch: " .. tostring(value),
					}
				finished += 1
			end)
		end
		while finished < #batches do
			task.wait(poll)
		end
		for _, batch in batches do
			deliver(batch.index, outcomes[batch.index])
		end
	end

	function pool.close(_self: Pool)
		if closed then
			return
		end
		closed = true
		pcall(fs.writeStringToFile, Mailbox.stopPath(directory), "stop")

		local deadline = clock() + 5
		local waiting = true
		while waiting and clock() < deadline do
			waiting = false
			for _, slot in slots do
				if slot.running and not slot.exited then
					waiting = true
				end
			end
			if waiting then
				task.wait(poll)
			end
		end
	end

	function pool.statistics(_self: Pool): Stats
		return table.clone(statistics)
	end

	return pool
end

return {
	DEFAULT_COMMAND = DEFAULT_COMMAND,
	DEFAULT_DIRECTORY = DEFAULT_DIRECTORY,
	DEFAULT_CAPABILITIES = DEFAULT_CAPABILITIES,
	DEFAULT_SIZE = DEFAULT_SIZE,
	create = create,
}
