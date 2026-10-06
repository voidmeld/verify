--!strict

type Span = { start: number, openEnd: number, closeStart: number, closeEnd: number, class: string, name: string? }

local function skipOpaque(xml: string, at: number): number?
	if xml:sub(at, at + 8) == "<![CDATA[" then
		local _, last = xml:find("]]>", at + 9, true)
		assert(last, "base place has an unterminated CDATA section")
		return last + 1
	end
	if xml:sub(at, at + 3) == "<!--" then
		local _, last = xml:find("-->", at + 4, true)
		assert(last, "base place has an unterminated comment")
		return last + 1
	end
	return nil
end

local function children(xml: string, from: number, to: number): { Span }
	local found: { Span } = {}
	local stack: { Span } = {}
	local cursor = from
	while true do
		local open = xml:find("<", cursor, true)
		if open == nil or open >= to then
			break
		end
		local skipped = skipOpaque(xml, open)
		if skipped ~= nil then
			cursor = skipped
		elseif xml:sub(open, open + 5) == "<Item " or xml:sub(open, open + 5) == "<Item>" then
			local close = xml:find(">", open, true)
			assert(close, "base place has an unterminated Item tag")
			local class = xml:sub(open, close):match 'class="([^"]*)"' or ""
			table.insert(stack, { start = open, openEnd = close, closeStart = 0, closeEnd = 0, class = class })
			cursor = close + 1
		elseif xml:sub(open, open + 6) == "</Item>" then
			local span = table.remove(stack)
			assert(span, "base place has an unmatched Item close")
			span.closeStart, span.closeEnd = open, open + 6
			if #stack == 0 then
				local nameAt = xml:find('<string name="Name">', span.openEnd, true)
				if nameAt ~= nil and nameAt < open then
					local finish = xml:find("</string>", nameAt, true)
					span.name = xml:sub(nameAt + #'<string name="Name">', (finish :: number) - 1)
				end
				table.insert(found, span)
			end
			cursor = open + 7
		else
			cursor = open + 1
		end
	end
	assert(#stack == 0, "base place has an unclosed Item")
	return found
end

local function wrap(classes: { string }, from: number, item: string): string
	local text = item
	for index = #classes, from, -1 do
		text = '<Item class="' .. classes[index] .. '">' .. text .. "</Item>"
	end
	return text
end

local function insert(
	xml: string,
	bodyStart: number,
	bodyEnd: number,
	classes: { string },
	depth: number,
	item: string,
	rootName: string?
): string
	local class = classes[depth]
	if class == nil then
		if rootName ~= nil then
			for _, child in children(xml, bodyStart, bodyEnd) do
				assert(
					child.name ~= rootName,
					("base place already contains an instance named %s here"):format(rootName)
				)
			end
		end
		return xml:sub(1, bodyEnd - 1) .. item .. xml:sub(bodyEnd)
	end
	for _, child in children(xml, bodyStart, bodyEnd) do
		if child.class == class then
			return insert(xml, child.openEnd + 1, child.closeStart, classes, depth + 1, item, rootName)
		end
	end
	return xml:sub(1, bodyEnd - 1) .. wrap(classes, depth, item) .. xml:sub(bodyEnd)
end

local function merge(base: string, additions: { { path: { string }, item: string, unique: string? } }): string
	assert(
		base:sub(1, 8) ~= "<roblox!",
		"base place is a binary place; only an XML place (.rbxlx) can be merged, save the base as XML"
	)
	local header = base:find("<roblox", 1, true)
	assert(header ~= nil, "base place is not an XML place")
	local bodyStart = (base:find(">", header, true) :: number) + 1
	local bodyEnd = base:find("</roblox>", bodyStart, true)
	assert(bodyEnd ~= nil, "base place is not a complete XML place")
	local xml = base
	for _, addition in additions do
		local closing = xml:find("</roblox>", bodyStart, true) :: number
		xml = insert(xml, bodyStart, closing, addition.path, 1, addition.item, addition.unique)
	end
	return xml
end

return { merge = merge }
