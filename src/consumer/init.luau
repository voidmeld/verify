--!strict

export type Finding = {
	code: string,
	offset: number,
	why: string,
	fix: string,
}

export type ProductionFinding = {
	code: string,
	path: string,
	why: string,
	fix: string,
}

export type DirEntry = { name: string, type: string }
export type ListDir = (path: string) -> { DirEntry }
export type ReadFile = (path: string) -> string

export type TreeFinding = Finding & { path: string }

export type TreeOptions = {
	listDir: ListDir,
	readFile: ReadFile,

	isSpecification: ((path: string) -> boolean)?,

	exempt: ((path: string) -> boolean)?,
}

export type TreeReport = {

	findings: { TreeFinding },

	productionFindings: { ProductionFinding },
}

local function longBracketLevel(contents: string, index: number): number?
	if string.sub(contents, index, index) ~= "[" then
		return nil
	end
	local cursor = index + 1
	while string.sub(contents, cursor, cursor) == "=" do
		cursor += 1
	end
	if string.sub(contents, cursor, cursor) ~= "[" then
		return nil
	end
	return cursor - index - 1
end

local function longBracketEnd(contents: string, openAt: number, level: number): number
	local closing = "]" .. string.rep("=", level) .. "]"
	local _, last = string.find(contents, closing, openAt + level + 2, true)
	return if last ~= nil then last else #contents
end

