--!strict

export type Element = {
	tag: string,
	attributes: { [string]: string },
	children: { Element },
	text: string,
	openEnd: number,
	closeStart: number?,
}

local ENTITIES: { [string]: string } = {
	lt = "<",
	gt = ">",
	amp = "&",
	quot = '"',
	apos = "'",
}

local function decode(text: string): string
	if string.find(text, "&", 1, true) == nil then
		return text
	end
	local decoded = string.gsub(text, "&(#?[%w]+);", function(entity: string): string
		local original = "&" .. entity .. ";"
		local code: number? = nil
		if string.sub(entity, 1, 2) == "#x" or string.sub(entity, 1, 2) == "#X" then
			code = tonumber(string.sub(entity, 3), 16)
		elseif string.sub(entity, 1, 1) == "#" then
			code = tonumber(string.sub(entity, 2))
		else
			return ENTITIES[entity] or original
		end
		return if code ~= nil then utf8.char(code) else original
	end)
	return decoded
end

local function lines(text: string): string
	if string.find(text, "\r", 1, true) == nil then
		return text
	end
	return (string.gsub(string.gsub(text, "\r\n", "\n"), "\r", "\n"))
end

local function element(tag: string, openEnd: number): Element
	return { tag = tag, attributes = {}, children = {}, text = "", openEnd = openEnd, closeStart = nil }
end

local function closing(text: string, from: number, marker: string, label: string): number
	local close = string.find(text, marker, from, true)
	if close == nil then
		error("unterminated " .. label, 0)
	end
	return close
end

local function tagEnd(text: string, from: number): number
	local quote: string? = nil
	for index = from, #text do
		local char = string.sub(text, index, index)
		if quote ~= nil then
			if char == quote then
				quote = nil
			end
		elseif char == '"' or char == "'" then
			quote = char
		elseif char == ">" then
			return index
		end
	end
	error("unterminated tag", 0)
end

local function parse(source: string): Element
	local document = element("#document", 0)
	local stack: { Element } = { document }
	local index = 1
	local function append(value: string)
		local current = stack[#stack]
		if #current.children == 0 then
			current.text ..= lines(value)
		end
	end
	while index <= #source do
		local open = string.find(source, "<", index, true)
		if open == nil then
			append(decode(string.sub(source, index)))
			break
		end
		if open > index then
			append(decode(string.sub(source, index, open - 1)))
		end
		if string.sub(source, open, open + 8) == "<![CDATA[" then
			local close = closing(source, open + 9, "]]>", "CDATA section")
			append(string.sub(source, open + 9, close - 1))
			index = close + 3
		elseif string.sub(source, open, open + 3) == "<!--" then
			index = closing(source, open + 4, "-->", "XML comment") + 3
		elseif string.sub(source, open, open + 1) == "<?" then
			index = closing(source, open + 2, "?>", "processing instruction") + 2
		elseif string.sub(source, open, open + 1) == "<!" then
			index = closing(source, open + 2, ">", "declaration") + 1
		elseif string.sub(source, open, open + 1) == "</" then
			local close = closing(source, open + 2, ">", "closing tag")
			local name = string.match(string.sub(source, open + 2, close - 1), "^%s*([^%s>]+)")
			local current = stack[#stack]
			if #stack == 1 or name ~= current.tag then
				error(("mismatched closing tag </%s>"):format(tostring(name)), 0)
			end
			current.closeStart = open
			table.remove(stack)
			index = close + 1
		else
			local close = tagEnd(source, open + 1)
			local body = string.sub(source, open + 1, close - 1)
			local selfClosing = string.sub(body, -1) == "/"
			if selfClosing then
				body = string.sub(body, 1, -2)
			end
			local name = string.match(body, "^([^%s/>]+)")
			if name == nil then
				error("malformed tag", 0)
			end
			local child = element(name, close)
			for key, _quote, value in string.gmatch(string.sub(body, #name + 1), "([%w_:%.%-]+)%s*=%s*(['\"])(.-)%2") do
				child.attributes[key] = decode(value :: string)
			end
			table.insert(stack[#stack].children, child)
			if not selfClosing then
				table.insert(stack, child)
			end
			index = close + 1
		end
	end
	if #stack ~= 1 then
		error(("unclosed element <%s>"):format(stack[#stack].tag), 0)
	end
	local root = document.children[1]
	if root == nil then
		error("the document has no root element", 0)
	end
	return root
end

local function children(parent: Element, tag: string): { Element }
	local found: { Element } = {}
	for _, child in parent.children do
		if child.tag == tag then
			table.insert(found, child)
		end
	end
	return found
end

local function first(parent: Element, tag: string): Element?
	for _, child in parent.children do
		if child.tag == tag then
			return child
		end
	end
	return nil
end

return table.freeze {
	parse = parse,
	children = children,
	first = first,
}
