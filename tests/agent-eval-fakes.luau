--!strict

local AgentEval = require "../src/agent-eval"
local Gate = require "../src/gate"
local Lute = require "../src/lute"
local Verify = require "../src/core"

export type Memory = {
	files: AgentEval.Files,
	contents: { [string]: string },
	directories: { [string]: boolean },
}

export type Handler = (job: Gate.Job, files: AgentEval.Files) -> Gate.JobOutcome

local function normalize(path: string): string
	local value = string.gsub(path, "\\", "/")
	value = string.gsub(value, "/+", "/")
	if #value > 1 and string.sub(value, -1) == "/" then
		value = string.sub(value, 1, -2)
	end
	return value
end

local function parentOf(path: string): string?
	return string.match(path, "^(.*)/[^/]+$")
end

local function memory(): Memory
	local contents: { [string]: string } = {}
	local directories: { [string]: boolean } = { ["/"] = true }
	local function ensureParent(path: string)
		local parent = parentOf(path)
		if parent ~= nil and parent ~= "" and not directories[parent] then
			error(("no directory %s for %s"):format(parent, path), 0)
		end
	end
	local function makeDirectory(path: string)
		local value = normalize(path)
		local built = ""
		for part in string.gmatch(value, "[^/]+") do
			built = built .. "/" .. part
			if contents[built] ~= nil then
				error(("%s is a file"):format(built), 0)
			end
			directories[built] = true
		end
	end
	local files: AgentEval.Files = {
		read = function(path: string): string
			local value = contents[normalize(path)]
			if value == nil then
				error(("no file %s"):format(path), 0)
			end
			return value
		end,
		write = function(path: string, text: string)
			local value = normalize(path)
			ensureParent(value)
			if directories[value] then
				error(("%s is a directory"):format(value), 0)
			end
			contents[value] = text
		end,
		exists = function(path: string): boolean
			local value = normalize(path)
			return contents[value] ~= nil or directories[value] == true
		end,
		isDirectory = function(path: string): boolean
			return directories[normalize(path)] == true
		end,
		list = function(path: string): { AgentEval.Entry }
			local value = normalize(path)
			if not directories[value] then
				error(("no directory %s"):format(value), 0)
			end
			local result: { AgentEval.Entry } = {}
			local prefix = value .. "/"
			for file in contents do
				if string.sub(file, 1, #prefix) == prefix and string.find(file, "/", #prefix + 1, true) == nil then
					table.insert(result, { name = string.sub(file, #prefix + 1), kind = "file" })
				end
			end
			for directory in directories do
				if
					string.sub(directory, 1, #prefix) == prefix
					and string.find(directory, "/", #prefix + 1, true) == nil
				then
					table.insert(result, { name = string.sub(directory, #prefix + 1), kind = "directory" })
				end
			end
			table.sort(result, function(left, right)
				return left.name < right.name
			end)
			return result
		end,
		makeDirectory = makeDirectory,
		remove = function(path: string)
			local value = normalize(path)
			contents[value] = nil
			local prefix = value .. "/"
			for file in table.clone(contents) do
				if string.sub(file, 1, #prefix) == prefix then
					contents[file] = nil
				end
			end
			for directory in table.clone(directories) do
				if directory == value or string.sub(directory, 1, #prefix) == prefix then
					directories[directory] = nil
				end
			end
		end,
		copy = function(from: string, to: string)
			local source = contents[normalize(from)]
			if source == nil then
				error(("no file %s"):format(from), 0)
			end
			local target = normalize(to)
			ensureParent(target)
			contents[target] = source
		end,
		move = function(from: string, to: string)
			local source = normalize(from)
			local target = normalize(to)
			ensureParent(target)
			if contents[source] ~= nil then
				contents[target] = contents[source]
				contents[source] = nil
				return
			end
			if not directories[source] then
				error(("no path %s"):format(from), 0)
			end
			local prefix = source .. "/"
			for file, text in table.clone(contents) do
				if string.sub(file, 1, #prefix) == prefix then
					contents[target .. "/" .. string.sub(file, #prefix + 1)] = text
					contents[file] = nil
				end
			end
			for directory in table.clone(directories) do
				if directory == source then
					directories[directory] = nil
					directories[target] = true
				elseif string.sub(directory, 1, #prefix) == prefix then
					directories[directory] = nil
					directories[target .. "/" .. string.sub(directory, #prefix + 1)] = true
				end
			end
		end,
	}
	return { files = files, contents = contents, directories = directories }
end

local function hash(text: string): string
	return ("%08x%08x"):format(AgentEval.random.hash(text), AgentEval.random.hash("salt:" .. text))
end

local function loader(files: AgentEval.Files): AgentEval.Loader
	return { files = files, hash = hash, decodeJson = Lute.parse }
end

local function exited(code: number): Gate.JobOutcome
	return {
		started = true,
		exitcode = code,
		timedOut = false,
		stdout = "",
		stderr = "",
	}
end

local function reportOf(cases: { { name: string, pass: boolean } }): Verify.Report
	local clock = 0
	local harness = Verify.createHarness {
		now = function(): number
			clock += 0.001
			return clock
		end,
		prefixIds = false,
	}
	for _, entry in cases do
		harness:case(entry.name, function(context)
			context:expect(entry.pass):toBe(true)
		end)
	end
	return harness:run { executor = "hidden" }
end

local function executor(files: AgentEval.Files, handlers: { [string]: Handler }, started: { Gate.Job }?): Gate.Executor
	local clock = 0
	return {
		now = function(): number
			return clock
		end,
		wait = function(seconds: number)
			clock += seconds
		end,
		start = function(job: Gate.Job): Gate.Task
			if started ~= nil then
				table.insert(started, job)
			end
			local handler = handlers[job.argv[1]]
			local outcome = if handler ~= nil then handler(job, files) else exited(127)
			clock += 0.25
			return {
				poll = function(): Gate.JobOutcome?
					return outcome
				end,
			}
		end,
	}
end

local function handlers(): { [string]: Handler }
	return {
		need = function(job: Gate.Job, files: AgentEval.Files): Gate.JobOutcome
			return exited(if files.exists(job.argv[2]) then 0 else 1)
		end,
		write = function(job: Gate.Job, files: AgentEval.Files): Gate.JobOutcome
			files.write(job.argv[2], job.argv[3])
			return exited(0)
		end,
		fail = function(): Gate.JobOutcome
			return exited(1)
		end,
		cases = function(job: Gate.Job, files: AgentEval.Files): Gate.JobOutcome
			local outcome = exited(0)
			local pass = files.exists(job.argv[2])
			outcome.report = {
				runId = job.runId,
				report = reportOf { { name = "loads", pass = true }, { name = "works", pass = pass } },
			}
			if not pass then
				outcome.exitcode = 1
			end
			return outcome
		end,
	}
end

local function services(files: AgentEval.Files, overrides: { [string]: Handler }?): (AgentEval.Services, { Gate.Job })
	local known = handlers()
	local extra: { [string]: Handler } = overrides or {}
	for name, handler in extra do
		known[name] = handler
	end
	local started: { Gate.Job } = {}
	local tick = 0
	local printed: { string } = {}
	local value: AgentEval.Services = {
		files = files,
		execute = function(_command: AgentEval.Command): AgentEval.Execution
			error("this test runs no process", 0)
		end,
		checks = function(gate: Gate.Definition, _directory: string, runId: string): Gate.Outcome
			return Gate.run(gate, executor(files, known, started), { runId = runId })
		end,
		hash = hash,
		now = function(): number
			tick += 1
			return tick
		end,
		clock = function(): number
			tick += 1
			return 1000 + tick
		end,
		spawn = function(body: () -> ())
			body()
		end,
		wait = function(_seconds: number) end,
		environment = function(_name: string): string?
			return nil
		end,
		print = function(line: string)
			table.insert(printed, line)
		end,
		workspaces = "/live",
	}
	return value, started
end

local function json(value: unknown): string
	return Lute.encode(value)
end

export type StreamOptions = {
	session: string,
	turns: number,
	output: number,
	subtype: string?,
	cost: number?,
	result: boolean?,
}

local function stream(options: StreamOptions): { AgentEval.Line }
	local lines: { AgentEval.Line } = {}
	local function emit(at: number, event: { [string]: unknown })
		event.session_id = options.session
		table.insert(lines, { at = at, text = json(event) })
	end
	emit(0.5, {
		type = "system",
		subtype = "init",
		model = "claude-opus-5-5",
		tools = { "Read", "Write" },
		mcp_servers = { { name = "docs", status = "connected" } },
		claude_code_version = "9.9.9",
	})
	local at = 0.5
	for turn = 1, options.turns do
		local id = ("%s-message-%d"):format(options.session, turn)
		local tool = ("%s-tool-%d"):format(options.session, turn)
		local usage = {
			input_tokens = 10,
			cache_creation_input_tokens = 100,
			cache_read_input_tokens = 1000,
			output_tokens = options.output,
		}
		local function assistant(time: number, content: { unknown })
			emit(
				time,
				{ type = "assistant", message = { id = id, role = "assistant", content = content, usage = usage } }
			)
		end
		at += 2
		assistant(at, { { type = "text", text = "working" } })
		assistant(at + 0.1, { { type = "tool_use", id = tool, name = "Write", input = {} } })
		at += 1
		emit(
			at,
			{
				type = "user",
				message = { role = "user", content = { { type = "tool_result", tool_use_id = tool, content = "ok" } } },
			}
		)
	end
	if options.result ~= false then
		at += 0.5
		emit(at, {
			type = "result",
			subtype = options.subtype or "success",
			is_error = options.subtype ~= nil and options.subtype ~= "success",
			num_turns = options.turns,
			duration_ms = at * 1000,
			duration_api_ms = options.turns * 1500,
			total_cost_usd = options.cost or 0.01 * options.turns,
			result = "done",
			usage = {
				input_tokens = 10 * options.turns,
				cache_creation_input_tokens = 100 * options.turns,
				cache_read_input_tokens = 1000 * options.turns,
				output_tokens = options.output * options.turns,
			},
			permission_denials = {},
		})
	end
	return lines
end
return {
	memory = memory,
	loader = loader,
	services = services,
	executor = executor,
	reportOf = reportOf,
	exited = exited,
	hash = hash,
	json = json,
	stream = stream,
}
