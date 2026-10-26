--!strict

local process = require "@std/process"
local system = require "@std/system"
local fs = require "@std/fs"

local Runtime = require "./runtime"

export type Files = {
	ensureDirectory: (path: string) -> (),
	claimDirectory: (base: string) -> string,
	removeIfPresent: (path: string) -> (),
}

local namespaceSequence = 0

local function create(fs: Runtime.Fs): Files
	local function present(path: string): boolean
		local asked, answer: unknown = pcall(fs.exists, path)
		return asked and answer == true
	end

	local function ensureDirectory(path: string)
		if present(path) then
			return
		end
		local thrown: unknown = nil
		local index = 1
		local drive = string.match(path, "^%a:[/\\]") ~= nil
		while true do
			local separator = if drive then string.find(path, "[/\\]", index) else string.find(path, "/", index, true)
			local prefix = if separator ~= nil then string.sub(path, 1, separator - 1) else path
			if prefix ~= "" then
				if not present(prefix) then
					local made, reason: unknown = pcall(fs.createDirectory, prefix)
					if not made then
						thrown = reason
					end
				end
			end
			if separator == nil then
				break
			end
			index = separator + 1
		end
		if not present(path) then
			error(("the directory %s could not be created: %s"):format(path, tostring(thrown)), 0)
		end
	end

	local function claimDirectory(base: string): string
		ensureDirectory(base)
		for _ = 1, 1024 do
			namespaceSequence += 1
			local candidate = ("%s/run-%d-%d"):format(base, os.time(), namespaceSequence)
			local made, reason: unknown = pcall(fs.createDirectory, candidate)
			if made then
				return candidate
			end
			if not present(candidate) then
				error(("cannot claim worker directory %s: %s"):format(candidate, tostring(reason)), 0)
			end
		end
		error("cannot claim an isolated worker directory under " .. base, 0)
	end

	local function removeIfPresent(path: string)
		pcall(fs.remove, path)
	end

	return {
		ensureDirectory = ensureDirectory,
		claimDirectory = claimDirectory,
		removeIfPresent = removeIfPresent,
	}
end

local bound = create(Runtime.fs)

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

local function readArtifact(reference: string): string
	assert(reference ~= "" and not hasScheme(reference), "reference is not a local file")
	local path = absolute(reference)
	local metadata = fs.metadata(path)
	assert(metadata.type == "file" and metadata.size > 0, "local reference must be a nonempty regular file")
	local bytes = fs.readFileToString(path)
	assert(#bytes > 0, "artifact became empty while reading")
	return bytes
end

local function writeArtifact(path: string, bytes: string)
	fs.writeStringToFile(path, bytes)
	assert(fs.metadata(path).size == #bytes, "artifact copy is incomplete")
end

return {
	create = create,
	ensureDirectory = bound.ensureDirectory,
	claimDirectory = bound.claimDirectory,
	removeIfPresent = bound.removeIfPresent,
	absolute = absolute,
	hasScheme = hasScheme,
	temporary = temporary,
	readArtifact = readArtifact,
	writeArtifact = writeArtifact,
}
