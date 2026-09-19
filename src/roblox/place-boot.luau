--!strict

local PlaceRuntime = require "./place-runtime"

export type Host = PlaceRuntime.Host
export type Cache = PlaceRuntime.Cache
export type Mounted = PlaceRuntime.Mounted

export type Files = {
	exists: (path: string) -> boolean,
	fileType: (path: string) -> string,
	listDirectory: (path: string) -> { { name: string, type: string } },
}

export type Opaque = {
	attribute: string?,
	fill: ((engine: any, object: any, path: string) -> ())?,
}

export type TreeDeps = {
	cache: Cache,
	host: Host,
	files: Files,
	opaque: Opaque?,
}

export type Viewport = { x: number, y: number }

export type Witness = {
	name: string,
	userId: number,
	jobId: string,
}

export type Identity = {
	universeId: number,
	placeId: number,
	placeVersion: number,
}

export type Stage = "server" | "player" | "client" | "viewport" | "character" | "settled"

export type View = {
	engine: any,
	runtime: any,
	player: any?,
	playerGui: any?,
}

export type Observer = (stage: Stage, view: View) -> ()

export type Attributes = {
	character: string?,
	workspace: string?,
}

export type Config = {
	projectPath: string,
	identity: Identity,
	witness: Witness,
	aliases: { [string]: string },
	firstViewport: Viewport,
	finalViewport: Viewport,
	frames: number?,
	engineProvidedInput: boolean,
	attributes: Attributes?,
	opaque: Opaque?,
	stabilize: ((line: string) -> string)?,
	observe: Observer?,
}

export type Deps = {
	newEngine: () -> any,
	cache: Cache,
	host: Host,
	files: Files,
}

export type Report = {
	engine: any,
	runtime: any,
	mounted: Mounted,
	player: any,
	playerGui: any,
	diagnostics: { any },
	serverScripts: { string },
	clientScripts: { string },
	firstScripts: { any },
	roots: { string },
	mountedRoots: { string },
	lines: { string },
	waits: { { target: string, name: string, source: string } },
	frames: number,
	blocked: number,
	step: () -> (),
}

local IMPLICIT_CLASS_NAME = "Folder"
local FRAME_SECONDS = 1 / 60
local DEFAULT_FRAME_BUDGET = 240
local COMMIT_PATTERN = string.rep("%x", 40)
local COMMIT_TOKEN = "<commit>"

local function stabilizeCommit(line: string): string
	return (string.gsub(line, COMMIT_PATTERN, COMMIT_TOKEN))
end

local function globToPattern(glob: string): string
	local pattern = "^"
	local index = 1
	while index <= #glob do
		local char = string.sub(glob, index, index)
		if char == "*" then
			if string.sub(glob, index + 1, index + 1) == "*" then
				pattern ..= ".*"
				index += 2
				if string.sub(glob, index, index) == "/" then
					index += 1
				end
			else
				pattern ..= "[^/]*"
				index += 1
			end
		elseif char == "?" then
			pattern ..= "[^/]"
			index += 1
		elseif string.match(char, "[%^%$%(%)%%%.%[%]%+%-]") ~= nil then
			pattern ..= "%" .. char
			index += 1
		else
			pattern ..= char
			index += 1
		end
	end
	return pattern .. "$"
end

local function ignored(path: string, patterns: { string }): boolean
	for _, pattern in patterns do
		if string.match(path, pattern) ~= nil then
			return true
		end
	end
	return false
end

local function scriptClass(fileName: string): (string?, string?)
	local client = string.match(fileName, "^(.+)%.client%.luau$")
	if client ~= nil then
		return "LocalScript", client
	end
	local server = string.match(fileName, "^(.+)%.server%.luau$")
	if server ~= nil then
		return "Script", server
	end
	local module = string.match(fileName, "^(.+)%.luau$")
	if module ~= nil then
		return "ModuleScript", module
	end
	return nil
end

