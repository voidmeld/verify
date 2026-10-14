--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local system = require "@std/system"
local task = require "@std/task"
local json = require "@std/json"
local Bounded = require "./bounded"
local Files = require "./files"
local Powershell = require "./powershell"
local Runtime = require "./runtime"
local Operations = require "../core/operations"
local Wire = require "./wire"

export type Exchange = {
	status: "answered" | "unsent" | "unanswered",
	result: unknown?,
	detail: string?,
	lost: boolean?,
}

export type Connection = {
	call: (name: string, arguments: { [string]: unknown }) -> unknown,
	callRaw: (name: string, argumentsJson: string, deadline: number) -> Exchange,
	close: () -> (),
	alive: () -> boolean,
}

local EXITED = "studio_mcp_exited"
local WRITE_SECONDS = 3
local LIVENESS_SECONDS = 0.5

local META =
	'"_meta":{"io.modelcontextprotocol/protocolVersion":"2025-06-18","io.modelcontextprotocol/clientCapabilities":{}}'

local function record(value: unknown): { [string]: unknown }
	assert(type(value) == "table", "Studio MCP returned a non-record")
	return value :: { [string]: unknown }
end

type Pipe = {
	alive: () -> boolean,
	send: (line: string) -> (boolean, string?),
	close: () -> (),
}

local function posixPipe(executable: string, directory: string, output: string, errors: string): Pipe
	local fifo = directory .. "/input"
	local started = process.run {
		"sh",
		"-c",
		'mkfifo "$1" || exit 1; exec 3<>"$1"; "$2" <&3 >"$3" 2>"$4" & echo $!',
		"verify-mcp",
		fifo,
		executable,
		output,
		errors,
	}
	assert(started.ok, started.stderr)
	local pid = tonumber(string.match(started.stdout, "%d+"))
	assert(pid ~= nil, "Studio MCP did not start")
	local requestFile = directory .. "/request"
	return {
		alive = function(): boolean
			return process.run({ "kill", "-0", tostring(pid) }).ok
		end,
		send = function(line: string): (boolean, string?)
			fs.writeStringToFile(requestFile, line)
			local sent =
				Bounded.run({ "sh", "-c", 'cat "$1" 1<>"$2"', "verify-mcp-send", requestFile, fifo }, WRITE_SECONDS)
			if sent.unsupported then
				return false, "no process group could be created for the pipe write"
			end
			if sent.timedOut then
				return false, "the pipe write did not finish in " .. WRITE_SECONDS .. "s"
			end
			return sent.ok, if sent.ok then nil else sent.stderr
		end,
		close = function()
			process.run { "kill", "-KILL", tostring(pid) }
		end,
	}
end

local BRIDGE = table.concat({
	"$ErrorActionPreference = 'Stop'",
	"$directory = $env:VERIFY_MCP_DIRECTORY",
	"$info = New-Object System.Diagnostics.ProcessStartInfo",
	"$info.FileName = $env:VERIFY_MCP_EXECUTABLE",
	"$info.UseShellExecute = $false",
	"$info.RedirectStandardInput = $true",
	"$info.RedirectStandardOutput = $true",
	"$info.RedirectStandardError = $true",
	"$info.CreateNoWindow = $true",
	"$child = [System.Diagnostics.Process]::Start($info)",
	"$share = [System.IO.FileShare]::ReadWrite",
	"$mode = [System.IO.FileMode]::Create",
	"$access = [System.IO.FileAccess]::Write",
	"$output = New-Object System.IO.FileStream((Join-Path $directory 'output'), $mode, $access, $share, 1)",
	"$errors = New-Object System.IO.FileStream((Join-Path $directory 'errors'), $mode, $access, $share, 1)",
	"$copies = [System.Threading.Tasks.Task[]]@(",
	"  $child.StandardOutput.BaseStream.CopyToAsync($output),",
	"  $child.StandardError.BaseStream.CopyToAsync($errors))",
	"[System.IO.File]::WriteAllText((Join-Path $directory 'pid'), [string]$child.Id)",
	"$stdin = $child.StandardInput.BaseStream",
	"$next = 1",
	"try {",
	"  while (-not $child.HasExited) {",
	"    $request = Join-Path $directory ('request-{0}' -f $next)",
	"    if ([System.IO.File]::Exists($request)) {",
	"      $bytes = [System.IO.File]::ReadAllBytes($request)",
	"      $stdin.Write($bytes, 0, $bytes.Length)",
	"      $stdin.Flush()",
	"      [System.IO.File]::Delete($request)",
	"      $next++",
	"    } elseif ([System.IO.File]::Exists((Join-Path $directory 'close'))) {",
	"      break",
	"    } else {",
	"      Start-Sleep -Milliseconds 5",
	"    }",
	"  }",
	"} finally {",
	"  if (-not $child.HasExited) { try { [void](& taskkill.exe /T /F /PID $child.Id) } catch { } }",
	"  if (-not $child.HasExited) { $child.Kill() }",
	"  [void]$child.WaitForExit(2000)",
	"  [void][System.Threading.Tasks.Task]::WaitAll($copies, 2000)",
	"  $output.Dispose()",
	"  $errors.Dispose()",
	"  [System.IO.File]::WriteAllText((Join-Path $directory 'exited'), [string]$child.ExitCode)",
	"}",
}, "\n")

