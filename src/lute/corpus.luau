--!strict

local Types = require "../core/types"

export type DirEntry = { name: string, type: string }
export type ListDir = (path: string) -> { DirEntry }
export type ReadFile = (path: string) -> string

export type Rule = {
	root: string,
	pattern: string,
	exclude: string?,
}

export type Discovery = {
	listDir: ListDir,
	rules: { Rule },
}

export type Query = {
	root: string?,
	pattern: string?,
	name: string?,
}

export type LockField = { name: string, value: number | string }
export type LockSection = { name: string, fields: { LockField } }

local LOCK_SCHEMA_VERSION = 1

local MAGIC = "([%^%$%(%)%%%.%[%]%*%+%-%?])"

local function literal(text: string): string
	return (string.gsub(text, MAGIC, "%%%1"))
end

local function walk(root: string, rule: Rule, listDir: ListDir, into: { string })
	local entries = listDir(root)
	table.sort(entries, function(left, right)
		return left.name < right.name
	end)
	for _, entry in entries do
		local child = root .. "/" .. entry.name
		if entry.type == "dir" then
			walk(child, rule, listDir, into)
		elseif entry.type == "file" and string.match(entry.name, rule.pattern) ~= nil then
			if rule.exclude == nil or string.match(entry.name, rule.exclude :: string) == nil then
				table.insert(into, child)
			end
		end
	end
end

local function discover(spec: Discovery): { string }
	if type(spec) ~= "table" or type(spec.listDir) ~= "function" or type(spec.rules) ~= "table" then
		error("corpus discovery needs a listDir and a rule list", 2)
	end
	local seen: { [string]: boolean } = {}
	local files: { string } = {}
	for index, rule in spec.rules do
		if type(rule.root) ~= "string" or rule.root == "" then
			error(("corpus rule %d has no root"):format(index), 2)
		end
		if type(rule.pattern) ~= "string" or rule.pattern == "" then
			error(("corpus rule %d has no pattern"):format(index), 2)
		end
		local found: { string } = {}
		walk(rule.root, rule, spec.listDir, found)
		for _, path in found do
			if not seen[path] then
				seen[path] = true
				table.insert(files, path)
			end
		end
	end
	table.sort(files)
	return files
end

local function groupByRequire(files: { string }, readFile: ReadFile, aliasPattern: string): { { string } }
	if type(aliasPattern) ~= "string" or aliasPattern == "" then
		error("grouping needs the consumer's require pattern", 2)
	end
	local indexOf: { [string]: number } = {}
	for index, file in files do
		indexOf[file] = index
	end

	local parent: { number } = table.create(#files)
	for index = 1, #files do
		parent[index] = index
	end
	local function find(node: number): number
		while parent[node] ~= node do
			parent[node] = parent[parent[node]]
			node = parent[node]
		end
		return node
	end
	local function union(left: number, right: number)
		local rootLeft, rootRight = find(left), find(right)
		if rootLeft ~= rootRight then
			parent[rootLeft] = rootRight
		end
	end

	for index, file in files do
		local read, source: any = pcall(readFile, file)
		if not read then
			continue
		end
		for capture in string.gmatch(source :: string, aliasPattern) do
			for _, candidate in { capture, capture .. ".luau", capture .. "/init.luau" } do
				local target = indexOf[candidate]
				if target ~= nil then
					union(index, target)
				end
			end
		end
	end

	local byRoot: { [number]: { string } } = {}
	for index, file in files do
		local root = find(index)
		local group = byRoot[root]
		if group == nil then
			group = {}
			byRoot[root] = group
		end
		table.insert(group, file)
	end

	local groups: { { string } } = {}
	for _, group in byRoot do
		table.sort(group)
		table.insert(groups, group)
	end
	table.sort(groups, function(left, right)
		return left[1] < right[1]
	end)
	return groups
end

local function workers(threadCount: number, override: number?, fileCount: number, margin: number, cap: number): number
	local count = if override ~= nil then override else threadCount - margin
	count = math.max(1, count)
	count = math.min(count, cap)
	count = math.min(count, math.max(1, fileCount))
	return count
end

local function selection(files: { string }, query: Query?): Types.PlanSelection
	local asked: Query = if query ~= nil then query else {}
	if asked.pattern ~= nil and asked.name ~= nil then
		error("a corpus query names a pattern or a literal name, never both", 2)
	end
	local pattern = if asked.name ~= nil then literal(asked.name :: string) else asked.pattern
	local root = asked.root
	local matched: { [string]: boolean } = {}
	for _, file in files do
		if root ~= nil and root ~= "" and file ~= root and string.sub(file, 1, #root + 1) ~= root .. "/" then
			continue
		end
		if pattern ~= nil and pattern ~= "" then
			local name = string.match(file, "([^/]+)$")
			if name == nil or string.match(name :: string, pattern :: string) == nil then
				continue
			end
		end
		matched[file] = true
	end
	return {
		predicate = function(subject: Types.SelectionSubject): boolean
			return matched[subject.id] == true
		end,
	}
end

local function lockText(sections: { LockSection }): string
	local lines: { string } = {
		"--!strict",
		"",
		"return table.freeze({",
		("	schemaVersion = %d,"):format(LOCK_SCHEMA_VERSION),
	}
	for _, section in sections do
		if type(section.name) ~= "string" or section.name == "" then
			error("every lock section needs a name", 2)
		end
		table.insert(lines, ("	%s = table.freeze({"):format(section.name))
		for _, field in section.fields do
			if type(field.name) ~= "string" or field.name == "" then
				error(("lock section %s has an unnamed field"):format(section.name), 2)
			end
			if type(field.value) == "number" then
				table.insert(lines, ("		%s = %d,"):format(field.name, field.value :: number))
			elseif type(field.value) == "string" then
				table.insert(lines, ("		%s = %q,"):format(field.name, field.value :: string))
			else
				error(("lock field %s.%s is neither a number nor a string"):format(section.name, field.name), 2)
			end
		end
		table.insert(lines, "	}),")
	end
	table.insert(lines, "})")
	table.insert(lines, "")
	return table.concat(lines, "\n")
end

return {
	LOCK_SCHEMA_VERSION = LOCK_SCHEMA_VERSION,
	discover = discover,
	groupByRequire = groupByRequire,
	workers = workers,
	literal = literal,
	selection = selection,
	lockText = lockText,
}
