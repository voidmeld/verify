--!strict

local Services = require "./services"

local function parseStamped(text: string): { Services.Line }
	local result: { Services.Line } = {}
	for line in string.gmatch(text, "[^\n]+") do
		local stamp, rest = string.match(line, "^(%d+%.?%d*)\t(.*)$")
		if stamp ~= nil then
			table.insert(result, { at = tonumber(stamp), text = (string.gsub(assert(rest), "\r$", "")) })
		else
			table.insert(result, { at = nil, text = (string.gsub(line, "\r$", "")) })
		end
	end
	return result
end

return { parseStamped = parseStamped }