local function windowsPipe(executable: string, directory: string, deadline: number): Pipe
	local pidPath, exitedPath = directory .. "/pid", directory .. "/exited"
	local bridge: { done: boolean, detail: string } = { done = false, detail = "" }
	task.spawn(function()
		local ran, result = pcall(
			Runtime.process.run,
			Powershell.command(BRIDGE),
			{ env = { VERIFY_MCP_DIRECTORY = directory, VERIFY_MCP_EXECUTABLE = executable } }
		)
		bridge.detail = if ran then (result :: Runtime.ProcessResult).stderr else tostring(result)
		bridge.done = true
	end)
	while not fs.exists(pidPath) and not bridge.done and os.clock() < deadline do
		task.wait(0.01)
	end
	local pid = if fs.exists(pidPath) then tonumber(fs.readFileToString(pidPath)) else nil
	if pid == nil then
		fs.writeStringToFile(directory .. "/close", "")
		error("Studio MCP did not start: " .. bridge.detail, 0)
	end
	local sent = 0
	local function alive(): boolean
		return not bridge.done and not fs.exists(exitedPath)
	end
	return {
		alive = alive,
		send = function(line: string): (boolean, string?)
			if not alive() then
				return false, EXITED
			end
			sent += 1
			local staged = ("%s/staged-%d"):format(directory, sent)
			fs.writeStringToFile(staged, line)
			fs.move(staged, ("%s/request-%d"):format(directory, sent))
			return true, nil
		end,
		close = function()
			fs.writeStringToFile(directory .. "/close", "")
			local limit = os.clock() + WRITE_SECONDS
			while not bridge.done and os.clock() < limit do
				task.wait(0.02)
			end
			if not bridge.done then
				process.run { "taskkill", "/T", "/F", "/PID", tostring(pid) }
			end
		end,
	}
end

local function connect(executable: string, directory: string, deadline: number): Connection
	Files.ensureDirectory(directory)
	local output, errors = directory .. "/output", directory .. "/errors"
	local pipe = if system.win32
		then windowsPipe(executable, directory, deadline)
		else posixPipe(executable, directory, output, errors)
	local closed, sequence, consumed = false, 0, 0
	local function alive(): boolean
		return not closed and pipe.alive()
	end
	local send = pipe.send
	local answers: { [number]: { [string]: unknown } } = {}
	local function close()
		if closed then
			return
		end
		closed = true
		pipe.close()
	end
	local function exchange(method: string, paramsJson: string, limit: number): Exchange
		if closed or os.clock() >= limit then
			return { status = "unsent", detail = "Studio MCP deadline expired before " .. method }
		end
		sequence += 1
		local id = sequence
		local line = ('{"jsonrpc":"2.0","id":%d,"method":%s,"params":%s}\n'):format(
			id,
			json.serialize(method),
			paramsJson
		)
		if not alive() then
			return { status = "unsent", detail = EXITED, lost = true }
		end
		local wrote, reason = send(line)
		if not wrote then
			return { status = "unsent", detail = tostring(reason) }
		end
		local checkedAt = os.clock()
		while os.clock() < limit and not closed do
			local bytes = if fs.exists(output) then fs.readFileToString(output) else ""
			if #bytes > consumed then
				local chunk = bytes:sub(consumed + 1)
				for text in string.gmatch(chunk, "([^\n]+)\n") do
					local parsed, value: unknown = pcall(Wire.parse, text)
					if parsed and type(value) == "table" then
						local fields = value :: { [string]: unknown }
						if type(fields.id) == "number" then
							answers[fields.id] = fields
						end
					end
				end
				consumed += string.find(chunk, "\n[^\n]*$") or 0
			end
			local fields = answers[id]
			if fields ~= nil then
				answers[id] = nil
				if fields.error ~= nil then
					return { status = "answered", detail = json.serialize(fields.error :: json.Value) }
				end
				return { status = "answered", result = fields.result }
			end
			if os.clock() - checkedAt >= LIVENESS_SECONDS then
				checkedAt = os.clock()
				if not alive() then
					return { status = "unanswered", detail = EXITED, lost = true }
				end
			end
			task.wait(0.05)
		end
		return { status = "unanswered", detail = "Studio MCP deadline expired for " .. method }
	end
	local function handshake()
		local initialize = exchange(
			"initialize",
			'{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"verify","version":"1"},'
				.. META
				.. "}",
			deadline
		)
		assert(initialize.status == "answered" and initialize.detail == nil, initialize.detail or initialize.status)
		local notified, problem = send '{"jsonrpc":"2.0","method":"notifications/initialized"}\n'
		assert(notified, problem)
	end
	local ok, reason: unknown = pcall(handshake)
	if not ok then
		close()
		error(reason, 0)
	end
	local function callRaw(name: string, argumentsJson: string, limit: number): Exchange
		return exchange(
			"tools/call",
			('{"name":%s,"arguments":%s,%s}'):format(json.serialize(name), argumentsJson, META),
			limit
		)
	end
	return {
		close = close,
		alive = alive,
		callRaw = callRaw,
		call = function(name, arguments)
			local argumentsJson = if next(arguments) == nil
				then "{}"
				else json.serialize(Operations.snapshot(arguments) :: json.Value)
			local reply = callRaw(name, argumentsJson, deadline)
			assert(reply.status == "answered" and reply.detail == nil, reply.detail or reply.status)
			local result = record(reply.result)
			assert(
				result.isError ~= true,
				"Studio MCP tool failed: " .. json.serialize((result :: unknown) :: json.Value)
			)
			return result
		end,
	}
end

return { connect = connect, record = record, EXITED = EXITED }
