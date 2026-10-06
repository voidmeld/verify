--!strict

local Core = require "../core"

local TAG = "VERIFY_PROGRESS"

local function publisher(runId: string, encode: (unknown) -> string, emit: (string) -> ()): Core.RunProgress
	return Core.progress.create(runId, function(event: Core.ProgressEvent)
		for _, line in Core.frame(TAG, encode(event)) do
			emit(line)
		end
	end)
end

local function collect(bytes: string, runId: string, decode: (string) -> unknown): { Core.ProgressEvent }
	local seen: { [number]: boolean } = {}
	local events: { Core.ProgressEvent } = {}
	for _, record in Core.extract(bytes, TAG) do
		if record.chunkIndex == nil then
			local decoded, value = pcall(decode, record.payload)
			if decoded then
				local valid, event = pcall(Core.progress.valid, value, runId)
				if valid and not seen[(event :: Core.ProgressEvent).sequence] then
					seen[(event :: Core.ProgressEvent).sequence] = true
					table.insert(events, event :: Core.ProgressEvent)
				end
			end
		end
	end
	table.sort(events, function(left, right)
		return left.sequence < right.sequence
	end)
	return events
end

return { TAG = TAG, publisher = publisher, collect = collect }
