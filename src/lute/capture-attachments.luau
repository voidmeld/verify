--!strict

local fs = require "@std/fs"
local Parts = require "../roblox/capture-attachments"
local Wire = require "./wire"
local Files = require "./files"
local sha256 = require "./hash"

local function write<A>(artifacts: { A }, directory: string): { [string]: string }
	assert(not fs.exists(directory), "capture attachment directory exists; preserve and reconcile it")
	local content = Parts.reassemble(artifacts, Wire.parse, sha256)
	Files.ensureDirectory(directory)
	local paths: { [string]: string } = {}
	for name, bytes in content do
		local path = directory .. "/" .. name
		fs.writeStringToFile(path, bytes)
		local saved = fs.readFileToString(path)
		assert(#saved == #bytes and sha256(saved) == sha256(bytes), "capture disk byte count or SHA-256 differs")
		paths[name] = path
	end
	return paths
end

return { write = write }
