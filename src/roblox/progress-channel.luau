--!strict

local Core = require "../core"

local LOGGER = "VerifyProgress"

export type Collected = {
	events: { Core.ProgressEvent },
	rejected: number,
	foreign: number,
	first: string?,
}

local function publisher(runId: string, token: string, emit: (string, unknown) -> ()): Core.RunProgress
	assert(token ~= "", "progress token must not be empty")
	return Core.progress.create(runId, function(event: Core.ProgressEvent)
		emit("step", { token = token, event = event })
	end)
end

local function collect(rows: { unknown }, token: string, runId: string): Collected
	local seen: { [number]: boolean } = {}
	local result: Collected = { events = {}, rejected = 0, foreign = 0, first = nil }
	for _, value in rows do
		local row: { [string]: unknown } = if type(value) == "table" then value :: { [string]: unknown } else {}
		if row.loggerFullPath ~= LOGGER then
			continue
		end
		local context = row.context
		if type(context) ~= "table" then
			result.rejected += 1
			result.first = result.first or "progress context is missing"
		elseif (context :: { [string]: unknown }).token ~= token then
			result.foreign += 1
		else
			local valid, event = pcall(Core.progress.valid, (context :: { [string]: unknown }).event, runId)
			if not valid then
				result.rejected += 1
				result.first = result.first or "progress context is not a valid event of this run"
			elseif not seen[(event :: Core.ProgressEvent).sequence] then
				seen[(event :: Core.ProgressEvent).sequence] = true
				table.insert(result.events, event :: Core.ProgressEvent)
			end
		end
	end
	table.sort(result.events, function(left, right)
		return left.sequence < right.sequence
	end)
	return result
end

local history = [==[
local rows = {}
for _, entry in game:GetService('LogService'):GetLogHistory() do
    if entry.loggerFullPath == 'VerifyProgress' then
        table.insert(rows, {loggerFullPath = entry.loggerFullPath, context = entry.context})
    end
end
]==]

local read = history .. "return game:GetService('HttpService'):JSONEncode(rows)\n"

local function readPage(token: string, afterSequence: number): string
	assert(token ~= "", "progress token must not be empty")
	assert(afterSequence >= 0 and afterSequence < math.huge and afterSequence % 1 == 0, "invalid progress cursor")
	return string.format("local PROGRESS_TOKEN = %q\nlocal AFTER = %.0f\n", token, afterSequence)
		.. history
		.. [==[
local http = game:GetService('HttpService')
local pieces, bytes = {}, 2
for _, row in rows do
    local context = row.context
    local event = if type(context) == 'table' then context.event else nil
    local sequence = if type(event) == 'table' then event.sequence else nil
    if type(context) ~= 'table' or (context.token == PROGRESS_TOKEN and (type(sequence) ~= 'number' or sequence > AFTER)) then
        local encoded = http:JSONEncode(row)
        assert(#encoded + 2 <= 32768, 'progress event exceeds the transport page limit')
        local added = #encoded + (if #pieces > 0 then 1 else 0)
        if bytes + added > 32768 then break end
        table.insert(pieces, encoded)
        bytes += added
    end
end
return '[' .. table.concat(pieces, ',') .. ']'
]==]
end

return { LOGGER = LOGGER, publisher = publisher, collect = collect, read = read, readPage = readPage }
