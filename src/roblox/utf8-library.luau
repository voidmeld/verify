--!strict

local function extends(codepoint: number): boolean
	return (codepoint >= 0x0300 and codepoint <= 0x036F)
		or (codepoint >= 0x1AB0 and codepoint <= 0x1AFF)
		or (codepoint >= 0x1DC0 and codepoint <= 0x1DFF)
		or (codepoint >= 0x20D0 and codepoint <= 0x20FF)
		or (codepoint >= 0xFE00 and codepoint <= 0xFE0F)
		or (codepoint >= 0xFE20 and codepoint <= 0xFE2F)
		or (codepoint >= 0x1F3FB and codepoint <= 0x1F3FF)
		or (codepoint >= 0xE0020 and codepoint <= 0xE007F)
		or codepoint == 0x200C
end

local function graphemes(text: string): () -> (number?, number?)
	assert(type(text) == "string", "utf8.graphemes expects a string")
	local length = #text
	local iterator, state, control = utf8.codes(text)
	local cursor: number = control
	local pendingStart: number? = nil
	local pendingStop = 0
	local joined = false
	local exhausted = false
	return function(): (number?, number?)
		while not exhausted do
			local position, codepoint = iterator(state, cursor)
			if position == nil then
				exhausted = true
				break
			end
			cursor = position
			local width = #utf8.char(codepoint)
			local stop = position + width - 1
			if pendingStart == nil then
				pendingStart, pendingStop, joined = position, stop, codepoint == 0x200D
			elseif joined or extends(codepoint) or codepoint == 0x200D then
				pendingStop, joined = stop, codepoint == 0x200D
			else
				local first, last = pendingStart, pendingStop
				pendingStart, pendingStop, joined = position, stop, false
				return first, last
			end
		end
		if pendingStart ~= nil and pendingStop <= length then
			local first, last = pendingStart, pendingStop
			pendingStart = nil
			return first, last
		end
		return nil, nil
	end
end

local function create(): { [string]: unknown }
	local native: { [string]: unknown } = {
		char = utf8.char,
		charpattern = utf8.charpattern,
		codepoint = utf8.codepoint,
		codes = utf8.codes,
		len = utf8.len,
		offset = utf8.offset,
	}
	native.graphemes = graphemes
	return table.freeze(native)
end

return table.freeze { create = create, graphemes = graphemes }
