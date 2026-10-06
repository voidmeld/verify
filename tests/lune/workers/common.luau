--!strict

local Lune = require "../../../src/lune"
local Verify = require "../../../src/core"

local load = require :: (string) -> unknown
local fs = load "@lune/fs" :: { readFile: (string) -> string, writeFile: (string, string) -> () }
local process = load "@lune/process" :: {
	args: { string },
	exit: (number?) -> (),
	exec: (string, { string }?) -> { ok: boolean, code: number, stdout: string, stderr: string },
}

local function register(harness: Verify.Harness, passing: boolean)
	harness:suite("fixture", function()
		harness:case("first", function(context)
			context:expect(1):toBe(1)
		end)
		harness:case(if passing then "second" else "broken", function(context)
			context:expect(1):toBe(if passing then 1 else 2)
		end)
	end)
end

local operations: Lune.WorkerOperations = {
	load = function(locator: string): unknown
		if locator == "pass" then
			return function(harness: Verify.Harness)
				register(harness, true)
			end
		elseif locator == "fail" then
			return function(harness: Verify.Harness)
				register(harness, false)
			end
		elseif locator == "load-error" then
			error("load boom", 0)
		elseif locator == "not-function" then
			return 7
		elseif locator == "registration-error" then
			return function()
				error("registration boom", 0)
			end
		elseif locator == "hang" then
			while true do
			end
		elseif locator == "needs-gpu" then
			error("gpu required", 0)
		elseif locator == "skip-me" then
			error("skip requested", 0)
		end
		error("unknown locator " .. locator, 0)
	end,
	classifyLoadFailure = function(locator: string, _thrown: unknown): Lune.LoadDisposition?
		if locator == "needs-gpu" then
			return { status = "unsupported", missingCapabilities = { "gpu" } }
		elseif locator == "skip-me" then
			return { status = "skipped", reason = "skipped on purpose" }
		end
		return nil
	end,
}

local function produce(): (Verify.PlanBatch, Verify.Report)
	local batch = Lune.decodeBatch(fs.readFile(process.args[1]))
	return batch, Lune.runWorkerBatch(batch, operations)
end

return {
	operations = operations,
	produce = produce,
	args = process.args,
	exit = function(code: number)
		process.exit(code)
	end,
	writeFile = fs.writeFile,
	exec = process.exec,
}
