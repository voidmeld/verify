--!strict

local process = require "@std/process"

local Bounded = require "../runtime/bounded"

export type Result = Bounded.Result

export type Runner = (argv: { string }) -> process.ProcessResult

local function run(argv: { string }, seconds: number, runner: Runner?): Result
	local chosen: Runner = runner or process.run
	return Bounded.run(argv, seconds, function(command: { string }): process.ProcessResult
		return chosen(command)
	end)
end

return {
	run = run,
}
