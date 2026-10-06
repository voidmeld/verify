--!strict

local fs = require "@std/fs"
local process = require "@std/process"

local function exitcode(argv: { string }): number
	return process.run(argv).exitcode
end

local function directoryLock(root: string): ((name: string) -> (string?, string?), (handle: string) -> ())
	local function acquire(name: string): (string?, string?)
		local lock = ("%s/.%s.lock"):format(root, name)
		if not fs.exists(root) then
			fs.createDirectory(root, { makeParents = true })
		end
		if exitcode { "mkdir", lock } == 0 then
			fs.writeStringToFile(lock .. "/owner", tostring(process.pid()))
			return lock, nil
		end
		local owner = if fs.exists(lock .. "/owner") then tonumber(fs.readFileToString(lock .. "/owner")) else nil
		if owner ~= nil and exitcode { "kill", "-0", tostring(owner) } ~= 0 then
			exitcode { "rm", "-rf", lock }
		end
		return nil, "held_by_" .. tostring(owner or "unknown")
	end
	local function release(handle: string)
		exitcode { "rm", "-rf", handle }
	end
	return acquire, release
end

return {
	directoryLock = directoryLock,
}
