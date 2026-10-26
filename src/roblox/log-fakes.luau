--!strict

local Environment = require "./environment-types"
local Enum = require "./datatypes/enum"

export type Entry = { message: string, messageType: Enum.EnumItem, timestamp: number }

local function attach(
	environment: Environment.Environment,
	messageTypes: Enum.EnumFamily,
	service: () -> Environment.Instance
): (string, string) -> ()
	local history: { Entry } = {}
	environment.fake("LogService.GetLogHistory", function(): { Entry }
		local result: { Entry } = {}
		for _, entry in history do
			table.insert(result, table.clone(entry))
		end
		return result
	end)
	environment.fake("LogService.ClearOutput", function()
		table.clear(history)
	end)
	return function(kind: string, message: string)
		local level = if kind == "error"
			then "MessageError"
			elseif kind == "warn" then "MessageWarning"
			else "MessageOutput"
		local messageType = messageTypes[level]
		table.insert(history, { message = message, messageType = messageType, timestamp = environment.now() })
		if #history > 512 then
			table.remove(history, 1)
		end
		environment.fire(service(), "MessageOut", message, messageType)
	end
end

return { attach = attach }
