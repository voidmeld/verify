--!strict

local Xml = require "../codec/xml"

export type Property = { type: string, value: string }

export type Instance = {
	className: string,
	name: string,
	path: string,
	properties: { [string]: Property },
	children: { Instance },
}

local function instance(item: Xml.Element, prefix: string): Instance
	local className = item.attributes.class or ""
	local properties: { [string]: Property } = {}
	local declared = Xml.first(item, "Properties")
	if declared ~= nil then
		for _, property in declared.children do
			local key = property.attributes.name
			if key ~= nil then
				properties[key] = { type = property.tag, value = property.text }
			end
		end
	end
	local name = if properties.Name ~= nil then properties.Name.value else className
	local path = if prefix == "" then name else prefix .. "/" .. name
	local built: Instance = { className = className, name = name, path = path, properties = properties, children = {} }
	for _, child in Xml.children(item, "Item") do
		table.insert(built.children, instance(child, path))
	end
	return built
end

local function read(text: string): { Instance }
	local root = Xml.parse(text)
	assert(root.tag == "roblox", "the document is not a Roblox XML model or place")
	local roots: { Instance } = {}
	for _, item in Xml.children(root, "Item") do
		table.insert(roots, instance(item, ""))
	end
	return roots
end

local function descendants(roots: { Instance }): { Instance }
	local found: { Instance } = {}
	local function visit(list: { Instance })
		for _, item in list do
			table.insert(found, item)
			visit(item.children)
		end
	end
	visit(roots)
	return found
end

local function find(roots: { Instance }, path: string): Instance?
	for _, item in descendants(roots) do
		if item.path == path then
			return item
		end
	end
	return nil
end

return table.freeze {
	read = read,
	descendants = descendants,
	find = find,
}
