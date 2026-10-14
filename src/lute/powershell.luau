--!strict

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function encodeBase64(bytes: string): string
	local out: { string } = {}
	for offset = 1, #bytes, 3 do
		local a, b, c = string.byte(bytes, offset, offset + 2)
		local group = bit32.lshift(a, 16) + bit32.lshift(b or 0, 8) + (c or 0)
		for position = 0, 3 do
			if position >= 2 and offset + position - 1 > #bytes then
				table.insert(out, "=")
			else
				local index = bit32.band(bit32.rshift(group, 18 - position * 6), 63) + 1
				table.insert(out, string.sub(ALPHABET, index, index))
			end
		end
	end
	return table.concat(out)
end

local function utf16(script: string): string
	local units: { string } = {}
	for _, code in utf8.codes(script) do
		if code >= 0x10000 then
			local rest = code - 0x10000
			local high = 0xD800 + bit32.rshift(rest, 10)
			local low = 0xDC00 + bit32.band(rest, 0x3FF)
			table.insert(units, string.pack("<I2I2", high, low))
		else
			table.insert(units, string.pack("<I2", code))
		end
	end
	return table.concat(units)
end

local function command(script: string): { string }
	return {
		"powershell",
		"-NoProfile",
		"-NonInteractive",
		"-ExecutionPolicy",
		"Bypass",
		"-EncodedCommand",
		encodeBase64(utf16(script)),
	}
end

return {
	command = command,
	encodeBase64 = encodeBase64,
}
