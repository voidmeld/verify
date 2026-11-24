--!strict

local count = 0

return {
	increment = function()
		count += 1
	end,
	value = function()
		return count
	end,
}