local function buildTree(engine: any, projectPath: string, deps: TreeDeps): Mounted
	local cache = deps.cache
	local files = deps.files
	local opaque = deps.opaque
	local project: any = deps.host.decodeJson(deps.host.readFile(projectPath))
	local patterns: { string } = {}
	for _, glob in (project.globIgnorePaths or {}) :: { string } do
		patterns[#patterns + 1] = globToPattern(glob)
	end

	local scripts: { any } = {}
	local sources: { [any]: string } = {}

	local function attach(object: any, parent: any, name: string)
		engine.stateOf(object).name = name
		engine.stateOf(object).values.Name = name
		object.Parent = parent
	end

	local function makeScript(className: string, name: string, path: string, parent: any): any
		local object = engine.newInstance(className, true)
		attach(object, parent, name)
		sources[object] = path
		cache.read(path)
		if className ~= "ModuleScript" then
			scripts[#scripts + 1] = object
		end
		return object
	end

	local function mountPath(path: string, name: string, parent: any): any?
		if ignored(path, patterns) then
			return nil
		end
		if not files.exists(path) then
			return nil
		end
		if files.fileType(path) == "file" then
			local className = scriptClass(string.match(path, "([^/]+)$") :: string)
			if className == nil then
				return nil
			end
			return makeScript(className, name, path, parent)
		end
		local entries = files.listDirectory(path)
		local container: any = nil
		for _, entry in entries do
			if entry.type ~= "file" then
				continue
			end
			if entry.name == "init.luau" then
				container = makeScript("ModuleScript", name, path .. "/init.luau", parent)
			elseif entry.name == "init.client.luau" then
				container = makeScript("LocalScript", name, path .. "/init.client.luau", parent)
			elseif entry.name == "init.server.luau" then
				container = makeScript("Script", name, path .. "/init.server.luau", parent)
			end
		end
		if container == nil then
			container = engine.newInstance("Folder", true)
			attach(container, parent, name)
		end
		for _, entry in entries do
			local childPath = path .. "/" .. entry.name
			if entry.type == "dir" then
				mountPath(childPath, entry.name, container)
				continue
			end
			if string.match(entry.name, "^init%.") ~= nil then
				continue
			end
			local resolved, base = scriptClass(entry.name)
			if resolved == nil then
				continue
			end
			if ignored(childPath, patterns) then
				continue
			end
			makeScript(resolved, base :: string, childPath, container)
		end
		return container
	end

	local function mountNode(node: any, name: string, parent: any?): any
		local object: any = nil
		local path = node["$path"]
		if parent == nil then
			object = engine.game
		elseif path ~= nil then
			if string.match(path, "%.rbx[m]?[x]?$") ~= nil then
				object = engine.newInstance("Model", true)
				attach(object, parent, name)
				if opaque ~= nil then
					if opaque.attribute ~= nil then
						object:SetAttribute(opaque.attribute :: string, path)
					end
					if opaque.fill ~= nil then
						(opaque.fill :: any)(engine, object, path)
					end
				end
			else
				object = mountPath(path, name, parent)
			end
			if object == nil then
				object = engine.newInstance(node["$className"] or IMPLICIT_CLASS_NAME, true)
				attach(object, parent, name)
			end
		elseif node["$className"] ~= nil then
			if engine.surface.services[node["$className"]] == true and parent == engine.game then
				object = engine.service(node["$className"])
			else
				object = engine.newInstance(node["$className"], true)
				attach(object, parent, name)
			end
		else
			object = engine.newInstance("Folder", true)
			attach(object, parent, name)
		end
		local properties = node["$properties"]
		if properties ~= nil then
			for key, value in properties :: { [string]: any } do
				if type(key) ~= "string" then
					continue
				end
				local kind = engine.surface.memberKind(engine.stateOf(object).className, key)
				if kind == "property" then
					local declared = engine.surface.memberType(engine.stateOf(object).className, key)
					if type(value) == "string" and string.match(declared or "", "^Enum") ~= nil then
						local category = string.match(declared :: string, "^Enum(%w+)$")
						if category ~= nil then
							local ok, item = pcall(function()
								return (engine.datatypes.Enum :: any)[category][value]
							end)
							value = if ok then item else value
						end
					end
					engine.stateOf(object).values[key] = value
				end
			end
		end
		for key, value in node do
			if type(key) ~= "string" or string.sub(key, 1, 1) == "$" then
				continue
			end
			mountNode(value, key, object)
		end
		return object
	end

	for name, node in project.tree :: { [string]: any } do
		if type(name) ~= "string" or string.sub(name, 1, 1) == "$" then
			continue
		end
		local service = engine.service(if node["$className"] ~= nil then node["$className"] else name)
		local properties = node["$properties"]
		if properties ~= nil then
			for key, value in properties :: { [string]: any } do
				if type(key) ~= "string" then
					continue
				end
				if engine.surface.memberKind(engine.stateOf(service).className, key) == "property" then
					engine.stateOf(service).values[key] = value
				end
			end
		end
		for key, value in node do
			if type(key) ~= "string" or string.sub(key, 1, 1) == "$" then
				continue
			end
			mountNode(value, key, service)
		end
	end

	return { root = engine.game, scripts = scripts, sources = sources }
end

local function frameOnce(engine: any, runtime: any)
	local run = engine.service "RunService"
	local scheduler = engine.scheduler
	scheduler.advance(FRAME_SECONDS)
	scheduler.drain(64)
	engine.fire(engine.stateOf(run).signals.PreRender or engine.signalOf(run, "PreRender"), FRAME_SECONDS)
	engine.fire(engine.signalOf(run, "Stepped"), scheduler.clock(), FRAME_SECONDS)
	engine.fire(engine.signalOf(run, "PreSimulation"), FRAME_SECONDS)
	engine.fire(engine.signalOf(run, "PostSimulation"), FRAME_SECONDS)
	engine.fire(engine.signalOf(run, "RenderStepped"), FRAME_SECONDS)
	engine.fire(engine.signalOf(run, "Heartbeat"), FRAME_SECONDS)
	for _, callback in runtime.renderSteps do
		engine.scheduler.spawn(callback, FRAME_SECONDS)
	end
	scheduler.drain(64)
end

local function scriptsUnder(container: any, className: string, out: { any })
	for _, child in container:GetChildren() do
		if child.ClassName == className then
			out[#out + 1] = child
		end
		scriptsUnder(child, className, out)
	end
end

local function named(engine: any, className: string, name: string, parent: any): any
	local object = engine.newInstance(className, true)
	engine.stateOf(object).name = name
	engine.stateOf(object).values.Name = name
	object.Parent = parent
	return object
end

local function mountEngineProvided(engine: any, player: any, provided: boolean)
	if provided then
		local contexts = named(engine, "Folder", "InputContexts", player)
		local character = named(engine, "InputContext", "CharacterContext", contexts)
		named(engine, "InputAction", "MoveAction", character)
		named(engine, "InputAction", "JumpAction", character)
	end
	local textChat = engine.service "TextChatService"
	if textChat:FindFirstChild "ChatWindowConfiguration" == nil then
		named(engine, "ChatWindowConfiguration", "ChatWindowConfiguration", textChat)
	end
	if textChat:FindFirstChild "ChatInputBarConfiguration" == nil then
		named(engine, "ChatInputBarConfiguration", "ChatInputBarConfiguration", textChat)
	end
	if textChat:FindFirstChild "BubbleChatConfiguration" == nil then
		named(engine, "BubbleChatConfiguration", "BubbleChatConfiguration", textChat)
	end
	if textChat:FindFirstChild "ChannelTabsConfiguration" == nil then
		named(engine, "ChannelTabsConfiguration", "ChannelTabsConfiguration", textChat)
	end
	local channels = textChat:FindFirstChild "TextChannels"
	if channels == nil then
		channels = named(engine, "Folder", "TextChannels", textChat)
	end
	if channels:FindFirstChild "RBXGeneral" == nil then
		named(engine, "TextChannel", "RBXGeneral", channels)
	end
end

local function makeCharacter(engine: any, name: string): any
	local character = engine.newInstance("Model", true)
	engine.stateOf(character).name = name
	local root = engine.newInstance("Part", true)
	engine.stateOf(root).name = "HumanoidRootPart"
	root.Parent = character
	local head = engine.newInstance("Part", true)
	engine.stateOf(head).name = "Head"
	head.Parent = character
	local humanoid = engine.newInstance("Humanoid", true)
	humanoid.Parent = character
	local animator = engine.newInstance("Animator", true)
	animator.Parent = humanoid
	engine.stateOf(character).values.PrimaryPart = root
	return character
end

local function run(config: Config, deps: Deps): Report
	local engine = deps.newEngine()
	local mounted = buildTree(engine, config.projectPath, {
		cache = deps.cache,
		host = deps.host,
		files = deps.files,
		opaque = config.opaque,
	})
	local runtime = PlaceRuntime.create(engine, mounted, {
		aliases = config.aliases,
		cache = deps.cache,
		host = deps.host,
	})
	local watcher = config.observe
	local witnessed: any = nil
	local witnessedGui: any = nil
	local function reachedStage(stage: Stage)
		if watcher == nil then
			return
		end
		(watcher :: Observer)(stage, {
			engine = engine,
			runtime = runtime,
			player = witnessed,
			playerGui = witnessedGui,
		})
	end

	function engine.signalOf(object: any, name: string): any
		local state = engine.stateOf(object)
		local existing = state.signals[name]
		if existing == nil then
			existing = engine.signal()
			state.signals[name] = existing
		end
		return existing
	end

	engine.stateOf(engine.game).values.GameId = config.identity.universeId
	engine.stateOf(engine.game).values.PlaceId = config.identity.placeId
	engine.stateOf(engine.game).values.JobId = config.witness.jobId
	engine.stateOf(engine.game).values.PlaceVersion = config.identity.placeVersion

	local players = engine.service "Players"
	local workspace = engine.service "Workspace"
	local replicatedFirst = engine.service "ReplicatedFirst"
	local serverScriptService = engine.service "ServerScriptService"
	local starterPlayer = engine.service "StarterPlayer"

	local camera = engine.newInstance("Camera", true)
	engine.stateOf(camera).name = "Camera"
	engine.stateOf(camera).values.ViewportSize =
		engine.datatypes.Vector2.new(config.firstViewport.x, config.firstViewport.y)
	camera.Parent = workspace
	engine.stateOf(workspace).values.CurrentCamera = camera

	local terrain = engine.newInstance("Terrain", true)
	engine.stateOf(terrain).name = "Terrain"
	terrain.Parent = workspace
	engine.stateOf(workspace).values.Terrain = terrain

	local serverNames: { string } = {}
	local serverScripts: { any } = {}
	scriptsUnder(serverScriptService, "Script", serverScripts)
	scriptsUnder(workspace, "Script", serverScripts)
	for _, entry in serverScripts do
		serverNames[#serverNames + 1] = entry:GetFullName()
		runtime.runScript(entry, "server")
	end
	for _ = 1, 4 do
		frameOnce(engine, runtime)
	end
	reachedStage "server"

	local player = engine.newInstance("Player", true)
	engine.stateOf(player).name = config.witness.name
	engine.stateOf(player).values.UserId = config.witness.userId
	engine.stateOf(player).values.DisplayName = config.witness.name
	local playerGui = engine.newInstance("PlayerGui", true)
	engine.stateOf(playerGui).name = "PlayerGui"
	playerGui.Parent = player
	local seenRoots: { [string]: boolean } = {}
	engine.signalOf(playerGui, "ChildAdded"):Connect(function(child: any)
		seenRoots[child.Name] = true
	end)
	local playerScripts = engine.newInstance("PlayerScripts", true)
	engine.stateOf(playerScripts).name = "PlayerScripts"
	playerScripts.Parent = player
	local backpack = engine.newInstance("Backpack", true)
	engine.stateOf(backpack).name = "Backpack"
	backpack.Parent = player
	engine.stateOf(players).values.LocalPlayer = player
	runtime.localPlayer = player
	mountEngineProvided(engine, player, config.engineProvidedInput)
	player.Parent = players
	engine.fire(engine.signalOf(players, "PlayerAdded"), player)

	for _ = 1, 2 do
		frameOnce(engine, runtime)
	end
	witnessed = player
	witnessedGui = playerGui
	reachedStage "player"

	local clientNames: { string } = {}
	local firstScripts: { any } = {}
	scriptsUnder(replicatedFirst, "LocalScript", firstScripts)
	for _, entry in firstScripts do
		clientNames[#clientNames + 1] = entry:GetFullName()
		runtime.runScript(entry, "client")
	end

	local starterScripts = starterPlayer:FindFirstChild "StarterPlayerScripts"
	if starterScripts ~= nil then
		for _, child in starterScripts:GetChildren() do
			child.Parent = playerScripts
		end
	end
	local playerLocalScripts: { any } = {}
	scriptsUnder(playerScripts, "LocalScript", playerLocalScripts)
	for _, entry in playerLocalScripts do
		clientNames[#clientNames + 1] = entry:GetFullName()
		runtime.runScript(entry, "client")
	end

	frameOnce(engine, runtime)
	reachedStage "client"

	engine.stateOf(camera).values.ViewportSize =
		engine.datatypes.Vector2.new(config.finalViewport.x, config.finalViewport.y)
	local viewportChanged = engine.stateOf(camera).propertySignals.ViewportSize
	if viewportChanged ~= nil then
		engine.fire(viewportChanged)
	end

	frameOnce(engine, runtime)
	reachedStage "viewport"

	local character = makeCharacter(engine, engine.stateOf(player).name)
	character.Parent = workspace
	engine.stateOf(player).values.Character = character
	engine.fire(engine.signalOf(player, "CharacterAdded"), character)

	frameOnce(engine, runtime)
	reachedStage "character"

	local attributes = config.attributes
	if attributes ~= nil then
		if attributes.character ~= nil then
			character:SetAttribute(attributes.character :: string, true)
		end
		if attributes.workspace ~= nil then
			workspace:SetAttribute(attributes.workspace :: string, true)
		end
	end

	local budget = config.frames or DEFAULT_FRAME_BUDGET
	for _ = 1, budget do
		frameOnce(engine, runtime)
	end

	reachedStage "settled"

	local roots: { string } = {}
	for _, child in playerGui:GetChildren() do
		roots[#roots + 1] = child.Name
		seenRoots[child.Name] = true
	end
	table.sort(roots)
	local mountedRoots: { string } = {}
	for name in seenRoots do
		mountedRoots[#mountedRoots + 1] = name
	end
	table.sort(mountedRoots)

	local stabilize = config.stabilize or stabilizeCommit
	local lines: { string } = {}
	for _, entry in engine.diagnostics do
		if entry.kind == "error" or entry.kind == "warn" then
			local head = string.match(entry.text, "^([^\n]*)") or entry.text
			lines[#lines + 1] = entry.kind .. " " .. entry.source .. ": " .. stabilize(head)
		end
	end

	return {
		engine = engine,
		runtime = runtime,
		mounted = mounted,
		player = player,
		playerGui = playerGui,
		diagnostics = engine.diagnostics,
		serverScripts = serverNames,
		clientScripts = clientNames,
		firstScripts = firstScripts,
		roots = roots,
		mountedRoots = mountedRoots,
		lines = lines,
		waits = engine.outstandingWaits(),
		frames = engine.frames(),
		blocked = engine.blocked(),
		step = function()
			frameOnce(engine, runtime)
		end,
	}
end

return {
	COMMIT_TOKEN = COMMIT_TOKEN,
	FRAME_SECONDS = FRAME_SECONDS,
	STAGES = table.freeze { "server", "player", "client", "viewport", "character", "settled" },
	stabilizeCommit = stabilizeCommit,
	globToPattern = globToPattern,
	scriptClass = scriptClass,
	buildTree = buildTree,
	createCache = PlaceRuntime.createCache,
	createRuntime = PlaceRuntime.create,
	resolveAlias = PlaceRuntime.resolveAlias,
	run = run,
}
