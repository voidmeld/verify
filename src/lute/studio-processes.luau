--!strict

local process = require "@std/process"
local system = require "@std/system"
local task = require "@std/task"

local Powershell = require "./powershell"

export type Proc = { pid: number, ppid: number, command: string }

export type Deps = {
	list: () -> { Proc },
	signal: (pid: number, name: "TERM" | "KILL") -> (),
	wait: (seconds: number) -> (),
	now: () -> number,
}

export type Cleanup = { terminated: { number }, survivors: { number } }

export type Options = { root: number?, markers: { string }?, termSeconds: number?, killSeconds: number? }

export type Listing = () -> ({ Proc }, string?)

export type Studio = {
	pid: number,
	ppid: number,
	command: string,
	executable: string,
	arguments: { string },
	flags: { [string]: string },
	place: string?,
}

export type Inventory = { status: "ok", studios: { Studio } } | { status: "error", reason: string }

local STUDIO = "RobloxStudio"
local EXECUTABLE = if system.win32 then "RobloxStudioBeta.exe" else "/Contents/MacOS/RobloxStudio"

local function studioProcs(procs: { Proc }): { Proc }
	local found: { Proc } = {}
	for _, proc in procs do
		if string.find(proc.command, STUDIO, 1, true) ~= nil then
			table.insert(found, proc)
		end
	end
	return found
end

local LISTING = table.concat({
	"Get-CimInstance Win32_Process | ForEach-Object {",
	"  '{0} {1} {2}' -f $_.ProcessId, $_.ParentProcessId, ($_.CommandLine -replace '[\\r\\n]', ' ')",
	"}",
}, "\n")

local function parse(text: string): { Proc }
	local procs: { Proc } = {}
	for line in string.gmatch(text, "[^\r\n]+") do
		local pid, ppid, command = string.match(line, "^%s*(%d+)%s+(%d+)%s*(.*)$")
		if pid ~= nil then
			local processId, parentId = tonumber(pid), tonumber(ppid)
			assert(processId ~= nil and parentId ~= nil and command ~= nil)
			table.insert(procs, { pid = processId, ppid = parentId, command = command })
		end
	end
	return procs
end

local function listing(): ({ Proc }, string?)
	local result = if system.win32
		then process.run(Powershell.command(LISTING))
		else process.run { "ps", "-A", "-ww", "-o", "pid=,ppid=,command=" }
	if result.exitcode ~= 0 then
		return {}, "Studio process inventory failed"
	end
	return parse(result.stdout), nil
end

local function defaults(): Deps
	return {
		list = function(): { Proc }
			return (listing())
		end,
		signal = function(pid: number, name: "TERM" | "KILL")
			if system.win32 then
				process.run(
					if name == "KILL"
						then { "taskkill", "/F", "/PID", tostring(pid) }
						else { "taskkill", "/PID", tostring(pid) }
				)
				return
			end
			process.run { "kill", "-" .. name, tostring(pid) }
		end,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
		now = os.clock,
	}
end

local function spawn(argv: { string }, marker: string, deadline: number, list: (() -> { Proc })?): number
	local listing = list or defaults().list
	local quiet: process.ProcessRunOptions = { stdio = "none" }
	local launch: { failure: string?, exited: boolean } = { failure = nil, exited = false }
	task.spawn(function()
		local ran, result = pcall(process.run, argv, quiet)
		if not ran then
			launch.failure = tostring(result)
		end
		launch.exited = true
	end)
	local parent = process.pid()
	while not launch.exited and os.clock() < deadline do
		for _, proc in listing() do
			if proc.ppid == parent and string.find(proc.command, marker, 1, true) ~= nil then
				return proc.pid
			end
		end
		task.wait(0.25)
	end
	error(
		"the launched process was not observed: "
			.. (launch.failure or if launch.exited then "it exited first" else "the deadline passed"),
		0
	)
end

local function windowsStart(executable: string, place: string): string
	local function literal(value: string): string
		return "'" .. string.gsub(value, "'", "''") .. "'"
	end
	local arguments = '-task EditFile -localPlaceFile "' .. string.gsub(place, "/", "\\") .. '"'
	return table.concat({
		"$ErrorActionPreference = 'Stop'",
		"$studio = Start-Process -FilePath "
			.. literal(executable)
			.. " -ArgumentList "
			.. literal(arguments)
			.. " -WindowStyle Maximized -PassThru",
		"$studio.Id",
	}, "\n")
end

local function start(executable: string, place: string, marker: string, deadline: number, log: string): number
	if system.win32 then
		local command = Powershell.command(windowsStart(executable, place))
		table.insert(command, 2, "Hidden")
		table.insert(command, 2, "-WindowStyle")
		local launched = process.run(command)
		assert(launched.ok, launched.stderr)
		local pid = tonumber(string.match(launched.stdout, "^%s*(%d+)%s*$"))
		assert(pid ~= nil, "Studio launch did not return a process id")
		return pid
	end
	local launched = process.run {
		"sh",
		"-c",
		'"$1" -task EditFile -localPlaceFile "$2" >"$3" 2>&1 & echo $!',
		"verify-studio",
		executable,
		place,
		log,
	}
	assert(launched.ok, launched.stderr)
	local pid = tonumber(string.match(launched.stdout, "%d+"))
	assert(pid ~= nil, "Studio launch did not return a process id")
	return pid
end

local function snapshot(deps: Deps?): { [number]: boolean }
	local active = deps or defaults()
	local before: { [number]: boolean } = {}
	for _, proc in studioProcs(active.list()) do
		before[proc.pid] = true
	end
	return before
end

