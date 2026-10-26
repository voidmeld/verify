--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Batch = require "../src/lute/batch"
local Host = require "../src/lute/host"
local Runtime = require "../src/lute/runtime"
local Verify = require "../src/core"
local Wire = require "../src/lute/wire"
local Worker = require "../src/lute/worker"

type Script = (argv: { string }, files: { [string]: string }) -> Runtime.ProcessResult

type Memory = {
	files: { [string]: string },
	writes: { string },
	exited: { number },
	printed: { string },
	runtime: Runtime.Runtime,
}

local function memory(arguments: { string }, script: Script?): Memory
	local files: { [string]: string } = {}
	local state: Memory = {
		files = files,
		writes = {},
		exited = {},
		printed = {},
		runtime = table.clone(Runtime),
	}
	local runtime = state.runtime
	runtime.bounded = nil
	runtime.fs = {
		read = function(path: string): string
			return files[path] or error("missing " .. path, 0)
		end,
		write = function(path: string, contents: string)
			table.insert(state.writes, path)
			files[path] = contents
		end,
		exists = function(path: string): boolean
			return files[path] ~= nil
		end,
		createDirectory = function(path: string)
			files[path] = ""
		end,
		remove = function(path: string)
			files[path] = nil
		end,
	}
	runtime.process = {
		arguments = arguments,
		exit = function(code: number)
			table.insert(state.exited, code)
		end,
		run = function(argv: { string }): Runtime.ProcessResult
			if script ~= nil then
				return script(argv, files)
			end
			return { ok = true, exitcode = 0, stdout = "", stderr = "" }
		end,
	}
	runtime.time = {
		clock = function(): number
			return 0
		end,
		spawn = function(body: () -> ())
			body()
		end,
		wait = function(_seconds: number) end,
	}
	runtime.stdio = {
		print = function(line: string)
			table.insert(state.printed, line)
		end,
	}
	return state
end

local function batchOf(id: string, locator: string): Verify.PlanBatch
	return {
		id = id,
		index = 1,
		units = {
			{
				id = locator,
				locator = locator,
				tags = {},
				requires = {},
				weight = 1,
			},
		},
	}
end

local operations: Worker.Operations = {
	load = function(): unknown
		return function(harness: Verify.Harness)
			harness:case("one", function(context)
				context:expect(1):toBe(1)
			end)
		end
	end,
}

local function workerScript(exitcode: number): Script
	return function(argv: { string }, files: { [string]: string }): Runtime.ProcessResult
		local state = memory({ argv[#argv - 1], argv[#argv] }, nil)
		state.files[argv[#argv - 1]] = files[argv[#argv - 1]]
		Worker.create(state.runtime).main(operations)
		files[argv[#argv]] = state.files[argv[#argv]]
		return { ok = exitcode == 0, exitcode = exitcode, stdout = "", stderr = "" }
	end
end

local function outcomeOf(script: Script): Verify.BatchOutcome
	local state = memory({}, script)
	local host = Host.create({ worker = "w.luau" }, state.runtime)
	return host.runBatch(batchOf("b1", "unit-a"))
end

describe("worker", function()
	it("prints usage and exits nonzero without both paths", function()
		local state = memory({ "only-one" }, nil)
		Worker.create(state.runtime).main(operations)
		expect(state.exited):toEqual { 1 }
		expect(#state.printed):toBe(1)
		expect(#state.writes):toBe(0)
	end)

	it("writes the report of the batch to the result path", function()
		local plain = memory({ "batch.json", "plain.json" }, nil)
		plain.files["batch.json"] = Batch.encode(batchOf("b", "unit"))
		Worker.create(plain.runtime).main(operations)
		expect(Wire.decode(plain.files["plain.json"]).passed):toBe(1)
	end)
end)

describe("worker host", function()
	it("returns the validated report of a clean run", function()
		local outcome = outcomeOf(workerScript(0))
		expect(outcome.status):toBe "returned"
		expect((outcome.report :: Verify.Report).passed):toBe(1)
	end)

	it("returns the report of a worker that exits nonzero", function()
		expect(outcomeOf(workerScript(2)).status):toBe "returned"
	end)

	it("faults a clean exit without a report", function()
		local outcome = outcomeOf(function()
			return { ok = true, exitcode = 0, stdout = "chatter", stderr = "" }
		end)
		expect(outcome.status):toBe "faulted"
		expect(outcome.detail or ""):toContain "wrote no report"
		expect(outcome.detail or ""):toContain "chatter"
	end)

	it("faults an unreadable report", function()
		local outcome = outcomeOf(function(argv: { string }, files: { [string]: string }): Runtime.ProcessResult
			files[argv[#argv]] = "garbage"
			return { ok = true, exitcode = 0, stdout = "", stderr = "" }
		end)
		expect(outcome.status):toBe "faulted"
		expect(outcome.detail or ""):toContain "unreadable report"
	end)

	it("reports a timeout and a worker that cannot start", function()
		local timedOut = outcomeOf(function()
			return { ok = false, exitcode = 137, stdout = "", stderr = "verify_bounded_timeout\n" }
		end)
		expect(timedOut.status):toBe "timed_out"
		local unstartable = outcomeOf(function(): Runtime.ProcessResult
			error("no such program", 0)
		end)
		expect(unstartable.status):toBe "faulted"
		expect(unstartable.detail or ""):toContain "no such program"
	end)

	it("requires a worker path and delivers every batch through the time binding", function()
		local state = memory({}, workerScript(0))
		expect((pcall(Host.create, { worker = "" }, state.runtime))):toBe(false)
		local host = Host.create({ worker = "w.luau" }, state.runtime)
		local runBatch = host.runBatch
		local dispatched = 0
		host.runBatch = function(batch)
			dispatched += 1
			return runBatch(batch)
		end
		local delivered: { [number]: string } = {}
		local first = batchOf("one", "a")
		local second = batchOf("two", "b")
		second.index = 2
		(assert(host.runBatches))({ first, second }, function(index: number, outcome: Verify.BatchOutcome)
			delivered[index] = outcome.status
		end)
		expect(delivered):toEqual { "returned", "returned" }
		expect(dispatched):toBe(2)
	end)
end)

return nil
