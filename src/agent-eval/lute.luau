--!strict

local crypto = require "@lute/crypto"
local fs = require "@std/fs"
local json = require "@std/json"
local net = require "@std/net"
local process = require "@std/process"
local system = require "@std/system"
local task = require "@std/task"
local time = require "@std/time"

local Adapters = require "./adapters"
local Bounded = require "../lute/bounded"
local Gate = require "../gate"
local LuteGate = require "../lute/gate"
local Model = require "./model"
local Paths = require "./paths"
local Services = require "./services"
local Wire = require "../lute/wire"

export type Options = {
	workspaces: string?,
	shell: string?,
	print: ((line: string) -> ())?,
}

local STREAM = table.concat({
	"out=$1; code=$2; input=$3; lute=$4; stamp=$5; err=$6; shift 6",
	'{ cat "$input" | "$@" 2> "$err"; echo $? > "$code"; } | "$lute" run "$stamp" "$out"',
}, "\n")

local PLAIN = table.concat({
	"input=$1; shift",
	'cat "$input" | "$@"',
}, "\n")

local function cwd(): string
	return Paths.normalize(tostring(process.cwd()))
end

local function absolute(path: string): string
	local value = Paths.normalize(path)
	local full = if Paths.absolute(value) then value else cwd() .. "/" .. value
	local prefix = string.match(full, "^%a:/") or (if string.sub(full, 1, 1) == "/" then "/" else "")
	local parts: { string } = {}
	for part in string.gmatch(string.sub(full, #prefix + 1), "[^/]+") do
		if part == ".." then
			if #parts > 0 then
				table.remove(parts)
			end
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	return prefix .. table.concat(parts, "/")
end

local function moduleDirectory(): string
	local source = debug.info(1, "s")
	local path = if source ~= nil then string.gsub(source, "^@", "") else "src/agent-eval/lute.luau"
	return Paths.parent(absolute(path))
end

local STAMP = Paths.join(moduleDirectory(), "stamp.luau")

local function sha256(bytes: string): string
	local value = crypto.digest(crypto.hash.sha256, bytes)
	local out: { string } = {}
	for index = 0, buffer.len(value) - 1 do
		table.insert(out, string.format("%02x", buffer.readu8(value, index)))
	end
	return table.concat(out)
end

local function isDirectory(path: string): boolean
	return fs.exists(path) and fs.type(path) == "dir"
end

local files: Services.Files = {
	read = function(path: string): string
		return fs.readFileToString(path)
	end,
	write = function(path: string, contents: string)
		fs.writeStringToFile(path, contents)
	end,
	exists = function(path: string): boolean
		return fs.exists(path)
	end,
	isDirectory = isDirectory,
	list = function(path: string): { Services.Entry }
		local result: { Services.Entry } = {}
		for _, entry in fs.listDirectory(path) do
			table.insert(result, { name = entry.name, kind = if entry.type == "dir" then "directory" else "file" })
		end
		return result
	end,
	makeDirectory = function(path: string)
		if not fs.exists(path) then
			fs.createDirectory(path, { makeParents = true })
		end
	end,
	remove = function(path: string)
		if isDirectory(path) then
			fs.removeDirectory(path, { recursive = true })
		elseif fs.exists(path) then
			fs.remove(path)
		end
	end,
	copy = function(from: string, to: string)
		fs.copy(from, to)
	end,
	move = function(from: string, to: string)
		fs.move(from, to)
	end,
}

local sequence = 0

local function scratchDirectory(command: Services.Command): string
	sequence += 1
	local base = command.scratch or Paths.join(Paths.normalize(tostring(system.tmpdir())), "verify-agent-eval-io")
	local directory = Paths.join(base, ("io-%d-%d"):format(process.pid(), sequence))
	files.makeDirectory(directory)
	return directory
end

local function execute(shell: string): (command: Services.Command) -> Services.Execution
	return function(command: Services.Command): Services.Execution
		local started = time.now()
		local directory = scratchDirectory(command)
		local input = command.input or "/dev/null"
		local argv: { string }
		local outPath = Paths.join(directory, "stdout.stamped")
		local codePath = Paths.join(directory, "exit-code")
		local errPath = Paths.join(directory, "stderr.txt")
		if command.stamp == true then
			argv = {
				shell,
				"-c",
				STREAM,
				"verify-agent-eval",
				outPath,
				codePath,
				input,
				Paths.normalize(tostring(process.execPath())),
				STAMP,
				errPath,
			}
		else
			argv = { shell, "-c", PLAIN, "verify-agent-eval", input }
		end
		for _, word in command.argv do
			table.insert(argv, word)
		end
		local ran = Bounded.run(argv, command.deadlineSeconds, nil, { env = command.env, cwd = command.cwd })
		local seconds = time.since(started)
		local launched = not ran.unsupported and (ran.exitcode ~= -1 or ran.stderr == "" or ran.timedOut)
		local execution: Services.Execution = {
			started = launched,
			exitcode = ran.exitcode,
			timedOut = ran.timedOut,
			unsupported = ran.unsupported,
			stdout = ran.stdout,
			stderr = ran.stderr,
			lines = {},
			seconds = seconds,
			detail = if ran.unsupported or not launched then ran.stderr else nil,
		}
		if command.stamp == true then
			if fs.exists(outPath) then
				local text = fs.readFileToString(outPath)
				execution.stdout = text
				execution.lines = Adapters.parseStamped(text)
			end
			if fs.exists(errPath) then
				execution.stderr = fs.readFileToString(errPath) .. ran.stderr
			end
			if fs.exists(codePath) then
				local code = tonumber(string.match(fs.readFileToString(codePath), "%-?%d+") or "")
				if code ~= nil then
					execution.exitcode = code
				end
			elseif not ran.timedOut and execution.started then
				execution.exitcode = -1
			end
		else
			execution.lines = Services.lines(ran.stdout)
		end
		pcall(files.remove, directory)
		return execution
	end
end

local function request(input: Services.HttpRequest): (Services.HttpResponse?, string?)
	local done = false
	local response: Services.HttpResponse? = nil
	local problem: string? = nil
	task.spawn(function()
		local ok, value = pcall(net.request, input.url, {
			method = input.method,
			headers = input.headers,
			body = input.body,
		})
		if ok then
			local answer = value :: net.Response
			response = { status = answer.status, body = answer.body }
		else
			problem = tostring(value)
		end
		done = true
	end)
	local started = time.now()
	while not done do
		if time.since(started) > input.deadlineSeconds then
			return nil, ("no answer within %d second(s)"):format(math.ceil(input.deadlineSeconds))
		end
		task.wait(0.05)
	end
	return response, problem
end

local function checks(gate: Gate.Definition, directory: string, runId: string): Gate.Outcome
	return LuteGate.run(gate, { directory = directory, runId = runId })
end

local function encode(value: unknown): string
	return json.serialize(value :: json.Value, true)
end

local function decode(text: string): unknown
	return Wire.parse(text)
end

local function services(options: Options?): Services.Services
	local given: Options = options or {}
	local workspaces =
		absolute(given.workspaces or Paths.join(Paths.normalize(tostring(system.tmpdir())), "verify-agent-eval"))
	local started = time.now()
	return {
		files = files,
		execute = execute(given.shell or "sh"),
		checks = checks,
		hash = sha256,
		now = function(): number
			return time.since(started)
		end,
		clock = function(): number
			return os.time()
		end,
		spawn = function(body: () -> ())
			task.spawn(body)
		end,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
		request = request,
		environment = function(name: string): string?
			return process.env[name]
		end,
		print = given.print or function(line: string)
			print(line)
		end,
		workspaces = workspaces,
	}
end

local function loader(): Model.Loader
	return { files = files, hash = sha256, decodeJson = decode }
end

return {
	STAMP = STAMP,
	services = services,
	loader = loader,
	files = files,
	encode = encode,
	decode = decode,
	absolute = absolute,
	sha256 = sha256,
}
