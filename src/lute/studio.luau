--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local task = require "@std/task"
local json = require "@std/json"
local Core = require "../core"
local Attach = require "./studio-attach"
local Bounded = require "./bounded"
local Detached = require "./studio-detached"
local Files = require "./files"
local Wire = require "./wire"
local Mcp = require "./studio-mcp"
local ProgressChannel = require "../roblox/progress-channel"
local ProgressFile = require "./progress-file"
local Reply = require "./studio-reply"

local CALL_SECONDS = 30

export type Options = {
	finalCapture: boolean?,
	players: number?,
	place: string?,
	code: string,
	worker: string?,
	attach: Attach.Options?,
	context: ("Server" | "Client")?,
	studioExecutable: string?,
	mcpExecutable: string?,
	deadlineSeconds: number?,
	directory: string?,
	progressFile: string?,
}

local function studios(connection: Mcp.Connection): { [string]: string }
	local result: { [string]: string } = {}
	local function visit(value: unknown)
		if type(value) ~= "table" then
			return
		end
		local fields = value :: { [unknown]: unknown }
		if type(fields.id) == "string" and type(fields.name) == "string" then
			result[fields.id] = fields.name
		end
		for _, child in fields do
			if type(child) == "table" then
				visit(child)
			end
		end
	end
	visit(Wire.parse(Reply.texts(connection.call("list_roblox_studios", {}))))
	return result
end

