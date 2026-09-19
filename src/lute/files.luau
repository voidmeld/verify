--!strict

local fs = require "@std/fs"

local function present(path: string): boolean
	local asked, answer: any = pcall(fs.exists, path)
	return asked and answer == true
end

local function ensureDirectory(path: string)
	if present(path) then
		return
	end
	local thrown: unknown = nil
	local index = 1
	while true do
		local separator = string.find(path, "/", index, true)
		local prefix = if separator ~= nil then string.sub(path, 1, separator - 1) else path
		if prefix ~= "" then
			if not present(prefix) then
				local made, reason: any = pcall(fs.createDirectory, prefix)
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

local namespaceSequence = 0

local function claimDirectory(base: string): string
	ensureDirectory(base)
	for _ = 1, 1024 do
		namespaceSequence += 1
		local candidate = ("%s/run-%d-%d"):format(base, os.time(), namespaceSequence)
		local made, reason: any = pcall(fs.createDirectory, candidate)
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

local function listFileNames(directory: string): { string }
	local listed, entries: any = pcall(fs.listDirectory, directory)
	if not listed then
		return {}
	end
	local names: { string } = {}
	for _, entry in entries :: { { name: string, type: string } } do
		if entry.type == "file" then
			table.insert(names, entry.name)
		end
	end
	return names
end

return {
	ensureDirectory = ensureDirectory,
	claimDirectory = claimDirectory,
	removeIfPresent = removeIfPresent,
	listFileNames = listFileNames,
}
