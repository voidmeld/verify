--!strict

local fs = require "@std/fs"
local task = require "@std/task"
local json = require "@std/json"
local Core = require "../core"
local Channel = require "../roblox/report-channel"
local Bounded = require "./bounded"
local Wire = require "./wire"

export type Session = {
	read: (remainingSeconds: number) -> string,
	alive: (remainingSeconds: number) -> boolean,
	close: () -> (),
}
export type Backend = {
	now: () -> number,
	sleep: (number) -> (),
	launch: (url: string, deadline: number) -> Session,
}
export type Selection = { caseIds: { string }?, entry: string? }
export type Options = {
	logPath: string?,
	caseIds: { string }?,
	entry: string?,
	placeId: number,
	runId: string,
	deadlineSeconds: number?,
	backend: Backend?,
}

local function encode(value: string): string
	return (string.gsub(value, "[^%w%-%._~]", function(byte)
		return string.format("%%%02X", string.byte(byte))
	end))
end

local function url(placeId: number, runId: string, selection: Selection?): string
	assert(placeId > 0 and placeId <= 9007199254740991 and placeId % 1 == 0, "Player requires a published place id")
	assert(runId ~= "" and #runId <= 256, "Player requires a unique run id of at most 256 bytes")
	local fields: { [string]: unknown } = { verifyRun = runId }
	if selection ~= nil then
		if selection.entry ~= nil then
			assert(selection.entry ~= "", "Player entry must not be empty")
			fields.verifyEntry = selection.entry
		end
		if selection.caseIds ~= nil then
			local seen: { [string]: boolean } = {}
			local ids: { string } = {}
			for _, id in selection.caseIds do
				assert(id ~= "" and not seen[id], "Player case ids must be unique and nonempty")
				seen[id] = true
				table.insert(ids, id)
			end
			assert(#ids > 0, "Player case selection must not be empty")
			fields.verifyCases = ids
		end
	end
	return "roblox://placeId="
		.. string.format("%.0f", placeId)
		.. "&launchData="
		.. encode(json.serialize(fields :: json.Object))
end

local function command(argv: { string }, seconds: number): Bounded.Result
	assert(seconds > 0, "Player launch deadline expired")
	local result = Bounded.run(argv, math.min(seconds, 3))
	assert(not result.timedOut, "Player host command timed out")
	return result
end

local function pids(seconds: number): { number }
	local result = command({ "/usr/bin/pgrep", "-x", "RobloxPlayer" }, seconds)
	assert(result.ok or result.exitcode == 1, result.stderr)
	local values: { number } = {}
	for digits in string.gmatch(result.stdout, "%d+") do
		table.insert(values, tonumber(digits) :: number)
	end
	return values
end

local function identity(pid: number, seconds: number): string
	local result = command({ "/bin/ps", "-p", tostring(pid), "-o", "lstart=,comm=" }, seconds)
	return if result.ok then result.stdout else ""
end

local function nativeLaunch(address: string, deadline: number): Session
	assert(fs.exists "/Applications/Roblox.app", "reference Player launcher requires Roblox.app on macOS")
	assert(#pids(deadline - os.clock()) == 0, "close existing Roblox Player before launching an isolated test")
	local opened = command({ "/usr/bin/open", address }, deadline - os.clock())
	assert(opened.ok, opened.stderr)
	local pid: number? = nil
	while pid == nil do
		local found = pids(deadline - os.clock())
		assert(#found <= 1, "multiple Players appeared; refusing ambiguous process ownership")
		pid = found[1]
		if pid == nil then
			task.wait(math.min(0.1, math.max(0, deadline - os.clock())))
		end
	end
	local owned = pid :: number
	local started = identity(owned, 2)
	assert(
		started ~= "" and string.find(started, "/RobloxPlayer", 1, true) ~= nil,
		"new Player process identity was not confirmed"
	)
	local closed = false
	local function same(seconds: number): boolean
		return not closed and identity(owned, seconds) == started
	end
	local function close()
		if same(2) then
			local result = command({ "kill", "-KILL", tostring(owned) }, 2)
			assert(result.ok, "could not stop owned Player: " .. result.stderr)
		end
		closed = true
	end
	local log: string? = nil
	return {
		alive = same,
		close = close,
		read = function(seconds)
			if log == nil then
				local files = command({ "/usr/sbin/lsof", "-a", "-p", tostring(owned), "-Fn" }, seconds)
				assert(files.ok, "cannot identify the owned Player log: " .. files.stderr)
				local candidates: { [string]: boolean } = {}
				for line in string.gmatch(files.stdout, "[^\n]+") do
					local path = string.match(line, "^n(.+)$")
					if
						path ~= nil
						and string.find(path, "/Logs/Roblox/", 1, true)
						and string.find(path, "_Player_", 1, true)
						and string.sub(path, -4) == ".log"
					then
						candidates[path] = true
					end
				end
				for path in candidates do
					assert(log == nil, "owned Player has multiple candidate logs")
					log = path
				end
			end
			return if log ~= nil then fs.readFileToString(log :: string) else ""
		end,
	}
end

local NATIVE: Backend = { now = os.clock, sleep = task.wait, launch = nativeLaunch }

local function run(options: Options): Core.BatchOutcome
	local address = url(options.placeId, options.runId, { caseIds = options.caseIds, entry = options.entry })
	local seconds = options.deadlineSeconds or 90
	assert(seconds > 0 and seconds < math.huge, "Player deadline must be finite and positive")
	local backend = options.backend or NATIVE
	local deadline = backend.now() + seconds
	local session: Session? = nil
	local timedOut = false
	local lastBytes = ""
	local ok, result = pcall(function(): Core.Report
		session = backend.launch(address, deadline)
		local active = session :: Session
		while true do
			local remaining = deadline - backend.now()
			if remaining <= 0 then
				timedOut = true
				error("Player did not emit a complete report before its deadline", 0)
			end
			local bytes = active.read(remaining)
			lastBytes = bytes
			if backend.now() >= deadline then
				timedOut = true
				error("Player report arrived after its deadline", 0)
			end
			local complete = string.match(bytes, "^(.*)\n") or ""
			local payload, reason = Core.receipt(complete, "VERIFY_REPORT")
			if payload ~= nil then
				return Channel.receive(Wire.parse(payload), options.runId)
			end
			assert(
				reason == "no tagged record was emitted" or string.find(reason or "", " is missing", 1, true) ~= nil,
				reason
			)
			assert(active.alive(math.max(0.001, deadline - backend.now())), "Player exited without a complete report")
			backend.sleep(math.min(0.1, math.max(0, deadline - backend.now())))
		end
	end)
	local saved, saveError = pcall(function()
		if options.logPath ~= nil then
			fs.writeStringToFile(options.logPath, lastBytes)
		end
	end)
	local cleanupOk, cleanupError = pcall(function()
		if session ~= nil then
			(session :: Session).close()
		end
	end)
	if not cleanupOk then
		return {
			status = "faulted",
			detail = "Player cleanup failed: " .. tostring(cleanupError) .. (if ok
				then ""
				else "; " .. tostring(result)),
		}
	end
	if not saved then
		return { status = "faulted", detail = "Player log could not be saved: " .. tostring(saveError) }
	end
	if not ok then
		return {
			status = if timedOut or backend.now() >= deadline then "timed_out" else "faulted",
			detail = tostring(result),
		}
	end
	return { status = "returned", report = result :: Core.Report }
end

return { run = run, url = url }
