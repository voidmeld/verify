--!strict

local sha256 = require "../lute/hash"
local fs = require "@std/fs"
local json = require "@std/json"
local net = require "@std/net"
local process = require "@std/process"
local system = require "@std/system"
local task = require "@std/task"
local time = require "@std/time"

local Adapters = require "./adapters"
local Bounded = require "../lute/bounded"
local Files = require "../lute/files"
local Gate = require "../gate"
local LuteGate = require "../lute/gate"
local Model = require "./model"
local Paths = require "../core/path"
local Powershell = require "../lute/powershell"
local Services = require "./services"
local Wire = require "../lute/wire"
local Studio = require "../lute/studio"
local Install = require "../lute/studio-install"

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

local BRIDGE = table.concat({
	"$ErrorActionPreference = 'Stop'",
	"$ProgressPreference = 'SilentlyContinue'",
	"$spec = [System.IO.File]::ReadAllText($specPath) | ConvertFrom-Json",
	"$utf8 = New-Object System.Text.UTF8Encoding($false)",
	"try { [Console]::InputEncoding = $utf8 } catch { }",
	"$info = New-Object System.Diagnostics.ProcessStartInfo",
	"$info.FileName = $spec.file",
	"$info.Arguments = $spec.arguments",
	"$info.UseShellExecute = $false",
	"$info.RedirectStandardInput = $true",
	"$info.RedirectStandardOutput = $true",
	"$info.RedirectStandardError = $true",
	"$info.StandardOutputEncoding = $utf8",
	"$info.StandardErrorEncoding = $utf8",
	"$info.CreateNoWindow = $true",
	"$watch = [System.Diagnostics.Stopwatch]::StartNew()",
	"try { $child = [System.Diagnostics.Process]::Start($info) } catch {",
	"  $message = 'the command could not start: ' + $_.Exception.Message",
	"  if ($spec.stamp) { [System.IO.File]::WriteAllText($spec.err, $message); [System.IO.File]::WriteAllText($spec.code, '127') }",
	"  else { [Console]::Error.WriteLine($message) }",
	"  exit 127",
	"}",
	"if ($spec.stamp) { $errorSink = New-Object System.IO.FileStream($spec.err, [System.IO.FileMode]::Create) }",
	"else { $errorSink = [Console]::OpenStandardError() }",
	"$errors = $child.StandardError.BaseStream.CopyToAsync($errorSink)",
	"$source = $null",
	"$feed = $null",
	"if ($spec.input) {",
	"  $source = [System.IO.File]::OpenRead($spec.input)",
	"  $feed = $source.CopyToAsync($child.StandardInput.BaseStream)",
	"}",
	"$script:open = $true",
	"function Close-Input {",
	"  if ($script:open -and ($feed -eq $null -or $feed.IsCompleted)) {",
	"    if ($source -ne $null) { $source.Dispose() }",
	"    try { $child.StandardInput.Close() } catch { }",
	"    $script:open = $false",
	"  }",
	"}",
	"if ($spec.stamp) {",
	"  $out = New-Object System.IO.StreamWriter($spec.out, $false, $utf8)",
	"  $out.AutoFlush = $true",
	"  $culture = [System.Globalization.CultureInfo]::InvariantCulture",
	"  $pending = $child.StandardOutput.ReadLineAsync()",
	"  while ($true) {",
	"    Close-Input",
	"    if ($pending.Wait(20)) {",
	"      $text = $pending.Result",
	"      if ($text -eq $null) { break }",
	"      $out.Write($watch.Elapsed.TotalSeconds.ToString('F6', $culture) + [char]9 + $text + [char]10)",
	"      $pending = $child.StandardOutput.ReadLineAsync()",
	"    }",
	"  }",
	"  $out.Dispose()",
	"} else {",
	"  $copy = $child.StandardOutput.BaseStream.CopyToAsync([Console]::OpenStandardOutput())",
	"  while (-not $copy.Wait(20)) { Close-Input }",
	"}",
	"Close-Input",
	"[void]$errors.Wait(5000)",
	"$child.WaitForExit()",
	"$errorSink.Flush()",
	"if ($spec.stamp) { $errorSink.Dispose(); [System.IO.File]::WriteAllText($spec.code, [string]$child.ExitCode); exit 0 }",
	"exit $child.ExitCode",
}, "\n")

local function windowsArgument(word: string): string
	if word ~= "" and string.find(word, '[%s"]') == nil then
		return word
	end
	local parts: { string } = { '"' }
	local slashes = 0
	for index = 1, #word do
		local character = string.sub(word, index, index)
		if character == "\\" then
			slashes += 1
		elseif character == '"' then
			table.insert(parts, string.rep("\\", slashes * 2 + 1) .. '"')
			slashes = 0
		else
			table.insert(parts, string.rep("\\", slashes) .. character)
			slashes = 0
		end
	end
	table.insert(parts, string.rep("\\", slashes * 2) .. '"')
	return table.concat(parts)
