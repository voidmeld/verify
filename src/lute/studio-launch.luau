--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local task = require "@std/task"
local Attach = require "./studio-attach"
local Files = require "./files"
local Install = require "./studio-install"
local Processes = require "./studio-processes"
local Reply = require "./studio-reply"

export type Options = {
	place: string,
	directory: string?,
	studioExecutable: string?,
	mcpExecutable: string?,
	launchSeconds: number?,
	callSeconds: number?,
	runSeconds: number?,
	cleanupSeconds: number?,
	authorize: ((Attach.Request) -> Attach.Authorization)?,
	transport: Attach.Transport?,
	start: ((place: string, name: string, deadline: number) -> number)?,
	processes: Processes.Deps?,
}

export type Closed = { session: Attach.Cleanup, terminated: { number }, survivors: { number } }

export type Launched = {
	session: Attach.Session,
	directory: string,
	place: string,
	name: string,
	pid: number,
	close: () -> Closed,
}

local LIST = "list_roblox_studios"

local function allow(_request: Attach.Request): Attach.Authorization
	return { ok = true }
end

local function listed(transport: Attach.Transport, deadline: number): ({ Attach.StudioInfo }?, string?)
	local exchange = transport.call(LIST, "{}", deadline)
	if exchange.status ~= "answered" then
		return nil, exchange.detail or exchange.status
	end
	if exchange.detail ~= nil then
		return nil, exchange.detail
	end
	local parsed, value: unknown = pcall(function(): { Attach.StudioInfo }
		return Attach.discovered(Reply.texts(exchange.result))
	end)
	if not parsed then
		return nil, tostring(value)
	end
	return value :: { Attach.StudioInfo }, nil
end

local function open(
	options: Options,
	directory: string,
	place: string,
	name: string,
	deadline: number
): (Launched?, string?)
	local transport = options.transport or Attach.transport(options.mcpExecutable :: string, directory .. "/mcp")
	local before = Processes.snapshot(options.processes)
	local pid: number? = nil

	local function abandon(detail: string): (Launched?, string?)
		pcall(transport.close)
		local cleanup = Processes.reap(before, { root = pid, markers = { name } }, options.processes)
		if #cleanup.survivors > 0 then
			detail ..= ("; Studio processes survived cleanup and need a manual kill: %s"):format(
				table.concat(cleanup.survivors, ",")
			)
		end
		return nil, detail
	end

	local previous, problem = listed(transport, deadline)
	if previous == nil then
		return abandon("the Studio MCP server did not list the open Studios: " .. tostring(problem))
	end
	local known: { [string]: boolean } = {}
	for _, studio in previous do
		known[studio.id] = true
	end
	local started, value: unknown = pcall(function(): number
		if options.start ~= nil then
			return options.start(place, name, deadline)
		end
		return Processes.start(options.studioExecutable :: string, place, name, deadline, directory .. "/studio.log")
	end)
	if not started then
		return abandon("Studio did not start: " .. tostring(value))
	end
	pid = value :: number
	local selected: Attach.StudioInfo? = nil
	local last = "no listing arrived"
	while selected == nil and os.clock() < deadline do
		local studios, failure = listed(transport, deadline)
		if studios == nil then
			last = tostring(failure)
		else
			local matches: { Attach.StudioInfo } = {}
			for _, studio in studios do
				if not known[studio.id] and studio.name == name then
					table.insert(matches, studio)
				end
			end
			if #matches > 1 then
				return abandon "several new Studios opened the launched place; refusing to choose one"
			end
			selected = matches[1]
			local names: { string } = {}
			for _, studio in studios do
				table.insert(names, ("%s (%s)"):format(studio.name, if known[studio.id] then "open before" else "new"))
			end
			last = ("the list held %d Studio(s): %s"):format(#studios, table.concat(names, ", "))
		end
		if selected == nil then
			task.wait(0.5)
		end
	end
	if selected == nil then
		return abandon("the launched Studio did not appear before its launch deadline; " .. last)
	end
	local session, refusal = Attach.attach {
		authorize = options.authorize or allow,
		studioId = (selected :: Attach.StudioInfo).id,
		transport = transport,
		mode = "edit",
		callSeconds = options.callSeconds,
		runSeconds = options.runSeconds,
		cleanupSeconds = options.cleanupSeconds,
	}
	if session == nil then
		local why = refusal :: Attach.Refusal
		return abandon(("attach %s: %s"):format(why.kind, why.detail))
	end
	local opened = session :: Attach.Session
	local owner = pid :: number
	local closed: Closed? = nil
	return {
		session = opened,
		directory = directory,
		place = place,
		name = name,
		pid = owner,
		close = function(): Closed
			if closed ~= nil then
				return closed :: Closed
			end
			local cleanup = opened.close()
			local reaped = Processes.reap(before, { root = owner, markers = { name } }, options.processes)
			local result: Closed = { session = cleanup, terminated = reaped.terminated, survivors = reaped.survivors }
			closed = result
			return result
		end,
	},
		nil
end

local function extension(source: string): string?
	if string.sub(source, 1, 8) == "<roblox!" then
		return if string.sub(source, 1, 14) == "<roblox!\137\255\r\n\26\n" then ".rbxl" else nil
	end
	return if string.find(source, "<roblox", 1, true) ~= nil then ".rbxlx" else nil
end

local function launch(options: Options): (Launched?, string?)
	if type(options) ~= "table" or type(options.place) ~= "string" or options.place == "" then
		return nil, "launch requires the path of a Roblox place"
	end
	if not fs.exists(options.place) then
		return nil, "no place exists at " .. options.place
	end
	local source = fs.readFileToString(options.place)
	local format = extension(source)
	if format == nil then
		return nil, "launch requires a Roblox XML or binary place"
	end
	local studioExecutable = options.studioExecutable
	local mcpExecutable = options.mcpExecutable
	if (options.start == nil and studioExecutable == nil) or (options.transport == nil and mcpExecutable == nil) then
		local installed, missing = Install.locate()
		if installed == nil then
			return nil, "Roblox Studio was not found: " .. tostring(missing)
		end
		studioExecutable = studioExecutable or installed.studio
		mcpExecutable = mcpExecutable or installed.mcp
	end
	local launchSeconds = options.launchSeconds or 180
	if not (launchSeconds > 0 and launchSeconds < math.huge) then
		return nil, "the launch deadline must be finite and positive"
	end
	local directory = Files.claimDirectory(options.directory or Files.temporary "verify-studio-launch")
	local leaf = string.match(directory, "[^/\\]+$") or "run"
	local name = ("Verify-%d-%s%s"):format(process.pid(), leaf, format)
	local place = directory .. "/" .. name
	fs.writeStringToFile(place, source)
	local deadline = os.clock() + launchSeconds
	local settings = table.clone(options)
	settings.studioExecutable = studioExecutable
	settings.mcpExecutable = mcpExecutable
	return open(settings, directory, place, name, deadline)
end

return { launch = launch, open = open, extension = extension }
