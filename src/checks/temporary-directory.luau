--!strict

local fs = require "@std/fs"
local process = require "@lute/process"
local system = require "@std/system"

local TemporaryDirectory = {}

local ATTEMPTS = 32
local sequence = 0

function TemporaryDirectory.root(): string
	local root = string.gsub(tostring(system.tmpdir()), "\\", "/")
	return (string.gsub(root, "/+$", ""))
end

local function allocate(parent: string, prefix: string): string
	local base = string.gsub(string.gsub(parent, "\\", "/"), "/+$", "")
	for _ = 1, ATTEMPTS do
		sequence += 1
		local suffix = ("%x%04x%06x"):format(process.pid(), sequence, math.random(0, 0xFFFFFF))
		local path = ("%s/%s.%s"):format(base, prefix, suffix)
		if not fs.exists(path) then
			local created = pcall(function()
				fs.createDirectory(path)
			end)
			if created then
				return path
			end
		end
	end
	error("temporary-directory: allocation failed under " .. base, 0)
end

local function removeTree(path: string): string?
	local removed, failure = pcall(function()
		fs.removeDirectory(path, { recursive = true })
	end)
	return if removed then nil else tostring(failure)
end

local function remove(path: string): string?
	local failure = removeTree(path)
	if failure == nil or not system.win32 then
		return failure
	end
	process.run { "attrib", "-R", (string.gsub(path, "/", "\\")) .. "\\*", "/S", "/D" }
	return removeTree(path)
end

function TemporaryDirectory.run<T>(parent: string, prefix: string, body: (string) -> T): T
	assert(string.match(prefix, "^[%w%-]+$") ~= nil, "temporary-directory: invalid prefix")
	local path = allocate(parent, prefix)
	local ok, result = pcall(body, path)
	local cleanupError = remove(path)
	if cleanupError ~= nil then
		error("temporary-directory: cleanup failed for " .. path .. ": " .. cleanupError, 0)
	end
	if not ok then
		error(result, 0)
	end
	return result
end

return TemporaryDirectory
