--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local system = require "@std/system"

local Files = require "../runtime/files"

local bound = Files.create {
	read = fs.readFileToString,
	write = fs.writeStringToFile,
	exists = fs.exists,
	createDirectory = fs.createDirectory,
	remove = fs.remove,
}

local function absolute(path: string): string
	if not system.win32 then
		return if string.sub(path, 1, 1) == "/" then path else tostring(process.cwd()) .. "/" .. path
	end
	local slashed = string.gsub(path, "\\", "/")
	if string.match(slashed, "^%a:/") ~= nil or string.sub(slashed, 1, 1) == "/" then
		return slashed
	end
	return (string.gsub(tostring(process.cwd()), "\\", "/")) .. "/" .. slashed
end

local function hasScheme(reference: string): boolean
	if system.win32 and string.match(reference, "^%a:[/\\]") ~= nil then
		return false
	end
	return string.match(reference, "^%a[%w+.-]*:") ~= nil
end

local function temporary(name: string): string
	assert(name ~= "" and string.find(name, "[/\\]") == nil, "a temporary directory needs a plain name")
	if system.win32 then
		return (string.gsub(tostring(system.tmpdir()), "\\", "/")) .. "/" .. name
	end
	return "/tmp/" .. name
end

return {
	ensureDirectory = bound.ensureDirectory,
	claimDirectory = bound.claimDirectory,
	removeIfPresent = bound.removeIfPresent,
	absolute = absolute,
	hasScheme = hasScheme,
	temporary = temporary,
}
