--!strict

local fs = require "@std/fs"

local Paths = require "../codec/path"
local Xml = require "../codec/xml"

export type Options = {
	output: string,
	roots: { string },
	modules: { string }?,
	clientSource: string?,
	serverSource: string?,
	rootName: string?,
	basePlace: string?,
}
local function normalize(path: string): string
	return Paths.collapse(path, "module path escapes its root")
end
local function filesUnder(path: string, files: { [string]: string })
	for _, entry in fs.listDirectory(path) do
		local child = path .. "/" .. entry.name
		if entry.type == "dir" then
			filesUnder(child, files)
		elseif entry.name:sub(-5) == ".luau" then
			files[child] = fs.readFileToString(child)
		end
	end
end

local function xml(value: string): string
	return (value:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end
local function logical(path: string): string
	return (normalize(path):gsub("^/", ""):gsub("%.luau$", ""):gsub("/init$", ""))
end
local function resolve(path: string, present: { [string]: boolean }): string
	local joined = normalize(path)
	if present[joined] then
		return joined
	end
	if present[joined .. ".luau"] then
		return joined .. ".luau"
	end
	assert(present[joined .. "/init.luau"], "unresolved fixture module " .. joined)
	return joined .. "/init.luau"
end
local function reference(file: string, target: string): string
	local own = file:gsub("%.luau$", "")
	if own == "init" then
		own = ""
	elseif own:sub(-5) == "/init" then
		own = own:sub(1, -6)
	end
	if target:sub(1, 6) == "@self/" then
		return (if own == "" then "." else own) .. "/" .. target:sub(7)
	end
	return (own:match "^(.*)/[^/]+$" or ".") .. "/" .. target
end
local function rewrite(source: string, replacement: (string) -> string): string
	local pieces: { string } = {}
	local cursor = 1
	while cursor <= #source do
		local rest = source:sub(cursor)
		local comment = rest:sub(1, 2) == "--"
		local start = if comment then 3 else 1
		local equals = rest:sub(start):match "^%[(=*)%["
		local finish: number? = nil
		if equals then
			local _, last = source:find("]" .. equals .. "]", cursor + start + #equals + 1, true)
			assert(last, "unterminated long source literal")
			finish = last
		elseif comment then
			finish = (source:find("\n", cursor, true) or (#source + 1)) - 1
		elseif rest:sub(1, 1) == '"' or rest:sub(1, 1) == "'" or rest:sub(1, 1) == "`" then
			local quote = rest:sub(1, 1)
			local index = cursor + 1
			while index <= #source do
				if source:sub(index, index) == "\\" then
					index += 2
				elseif source:sub(index, index) == quote then
					finish = index
					break
				else
					index += 1
				end
			end
			assert(finish, "unterminated source string")
		end
		if finish then
			table.insert(pieces, source:sub(cursor, finish))
			cursor = finish + 1
		else
			local identifier = rest:match "^[%a_][%w_]*"
			if
				identifier == "require"
				and source:sub(cursor - 1, cursor - 1) ~= "."
				and source:sub(cursor - 1, cursor - 1) ~= ":"
			then
				local tail = source:sub(cursor + 7)
				local prefix = tail:match "^%s*%(?%s*" or ""
				local quote = tail:sub(#prefix + 1, #prefix + 1)
				assert(quote == '"' or quote == "'", "place requires literal module imports")
				local ending = tail:find(quote, #prefix + 2, true)
				assert(ending, "unterminated module import")
				local target = tail:sub(#prefix + 2, ending - 1)
				assert(not target:find("\\", 1, true), "escaped module paths are unsupported")
				local consumed = ending
				if prefix:find("(", 1, true) then
					local suffix = tail:sub(ending + 1):match "^%s*%)"
					assert(suffix, "literal require must have one argument")
					consumed += #suffix
				end
				table.insert(pieces, replacement(target))
				cursor += 7 + consumed
			elseif identifier then
				table.insert(pieces, identifier)
				cursor += #identifier
			else
				table.insert(pieces, source:sub(cursor, cursor))
				cursor += 1
			end
		end
	end
	return table.concat(pieces)
end
local function moduleExpression(path: string, rootName: string?): string
	local expression = 'game:GetService("ReplicatedStorage"):WaitForChild('
		.. string.format("%q", rootName or "VerifyModules")
		.. ")"
	for part in logical(path):gmatch "[^/]+" do
		expression ..= ":WaitForChild(" .. string.format("%q", part) .. ")"
	end
	return expression
end

type Addition = { path: { string }, item: string, unique: string? }

local function nameOf(item: Xml.Element): string?
	local properties = Xml.first(item, "Properties")
	if properties ~= nil then
		for _, property in properties.children do
			if property.attributes.name == "Name" then
				return property.text
			end
		end
	end
	return nil
end

local function wrap(classes: { string }, from: number, item: string): string
	local text = item
	for index = #classes, from, -1 do
		text = '<Item class="' .. classes[index] .. '">' .. text .. "</Item>"
	end
	return text
end

local function merge(base: string, additions: { Addition }): string
	assert(
		base:sub(1, 8) ~= "<roblox!",
		"base place is a binary place; only an XML place (.rbxlx) can be merged, save the base as XML"
	)
	local xml = base
	for _, addition in additions do
		local parent = Xml.parse(xml)
		assert(parent.tag == "roblox", "base place is not an XML place")
		local depth = 1
		while depth <= #addition.path do
			local found: Xml.Element? = nil
			for _, child in Xml.children(parent, "Item") do
				if child.attributes.class == addition.path[depth] then
					found = child
					break
				end
			end
			if found == nil then
				break
			end
			parent = found
			depth += 1
		end
		if depth > #addition.path and addition.unique ~= nil then
			for _, child in Xml.children(parent, "Item") do
				assert(
					nameOf(child) ~= addition.unique,
					("base place already contains an instance named %s here"):format(addition.unique)
				)
			end
		end
		local at = assert(parent.closeStart, "base place has a self-closing container")
		xml = xml:sub(1, at - 1) .. wrap(addition.path, depth, addition.item) .. xml:sub(at)
	end
	return xml
end

local function build(options: Options)
	local path, clientSource = options.output, options.clientSource
	local rootName = options.rootName or "VerifyModules"
	assert(rootName ~= "", "place module root needs a name")
	local files: { [string]: string } = {}
	for _, root in options.roots do
		filesUnder(normalize(root), files)
	end
	local modules: { string } = options.modules or {}
	for _, file in modules do
		files[normalize(file)] = fs.readFileToString(file)
	end
	local pending: { string } = {}
	for file in files do
		table.insert(pending, file)
	end
	local index = 1
	while index <= #pending do
		local file = pending[index]
		index += 1
		local imports: { string } = {}
		rewrite(files[file], function(target)
			assert(
				target:sub(1, 1) == "." or target:sub(1, 6) == "@self/",
				"external module is unavailable: " .. target
			)
			table.insert(imports, normalize(reference(file, target)))
			return ""
		end)
		for _, target in imports do
			local resolved: string? = nil
			local candidates: { string } = if target:sub(-5) == ".luau"
				then { target }
				else { target .. ".luau", target .. "/init.luau" }
			for _, candidate in candidates do
				if files[candidate] ~= nil or fs.exists(candidate) then
					resolved = candidate
					break
				end
			end
			assert(resolved ~= nil, "unresolved fixture module " .. target)
			if files[resolved :: string] == nil then
				files[resolved :: string] = fs.readFileToString(resolved :: string)
				table.insert(pending, resolved :: string)
			end
		end
	end
	local present: { [string]: boolean } = {}
	for file in files do
		present[file] = true
	end
	local sources: { [string]: string } = {}
	local children: { [string]: { string } } = { [""] = {} }
	local function ensure(name: string)
		if children[name] ~= nil then
			return
		end
		local parent = name:match "^(.*)/[^/]+$" or ""
		ensure(parent)
		children[name] = {}
		table.insert(children[parent], name)
	end
	for file in files do
		assert(sources[logical(file)] == nil, "duplicate module mount: " .. file)
		sources[logical(file)] = ""
		ensure(logical(file))
	end
	for file, contents in files do
		sources[logical(file)] = rewrite(contents, function(target)
			assert(
				target:sub(1, 1) == "." or target:sub(1, 6) == "@self/",
				"external module is unavailable: " .. target
			)
			local resolved = resolve(reference(file, target), present)
			return "require(" .. moduleExpression(resolved, rootName) .. ")"
		end)
	end
	local function node(name: string): string
		local source = sources[name]
		local label = if name == "" then rootName else name:match "[^/]+$" :: string
		local pieces = {
			'<Item class="'
				.. (if source then "ModuleScript" else "Folder")
				.. '"><Properties><string name="Name">'
				.. xml(label)
				.. "</string>",
		}
		if source then
			table.insert(pieces, '<ProtectedString name="Source">' .. xml(source) .. "</ProtectedString>")
		end
		table.insert(pieces, "</Properties>")
		table.sort(children[name])
		for _, child in children[name] do
			table.insert(pieces, node(child))
		end
		table.insert(pieces, "</Item>")
		return table.concat(pieces)
	end
	local clientItem = if clientSource
		then '<Item class="LocalScript"><Properties><string name="Name">VerifyClient</string><ProtectedString name="Source">'
			.. xml(clientSource)
			.. "</ProtectedString></Properties></Item>"
		else nil
	local serverItem = if options.serverSource
		then '<Item class="Script"><Properties><string name="Name">VerifyServer</string><ProtectedString name="Source">'
			.. xml(options.serverSource)
			.. "</ProtectedString></Properties></Item>"
		else nil
	if options.basePlace ~= nil then
		local additions: { Addition } = {
			{ path = { "ReplicatedStorage" }, item = node "", unique = rootName },
		}
		if clientItem then
			table.insert(additions, {
				path = { "StarterPlayer", "StarterPlayerScripts" },
				item = clientItem,
				unique = "VerifyClient",
			})
		end
		if serverItem then
			table.insert(additions, { path = { "ServerScriptService" }, item = serverItem, unique = "VerifyServer" })
		end
		fs.writeStringToFile(path, merge(fs.readFileToString(options.basePlace), additions))
		return
	end
	fs.writeStringToFile(
		path,
		'<roblox version="4"><Item class="ReplicatedStorage">'
			.. node ""
			.. "</Item>"
			.. '<Item class="Lighting"><Properties><token name="Technology">4</token></Properties></Item>'
			.. (if clientItem
				then '<Item class="StarterPlayer"><Item class="StarterPlayerScripts">' .. clientItem .. "</Item></Item>"
				else "")
			.. (if serverItem then '<Item class="ServerScriptService">' .. serverItem .. "</Item>" else "")
			.. '<Item class="Workspace"><Item class="Part"><Properties><string name="Name">Floor</string><bool name="Anchored">true</bool><Vector3 name="size"><X>200</X><Y>1</Y><Z>200</Z></Vector3></Properties></Item><Item class="SpawnLocation"><Properties><bool name="Anchored">true</bool><CoordinateFrame name="CFrame"><X>0</X><Y>3</Y><Z>0</Z><R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22></CoordinateFrame></Properties></Item></Item></roblox>'
	)
end

return { build = build, moduleExpression = moduleExpression }
