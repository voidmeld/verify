--!strict

local fs = require "@std/fs"
local path = require "@std/path"
local process = require "@std/process"
local system = require "@std/system"
local task = require "@std/task"

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

export type BoundedMechanism = "auto" | "job" | "setsid" | "perl" | "tree" | "none"

export type BoundedSettings = {
	shell: string?,
	mechanism: BoundedMechanism?,
	watchdog: { string }?,
}

export type Runtime = {
	fs: Fs,
	process: Process,
	time: Time,
	stdio: Stdio,
	bounded: BoundedSettings?,
}

local function arguments(): { string }
	local result: { string } = {}
	for index = 2, #process.args do
		table.insert(result, process.args[index])
	end
	return result
end

local function bounded(): BoundedSettings?
	if not system.win32 then
		return nil
	end
	local directory = path.dirname(path.resolve(debug.info(1, "s")))
	local watchdog = path.format(path.join(directory, "tree-watchdog.luau"))
	return { mechanism = "tree", watchdog = { path.format(process.execPath()), "run", watchdog } }
end

local runtime: Runtime = {
	fs = {
		read = fs.readFileToString,
		write = fs.writeStringToFile,
		exists = fs.exists,
		createDirectory = fs.createDirectory,
		remove = fs.remove,
	},
	process = {
		arguments = arguments(),
		exit = function(code: number)
			process.exit(code)
		end,
		run = function(argv: { string }, options: RunOptions?): ProcessResult
			local settings: process.ProcessRunOptions = { cwd = nil, stdio = nil, env = nil, timeout = nil }
			if options ~= nil then
				settings.cwd = options.cwd
				if options.env ~= nil then
					local merged: { [string]: string } = {}
					for key, value in process.env do
						merged[key] = value
					end
					for key, value in options.env do
						merged[key] = value
					end
					settings.env = merged
				end
			end
			return process.run(argv, settings)
		end,
	},
	time = {
		clock = os.clock,
		spawn = function(body: () -> ())
			task.spawn(body)
		end,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
	},
	stdio = {
		print = function(line: string)
			print(line)
		end,
	},
	bounded = bounded(),
}

return runtime
