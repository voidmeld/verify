--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local system = require "@std/system"
local json = require "@std/json"
local Core = require "../core"
local Attach = require "./studio-attach"
local Bounded = require "./bounded"
local Detached = require "./studio-detached"
local Files = require "./files"
local Wire = require "./wire"
local Mcp = require "./studio-mcp"
local Processes = require "./studio-processes"
local Reply = require "./studio-reply"
local Install = require "./studio-install"
local Launch = require "./studio-launch"
local Logs = require "./studio-logs"
local Identity = require "./studio-identity"

export type Identity = Identity.Identity

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
	identity: Identity?,
}

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
	local launched, failure = Launch.open({
		place = textField "place",
		studioExecutable = textField "studioExecutable",
		mcpExecutable = textField "mcpExecutable",
		runSeconds = seconds,
		callSeconds = CALL_SECONDS,
	}, directory, textField "place", textField "placeName", deadline)
	assert(launched ~= nil, failure)
	local owner = launched :: Launch.Launched
	local session = owner.session
	local function call(tool: string, arguments: { [string]: unknown }): unknown
		local response = session.call(tool, Wire.encode(arguments))
		assert(response.ok, response.detail)
		return response.result
	end
	local ok, reason = pcall(function()
		local id = session.studio.id
		local token = string.format("%q", runId)
		local edit = Reply.texts(call("execute_luau", {
			studio_id = id,
			datamodel_type = "Edit",
			code = "game:GetService('ReplicatedStorage'):SetAttribute('VerifyRun', "
				.. token
				.. "); return game:GetService('ReplicatedStorage'):GetAttribute('VerifyRun')",
		}))
		assert(string.find(edit, runId, 1, true) ~= nil, "Studio did not acknowledge run identity")
		if fields.identity ~= nil then
			local configured = session.execute("Edit", Identity.source(Identity.read(fields.identity)))
			assert(configured.ok, configured.detail)
			assert(
				string.find(Reply.texts(configured.result), "verify-studio-identity-ok", 1, true),
				"Studio did not acknowledge place identity"
			)
		end
		local installedLogs = session.execute("Edit", Logs.install)
		assert(installedLogs.ok, installedLogs.detail)
		local progressToken = Detached.tokenFor(runId)
		local players = fields.players
		local datamodel = textField "context"
		local code: string
		if type(players) == "number" then
			assert(players >= 1 and players <= 8 and players % 1 == 0, "Studio multiplayer supports 1 to 8 clients")
			local source = "game:GetService('ReplicatedStorage'):SetAttribute('VerifyRun', "
				.. token
				.. "); local runId = "
				.. token
				.. "; local progressToken = "
				.. string.format("%q", progressToken)
				.. "; local ok, result = pcall(function() "
				.. textField "code"
				.. " end); game:GetService('StudioTestService'):EndTest(if ok then result else {error = tostring(result)})"
			call("execute_luau", {
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
			call("start_stop_play", { studio_id = id, is_start = true })
			datamodel = textField "context"
			code = "assert(game:GetService('ReplicatedStorage'):GetAttribute('VerifyRun') == "
				.. token
				.. ", 'wrong Verify run'); local runId = "
				.. token
				.. "; local progressToken = "
				.. string.format("%q", progressToken)
				.. "; "
				.. textField "code"
		end
		local outcome = Attach.runSession(session, {
			code = code,
			context = datamodel,
			progressFile = if type(fields.progressFile) == "string" then fields.progressFile else nil,
			finalCapture = fields.finalCapture == true,
		}, directory, runId)
		assert(outcome.status == "returned", outcome.detail)
		local report = outcome.report
		fs.writeStringToFile(directory .. "/report", Wire.encode(report))
	end)
	if fields.players ~= nil then
		pcall(
			session.execute,
			"Edit",
			"pcall(function() game:GetService('StudioTestService'):EndTest({}) end) return 'ended'"
		)
	end
	local cleanup = owner.close()
	fs.writeStringToFile(
		directory .. "/cleanup",
		json.serialize { terminated = cleanup.terminated, survivors = cleanup.survivors }
	)
	if not ok then
		if os.clock() >= deadline then
			process.exit(124)
		end
		error(reason, 0)
	end
end

local function run(options: Options): Core.BatchOutcome
	assert(options.identity == nil or options.attach == nil, "Studio identity requires a launched disposable Studio")
	if options.identity ~= nil then
		Identity.read(options.identity)
	end
	if options.attach ~= nil then
		return Attach.run {
			attach = options.attach,
			code = options.code,
			context = options.context,
			players = options.players,
			finalCapture = options.finalCapture,
			deadlineSeconds = options.deadlineSeconds,
			directory = options.directory,
			progressFile = options.progressFile,
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
	local installed, missing = Install.locate()
	local studioExecutable = options.studioExecutable or if installed ~= nil then installed.studio else nil
	local mcpExecutable = options.mcpExecutable or if installed ~= nil then installed.mcp else nil
	if studioExecutable == nil or mcpExecutable == nil then
		return { status = "faulted", detail = "Roblox Studio was not found: " .. tostring(missing) }
	end
	local directory = Files.claimDirectory(options.directory or Files.temporary "verify-studio")
	local input = directory .. "/request"
	local placeName = "Verify-"
		.. tostring(process.pid())
		.. "-"
		.. (string.match(directory, if system.win32 then "[^/\\]+$" else "[^/]+$") :: string)
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
			identity = options.identity,
			runId = directory,
			place = placePath,
			placeName = placeName,
			code = options.code,
			context = options.context or "Server",
			deadlineSeconds = seconds,
			progressFile = options.progressFile,
			studioExecutable = studioExecutable,
			mcpExecutable = mcpExecutable,
		}
	)
	local before = Processes.snapshot()
	local result = Bounded.run({ "lute", "run", workerPath, input }, seconds + 1)
	local parentCleanup = Processes.reap(before, { markers = { placeName } })
	local survivors = parentCleanup.survivors
	local recorded = Processes.read(directory .. "/cleanup")
	if recorded ~= nil then
		for _, pid in recorded.survivors do
			table.insert(survivors, pid)
		end
	end
	local leftover = if #survivors > 0
		then ("; Studio processes survived cleanup and need a manual kill: %s"):format(table.concat(survivors, ","))
		else ""
	if result.timedOut or result.exitcode == 124 then
		return {
			status = "timed_out",
			detail = "isolated Studio run exceeded its process deadline; diagnostics: " .. directory .. leftover,
		}
	end
	if not result.ok then
		return {
			status = "faulted",
			detail = result.stderr .. result.stdout .. "; diagnostics: " .. directory .. leftover,
		}
	end
	local decoded, report = pcall(function()
		return Wire.decode(fs.readFileToString(directory .. "/report"))
	end)
	if not decoded then
		return { status = "faulted", detail = "invalid or missing engine report: " .. tostring(report) }
	end
	if #survivors > 0 then
		local first = (report :: Core.Report).results[1]
		if first ~= nil then
			table.insert(first.limitations, leftover:sub(3))
		end
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

return { run = run, worker = worker, host = host, attach = Attach.attach, launch = Launch.launch }
