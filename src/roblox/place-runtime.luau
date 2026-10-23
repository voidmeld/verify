--!strict

local Scheduler = require "./scheduler"
local Datatypes = require "./datatypes"
local Environment = require "./environment"

export type Chunk = () -> unknown
export type Instance = Environment.Instance
export type Diagnostic = { kind: string, text: string, source: string }
export type Engine = {
	game: Instance,
	environment: Environment.Environment,
	newInstance: (string, boolean?) -> Instance,
	service: (string) -> Instance,
	setSourceResolver: (() -> string) -> (),
	currentSource: () -> string,
	record: (string, string, string) -> (),
	isInstance: (unknown) -> boolean,
	datatypes: typeof(Datatypes),
	typeName: (unknown) -> string,
	diagnostics: { Diagnostic },
	surface: {
		services: { [string]: boolean },
		memberKind: (string, string) -> string?,
		memberType: (string, string) -> string?,
	},
}
type Entry = { status: string, waiters: { thread }, value: unknown, failure: unknown }
export type Runtime = {
	localPlayer: Instance?,
	closeHandlers: { () -> () },
	renderSteps: { [string]: (number) -> () },
	tagAdded: { [string]: Environment.Signal },
	tagRemoved: { [string]: Environment.Signal },
	guidCount: number,
	dataStore: {
		GetAsync: () -> unknown,
		SetAsync: () -> unknown,
		UpdateAsync: (unknown, string, (unknown) -> unknown) -> unknown,
		RemoveAsync: () -> unknown,
		OnUpdate: () -> { Disconnect: () -> () },
	},
	globals: { [string]: unknown },
	requireInstance: (unknown) -> unknown,
	runScript: (Instance, string) -> thread?,
	step: (seconds: number) -> (),
}

export type Host<B = unknown, C = Chunk> = {
	readFile: (path: string) -> string,
	compile: (source: string) -> B,
	load: (bytecode: B, chunkName: string, environment: { [string]: unknown }) -> C,
	encodeJson: (value: unknown) -> string,
	decodeJson: (text: string) -> unknown,
}

export type Cache<B = unknown, C = Chunk> = {
	read: (path: string) -> string,
	bytecode: (path: string) -> B,
	load: (path: string, environment: { [string]: unknown }) -> C,
}

export type Mounted = {
	root: Instance,
	scripts: { Instance },
	sources: { [Instance]: string },
}

export type Client = { name: string, userId: number, viewport: { x: number, y: number } }

export type Options<B = unknown> = {
	aliases: { [string]: string },
	cache: Cache<B>,
	host: Host<B>,
	methodDoubles: { string }?,
	client: Client?,
	beforeRender: (() -> ())?,
}

local function createCache<B, C>(host: Host<B, C>): Cache<B, C>
	local texts: { [string]: string } = {}
	local bytecodes: { [string]: B } = {}

	local cache = {}

	function cache.read(path: string): string
		local existing = texts[path]
		if existing == nil then
			existing = host.readFile(path)
			texts[path] = existing
		end
		return existing
	end

	function cache.bytecode(path: string): B
		local existing = bytecodes[path]
		if existing == nil then
			existing = host.compile(cache.read(path))
			bytecodes[path] = existing
		end
		return existing
	end

	function cache.load(path: string, environment: { [string]: unknown }): C
		return host.load(cache.bytecode(path), "@" .. path, environment)
	end

	return cache
end

local function resolveAlias(aliases: { [string]: string }, target: string): string?
	local alias, rest = string.match(target, "^@([%w_]+)/(.+)$")
	if alias == nil then
		return nil
	end
	local root = aliases[alias :: string]
	if root == nil then
		return nil
	end
	return root .. "/" .. (rest :: string)
end