local function characters(contents: string): { string }
	local result = table.create(#contents)
	for index = 1, #contents do
		result[index] = string.sub(contents, index, index)
	end
	return result
end

local function mask(contents: string): string
	local masked = characters(contents)
	local function blank(first: number, last: number)
		for index = first, math.min(last, #contents) do
			if masked[index] ~= "\n" then
				masked[index] = " "
			end
		end
	end
	local index = 1
	while index <= #contents do
		if string.sub(contents, index, index + 1) == "--" then
			local level = longBracketLevel(contents, index + 2)
			if level ~= nil then
				local last = longBracketEnd(contents, index + 2, level)
				blank(index, last)
				index = last + 1
			else
				local last = string.find(contents, "\n", index + 2, true) or (#contents + 1)
				blank(index, last - 1)
				index = last
			end
		else
			local level = longBracketLevel(contents, index)
			local quote = string.sub(contents, index, index)
			if level ~= nil then
				local last = longBracketEnd(contents, index, level)
				blank(index, last)
				index = last + 1
			elseif quote == '"' or quote == "'" then
				local cursor = index + 1
				while cursor <= #contents do
					local character = string.sub(contents, cursor, cursor)
					if character == "\\" then
						cursor += 2
					elseif character == quote or character == "\n" then
						break
					else
						cursor += 1
					end
				end
				blank(index, math.min(cursor, #contents))
				index = cursor + 1
			else
				index += 1
			end
		end
	end
	return table.concat(masked)
end

local function maskFieldAccesses(source: string): string
	local masked = characters(source)
	local index = 1
	while index <= #source do
		local character = string.sub(source, index, index)
		if character == "." and string.sub(source, index + 1, index + 1) == "." then
			index += 2
		elseif character == "." or character == ":" then
			local cursor = index + 1
			while string.match(string.sub(source, cursor, cursor), "^%s$") ~= nil do
				cursor += 1
			end
			local _, last = string.find(source, "^[%a_][%w_]*", cursor)
			if last ~= nil then
				for position = cursor, last do
					masked[position] = " "
				end
				index = last + 1
			else
				index += 1
			end
		else
			index += 1
		end
	end
	return table.concat(masked)
end

local function declaredNames(source: string): { [string]: boolean }
	local declared: { [string]: boolean } = {}
	local function addList(list: string)
		for part in string.gmatch(list .. ",", "([^,]*),") do
			local name = string.match(part, "^%s*([%a_][%w_]*)")
			if name ~= nil then
				declared[name] = true
			end
		end
	end
	local from = 1
	while true do
		local _, last = string.find(source, "%f[%w_]local%f[^%w_]", from)
		if last == nil then
			break
		end
		from = last + 1
		local rest = string.sub(source, last + 1)
		local functionName = string.match(rest, "^%s*function%s+([%a_][%w_]*)")
		if functionName ~= nil then
			declared[functionName] = true
		else
			addList(string.match(rest, "^([^\n=]*)") or "")
		end
	end
	for parameters in string.gmatch(source, "%f[%w_]function%s*[%w_%.:]*%s*%(([^)]*)%)") do
		addList(parameters)
	end
	for names in string.gmatch(source, "%f[%w_]for%s+([^\n=]-)%f[%w_]in%f[^%w_]") do
		addList(names)
	end
	for name in string.gmatch(source, "%f[%w_]for%s+([%a_][%w_]*)%s*=") do
		declared[name] = true
	end
	return declared
end

local function addMatches(
	findings: { Finding },
	source: string,
	pattern: string,
	code: string,
	why: string,
	fix: string
)
	local from = 1
	while true do
		local first, last = string.find(source, pattern, from)
		if first == nil then
			break
		end
		table.insert(findings, { code = code, offset = first, why = why, fix = fix })
		from = (last :: number) + 1
	end
end

local function isPortable(path: string): boolean
	return string.match(path, "%.verify%.luau$") ~= nil
		and string.match(path, "%.lute%.verify%.luau$") == nil
		and string.match(path, "%.roblox%.verify%.luau$") == nil
end

local function scan(contents: string, path: string): { Finding }
	local source = mask(contents)
	local globals = maskFieldAccesses(source)
	local declared = declaredNames(source)
	local findings: { Finding } = {}
	if isPortable(path) then
		for _, pattern in { "task%.wait%s*%(", "task%.delay%s*%(", "task%.spawn%s*%(" } do
			addMatches(
				findings,
				source,
				pattern,
				"VRF001",
				"portable verification must not choose ambient scheduling",
				"express yielding or deadlines through the executor contract"
			)
		end
		if not declared.wait then
			addMatches(
				findings,
				globals,
				"%f[%w_]wait%s*%(",
				"VRF001",
				"portable verification must not choose ambient scheduling",
				"express yielding or deadlines through the executor contract"
			)
		end
		addMatches(
			findings,
			source,
			"os%.clock%s*%(",
			"VRF002",
			"portable verification must not read an ambient clock",
			"use executor-supplied time or a deterministic fixture clock"
		)
		if not declared.tick then
			addMatches(
				findings,
				globals,
				"%f[%w_]tick%s*%(",
				"VRF002",
				"portable verification must not read an ambient clock",
				"use executor-supplied time or a deterministic fixture clock"
			)
		end
		for _, name in { "game", "workspace" } do
			if not declared[name] then
				addMatches(
					findings,
					globals,
					"%f[%w_]" .. name .. "%f[^%w_]",
					"VRF003",
					"portable verification must not reach into a host directly",
					"inject a host fixture and declare its capability"
				)
			end
		end
	end
	for _, name in { "PublishAsync", "PostAsync", "RequestAsync", "CreateAssetAsync", "SavePlaceAsync" } do
		addMatches(
			findings,
			source,
			"[%.:]" .. name .. "%s*%(",
			"VRF004",
			"a verification specification must not acquire external mutation authority",
			"move the authorized operation into a product-owned executor"
		)
	end
	addMatches(
		findings,
		contents,
		"%-%-!native",
		"VRF005",
		"verification specifications are control-plane code without a measured native-codegen case",
		"remove the annotation; benchmark a compute-bound kernel separately if one emerges"
	)
	table.sort(findings, function(left, right)
		return if left.offset == right.offset then left.code < right.code else left.offset < right.offset
	end)
	return findings
end

local function scanProductionPaths(paths: { string }): { ProductionFinding }
	local findings: { ProductionFinding } = {}
	for _, path in paths do
		local normalized = string.gsub(path, "\\", "/")
		if string.match(normalized, "%.verify%.luau$") ~= nil then
			table.insert(findings, {
				code = "VRF006",
				path = path,
				why = "verification specifications must not enter a production manifest",
				fix = "exclude *.verify.luau from the production source graph",
			})
		elseif string.find("/" .. string.lower(normalized) .. "/", "/verify/", 1, true) ~= nil then
			table.insert(findings, {
				code = "VRF007",
				path = path,
				why = "the Verify framework must not enter a production manifest",
				fix = "mount Verify only in verification-specific manifests or places",
			})
		end
	end
	table.sort(findings, function(left, right)
		return if left.path == right.path then left.code < right.code else left.path < right.path
	end)
	return findings
end

local function defaultIsSpecification(path: string): boolean
	return string.match(path, "%.verify%.luau$") ~= nil
end

local function walkTree(root: string, listDir: ListDir, exempt: ((string) -> boolean)?, into: { string })
	local entries = listDir(root)
	table.sort(entries, function(left, right)
		return left.name < right.name
	end)
	for _, entry in entries do
		local child = root .. "/" .. entry.name
		if exempt ~= nil and exempt(child) then
			continue
		end
		if entry.type == "dir" then
			walkTree(child, listDir, exempt, into)
		elseif entry.type == "file" then
			table.insert(into, child)
		end
	end
end

local function scanTree(root: string, options: TreeOptions): TreeReport
	if type(options) ~= "table" or type(options.listDir) ~= "function" or type(options.readFile) ~= "function" then
		error("a tree scan needs a listDir and a readFile", 2)
	end
	if type(root) ~= "string" or root == "" then
		error("a tree scan needs a non-empty root", 2)
	end
	local isSpecification = options.isSpecification or defaultIsSpecification

	local paths: { string } = {}
	walkTree(root, options.listDir, options.exempt, paths)
	table.sort(paths)

	local findings: { TreeFinding } = {}
	for _, path in paths do
		if not isSpecification(path) then
			continue
		end
		local contents = options.readFile(path)
		for _, finding in scan(contents, path) do
			table.insert(findings, {
				code = finding.code,
				offset = finding.offset,
				why = finding.why,
				fix = finding.fix,
				path = path,
			})
		end
	end
	table.sort(findings, function(left, right)
		if left.path ~= right.path then
			return left.path < right.path
		end
		if left.offset ~= right.offset then
			return left.offset < right.offset
		end
		return left.code < right.code
	end)

	return {
		findings = findings,
		productionFindings = scanProductionPaths(paths),
	}
end

return {
	scan = scan,
	scanProductionPaths = scanProductionPaths,
	scanTree = scanTree,
}
