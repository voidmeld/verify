--!strict

local fs = require "@std/fs"

export type Package = { prefix: string, entry: string, load: () -> unknown }
export type Config = {
	docs: string,
	packages: { Package },
	undocumented: { [string]: string }?,
	recursive: boolean?,
	codeReferences: boolean?,
	includeTypes: boolean?,
}

local function check(config: Config): { string }
	local docs = fs.readFileToString(config.docs)
	local documented: { [string]: boolean } = {}
	local prefixes: { [string]: boolean } = {}
	for _, package in config.packages do
		prefixes[package.prefix] = true
	end
	if config.codeReferences then
		for entry in string.gmatch(docs, "`([%w_]+%.[%w_%.]+)") do
			local prefix = string.match(entry, "^([%w_]+)%.")
			if prefix ~= nil and prefixes[prefix] then
				documented[entry] = true
				local parent = string.match(entry, "^(.*)%.[%w_]+$")
				while parent ~= nil and string.find(parent, ".", 1, true) ~= nil do
					documented[parent] = true
					parent = string.match(parent, "^(.*)%.[%w_]+$")
				end
			end
		end
	else
		for line in string.gmatch(docs, "[^\n]+") do
			local entry = string.match(line, "^###%s+`([%w_.%-]+)`")
			if entry ~= nil then
				documented[entry] = true
			end
		end
	end
	local findings: { string } = {}
	local exported: { [string]: boolean } = {}
	local function visit(value: unknown, prefix: string, ancestors: { [unknown]: boolean })
		assert(type(value) == "table", prefix .. " does not return a table")
		if ancestors[value] then
			return
		end
		local nextAncestors = table.clone(ancestors)
		nextAncestors[value] = true
		for key, child in value :: { [string]: unknown } do
			local qualified = prefix .. "." .. key
			exported[qualified] = true
			if not documented[qualified] and (config.undocumented == nil or config.undocumented[qualified] == nil) then
				table.insert(findings, qualified .. " is exported but undocumented")
			end
			if config.recursive and type(child) == "table" and string.match(key, "^[%u_]+$") == nil then
				visit(child, qualified, nextAncestors)
			end
		end
	end
	for _, package in config.packages do
		if not fs.exists(package.entry) then
			table.insert(findings, package.entry .. " is absent")
			continue
		end
		local ok, value = pcall(package.load)
		if not ok or type(value) ~= "table" then
			table.insert(findings, package.prefix .. ": could not load a table: " .. tostring(value))
		else
			visit(value, package.prefix, {})
		end
		if config.includeTypes then
			for name in string.gmatch(fs.readFileToString(package.entry), "export%s+type%s+([%w_]+)") do
				exported[package.prefix .. "." .. name] = true
			end
		end
	end
	for entry in documented do
		if not exported[entry] then
			table.insert(findings, entry .. " is documented but absent")
		end
	end
	table.sort(findings)
	return findings
end

return check