local function worker(path: string)
	local fields = Mcp.record(Wire.parse(fs.readFileToString(path)))
	local function textField(name: string): string
		local value = fields[name]
		assert(type(value) == "string" and value ~= "", "native worker missing " .. name)
		return value
	end
	local directory, runId = textField "directory", textField "runId"
	local seconds = fields.deadlineSeconds
	assert(type(seconds) == "number" and seconds > 0, "native worker requires a deadline")
	local deadline = os.clock() + seconds
	local connection = Mcp.connect(textField "mcpExecutable", directory .. "/mcp", deadline)
	local pid: number? = nil
	local ok, reason = pcall(function()
		local previous = studios(connection)
		local launched = process.run {
			"sh",
			"-c",
			'"$1" -task EditFile -localPlaceFile "$2" >"$3" 2>&1 & echo $!',
			"verify-studio",
			textField "studioExecutable",
			textField "place",
			directory .. "/studio.log",
		}
		assert(launched.ok, launched.stderr)
		pid = tonumber(string.match(launched.stdout, "%d+"))
		assert(pid ~= nil, "Studio launch did not return a process id")
		local selected: string? = nil
		while selected == nil do
			local candidates: { string } = {}
			for id, name in studios(connection) do
				if not previous[id] and name == textField "placeName" then
					table.insert(candidates, id)
				end
			end
			assert(#candidates <= 1, "multiple Studios appeared during launch; refusing ambiguous target")
			selected = candidates[1]
			if selected == nil then
				task.wait(0.25)
			end
		end
		local id = selected :: string
		local token = string.format("%q", runId)
		local edit = Reply.texts(connection.call("execute_luau", {
			studio_id = id,
			datamodel_type = "Edit",
			code = "game:GetService('ReplicatedStorage'):SetAttribute('VerifyRun', "
				.. token
				.. "); return game:GetService('ReplicatedStorage'):GetAttribute('VerifyRun')",
		}))
		assert(string.find(edit, runId, 1, true) ~= nil, "Studio did not acknowledge run identity")
		local progressPath = fields.progressFile
		local polling = type(progressPath) == "string" and progressPath ~= ""
		local polled = 0
		local function pollProgress()
			local text = Reply.texts(connection.call("get_console_output", { studio_id = id }))
			for _, event in ProgressChannel.collect(text, runId, Wire.parse) do
				if event.sequence > polled then
					polled = event.sequence
					ProgressFile.append(progressPath :: string, event)
				end
			end
		end
		local function engine(datamodel: string, code: string): Detached.Reply
			local limit = math.min(deadline, os.clock() + CALL_SECONDS)
			local exchange = connection.callRaw(
				"execute_luau",
				json.serialize { studio_id = id, datamodel_type = datamodel, code = code },
				limit
			)
			if exchange.status ~= "answered" then
				return {
					ok = false,
					detail = exchange.detail or exchange.status,
					lost = exchange.lost == true,
					expired = exchange.lost ~= true and os.clock() >= limit,
				}
			end
			if exchange.detail ~= nil then
				return { ok = false, detail = exchange.detail, lost = false, expired = false }
			end
			local record = Mcp.record(exchange.result)
			local text = Reply.texts(exchange.result)
			if record.isError == true then
				return { ok = false, detail = text, lost = false, expired = false }
			end
			return { ok = true, text = text, lost = false, expired = false }
		end
		local players = fields.players
		local datamodel = textField "context"
		local code: string
		if type(players) == "number" then
			assert(players >= 1 and players <= 8 and players % 1 == 0, "Studio multiplayer supports 1 to 8 clients")
			local source = "game:GetService('ReplicatedStorage'):SetAttribute('VerifyRun', "
				.. token
				.. "); local runId = "
				.. token
				.. "; local ok, result = pcall(function() "
				.. textField "code"
				.. " end); game:GetService('StudioTestService'):EndTest(if ok then result else {error = tostring(result)})"
			connection.call("execute_luau", {
				studio_id = id,
				datamodel_type = "Edit",
				code = "local runner = Instance.new('Script'); runner.Name = 'VerifyServer'; runner.Source = "
					.. string.format("%q", source)
					.. "; runner.Parent = game:GetService('ServerScriptService')",
			})
			datamodel = "Edit"
			code = "return game:GetService('StudioTestService'):ExecuteMultiplayerTestAsync("
				.. tostring(players)
				.. ", {})"
		else
			connection.call("start_stop_play", { studio_id = id, is_start = true })
			datamodel = textField "context"
			code = "assert(game:GetService('ReplicatedStorage'):GetAttribute('VerifyRun') == "
				.. token
				.. ", 'wrong Verify run'); local runId = "
				.. token
				.. "; "
				.. textField "code"
		end
		local outcome = Detached.run {
			execute = engine,
			datamodel = datamodel,
			code = code,
			runId = runId,
			deadline = deadline,
			pollSeconds = 1,
			onPoll = if polling then pollProgress else nil,
		}
		if polling then
			pcall(pollProgress)
		end
		if outcome.status ~= "done" then
			error(outcome.detail or outcome.status, 0)
		end
		local payload = outcome.text :: string
		local report = Reply.report(payload, runId)
		assert(report ~= nil, "engine did not return the run-bound report envelope: " .. payload:sub(1, 1000))
		if fields.finalCapture == true then
			local image = Reply.saveCapture(
				connection.call("screen_capture", { studio_id = id, capture_id = "verify-final" }),
				directory,
				"final"
			)
			local final = report.results[#report.results]
			assert(final ~= nil, "cannot attach capture to empty report")
			table.insert(
				final.artifacts,
				{ name = "final Studio view", reference = image.reference, mediaType = image.mediaType }
			)
		end
		fs.writeStringToFile(directory .. "/report", Wire.encode(report))
	end)
	if pid ~= nil then
		process.run { "kill", "-KILL", tostring(pid) }
	end
	connection.close()
	if not ok then
		if os.clock() >= deadline then
			process.exit(124)
		end
		error(reason, 0)
	end
end

local function run(options: Options): Core.BatchOutcome
	if options.attach ~= nil then
		return Attach.run {
			attach = options.attach,
			code = options.code,
			context = options.context,
			players = options.players,
			finalCapture = options.finalCapture,
			deadlineSeconds = options.deadlineSeconds,
			directory = options.directory,
		}
	end
	local workerPath, place = options.worker, options.place
	assert(
		place ~= nil and workerPath ~= nil and place ~= "" and options.code ~= "" and workerPath ~= "",
		"Studio run requires place, code and worker"
	)
	if options.players ~= nil then
		assert(
			options.players >= 1 and options.players <= 8 and options.players % 1 == 0,
			"Studio requires one to eight clients"
		)
		assert(options.context == nil or options.context == "Server", "multiplayer code runs on the server")
	end
	assert(not options.finalCapture or options.players == nil, "final capture requires a single active Studio client")
	local seconds = options.deadlineSeconds or 90
	assert(seconds > 0 and seconds < math.huge, "Studio deadline must be finite and positive")
	local directory = Files.claimDirectory(options.directory or "/tmp/verify-studio")
	local input = directory .. "/request"
	local placeName = "Verify-"
		.. tostring(process.pid())
		.. "-"
		.. (string.match(directory, "[^/]+$") :: string)
		.. ".rbxlx"
	local placePath = directory .. "/" .. placeName
	local source = fs.readFileToString(place)
	assert(string.find(source, "<roblox", 1, true) ~= nil, "Studio launcher requires an XML rbxlx place")
	fs.writeStringToFile(placePath, source)
	fs.writeStringToFile(
		input,
		json.serialize {
			finalCapture = options.finalCapture,
			players = options.players,
			directory = directory,
			runId = directory,
			place = placePath,
			placeName = placeName,
			code = options.code,
			context = options.context or "Server",
			deadlineSeconds = seconds,
			progressFile = options.progressFile,
			studioExecutable = options.studioExecutable or "/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio",
			mcpExecutable = options.mcpExecutable or "/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP",
		}
	)
	local result = Bounded.run({ "lute", "run", workerPath, input }, seconds + 1)
	if result.timedOut or result.exitcode == 124 then
		return {
			status = "timed_out",
			detail = "isolated Studio run exceeded its process deadline; diagnostics: " .. directory,
		}
	end
	if not result.ok then
		return { status = "faulted", detail = result.stderr .. result.stdout .. "; diagnostics: " .. directory }
	end
	local decoded, report = pcall(function()
		return Wire.decode(fs.readFileToString(directory .. "/report"))
	end)
	if not decoded then
		return { status = "faulted", detail = "invalid or missing engine report: " .. tostring(report) }
	end
	return { status = "returned", report = report }
end

export type HostOptions = {
	finalCapture: boolean?,
	players: number?,
	place: string?,
	worker: string?,
	attach: Attach.Options?,
	context: ("Server" | "Client")?,
	studioExecutable: string?,
	mcpExecutable: string?,
	deadlineSeconds: number?,
	directory: string?,
	capabilities: { string },
	codeForBatch: (Core.PlanBatch) -> string,
}

local function host(options: HostOptions): Core.Host
	return {
		name = "roblox-studio",
		capabilities = options.capabilities,
		environment = { runtime = "roblox-studio" },
		now = os.clock,
		runBatch = function(batch)
			local settings: Options = {
				finalCapture = options.finalCapture,
				players = options.players,
				place = options.place,
				worker = options.worker,
				attach = options.attach,
				context = options.context,
				studioExecutable = options.studioExecutable,
				mcpExecutable = options.mcpExecutable,
				directory = options.directory,
				code = options.codeForBatch(batch),
				deadlineSeconds = batch.deadlineSeconds or options.deadlineSeconds,
			}
			return run(settings)
		end,
	}
end

return { run = run, worker = worker, host = host, attach = Attach.attach }
