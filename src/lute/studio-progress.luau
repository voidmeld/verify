--!strict

local fs = require "@std/fs"
local json = require "@std/json"
local Detached = require "./studio-detached"
local ProgressChannel = require "../roblox/progress-channel"
local ProgressFile = require "./progress-file"
local Wire = require "./wire"

export type Listener = {
	token: string,
	poll: () -> (),
	finish: () -> (),
}

local function listener(path: string, runId: string, readConsole: () -> string): Listener
	local token = Detached.tokenFor(runId)
	local polled = 0
	local rejected, foreign, failures = 0, 0, 0
	local firstProblem: string? = nil
	local function read()
		local collected = ProgressChannel.collect(readConsole(), token, runId, Wire.parse)
		rejected = math.max(rejected, collected.rejected)
		foreign = math.max(foreign, collected.foreign)
		if collected.first ~= nil and firstProblem == nil then
			firstProblem = collected.first
		end
		for _, event in collected.events do
			if event.sequence > polled then
				polled = event.sequence
				ProgressFile.append(path, event)
			end
		end
	end
	local function poll()
		local ok, problem: unknown = pcall(read)
		if not ok then
			failures += 1
			if firstProblem == nil then
				firstProblem = "progress poll failed: " .. tostring(problem)
			end
		end
	end
	local function finish()
		poll()
		if rejected > 0 or failures > 0 then
			fs.writeStringToFile(
				path .. ".diagnostics",
				json.serialize {
					rejected = rejected,
					failures = failures,
					foreign = foreign,
					first = firstProblem or "",
				}
			)
		end
	end
	return { token = token, poll = poll, finish = finish }
end

return { listener = listener }
