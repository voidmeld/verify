--!strict

local fs = require "@std/fs"
local system = require "@std/system"

local Files = require "../runtime/files"

local bound = Files.create {
	read = fs.readFileToString,
	write = fs.writeStringToFile,
	exists = fs.exists,
	createDirectory = fs.createDirectory,
	remove = fs.remove,
}

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
	temporary = temporary,
}
