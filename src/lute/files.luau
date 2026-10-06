--!strict

local fs = require "@std/fs"

local Files = require "../runtime/files"

local bound = Files.create {
	read = fs.readFileToString,
	write = fs.writeStringToFile,
	exists = fs.exists,
	createDirectory = fs.createDirectory,
	remove = fs.remove,
}

return {
	ensureDirectory = bound.ensureDirectory,
	claimDirectory = bound.claimDirectory,
	removeIfPresent = bound.removeIfPresent,
}