local function owned(procs: { Proc }, before: { [number]: boolean }, root: number?, markers: { string }?): { number }
	local byPid: { [number]: Proc } = {}
	for _, proc in procs do
		byPid[proc.pid] = proc
	end
	local roots: { [number]: boolean } = {}
	if root ~= nil then
		roots[root] = true
	end
	local extra: { string } = markers or {}
	for _, proc in studioProcs(procs) do
		if not before[proc.pid] then
			for _, marker in extra do
				if string.find(proc.command, marker, 1, true) ~= nil then
					roots[proc.pid] = true
				end
			end
		end
	end
	local function descends(proc: Proc): boolean
		local walk: Proc? = proc
		local guard = 0
		while walk ~= nil and guard < 64 do
			if roots[walk.pid] then
				return true
			end
			walk = byPid[walk.ppid]
			guard += 1
		end
		return false
	end
	local pids: { number } = {}
	for _, proc in studioProcs(procs) do
		if before[proc.pid] then
			continue
		end
		if descends(proc) then
			table.insert(pids, proc.pid)
		end
	end
	return pids
end

local function alive(deps: Deps, pids: { number }): { number }
	local present: { [number]: boolean } = {}
	for _, proc in deps.list() do
		present[proc.pid] = true
	end
	local remaining: { number } = {}
	for _, pid in pids do
		if present[pid] then
			table.insert(remaining, pid)
		end
	end
	return remaining
end

local function reap(before: { [number]: boolean }, options: Options?, injected: Deps?): Cleanup
	local deps = injected or defaults()
	local settings: Options = options or {}
	local targets = owned(deps.list(), before, settings.root, settings.markers)
	if #targets == 0 then
		return { terminated = {}, survivors = {} }
	end
	for _, pid in targets do
		deps.signal(pid, "TERM")
	end
	local termDeadline = deps.now() + (settings.termSeconds or 3)
	local remaining = alive(deps, targets)
	while #remaining > 0 and deps.now() < termDeadline do
		deps.wait(0.25)
		remaining = alive(deps, targets)
	end
	for _, pid in remaining do
		deps.signal(pid, "KILL")
	end
	local killDeadline = deps.now() + (settings.killSeconds or 3)
	remaining = alive(deps, remaining)
	while #remaining > 0 and deps.now() < killDeadline do
		deps.wait(0.25)
		remaining = alive(deps, remaining)
	end
	local gone: { number } = {}
	local stuck: { [number]: boolean } = {}
	for _, pid in remaining do
		stuck[pid] = true
	end
	for _, pid in targets do
		if not stuck[pid] then
			table.insert(gone, pid)
		end
	end
	return { terminated = gone, survivors = remaining }
end

local function tokens(command: string): { string }
	local values: { string } = {}
	local position = 1
	while true do
		local start = string.find(command, "%S", position)
		if start == nil then
			break
		end
		local value: string
		if string.sub(command, start, start) == '"' then
			local close = string.find(command, '"', start + 1, true) or #command + 1
			value = string.sub(command, start + 1, close - 1)
			position = close + 1
		else
			local finish = string.find(command, "%s", start) or #command + 1
			value = string.sub(command, start, finish - 1)
			position = finish
		end
		table.insert(values, (string.gsub(value, "\\", "/")))
	end
	return values
end

local function percentDecode(value: string): string
	return (
		string.gsub(value, "%%(%x%x)", function(hex: string): string
			return string.char(assert(tonumber(hex, 16)))
		end)
	)
end

local function describe(proc: Proc): Studio?
	local argv = tokens(proc.command)
	local executable = argv[1]
	if executable == nil or string.sub(executable, -#EXECUTABLE) ~= EXECUTABLE then
		return nil
	end
	table.remove(argv, 1)
	local flags: { [string]: string } = {}
	local place: string? = nil
	for index, value in argv do
		local name = string.match(value, "^%-%-?(.+)$")
		if name ~= nil and flags[name] == nil and argv[index + 1] ~= nil then
			flags[name] = argv[index + 1]
		end
		local encoded = string.match(value, "localPlaceFile:(.+)$")
		if encoded ~= nil and place == nil then
			place = percentDecode(encoded)
		end
	end
	return {
		pid = proc.pid,
		ppid = proc.ppid,
		command = proc.command,
		executable = executable,
		arguments = argv,
		flags = flags,
		place = place,
	}
end

local function inventory(list: Listing?): Inventory
	local procs, reason = (list or listing)()
	if reason ~= nil then
		return { status = "error", reason = reason }
	end
	local studios: { Studio } = {}
	for _, proc in procs do
		local studio = describe(proc)
		if studio ~= nil then
			table.insert(studios, studio)
		end
	end
	table.sort(studios, function(left: Studio, right: Studio): boolean
		return left.pid < right.pid
	end)
	return { status = "ok", studios = studios }
end

local function read(path: string): Cleanup?
	local fs = require "@std/fs"
	if not fs.exists(path) then
		return nil
	end
	local json = require "@std/json"
	local ok, value: unknown = pcall(json.deserialize, fs.readFileToString(path))
	if not ok or type(value) ~= "table" then
		return nil
	end
	local fields = value
	local survivors: { number } = {}
	if type(fields.survivors) == "table" then
		for _, pid in fields.survivors do
			if type(pid) == "number" then
				table.insert(survivors, pid)
			end
		end
	end
	return { terminated = {}, survivors = survivors }
end

return {
	inventory = inventory,
	read = read,
	snapshot = snapshot,
	reap = reap,
	owned = owned,
	defaults = defaults,
	parse = parse,
	spawn = spawn,
	start = start,
	windowsStart = windowsStart,
}
