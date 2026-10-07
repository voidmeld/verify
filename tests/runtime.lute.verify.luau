--!strict

local Batch = require "../src/runtime/batch"
local Binding = require "../src/runtime/binding"
local Host = require "../src/runtime/host"
local Receipt = require "../src/runtime/receipt"
local Runtime = require "../src/lute/runtime"
local Verify = require "../src/core"
local Wire = require "../src/runtime/wire"
local Worker = require "../src/runtime/worker"

type Script = (argv: { string }, files: { [string]: string }) -> Binding.ProcessResult

type Memory = {
	files: { [string]: string },
	writes: { string },
	exited: { number },
	printed: { string },
	runtime: Binding.Runtime,
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
	runtime.name = "memory"
	runtime.defaultCommand = { "worker-runtime" }
	runtime.defaultDirectory = "out"
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
		run = function(argv: { string }): Binding.ProcessResult
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
				group = nil,
				tags = {},
				requires = {},
				deadlineSeconds = nil,
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

local function reportFor(state: Memory, batch: Verify.PlanBatch): Verify.Report
	return Worker.create(state.runtime).runBatch(batch, operations)
end

local function workerScript(exitcode: number, mutate: ((encoded: string, argv: { string }) -> string)?): Script
	return function(argv: { string }, files: { [string]: string }): Binding.ProcessResult
		local state = memory({ argv[#argv - 2], argv[#argv - 1], argv[#argv] }, nil)
		state.files[argv[#argv - 2]] = files[argv[#argv - 2]]
		Worker.create(state.runtime).main(operations)
		local written = state.files[argv[#argv - 1]]
		files[argv[#argv - 1]] = if mutate ~= nil then mutate(written, argv) else written
		return { ok = exitcode == 0, exitcode = exitcode, stdout = "", stderr = "" }
	end
end

local function outcomeOf(script: Script, mode: ("report" | "bound")?): Verify.BatchOutcome
	local state = memory({}, script)
	local host = Host.create(state.runtime, { worker = "w.luau", receipts = mode or "bound" })
	return host.runBatch(batchOf("b1", "unit-a"))
end

return function(suite: Verify.Harness)
	suite:suite("runtime bindings", function()
		suite:case("refuse a binding with a missing service, member or name", function(check)
			local state = memory({}, nil)
			check:expect((pcall(Binding.validate, state.runtime))):toBe(true)
			local noTime = table.clone(state.runtime)
			noTime.time = (({}) :: unknown) :: Binding.Time
			check:expect((pcall(Binding.validate, noTime))):toBe(false)
			local noRemove = table.clone(state.runtime)
			local fsCopy = table.clone(state.runtime.fs)
			local loose = (fsCopy :: unknown) :: { [string]: unknown }
			loose.remove = nil
			noRemove.fs = fsCopy
			check:expect((pcall(Binding.validate, noRemove))):toBe(false)
			local unnamed = table.clone(state.runtime)
			unnamed.name = ""
			check:expect((pcall(Binding.validate, unnamed))):toBe(false)
		end)

		suite:case("the worker prints usage and exits nonzero without both paths", function(check)
			local state = memory({ "only-one" }, nil)
			Worker.create(state.runtime).main(operations)
			check:expect(state.exited):toEqual { 1 }
			check:expect(#state.printed):toBe(1)
			check:expect(#state.writes):toBe(0)
		end)

		suite:case("the worker writes a plain report without a run id and a bound receipt with one", function(check)
			local batch = batchOf("b", "unit")
			local plain = memory({ "batch.json", "plain.json" }, nil)
			plain.files["batch.json"] = Batch.create(plain.runtime.json).encode(batch)
			Worker.create(plain.runtime).main(operations)
			check:expect(Wire.create(plain.runtime.json).decode(plain.files["plain.json"]).passed):toBe(1)

			local bound = memory({ "batch.json", "bound.json", "run-7" }, nil)
			bound.files["batch.json"] = plain.files["batch.json"]
			Worker.create(bound.runtime).main(operations)
			local verdict = Receipt.check(bound.runtime.json, bound.files["bound.json"], "run-7", "b")
			check:expect(verdict.kind):toBe "accepted"
			check:expect((verdict.report :: Verify.Report).passed):toBe(1)
		end)

		suite:case("classifies every way a receipt can be wrong", function(check)
			local state = memory({}, nil)
			local json = state.runtime.json
			local good = Receipt.encode(json, "run", "batch", reportFor(state, batchOf("batch", "unit")))
			check:expect(Receipt.check(json, good, "run", "batch").kind):toBe "accepted"
			check:expect(Receipt.check(json, good, "other", "batch").kind):toBe "stale"
			check:expect(Receipt.check(json, good, "run", "other").kind):toBe "foreign"
			check:expect(Receipt.check(json, "{broken", "run", "batch").kind):toBe "malformed"
			check:expect(Receipt.check(json, "[1]", "run", "batch").kind):toBe "malformed"
			check:expect(Receipt.check(json, "7", "run", "batch").kind):toBe "malformed"
			check:expect(Receipt.check(json, '{"receiptVersion":2}', "run", "batch").kind):toBe "malformed"
			local invalid =
				json.encode { receiptVersion = 1, runId = "run", batchId = "batch", report = { total = "x" } }
			check:expect(Receipt.check(json, invalid, "run", "batch").kind):toBe "invalid"
			local verdict = Receipt.check(json, invalid, "run", "batch")
			check:expect(verdict.report):toBe(nil)
		end)
	end)

	suite:suite("shared worker host", function()
		suite:case("returns the validated report of a clean run", function(check)
			local outcome = outcomeOf(workerScript(0, nil))
			check:expect(outcome.status):toBe "returned"
			check:expect((outcome.report :: Verify.Report).passed):toBe(1)
		end)

		suite:case("faults a clean exit without a receipt", function(check)
			local outcome = outcomeOf(function()
				return { ok = true, exitcode = 0, stdout = "chatter", stderr = "" }
			end)
			check:expect(outcome.status):toBe "faulted"
			check:expect(string.find(outcome.detail or "", "wrote no receipt", 1, true) ~= nil):toBe(true)
			check:expect(string.find(outcome.detail or "", "chatter", 1, true) ~= nil):toBe(true)
		end)

		suite:case("faults a receipt that disagrees with the exit status", function(check)
			local outcome = outcomeOf(workerScript(4, nil))
			check:expect(outcome.status):toBe "faulted"
			check
				:expect(string.find(outcome.detail or "", "exited 4 yet wrote a valid receipt", 1, true) ~= nil)
				:toBe(true)
		end)

		suite:case("faults stale, foreign and malformed receipts", function(check)
			local function rewrite(replace: string, with: string): Script
				return workerScript(0, function(encoded: string): string
					return (string.gsub(encoded, replace, with))
				end)
			end
			local stale = outcomeOf(rewrite('"runId":"[^"]*"', '"runId":"old-run"'))
			check:expect(string.find(stale.detail or "", "stale receipt", 1, true) ~= nil):toBe(true)
			local foreign = outcomeOf(rewrite('"batchId":"[^"]*"', '"batchId":"elsewhere"'))
			check:expect(string.find(foreign.detail or "", "foreign receipt", 1, true) ~= nil):toBe(true)
			local malformed = outcomeOf(workerScript(0, function(): string
				return "garbage"
			end))
			check:expect(string.find(malformed.detail or "", "malformed receipt", 1, true) ~= nil):toBe(true)
			for _, outcome in { stale, foreign, malformed } do
				check:expect(outcome.status):toBe "faulted"
				check:expect(outcome.report):toBe(nil)
			end
		end)

		suite:case("reports a timeout and a worker that cannot start", function(check)
			local timedOut = outcomeOf(function()
				return { ok = false, exitcode = 137, stdout = "", stderr = "verify_bounded_timeout\n" }
			end)
			check:expect(timedOut.status):toBe "timed_out"
			local unstartable = outcomeOf(function(): Binding.ProcessResult
				error("no such program", 0)
			end)
			check:expect(unstartable.status):toBe "faulted"
			check:expect(string.find(unstartable.detail or "", "no such program", 1, true) ~= nil):toBe(true)
		end)

		suite:case("keeps the legacy report mode and its exit-agnostic behaviour", function(check)
			local outcome = outcomeOf(function(argv: { string }, files: { [string]: string }): Binding.ProcessResult
				local state = memory({ argv[#argv - 1], argv[#argv] }, nil)
				state.files[argv[#argv - 1]] = files[argv[#argv - 1]]
				Worker.create(state.runtime).main(operations)
				files[argv[#argv]] = state.files[argv[#argv]]
				return { ok = false, exitcode = 2, stdout = "", stderr = "" }
			end, "report")
			check:expect(outcome.status):toBe "returned"
		end)

		suite:case("requires a worker path and delivers every batch through the time binding", function(check)
			local state = memory({}, workerScript(0, nil))
			check:expect((pcall(Host.create, state.runtime, { worker = "" }))):toBe(false)
			local host = Host.create(state.runtime, { worker = "w.luau", receipts = "bound" })
			local delivered: { [number]: string } = {}
			local first = batchOf("one", "a")
			local second = batchOf("two", "b")
			second.index = 2
			(host.runBatches :: ({ Verify.PlanBatch }, (number, Verify.BatchOutcome) -> ()) -> ())(
				{ first, second },
				function(index: number, outcome: Verify.BatchOutcome)
					delivered[index] = outcome.status
				end
			)
			check:expect(delivered):toEqual { "returned", "returned" }
		end)
	end)
end