end

local function windowsCommandLine(words: { string }): string
	local quoted: { string } = {}
	for _, word in words do
		table.insert(quoted, windowsArgument(word))
	end
	return table.concat(quoted, " ")
end

local function cwd(): string
	return Paths.normalize(tostring(process.cwd()))
end

local function absolute(path: string): string
	local value = Paths.normalize(path)
	local full = if Paths.absolute(value) then value else cwd() .. "/" .. value
	return Paths.collapse(full)
end

local function moduleDirectory(): string
	local source = debug.info(1, "s")
	local path = if source ~= nil then string.gsub(source, "^@", "") else "src/agent-eval/lute.luau"
	return Paths.parent(absolute(path))
end

local STAMP = Paths.join(moduleDirectory(), "stamp.luau")

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
	makeDirectory = Files.ensureDirectory,
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

local function bridged(
	command: Services.Command,
	directory: string,
	outPath: string,
	codePath: string,
	errPath: string
): { string }
	local specPath = Paths.join(directory, "command.json")
	fs.writeStringToFile(
		specPath,
		json.serialize({
			file = command.argv[1],
			arguments = windowsCommandLine { table.unpack(command.argv, 2) },
			input = command.input or "",
			stamp = command.stamp == true,
			out = outPath,
			code = codePath,
			err = errPath,
		} :: json.Value)
	)
	local literal = "'" .. string.gsub(specPath, "'", "''") .. "'"
	return Powershell.command("$specPath = " .. literal .. "\n" .. BRIDGE)
end

local function posix(
	shell: string,
	command: Services.Command,
	outPath: string,
	codePath: string,
	errPath: string
): { string }
	local input = command.input or "/dev/null"
	local argv: { string } = if command.stamp == true
		then {
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
		else { shell, "-c", PLAIN, "verify-agent-eval", input }
	for _, word in command.argv do
		table.insert(argv, word)
	end
	return argv
end

local function execute(shell: string?): (command: Services.Command) -> Services.Execution
	return function(command: Services.Command): Services.Execution
		local started = time.now()
		local directory = scratchDirectory(command)
		local outPath = Paths.join(directory, "stdout.stamped")
		local codePath = Paths.join(directory, "exit-code")
		local errPath = Paths.join(directory, "stderr.txt")
		local argv = if shell == nil
			then bridged(command, directory, outPath, codePath, errPath)
			else posix(shell, command, outPath, codePath, errPath)
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

local function studio(
	workspace: string,
	directory: string,
	place: string,
	build: { string },
	seconds: number
): { config: string, close: (keep: boolean?) -> () }
	assert(#build > 0, "scoped Studio requires a build command")
	local built = execute(if system.win32 then nil else "sh") {
		argv = build,
		cwd = workspace,
		deadlineSeconds = math.min(seconds, 300),
	}
	assert(built.started and built.exitcode == 0 and not built.timedOut, "Studio build failed: " .. built.stderr)
	local installed, missing = Install.locate()
	assert(installed ~= nil, missing)
	local launched, problem =
		Studio.launch { place = place, directory = directory .. "/studio", runSeconds = seconds + 300 }
	assert(launched ~= nil, problem)
	local opened = launched
	local scopeFile = directory .. "/studio-scope.json"
	local config = directory .. "/mcp.json"
	local script = absolute(Paths.join(moduleDirectory(), "../../tools/scoped-studio-mcp.luau"))
	local ok, reason = pcall(function()
		files.write(
			scopeFile,
			encode {
				studio = opened.session.studio,
				executable = installed.mcp,
				directory = directory .. "/studio-proxy",
				seconds = seconds,
			}
		)
		files.write(
			config,
			encode { mcpServers = { studio = { command = "lute", args = { "run", script, scopeFile } } } }
		)
	end)
	if not ok then
		opened.close()
		error(reason, 0)
	end
	return {
		config = config,
		close = function(keep: boolean?)
			if keep then
				local stopped = opened.session.play(false)
				assert(stopped.ok, stopped.detail)
				local released = opened.session.close()
				assert(released.acknowledged and released.restored, "scoped Studio release failed")
				files.write(
					directory .. "/studio-place.json",
					encode {
						studio = opened.session.studio,
						place = opened.place,
						pid = opened.pid,
					}
				)
				files.remove(scopeFile)
				return
			end
			local closed = opened.close()
			files.remove(scopeFile)
			assert(#closed.survivors == 0 and closed.session.acknowledged, "scoped Studio cleanup failed")
		end,
	}
end

local function services(options: Options?): Services.Services
	local given: Options = options or {}
	local workspaces =
		absolute(given.workspaces or Paths.join(Paths.normalize(tostring(system.tmpdir())), "verify-agent-eval"))
	local started = time.now()
	return {
		studio = studio,
		files = files,
		execute = execute(given.shell or (if system.win32 then nil else "sh")),
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
