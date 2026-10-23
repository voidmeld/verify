--!strict

local PlaceRuntime = require "./place-runtime"
local Paths = require "../core/path"
type Instance = PlaceRuntime.Instance
export type Engine = PlaceRuntime.Engine
type Runtime = PlaceRuntime.Runtime
type ProjectNode = { [string]: unknown }
type Project = { globIgnorePaths: { string }?, tree: { [string]: ProjectNode } }

export type Host<B = unknown, C = () -> unknown> = PlaceRuntime.Host<B, C>
export type Cache<B = unknown, C = () -> unknown> = PlaceRuntime.Cache<B, C>
export type Mounted = PlaceRuntime.Mounted

export type Files = {
	exists: (path: string) -> boolean,
	fileType: (path: string) -> string,
	listDirectory: (path: string) -> { { name: string, type: string } },
}

export type Opaque = {
	attribute: string?,
	fill: ((engine: PlaceRuntime.Engine, object: Instance, path: string) -> ())?,
}

export type TreeDeps<B = unknown> = {
	cache: Cache<B>,
	host: Host<B>,
	files: Files,
	opaque: Opaque?,
}

export type Viewport = { x: number, y: number }

export type Subject = {
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
	engine: Engine,
	runtime: Runtime,
	player: Instance?,
	playerGui: Instance?,
}

export type Observer = (stage: Stage, view: View) -> ()

export type Attributes = {
	character: string?,
	workspace: string?,
}

