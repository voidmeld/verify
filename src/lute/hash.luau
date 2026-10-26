--!strict

local crypto = require "@lute/crypto"

local function sha256(bytes: string): string
	local value = crypto.digest(crypto.hash.sha256, bytes)
	local out: { string } = {}
	for index = 0, buffer.len(value) - 1 do
		table.insert(out, string.format("%02x", buffer.readu8(value, index)))
	end
	return table.concat(out)
end

return sha256