local function create<B>(engine: Engine, mounted: Mounted, options: Options<B>): Runtime
	local aliases = options.aliases
	local cache = options.cache
	local host = options.host
	local runtime = {} :: Runtime
	local environment = engine.environment
	local scheduler = environment.scheduler
	local modules: { [string]: { [Instance]: Entry } } = { server = {}, client = {} }
	local fileModules: { [string]: Entry } = {}
	local globals: { [string]: unknown } = {}

	local function context(): string
		local tag = scheduler.context()
		return if type(tag) == "table" then (tag :: { context: string }).context else "server"
	end

	local function source(): string
		local tag = scheduler.context()
		return if type(tag) == "table" then (tag :: { source: string }).source else "engine"
	end

	engine.setSourceResolver(source)
	scheduler.onFailure(function(message: string)
		engine.record("error", message, source())
	end)

	local function loadSource(path: string, _chunkName: string, environment: { [string]: unknown }): Chunk
		return cache.load(path, environment)
	end

	local resolveInstanceRequire: (Instance, string) -> unknown

	local function environmentFor(scriptInstance: Instance): { [string]: unknown }
		local environment: { [string]: unknown } = (
			setmetatable({}, { __index = globals }) :: unknown
		) :: { [string]: unknown }
		environment.script = scriptInstance
		environment.getfenv = function(): unknown
			return environment
		end
		environment.setfenv = function(_level: unknown, replacement: unknown): unknown
			return replacement
		end
		environment.require = function(target: unknown): unknown
			if type(target) == "string" then
				return resolveInstanceRequire(scriptInstance, target)
			end
			return (globals.require :: (unknown) -> unknown)(target)
		end
		return environment
	end

	local requireInstance: (unknown) -> unknown
	local requirePath: (string) -> unknown

	local function awaitEntry(entry: Entry): unknown
		if entry.status == "loading" then
			scheduler.block(function(thread: thread)
				table.insert(entry.waiters, thread)
			end)
		end
		if entry.status ~= "done" then
			error(entry.failure, 0)
		end
		return entry.value
	end

	local function settle(entry: Entry, status: string, value: unknown)
		entry.status = status
		if status == "done" then
			entry.value = value
		else
			entry.failure = value
		end
		local waiters = entry.waiters
		entry.waiters = {}
		for _, thread in waiters do
			scheduler.resume(thread)
		end
	end

	function requirePath(path: string): unknown
		local cached = fileModules[path]
		if cached ~= nil then
			return awaitEntry(cached)
		end
		local environment: { [string]: unknown } = (
			setmetatable({}, { __index = globals }) :: unknown
		) :: { [string]: unknown }
		environment.script = nil
		environment.getfenv = function(): unknown
			return environment
		end
		local entry: Entry = { status = "loading", waiters = {}, value = nil, failure = nil }
		fileModules[path] = entry
		local ok, value = pcall(function(): unknown
			return loadSource(path, "@" .. path, environment)()
		end)
		settle(entry, if ok then "done" else "failed", value)
		if not ok then
			error(value, 0)
		end
		return value
	end

	function resolveInstanceRequire(scriptInstance: Instance, target: string): unknown
		local selfPath = string.match(target, "^@self/(.+)$")
		local base: Instance? = nil
		local rest: string? = nil
		if selfPath ~= nil then
			base = scriptInstance
			rest = selfPath
		else
			local container = scriptInstance.Parent
			local upward = string.match(target, "^%.%./(.+)$")
			if upward ~= nil then
				base = (container :: Instance).Parent
				rest = upward
			else
				local sibling = string.match(target, "^%./(.+)$")
				if sibling ~= nil then
					base = container
					rest = sibling
				end
			end
		end
		if base == nil then
			return requireInstance(target)
		end
		local walk = base
		for segment in string.gmatch(rest :: string, "[^/]+") do
			local child = walk:FindFirstChild(segment)
			if child == nil then
				error(
					("place runtime cannot resolve require(%q) from %s"):format(target, scriptInstance:GetFullName()),
					2
				)
			end
			walk = child
		end
		return requireInstance(walk)
	end

	function requireInstance(target: unknown): unknown
		if type(target) == "string" then
			local resolved = resolveAlias(aliases, target)
			if resolved == nil then
				error(("place runtime cannot resolve require(%q)"):format(target), 2)
			end
			return requirePath(resolved :: string)
		end
		if not engine.isInstance(target) then
			error("Attempted to call require with invalid argument(s).", 2)
		end
		local object = target :: Instance
		if object.ClassName ~= "ModuleScript" then
			error(("Attempted to require a %s"):format(object.ClassName), 2)
		end
		local moduleCache = modules[context()]
		local cached = moduleCache[object]
		if cached ~= nil then
			return awaitEntry(cached)
		end
		local path = mounted.sources[object]
		if path == nil then
			error(("place runtime has no source for %s"):format(object:GetFullName()), 2)
		end
		local entry: Entry = { status = "loading", waiters = {}, value = nil, failure = nil }
		moduleCache[object] = entry
		local ok, value = pcall(function(): unknown
			return loadSource(path, "@" .. path, environmentFor(object))()
		end)
		local failure = "Requested module experienced an error while loading"
		settle(entry, if ok then "done" else "failed", if ok then value else failure)
		if not ok then
			engine.record("error", tostring(value), path)
			error(failure, 0)
		end
		return value
	end

	local contextActionGui: Instance? = nil
	local contextActionButtons: { [string]: Instance } = {}

	local function contextActionButton(name: string): Instance?
		local player = runtime.localPlayer
		local playerGui = if player ~= nil then player:FindFirstChild "PlayerGui" else nil
		if playerGui == nil then
			return nil
		end
		if contextActionGui == nil or contextActionGui.Parent ~= playerGui then
			local gui = engine.newInstance "ScreenGui"
			gui.Name = "ContextActionGui"
			gui.Parent = playerGui
			local frame = engine.newInstance "Frame"
			frame.Name = "ContextButtonFrame"
			frame.Parent = gui
			contextActionGui = gui
			table.clear(contextActionButtons)
		end
		local existing = contextActionButtons[name]
		if existing ~= nil then
			return existing
		end
		local button = engine.newInstance "ImageButton"
		button.Name = name
		button.Parent = (contextActionGui :: Instance):FindFirstChild "ContextButtonFrame"
		local title = engine.newInstance "TextLabel"
		title.Name = "ActionTitle"
		title.Parent = button
		contextActionButtons[name] = button
		return button
	end

	local function serviceOverrides()
		local overrides: { [string]: { [string]: unknown } } = {}
		overrides.ContextActionService = {
			BindAction = function(_service: Instance, name: string, _handler: unknown, createTouchButton: unknown)
				if createTouchButton == true then
					contextActionButton(name)
				end
			end,
			BindActionAtPriority = function(
				_service: Instance,
				name: string,
				_handler: unknown,
				createTouchButton: unknown
			)
				if createTouchButton == true then
					contextActionButton(name)
				end
			end,
			UnbindAction = function(_service: Instance, name: string)
				local button = contextActionButtons[name]
				if button ~= nil then
					contextActionButtons[name] = nil
					button:Destroy()
				end
			end,
			GetButton = function(_service: Instance, name: string): unknown
				return contextActionButtons[name]
			end,
			SetTitle = function(_service: Instance, name: string, title: string)
				local button = contextActionButtons[name]
				local label = if button ~= nil then button:FindFirstChild "ActionTitle" else nil
				if label ~= nil then
					label.Text = title
				end
			end,
			SetPosition = function(_service: Instance, name: string, position: unknown)
				local button = contextActionButtons[name]
				if button ~= nil then
					button.Position = position
				end
			end,
			SetImage = function() end,
		}
		overrides.DataModel = {
			GetService = function(_self: Instance, name: string): unknown
				return engine.service(name)
			end,
			FindService = function(_self: Instance, name: string): unknown
				return engine.service(name)
			end,
			BindToClose = function(_self: Instance, callback: () -> ())
				runtime.closeHandlers[#runtime.closeHandlers + 1] = callback
			end,
			IsLoaded = function(): boolean
				return true
			end,
			GetFullName = function(): string
				return ""
			end,
		}
		overrides.RunService = {
			IsServer = function(): boolean
				return context() == "server"
			end,
			IsClient = function(): boolean
				return context() == "client"
			end,
			IsStudio = function(): boolean
				return false
			end,
			IsRunning = function(): boolean
				return true
			end,
			IsRunMode = function(): boolean
				return true
			end,
			IsEdit = function(): boolean
				return false
			end,
			BindToRenderStep = function(_service: Instance, name: string, _priority: number, callback: (number) -> ())
				runtime.renderSteps[name] = callback
			end,
			UnbindFromRenderStep = function(_service: Instance, name: string)
				runtime.renderSteps[name] = nil
			end,
		}
		overrides.Players = {
			GetPlayers = function(service: Instance): { Instance }
				local out: { Instance } = {}
				for _, child in service:GetChildren() do
					if child.ClassName == "Player" then
						out[#out + 1] = child
					end
				end
				return out
			end,
			GetPlayerFromCharacter = function(service: Instance, character: Instance): unknown
				for _, player in ((service.GetPlayers :: unknown) :: (Instance) -> { Instance })(service) do
					if player.Character == character then
						return player
					end
				end
				return nil
			end,
			GetPlayerByUserId = function(service: Instance, userId: number): unknown
				for _, player in ((service.GetPlayers :: unknown) :: (Instance) -> { Instance })(service) do
					if player.UserId == userId then
						return player
					end
				end
				return nil
			end,
		}
		local function signalOn(object: Instance, name: string): Environment.Signal
			return object[name] :: Environment.Signal
		end
		local function callbackOf(object: Instance, name: string): unknown
			return environment.propertyOf(object, name)
		end
		overrides.RemoteEvent = {
			FireServer = function(object: Instance, ...: unknown)
				signalOn(object, "OnServerEvent"):Fire(runtime.localPlayer, ...)
			end,
			FireClient = function(object: Instance, _player: unknown, ...: unknown)
				signalOn(object, "OnClientEvent"):Fire(...)
			end,
			FireAllClients = function(object: Instance, ...: unknown)
				signalOn(object, "OnClientEvent"):Fire(...)
			end,
		}
		overrides.UnreliableRemoteEvent = overrides.RemoteEvent
		overrides.RemoteFunction = {
			InvokeServer = function(object: Instance, ...: unknown): ...unknown
				local callback = callbackOf(object, "OnServerInvoke")
				if callback == nil then
					error(
						("Attempt to call a RemoteFunction %s with no OnServerInvoke"):format(object:GetFullName()),
						2
					)
				end
				return (callback :: (Instance?, ...unknown) -> ...unknown)(runtime.localPlayer, ...)
			end,
			InvokeClient = function(object: Instance, _player: unknown, ...: unknown): ...unknown
				local callback = callbackOf(object, "OnClientInvoke")
				if callback == nil then
					error(
						("Attempt to call a RemoteFunction %s with no OnClientInvoke"):format(object:GetFullName()),
						2
					)
				end
				return (callback :: (...unknown) -> ...unknown)(...)
			end,
		}
		overrides.BindableEvent = {
			Fire = function(object: Instance, ...: unknown)
				signalOn(object, "Event"):Fire(...)
			end,
		}
		overrides.BindableFunction = {
			Invoke = function(object: Instance, ...: unknown): ...unknown
				local callback = callbackOf(object, "OnInvoke")
				if callback == nil then
					error(("Attempt to call a BindableFunction %s with no OnInvoke"):format(object:GetFullName()), 2)
				end
				return (callback :: (...unknown) -> ...unknown)(...)
			end,
		}
		overrides.HttpService = {
			GenerateGUID = function(_service: Instance, wrapInCurlyBraces: boolean?): string
				runtime.guidCount += 1
				local body = ("%08x-0000-4000-8000-%012x"):format(runtime.guidCount, runtime.guidCount)
				if wrapInCurlyBraces == false then
					return body
				end
				return "{" .. body .. "}"
			end,
			JSONEncode = function(_service: Instance, value: unknown): string
				return host.encodeJson(value)
			end,
			JSONDecode = function(_service: Instance, text: string): unknown
				return host.decodeJson(text)
			end,
		}
		local pendingDetach = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: boolean }
		local function tagged(tag: string): { Instance }
			local out: { Instance } = {}
			local candidates = engine.game:GetDescendants()
			table.insert(candidates, 1, engine.game)
			for _, object in candidates do
				if not pendingDetach[object] and table.find(environment.tagsOf(object), tag) then
					table.insert(out, object)
				end
			end
			return out
		end
		if options.methodDoubles == nil or table.find(options.methodDoubles, "CollectionService") then
			local function notify(object: Instance, present: boolean)
				for _, tag in environment.tagsOf(object) do
					local signals: { [string]: Environment.Signal } = if present
						then runtime.tagAdded
						else runtime.tagRemoved
					local signal = signals[tag]
					if signal then
						signal:Fire(object)
					end
				end
			end
			local added = engine.game.DescendantAdded:Connect(function(object)
				pendingDetach[object] = nil
				notify(object, true)
			end)
			local removed = engine.game.DescendantRemoving:Connect(function(object)
				pendingDetach[object] = true
				notify(object, false)
			end)
			local tags = environment.tagChanged:Connect(function(object, tag, present)
				if not pendingDetach[object] and (object == engine.game or object:IsDescendantOf(engine.game)) then
					local signals: { [string]: Environment.Signal } = if present
						then runtime.tagAdded
						else runtime.tagRemoved
					local signal = signals[tag]
					if signal then
						signal:Fire(object)
					end
				end
			end)
			table.insert(runtime.closeHandlers, function()
				added:Disconnect()
				removed:Disconnect()
				tags:Disconnect()
				for _, map in { runtime.tagAdded, runtime.tagRemoved } do
					for _, signal in map do
						signal:DisconnectAll()
					end
					table.clear(map)
				end
				table.clear(pendingDetach)
			end)
		end
		overrides.CollectionService = {
			AddTag = function(_service: Instance, object: Instance, tag: string)
				environment.setTag(object, tag, true)
			end,
			RemoveTag = function(_service: Instance, object: Instance, tag: string)
				environment.setTag(object, tag, false)
			end,
			HasTag = function(_service: Instance, object: Instance, tag: string): boolean
				return table.find(environment.tagsOf(object), tag) ~= nil
			end,
			GetTagged = function(_service: Instance, tag: string): { Instance }
				return tagged(tag)
			end,
			GetInstanceAddedSignal = function(_service: Instance, tag: string): unknown
				local existing = runtime.tagAdded[tag]
				if existing == nil then
					existing = environment.newSignal()
					runtime.tagAdded[tag] = existing
				end
				return existing
			end,
			GetInstanceRemovedSignal = function(_service: Instance, tag: string): unknown
				local existing = runtime.tagRemoved[tag]
				if existing == nil then
					existing = environment.newSignal()
					runtime.tagRemoved[tag] = existing
				end
				return existing
			end,
		}
		overrides.TweenService = {
			Create = function(
				_service: Instance,
				target: Instance,
				_info: unknown,
				goal: { [string]: unknown }
			): unknown
				local tween = engine.newInstance("Tween", true)
				environment.poke(tween, "Instance", target)
				environment.fakeOn(tween, "Play", function(instance: Environment.Instance)
					for key, value in goal do
						target[key] = value
					end
					environment.fire(instance, "Completed", engine.datatypes.Enum.PlaybackState.Completed)
				end)
				environment.fakeOn(tween, "Cancel", function() end)
				environment.fakeOn(tween, "Pause", function() end)
				return tween
			end,
			GetValue = function(_service: Instance, alpha: number): number
				return alpha
			end,
		}
		overrides.Debris = {
			AddItem = function(_service: Instance, object: Instance, lifetime: number?)
				scheduler.delay(lifetime or 10, function()
					object:Destroy()
				end)
			end,
		}
		overrides.ContentProvider = {
			PreloadAsync = function(
				_service: Instance,
				instances: { Instance | string },
				_callback: ((string, Datatypes.EnumMember) -> ())?
			)
				assert(next(instances) == nil, "unsupported_place_asset: ContentProvider.PreloadAsync")
			end,
		}
		overrides.AssetService = {
			CreateMeshPartAsync = function(_service: Instance, content: unknown): unknown
				local part = engine.newInstance("MeshPart", true)
				environment.poke(
					part,
					"MeshId",
					if type(content) == "table" then (content :: { Uri: unknown }).Uri else tostring(content)
				)
				return part
			end,
		}
		overrides.PhysicsService = {
			RegisterCollisionGroup = function() end,
			CollisionGroupSetCollidable = function() end,
			IsCollisionGroupRegistered = function(): boolean
				return true
			end,
		}
		overrides.StarterGui = {
			SetCoreGuiEnabled = function() end,
			GetCoreGuiEnabled = function(): boolean
				return true
			end,
			SetCore = function() end,
			GetCore = function(): unknown
				return nil
			end,
		}
		overrides.DataStoreService = {
			GetDataStore = function(): unknown
				return runtime.dataStore
			end,
			GetOrderedDataStore = function(): unknown
				return runtime.dataStore
			end,
			GetGlobalDataStore = function(): unknown
				return runtime.dataStore
			end,
		}
		local allowed: { [string]: boolean }? = nil
		if options.methodDoubles then
			allowed = {}
			for _, name in options.methodDoubles do
				assert(allowed)[name] = true
			end
		end
		local function install(object: Environment.Object)
			local methods = overrides[object.ClassName]
			if methods and (allowed == nil or allowed[object.ClassName]) then
				for name, method in methods do
					environment.fakeOn(object, name, method :: Environment.Method)
				end
			end
		end
		install(engine.game)
		for _, object in engine.game:GetDescendants() do
			install(object)
		end
		local created = environment.onCreate(install)
		table.insert(runtime.closeHandlers, function()
			created:Disconnect()
		end)
	end

	runtime.localPlayer = nil
	runtime.closeHandlers = {}
	runtime.renderSteps = {}
	runtime.tagAdded = {}
	runtime.tagRemoved = {}
	runtime.guidCount = 0
	runtime.dataStore = {
		GetAsync = function(): unknown
			return nil
		end,
		SetAsync = function(): unknown
			return nil
		end,
		UpdateAsync = function(_self: unknown, _key: string, transform: (unknown) -> unknown): unknown
			return transform(nil)
		end,
		RemoveAsync = function(): unknown
			return nil
		end,
		OnUpdate = function(): { Disconnect: () -> () }
			return { Disconnect = function() end }
		end,
	}

	serviceOverrides()

	globals.game = engine.game
	globals.workspace = engine.service "Workspace"
	globals.Workspace = globals.workspace
	globals.require = requireInstance
	globals.Instance = {
		new = function(className: string, parent: Instance?): unknown
			local object = engine.newInstance(className)
			if parent ~= nil then
				object.Parent = parent
			end
			return object
		end,
		fromExisting = function(template: Instance): unknown
			return template:Clone()
		end,
	}
	for name, value in (engine.datatypes :: unknown) :: { [string]: unknown } do
		globals[name] = value
	end
	globals.typeof = engine.typeName
	globals.print = function(...: unknown)
		local parts: { string } = {}
		for index = 1, select("#", ...) do
			parts[#parts + 1] = tostring((select(index, ...)))
		end
		engine.record("print", table.concat(parts, " "), engine.currentSource())
	end
	globals.warn = function(...: unknown)
		local parts: { string } = {}
		for index = 1, select("#", ...) do
			parts[#parts + 1] = tostring((select(index, ...)))
		end
		engine.record("warn", table.concat(parts, " "), engine.currentSource())
	end
	globals.task = {
		wait = scheduler.wait,
		spawn = scheduler.spawn,
		defer = scheduler.defer,
		delay = scheduler.delay,
		cancel = function() end,
		synchronize = function() end,
		desynchronize = function() end,
	}
	globals.wait = scheduler.wait
	globals.spawn = scheduler.spawn
	globals.delay = function(seconds: number, callback: Scheduler.Task)
		return scheduler.delay(seconds, callback)
	end
	globals.tick = scheduler.clock
	globals.time = scheduler.clock
	globals.elapsedTime = scheduler.clock
	globals.os = {
		clock = scheduler.clock,
		time = function(): number
			return math.floor(1700000000 + scheduler.clock())
		end,
		date = os.date,
		difftime = os.difftime,
	}
	globals.string = string
	globals.table = table
	globals.math = math
	globals.coroutine = coroutine
	globals.bit32 = bit32
	globals.utf8 = utf8
	globals.buffer = buffer
	globals.debug = debug
	globals.select = select
	globals.pcall = pcall
	globals.xpcall = xpcall
	globals.error = error
	globals.assert = assert
	local nativeKinds = { Instance = true, Object = true, RBXScriptSignal = true, RBXScriptConnection = true }
	globals.type = function(value: unknown): string
		local kind = type(value)
		return if kind == "table" and nativeKinds[engine.typeName(value)] then "userdata" else kind
	end
	globals.tostring = tostring
	globals.tonumber = tonumber
	globals.pairs = pairs
	globals.ipairs = ipairs
	globals.next = next
	globals.unpack = table.unpack
	globals.setmetatable = setmetatable
	globals.getmetatable = getmetatable
	globals.rawget = rawget
	globals.rawset = rawset
	globals.rawequal = rawequal
	globals.rawlen = rawlen
	globals.newproxy = newproxy
	globals.shared = {}
	globals._G = {}
	globals._VERSION = _VERSION

	runtime.globals = globals
	runtime.requireInstance = requireInstance

	function runtime.runScript(scriptInstance: Instance, scriptContext: string)
		local path = mounted.sources[scriptInstance]
		if path == nil then
			return
		end
		local name = scriptInstance:GetFullName()
		local thread = coroutine.create(function()
			local ok, failure = xpcall(function()
				local chunk = loadSource(path, "@" .. path, environmentFor(scriptInstance))
				chunk()
			end, function(message: unknown): string
				return tostring(message)
			end)
			if not ok then
				engine.record("error", failure, name)
			end
		end)
		scheduler.tag(thread, { context = scriptContext, source = name })
		scheduler.spawn(thread)
		return thread
	end
	function runtime.step(seconds: number)
		assert(seconds >= 0 and seconds < math.huge, "frame duration must be finite and nonnegative")
		local run = engine.service "RunService"
		scheduler.advance(seconds)
		scheduler.drain(64)
		if options.beforeRender then
			options.beforeRender()
		end
		environment.fire(run, "PreRender", seconds)
		environment.fire(run, "Stepped", scheduler.clock(), seconds)
		environment.fire(run, "PreSimulation", seconds)
		environment.fire(run, "PostSimulation", seconds)
		environment.fire(run, "RenderStepped", seconds)
		environment.fire(run, "Heartbeat", seconds)
		for _, callback in runtime.renderSteps do
			scheduler.spawn(callback, seconds)
		end
		scheduler.drain(64)
	end
	local client = options.client
	if client then
		assert(
			client.viewport.x > 0 and client.viewport.x < math.huge,
			"client viewport width must be positive and finite"
		)
		assert(
			client.viewport.y > 0 and client.viewport.y < math.huge,
			"client viewport height must be positive and finite"
		)
		local players = engine.service "Players"
		local player = engine.newInstance("Player", true)
		environment.poke(player, "Name", client.name)
		environment.poke(player, "UserId", client.userId)
		player.Parent = players
		local playerGui = engine.newInstance("PlayerGui", true)
		playerGui.Parent = player
		runtime.localPlayer = player
		environment.poke(players, "LocalPlayer", player)
		local workspace = engine.service "Workspace"
		local camera = engine.newInstance("Camera", true)
		environment.poke(camera, "ViewportSize", engine.datatypes.Vector2.new(client.viewport.x, client.viewport.y))
		camera.Parent = workspace
		environment.poke(workspace, "CurrentCamera", camera)
	end

	return runtime
end

return {
	createCache = createCache,
	resolveAlias = resolveAlias,
	create = create,
}
