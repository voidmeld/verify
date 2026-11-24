--!strict

local Base64 = require "../codec/base64"

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
		Base64.encode(utf16(script)),
	}
end

return {
	command = command,
}
