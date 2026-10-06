--!strict

local fs = require "@std/fs"
local json = require "@std/json"
local process = require "@std/process"
local task = require "@std/task"

local Binding = require "../runtime/binding"

local function arguments(): { string }
	local result: { string } = {}
	for index = 2, #process.args do
		table.insert(result, process.args[index])
	end
	return result
end

local runtime: Binding.Runtime = {
	name = "lute",
	defaultCommand = { "lute", "run" },
	defaultDirectory = ".lute/tmp/verify",
	json = {
		encode = function(value: unknown): string
			return json.serialize(value :: json.Value)
		end,
		decode = function(encoded: string): unknown
			return json.deserialize(encoded)
		end,
	},
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
		run = function(argv: { string }, options: Binding.RunOptions?): Binding.ProcessResult
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
}

return runtime
