--!strict

local Binding = require "./binding"

export type Files = {
	ensureDirectory: (path: string) -> (),
	claimDirectory: (base: string) -> string,
	removeIfPresent: (path: string) -> (),
}

local namespaceSequence = 0

local function create(fs: Binding.Fs): Files
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
		while true do
			local separator = string.find(path, "/", index, true)
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

return {
	create = create,
}
