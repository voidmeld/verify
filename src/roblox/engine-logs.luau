--!strict

local Core = require "../core"

export type Row = { message: string, kind: string, actor: string, source: string?, line: number? }
export type Drain = () -> { Row }

local function finish(context: Core.Context, drain: Drain, expected: { string }?)
	local rows = drain()
	local expectedErrors: { string } = expected or {}
	local lines, failures = {}, {}
	for _, row in rows do
		table.insert(lines, ("[%s] %s %s"):format(row.actor, row.kind, row.message))
		local allowed = false
		for _, text in expectedErrors do
			assert(text ~= "", "expected engine error must not be empty")
			allowed = allowed or string.find(row.message, text, 1, true) ~= nil
		end
		if row.kind == "Enum.MessageType.MessageError" and not allowed then
			table.insert(failures, row.message)
		end
	end
	if #lines > 0 then
		context:attach("engine.log", "text/plain", table.concat(lines, "\n"))
	end
	assert(#failures == 0, "unexpected engine errors:\n" .. table.concat(failures, "\n"))
end

return { finish = finish }
