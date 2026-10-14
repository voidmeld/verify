--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local system = require "@std/system"

local function alive(pid: number): boolean
	if system.win32 then
		local listed = process.run { "tasklist", "/FI", ("PID eq %d"):format(pid), "/FO", "CSV", "/NH" }
		return listed.exitcode == 0 and string.find(listed.stdout, ('","%d","'):format(pid), 1, true) ~= nil
	end
	return process.run({ "kill", "-0", tostring(pid) }).exitcode == 0
end

local function remove(path: string)
	pcall(fs.removeDirectory, path, { recursive = true })
end

local function directoryLock(root: string): ((name: string) -> (string?, string?), (handle: string) -> ())
	local function acquire(name: string): (string?, string?)
		local lock = ("%s/.%s.lock"):format(root, name)
		if not fs.exists(root) then
			fs.createDirectory(root, { makeParents = true })
		end
		if pcall(fs.createDirectory, lock) then
			fs.writeStringToFile(lock .. "/owner", tostring(process.pid()))
			return lock, nil
		end
		local owner = if fs.exists(lock .. "/owner") then tonumber(fs.readFileToString(lock .. "/owner")) else nil
		if owner ~= nil and not alive(owner) then
			remove(lock)
		end
		return nil, "held_by_" .. tostring(owner or "unknown")
	end
	local function release(handle: string)
		remove(handle)
	end
	return acquire, release
end

return {
	directoryLock = directoryLock,
}