export type Config = {
	projectPath: string,
	identity: Identity,
	subject: Subject,
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

export type Deps<B = unknown> = {
	newEngine: () -> Engine,
	cache: Cache<B>,
	host: Host<B>,
	files: Files,
}

export type Report = {
	engine: Engine,
	runtime: Runtime,
	mounted: Mounted,
	player: Instance,
	playerGui: Instance,
	diagnostics: { PlaceRuntime.Diagnostic },
	serverScripts: { string },
	clientScripts: { string },
	firstScripts: { Instance },
	roots: { string },
	mountedRoots: { string },
	lines: { string },
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

local function numbers(value: unknown, count: number): { number }
	assert(type(value) == "table" and #(value :: { unknown }) == count, "invalid project datatype component count")
	for _, component in value :: { unknown } do
		assert(type(component) == "number", "project datatype requires numeric components")
	end
	return value :: { number }
end

local function projectValue(engine: PlaceRuntime.Engine, declared: string?, value: unknown): unknown
	local category = if declared then string.match(declared, "^Enum%.(.+)$") else nil
	if category then
		local family = engine.datatypes.Enum[category]
		if type(value) == "string" then
			return family[value]
		end
		if type(value) == "table" then
			local ordinal = (value :: { Enum: unknown }).Enum
			for _, item in family:GetEnumItems() do
				if item.Value == ordinal then
					return item
				end
			end
		end
		error("project property requires a declared Enum." .. category)
	end
	if type(value) ~= "table" or declared == nil then
		return value
	end
	local encoded = (value :: { [string]: unknown })[declared]
	if declared == "Color3" then
		local v = numbers(encoded, 3)
		return engine.datatypes.Color3.new(v[1], v[2], v[3])
	elseif declared == "Vector3" then
		local v = numbers(encoded, 3)
		return engine.datatypes.Vector3.new(v[1], v[2], v[3])
	elseif declared == "CFrame" then
		assert(type(encoded) == "table", "project CFrame requires position and orientation")
		local frame = encoded :: { position: unknown, orientation: { unknown } }
		local p = numbers(frame.position, 3)
		assert(type(frame.orientation) == "table" and #frame.orientation == 3, "project CFrame requires three rows")
		local x, y, z =
			numbers(frame.orientation[1], 3), numbers(frame.orientation[2], 3), numbers(frame.orientation[3], 3)
		return engine.datatypes.CFrame.new(p[1], p[2], p[3], x[1], x[2], x[3], y[1], y[2], y[3], z[1], z[2], z[3])
	end
	return value
end

local function buildTree<B>(engine: PlaceRuntime.Engine, projectPath: string, deps: TreeDeps<B>): Mounted
	local cache = deps.cache
	local files = deps.files
	local opaque = deps.opaque
	local project = deps.host.decodeJson(deps.host.readFile(projectPath)) :: Project
	local patterns: { string } = {}
	for _, glob in (project.globIgnorePaths or {}) :: { string } do
		patterns[#patterns + 1] = globToPattern(glob)
	end

	local scripts: { Instance } = {}
	local sources: { [Instance]: string } = {}

	local function attach(object: Instance, parent: Instance, name: string)
		engine.environment.poke(object, "Name", name)
		object.Parent = parent
	end

	local function makeScript(className: string, name: string, path: string, parent: Instance): Instance
		local object = engine.newInstance(className, true)
		attach(object, parent :: Instance, name)
		sources[object] = path
		cache.read(path)
		if className ~= "ModuleScript" then
			scripts[#scripts + 1] = object
		end
		return object
	end

	local function mountPath(path: string, name: string, parent: Instance, explicit: boolean?): Instance?
		if explicit ~= true and ignored(path, patterns) then
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
		local container: Instance? = nil
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
			attach(container :: Instance, parent :: Instance, name)
		end
		for _, entry in entries do
			local childPath = path .. "/" .. entry.name
			if entry.type == "dir" then
				mountPath(childPath, entry.name, container :: Instance)
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
			makeScript(resolved, base :: string, childPath, container :: Instance)
		end
		return container
	end

	local function mountNode(node: ProjectNode, name: string, parent: Instance?): Instance
		local object: Instance
		local path = node["$path"] :: string?
		if path then
			path = Paths.collapse(Paths.join(Paths.parent(projectPath), Paths.normalize(path)))
		end
		if parent == nil then
			object = engine.game
		elseif path ~= nil then
			if string.match(path, "%.rbx[m]?[x]?$") ~= nil then
				object = engine.newInstance("Model", true)
				attach(object, parent :: Instance, name)
				if opaque ~= nil then
					if opaque.attribute ~= nil then
						object:SetAttribute(opaque.attribute :: string, path)
					end
					if opaque.fill ~= nil then
						opaque.fill(engine, object, path)
					end
				end
			else
				object = mountPath(path, name, parent, true) :: Instance
			end
			if object == nil then
				object = engine.newInstance((node["$className"] :: string?) or IMPLICIT_CLASS_NAME, true)
				attach(object, parent :: Instance, name)
			end
		elseif (node["$className"] :: string) ~= nil then
			if engine.surface.services[node["$className"] :: string] == true and parent == engine.game then
				object = engine.service(node["$className"] :: string)
			else
				object = engine.newInstance(node["$className"] :: string, true)
				attach(object, parent :: Instance, name)
			end
		else
			object = engine.newInstance("Folder", true)
			attach(object, parent :: Instance, name)
		end
		local properties = node["$properties"]
		if properties ~= nil then
			for key, value in properties :: { [string]: unknown } do
				if type(key) ~= "string" then
					continue
				end
				local kind = engine.surface.memberKind(object.ClassName, key)
				if kind == "property" then
					local declared = engine.surface.memberType(object.ClassName, key)
					engine.environment.poke(object, key, projectValue(engine, declared, value))
				end
			end
		end
		for key, value in node do
			if type(key) ~= "string" or string.sub(key, 1, 1) == "$" then
				continue
			end
			mountNode(value :: ProjectNode, key, object)
		end
		return object
	end

	for name, node in project.tree do
		if type(name) ~= "string" or string.sub(name, 1, 1) == "$" then
			continue
		end
		local service =
			engine.service(if (node["$className"] :: string) ~= nil then node["$className"] :: string else name)
		local properties = node["$properties"]
		if properties ~= nil then
			for key, value in properties :: { [string]: unknown } do
				if type(key) ~= "string" then
					continue
				end
				if engine.surface.memberKind(service.ClassName, key) == "property" then
					engine.environment.poke(
						service,
						key,
						projectValue(engine, engine.surface.memberType(service.ClassName, key), value)
					)
				end
			end
		end
		for key, value in node do
			if type(key) ~= "string" or string.sub(key, 1, 1) == "$" then
				continue
			end
			mountNode(value :: ProjectNode, key, service)
		end
	end

	return { root = engine.game, scripts = scripts, sources = sources }
end

local function scriptsUnder(container: Instance, className: string, out: { Instance })
	for _, child in container:GetChildren() do
		if child.ClassName == className then
			out[#out + 1] = child
		end
		scriptsUnder(child, className, out)
	end
end

local function named(engine: Engine, className: string, name: string, parent: Instance): Instance
	local object = engine.newInstance(className, true)
	engine.environment.poke(object, "Name", name)
	object.Parent = parent
	return object
end

local function mountEngineProvided(engine: Engine, player: Instance, provided: boolean)
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
	if (channels :: Instance):FindFirstChild "RBXGeneral" == nil then
		named(engine, "TextChannel", "RBXGeneral", channels :: Instance)
	end
end

local function makeCharacter(engine: Engine, name: string): Instance
	local character = engine.newInstance("Model", true)
	engine.environment.poke(character, "Name", name)
	local root = engine.newInstance("Part", true)
	engine.environment.poke(root, "Name", "HumanoidRootPart")
	root.Parent = character
	local head = engine.newInstance("Part", true)
	engine.environment.poke(head, "Name", "Head")
	head.Parent = character
	local humanoid = engine.newInstance("Humanoid", true)
	humanoid.Parent = character
	local animator = engine.newInstance("Animator", true)
	animator.Parent = humanoid
	engine.environment.poke(character, "PrimaryPart", root)
	return character
end

local function run<B>(config: Config, deps: Deps<B>): Report
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
	local identified: Instance? = nil
	local identifiedGui: Instance? = nil
	local function reachedStage(stage: Stage)
		if watcher == nil then
			return
		end
		(watcher :: Observer)(stage, {
			engine = engine,
			runtime = runtime,
			player = identified,
			playerGui = identifiedGui,
		})
	end

	engine.environment.poke(engine.game, "GameId", config.identity.universeId)
	engine.environment.poke(engine.game, "PlaceId", config.identity.placeId)
	engine.environment.poke(engine.game, "JobId", config.subject.jobId)
	engine.environment.poke(engine.game, "PlaceVersion", config.identity.placeVersion)

	local players = engine.service "Players"
	local workspace = engine.service "Workspace"
	local replicatedFirst = engine.service "ReplicatedFirst"
	local serverScriptService = engine.service "ServerScriptService"
	local starterPlayer = engine.service "StarterPlayer"

	local camera = engine.newInstance("Camera", true)
	engine.environment.poke(camera, "Name", "Camera")
	engine.environment.poke(
		camera,
		"ViewportSize",
		engine.datatypes.Vector2.new(config.firstViewport.x, config.firstViewport.y)
	)
	camera.Parent = workspace
	engine.environment.poke(workspace, "CurrentCamera", camera)

	local terrain = engine.newInstance("Terrain", true)
	engine.environment.poke(terrain, "Name", "Terrain")
	terrain.Parent = workspace
	engine.environment.poke(workspace, "Terrain", terrain)

	local serverNames: { string } = {}
	local serverScripts: { Instance } = {}
	scriptsUnder(serverScriptService, "Script", serverScripts)
	scriptsUnder(workspace, "Script", serverScripts)
	for _, entry in serverScripts do
		serverNames[#serverNames + 1] = entry:GetFullName()
		runtime.runScript(entry, "server")
	end
	for _ = 1, 4 do
		runtime.step(FRAME_SECONDS)
	end
	reachedStage "server"

	local player = engine.newInstance("Player", true)
	engine.environment.poke(player, "Name", config.subject.name)
	engine.environment.poke(player, "UserId", config.subject.userId)
	engine.environment.poke(player, "DisplayName", config.subject.name)
	local playerGui = engine.newInstance("PlayerGui", true)
	engine.environment.poke(playerGui, "Name", "PlayerGui")
	playerGui.Parent = player
	local seenRoots: { [string]: boolean } = {}
	playerGui.ChildAdded:Connect(function(value: unknown)
		local child = value :: Instance
		seenRoots[tostring(child.Name)] = true
	end)
	local playerScripts = engine.newInstance("PlayerScripts", true)
	engine.environment.poke(playerScripts, "Name", "PlayerScripts")
	playerScripts.Parent = player
	local backpack = engine.newInstance("Backpack", true)
	engine.environment.poke(backpack, "Name", "Backpack")
	backpack.Parent = player
	engine.environment.poke(players, "LocalPlayer", player)
	runtime.localPlayer = player
	mountEngineProvided(engine, player, config.engineProvidedInput)
	player.Parent = players
	engine.environment.fire(players, "PlayerAdded", player)

	for _ = 1, 2 do
		runtime.step(FRAME_SECONDS)
	end
	identified = player
	identifiedGui = playerGui
	reachedStage "player"

	local clientNames: { string } = {}
	local firstScripts: { Instance } = {}
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
	local playerLocalScripts: { Instance } = {}
	scriptsUnder(playerScripts, "LocalScript", playerLocalScripts)
	for _, entry in playerLocalScripts do
		clientNames[#clientNames + 1] = entry:GetFullName()
		runtime.runScript(entry, "client")
	end

	runtime.step(FRAME_SECONDS)
	reachedStage "client"

	engine.environment.poke(
		camera,
		"ViewportSize",
		engine.datatypes.Vector2.new(config.finalViewport.x, config.finalViewport.y)
	)

	runtime.step(FRAME_SECONDS)
	reachedStage "viewport"

	local character = makeCharacter(engine, tostring(player.Name))
	character.Parent = workspace
	engine.environment.poke(player, "Character", character)
	engine.environment.fire(player, "CharacterAdded", character)

	runtime.step(FRAME_SECONDS)
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
		runtime.step(FRAME_SECONDS)
	end

	reachedStage "settled"

	local roots: { string } = {}
	for _, child in playerGui:GetChildren() do
		roots[#roots + 1] = tostring(child.Name)
		seenRoots[tostring(child.Name)] = true
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
		step = function()
			runtime.step(FRAME_SECONDS)
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
