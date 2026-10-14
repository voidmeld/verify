--!strict

local Binding = require "../runtime/binding"
local Bounded = require "../runtime/bounded"
local Runtime = require "./runtime"

export type Result = Bounded.Result

export type Runner = (argv: { string }, options: Binding.RunOptions?) -> Binding.ProcessResult

local function run(argv: { string }, seconds: number, runner: Runner?, options: Binding.RunOptions?): Result
	return Bounded.run(argv, seconds, runner or Runtime.process.run, options, Runtime.bounded)
end

return {
	CAPABILITIES = Bounded.capabilities(Runtime.bounded),
	run = run,
}
