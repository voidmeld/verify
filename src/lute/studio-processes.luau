--!strict

local process = require "@std/process"
local task = require "@std/task"

export type Proc = { pid: number, ppid: number, command: string }

export type Deps = {
	list: () -> { Proc },
	signal: (pid: number, name: "TERM" | "KILL") -> (),
	wait: (seconds: number) -> (),
	now: () -> number,
}

export type Cleanup = { terminated: { number }, survivors: { number } }

export type Options = { root: number?, markers: { string }?, termSeconds: number?, killSeconds: number? }

local STUDIO = "RobloxStudio"
local MULTIPLAYER_FLAGS = { "-task StartServer", "-rbxTransportToken" }

local function studioProcs(procs: { Proc }): { Proc }
	local found: { Proc } = {}
	for _, proc in procs do
		if string.find(proc.command, STUDIO, 1, true) ~= nil then
			table.insert(found, proc)
		end
	end
	return found
end

local function defaults(): Deps
	return {
		list = function(): { Proc }
			local result = process.run { "ps", "-Ao", "pid=,ppid=,command=" }
			local procs: { Proc } = {}
			for line in string.gmatch(result.stdout, "[^\n]+") do
				local pid, ppid, command = string.match(line, "^%s*(%d+)%s+(%d+)%s+(.*)$")
				if pid ~= nil then
					table.insert(
						procs,
						{ pid = tonumber(pid) :: number, ppid = tonumber(ppid) :: number, command = command :: string }
					)
				end
			end
			return procs
		end,
		signal = function(pid: number, name: "TERM" | "KILL")
			process.run { "kill", "-" .. name, tostring(pid) }
		end,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
		now = os.clock,
	}
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
	local function descends(proc: Proc): boolean
		local walk: Proc? = proc
		local guard = 0
		while walk ~= nil and guard < 64 do
			if walk.pid == root then
				return true
			end
			walk = byPid[walk.ppid]
			guard += 1
		end
		return false
	end
	local extra: { string } = markers or {}
	local pids: { number } = {}
	for _, proc in studioProcs(procs) do
		if before[proc.pid] then
			continue
		end
		local flagged = false
		for _, flag in MULTIPLAYER_FLAGS do
			flagged = flagged or string.find(proc.command, flag, 1, true) ~= nil
		end
		for _, marker in extra do
			flagged = flagged or string.find(proc.command, marker, 1, true) ~= nil
		end
		if proc.pid == root or (root ~= nil and descends(proc)) or flagged then
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
	local fields = value :: { [string]: unknown }
	local survivors: { number } = {}
	if type(fields.survivors) == "table" then
		for _, pid in fields.survivors :: { unknown } do
			if type(pid) == "number" then
				table.insert(survivors, pid)
			end
		end
	end
	return { terminated = {}, survivors = survivors }
end

return { read = read, snapshot = snapshot, reap = reap, owned = owned, defaults = defaults }
