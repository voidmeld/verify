--!strict

local fs = require "@std/fs"

export type File = {
	path: string,
	contents: string,
}

export type Skip = (relative: string, kind: string) -> boolean

local function listSorted(root: string): ({ string }, { [string]: string })
	local names: { string } = {}
	local kinds: { [string]: string } = {}
	for _, entry in fs.listDirectory(root) do
		table.insert(names, entry.name)
		kinds[entry.name] = entry.type
	end
	table.sort(names)
	return names, kinds
end

local function collectPaths(root: string, relativeRoot: string, suffixes: { string }, skip: Skip?, found: { string })
	local names, kinds = listSorted(root)
	for _, name in names do
		local child = root .. "/" .. name
		local relative = if relativeRoot == "" then name else relativeRoot .. "/" .. name
		local kind = kinds[name]
		if skip ~= nil and skip(relative, kind) then
			continue
		end
		if kind == "dir" then
			collectPaths(child, relative, suffixes, skip, found)
		else
			for _, suffix in suffixes do
				if suffix == "" or string.sub(name, -#suffix) == suffix then
					table.insert(found, child)
					break
				end
			end
		end
	end
end

local function paths(root: string, suffixes: { string }, found: { string }?): { string }
	local collected = if found ~= nil then found else {}
	if not fs.exists(root) then
		return collected
	end
	collectPaths(root, "", suffixes, nil, collected)
	return collected
end

local function pathsSkipping(root: string, suffixes: { string }, skip: Skip): { string }
	local collected: { string } = {}
	if fs.exists(root) then
		collectPaths(root, "", suffixes, skip, collected)
	end
	return collected
end

local function files(root: string, suffixes: { string }): { File }
	local collected: { File } = {}
	for _, path in paths(root, suffixes) do
		table.insert(collected, { path = path, contents = fs.readFileToString(path) })
	end
	return collected
end

local function filesSkipping(root: string, suffixes: { string }, skip: Skip): { File }
	local collected: { File } = {}
	for _, path in pathsSkipping(root, suffixes, skip) do
		table.insert(collected, { path = path, contents = fs.readFileToString(path) })
	end
	return collected
end

local function lineOf(contents: string, offset: number): number
	local line = 1
	for index = 1, offset - 1 do
		if string.byte(contents, index) == 10 then
			line += 1
		end
	end
	return line
end

return {
	paths = paths,
	pathsSkipping = pathsSkipping,
	files = files,
	filesSkipping = filesSkipping,
	lineOf = lineOf,
}
