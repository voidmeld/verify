--!strict

export type Json = {
	encode: (value: unknown) -> string,
	decode: (encoded: string) -> unknown,
}

export type Fs = {
	read: (path: string) -> string,
	write: (path: string, contents: string) -> (),
	exists: (path: string) -> boolean,
	createDirectory: (path: string) -> (),
	remove: (path: string) -> (),
}

export type ProcessResult = {
	ok: boolean,
	exitcode: number,
	stdout: string,
	stderr: string,
}

export type RunOptions = {
	env: { [string]: string }?,
	cwd: string?,
}

export type Process = {
	arguments: { string },
	exit: (code: number) -> (),
	run: (argv: { string }, options: RunOptions?) -> ProcessResult,
}

export type Time = {
	clock: () -> number,
	spawn: (task: () -> ()) -> (),
	wait: (seconds: number) -> (),
}

export type Stdio = {
	print: (line: string) -> (),
}

export type Runtime = {
	name: string,
	defaultCommand: { string },
	defaultDirectory: string,
	json: Json,
	fs: Fs,
	process: Process,
	time: Time,
	stdio: Stdio,
}

local function validate(runtime: Runtime): Runtime
	assert(type(runtime) == "table" and type(runtime.name) == "string" and runtime.name ~= "", "runtime needs a name")
	assert(type(runtime.defaultCommand) == "table" and #runtime.defaultCommand > 0, "runtime needs a default command")
	assert(type(runtime.defaultDirectory) == "string" and runtime.defaultDirectory ~= "", "runtime needs a directory")
	local required: { [string]: { string } } = {
		json = { "encode", "decode" },
		fs = { "read", "write", "exists", "createDirectory", "remove" },
		process = { "exit", "run" },
		time = { "clock", "spawn", "wait" },
		stdio = { "print" },
	}
	local services = (runtime :: unknown) :: { [string]: { [string]: unknown } }
	for service, members in required do
		assert(type(services[service]) == "table", ("runtime binding %s is missing"):format(service))
		for _, member in members do
			assert(
				type(services[service][member]) == "function",
				("runtime binding %s.%s must be a function"):format(service, member)
			)
		end
	end
	assert(type(runtime.process.arguments) == "table", "runtime binding process.arguments must be a list")
	return runtime
end

return {
	validate = validate,
}
