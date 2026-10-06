--!strict

local fs = require "@std/fs"
local json = require "@std/json"
local Core = require "../core"

local function append(path: string, event: Core.ProgressEvent)
	local handle = fs.open(path, "a")
	local written = pcall(fs.write, handle, json.serialize((event :: unknown) :: json.Value) .. "\n")
	fs.close(handle)
	assert(written, "progress line was not written")
end

local function emitter(path: string): (Core.ProgressEvent) -> ()
	return function(event: Core.ProgressEvent)
		append(path, event)
	end
end

local function read(path: string, runId: string): { Core.ProgressEvent }
	local events: { Core.ProgressEvent } = {}
	if not fs.exists(path) then
		return events
	end
	for line in string.gmatch(fs.readFileToString(path) .. "\n", "(.-)\n") do
		if line ~= "" then
			local decoded, value = pcall(json.deserialize, line)
			if decoded then
				local valid, event = pcall(Core.progress.valid, value, runId)
				if valid then
					table.insert(events, event :: Core.ProgressEvent)
				end
			end
		end
	end
	return events
end

return { append = append, emitter = emitter, read = read }
