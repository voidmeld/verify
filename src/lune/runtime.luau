--!strict

local Binding = require "../runtime/binding"

type LuneProcessResult = { ok: boolean, code: number, stdout: string, stderr: string }

type LuneFs = {
	readFile: (path: string) -> string,
	writeFile: (path: string, contents: string) -> (),
	isFile: (path: string) -> boolean,
	isDir: (path: string) -> boolean,
	writeDir: (path: string) -> (),
	removeFile: (path: string) -> (),
	removeDir: (path: string) -> (),
}

type LuneExecOptions = { cwd: string?, env: { [string]: string }? }

type LuneProcess = {
	args: { string },
	exit: (code: number?) -> (),
	exec: (program: string, params: { string }?, options: LuneExecOptions?) -> LuneProcessResult,
}

type LuneTask = {
	spawn: (task: () -> ()) -> thread,
	wait: (seconds: number?) -> number,
}

type LuneSerde = {
	encode: (format: string, value: unknown) -> string,
	decode: (format: string, encoded: string) -> unknown,
}

type LuneStdio = {
	write: (contents: string) -> (),
}

local load = require :: (string) -> unknown

local fs = load "@lune/fs" :: LuneFs
local process = load "@lune/process" :: LuneProcess
local task = load "@lune/task" :: LuneTask
local serde = load "@lune/serde" :: LuneSerde
local stdio = load "@lune/stdio" :: LuneStdio

local runtime: Binding.Runtime = {
	name = "lune",
	defaultCommand = { "lune", "run" },
	defaultDirectory = ".verify/lune",
	json = {
		encode = function(value: unknown): string
			return serde.encode("json", value)
		end,
		decode = function(encoded: string): unknown
			return serde.decode("json", encoded)
		end,
	},
	fs = {
		read = fs.readFile,
		write = fs.writeFile,
		exists = function(path: string): boolean
			return fs.isFile(path) or fs.isDir(path)
		end,
		createDirectory = fs.writeDir,
		remove = function(path: string)
			if fs.isDir(path) then
				fs.removeDir(path)
			else
				fs.removeFile(path)
			end
		end,
	},
	process = {
		arguments = table.clone(process.args),
		exit = function(code: number)
			process.exit(code)
		end,
		run = function(argv: { string }, options: Binding.RunOptions?): Binding.ProcessResult
			local params: { string } = {}
			for index = 2, #argv do
				table.insert(params, argv[index])
			end
			local settings: LuneExecOptions = {}
			if options ~= nil then
				settings.cwd = options.cwd
				settings.env = options.env
			end
			local result = process.exec(argv[1], params, settings)
			return { ok = result.ok, exitcode = result.code, stdout = result.stdout, stderr = result.stderr }
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
			stdio.write(line .. "\n")
		end,
	},
}

return runtime
