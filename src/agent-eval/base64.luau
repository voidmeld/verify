--!strict

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local PAD = string.byte "="

local symbols: { number } = {}
for index = 1, #ALPHABET do
	symbols[index - 1] = string.byte(ALPHABET, index)
end

local function encode(bytes: string): string
	local length = #bytes
	if length == 0 then
		return ""
	end
	local source = buffer.fromstring(bytes)
	local output = buffer.create(4 * math.ceil(length / 3))
	local cursor = 0
	local whole = length - length % 3
	local index = 0
	while index < whole do
		local triple = bit32.bor(
			bit32.lshift(buffer.readu8(source, index), 16),
			bit32.lshift(buffer.readu8(source, index + 1), 8),
			buffer.readu8(source, index + 2)
		)
		buffer.writeu8(output, cursor, symbols[bit32.extract(triple, 18, 6)])
		buffer.writeu8(output, cursor + 1, symbols[bit32.extract(triple, 12, 6)])
		buffer.writeu8(output, cursor + 2, symbols[bit32.extract(triple, 6, 6)])
		buffer.writeu8(output, cursor + 3, symbols[bit32.extract(triple, 0, 6)])
		cursor += 4
		index += 3
	end
	local rest = length - whole
	if rest > 0 then
		local first = buffer.readu8(source, whole)
		local second = if rest == 2 then buffer.readu8(source, whole + 1) else 0
		local triple = bit32.bor(bit32.lshift(first, 16), bit32.lshift(second, 8))
		buffer.writeu8(output, cursor, symbols[bit32.extract(triple, 18, 6)])
		buffer.writeu8(output, cursor + 1, symbols[bit32.extract(triple, 12, 6)])
		buffer.writeu8(output, cursor + 2, if rest == 2 then symbols[bit32.extract(triple, 6, 6)] else PAD)
		buffer.writeu8(output, cursor + 3, PAD)
	end
	return buffer.tostring(output)
end

local values: { [number]: number } = {}
for index = 1, #ALPHABET do
	values[string.byte(ALPHABET, index)] = index - 1
end

local function decode(text: string): string?
	if #text % 4 ~= 0 then
		return nil
	end
	if #text == 0 then
		return ""
	end
	local padding = 0
	if string.byte(text, #text) == PAD then
		padding += 1
		if string.byte(text, #text - 1) == PAD then
			padding += 1
		end
	end
	local output = buffer.create(#text // 4 * 3 - padding)
	local cursor = 0
	for index = 1, #text, 4 do
		local quad = 0
		local count = 0
		for offset = 0, 3 do
			local byte = string.byte(text, index + offset)
			local value = values[byte]
			if value == nil then
				if byte ~= PAD or index + offset <= #text - padding then
					return nil
				end
				value = 0
			else
				count += 1
			end
			quad = bit32.bor(bit32.lshift(quad, 6), value)
		end
		local produced = if count == 4 then 3 elseif count == 3 then 2 else 1
		for shift = 0, produced - 1 do
			buffer.writeu8(output, cursor, bit32.extract(quad, 16 - 8 * shift, 8))
			cursor += 1
		end
	end
	return buffer.tostring(output)
end

return {
	encode = encode,
	decode = decode,
}
