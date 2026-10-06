--!strict

local Scheduler = require "./scheduler"
local Datatypes = require "./datatypes"
local Environment = require "./environment"

export type Chunk = () -> unknown
export type Instance = {
	[string]: unknown,
	Name: string,
	ClassName: string,
	Parent: Instance?,
	Character: Instance?,
	UserId: number,
	GetChildren: (Instance) -> { Instance },
	FindFirstChild: (Instance, string) -> Instance?,
	GetFullName: (Instance) -> string,
	GetPlayers: (Instance) -> { Instance },
	Destroy: (Instance) -> (),
	Clone: (Instance) -> Instance,
	AddTag: (Instance, string) -> (),
	RemoveTag: (Instance, string) -> (),
	HasTag: (Instance, string) -> boolean,
	SetAttribute: (Instance, string, unknown) -> (),
	GetAttributes: (Instance) -> { [string]: unknown },
}
export type State = {
	name: string,
	className: string,
	values: { [string]: unknown },
	signals: { [string]: Environment.Signal },
	propertySignals: { [string]: Environment.Signal },
}
export type Diagnostic = { kind: string, text: string, source: string }
export type Engine = {
	game: Instance,
	scheduler: Scheduler.Scheduler,
	newInstance: (string, boolean?) -> Instance,
	stateOf: (Instance) -> State,
	service: (string) -> Instance,
	serviceMethods: { [string]: { [string]: unknown } },
	setSourceResolver: (() -> string) -> (),
	currentSource: () -> string,
	record: (string, string, string) -> (),
	isInstance: (unknown) -> boolean,
	signal: () -> Environment.Signal,
	signalOf: (Instance, string) -> Environment.Signal,
	fire: (Environment.Signal, ...unknown) -> (),
	datatypes: typeof(Datatypes),
	methods: { Destroy: (Instance) -> () },
	typeName: (unknown) -> string,
	diagnostics: { Diagnostic },
	surface: {
		services: { [string]: boolean },
		memberKind: (string, string) -> string?,
		memberType: (string, string) -> string?,
	},
	outstandingWaits: () -> { { target: string, name: string, source: string } },
	frames: () -> number,
	blocked: () -> number,
}
type Entry = { status: string, waiters: { thread }, value: unknown, failure: unknown }
export type Runtime = {
	localPlayer: Instance?,
	closeHandlers: { () -> () },
	renderSteps: { [string]: (number) -> () },
	tagged: { [string]: { Instance } },
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

export type Options<B = unknown> = {
	aliases: { [string]: string },
	cache: Cache<B>,
	host: Host<B>,
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
	local scheduler = engine.scheduler
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
		if entry.status == "done" then
			return entry.value
		end
		scheduler.block(function(thread: thread)
			table.insert(entry.waiters, thread)
		end)
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
		local chunk = loadSource(path, "@" .. path, environment)
		local ok, value = pcall(chunk)
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
			local origin = mounted.sources[scriptInstance]
			local container = if origin ~= nil and string.match(origin, "/init%.[%w.]+luau$") ~= nil
				then scriptInstance
				else scriptInstance.Parent
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
		local chunk = loadSource(path, "@" .. path, environmentFor(object))
		local ok, value = pcall(chunk)
		settle(entry, if ok then "done" else "failed", value)
		if not ok then
			error(value, 0)
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
		local overrides = engine.serviceMethods
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
				for _, player in service:GetPlayers() do
					if player.Character == character then
						return player
					end
				end
				return nil
			end,
			GetPlayerByUserId = function(service: Instance, userId: number): unknown
				for _, player in service:GetPlayers() do
					if player.UserId == userId then
						return player
					end
				end
				return nil
			end,
		}
		local function signalOn(object: Instance, name: string): Environment.Signal
			local state = engine.stateOf(object)
			local existing = state.signals[name]
			if existing == nil then
				existing = engine.signal()
				state.signals[name] = existing
			end
			return existing
		end
		local function callbackOf(object: Instance, name: string): unknown
			return engine.stateOf(object).values[name]
		end
		overrides.RemoteEvent = {
			FireServer = function(object: Instance, ...: unknown)
				engine.fire(signalOn(object, "OnServerEvent"), runtime.localPlayer, ...)
			end,
			FireClient = function(object: Instance, _player: unknown, ...: unknown)
				engine.fire(signalOn(object, "OnClientEvent"), ...)
			end,
			FireAllClients = function(object: Instance, ...: unknown)
				engine.fire(signalOn(object, "OnClientEvent"), ...)
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
				engine.fire(signalOn(object, "Event"), ...)
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
		overrides.CollectionService = {
			AddTag = function(_service: Instance, object: Instance, tag: string)
				object:AddTag(tag)
				local list = runtime.tagged[tag]
				if list == nil then
					list = {}
					runtime.tagged[tag] = list
				end
				list[#list + 1] = object
				local added = runtime.tagAdded[tag]
				if added ~= nil then
					engine.fire(added, object)
				end
			end,
			RemoveTag = function(_service: Instance, object: Instance, tag: string)
				object:RemoveTag(tag)
			end,
			HasTag = function(_service: Instance, object: Instance, tag: string): boolean
				return object:HasTag(tag)
			end,
			GetTagged = function(_service: Instance, tag: string): { Instance }
				local out: { Instance } = {}
				local tagged: { Instance } = runtime.tagged[tag] or {}
				for _, object in tagged do
					if object:HasTag(tag) then
						out[#out + 1] = object
					end
				end
				return out
			end,
			GetInstanceAddedSignal = function(_service: Instance, tag: string): unknown
				local existing = runtime.tagAdded[tag]
				if existing == nil then
					existing = engine.signal()
					runtime.tagAdded[tag] = existing
				end
				return existing
			end,
			GetInstanceRemovedSignal = function(_service: Instance, tag: string): unknown
				local existing = runtime.tagRemoved[tag]
				if existing == nil then
					existing = engine.signal()
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
				engine.stateOf(tween).values.Instance = target
				local completed = engine.signal()
				engine.stateOf(tween).signals.Completed = completed
				engine.serviceMethods.Tween = engine.serviceMethods.Tween or {}
				engine.serviceMethods.Tween.Play = function(instance: Instance)
					for key, value in goal do
						target[key] = value
					end
					engine.fire(
						engine.stateOf(instance).signals.Completed,
						engine.datatypes.Enum.PlaybackState.Completed
					)
				end
				engine.serviceMethods.Tween.Cancel = function() end
				engine.serviceMethods.Tween.Pause = function() end
				engine.serviceMethods.Tween.Destroy = function(instance: Instance)
					engine.methods.Destroy(instance)
				end
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
				instances: { Instance },
				callback: ((Instance, Datatypes.EnumMember) -> ())?
			)
				for _, object in instances do
					if callback ~= nil then
						callback(object, engine.datatypes.Enum.AssetFetchStatus.Success)
					end
				end
			end,
		}
		overrides.AssetService = {
			CreateMeshPartAsync = function(_service: Instance, content: unknown): unknown
				local part = engine.newInstance("MeshPart", true)
				engine.stateOf(part).values.MeshId = if type(content) == "table"
					then (content :: { Uri: unknown }).Uri
					else tostring(content)
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
	end

	runtime.localPlayer = nil
	runtime.closeHandlers = {}
	runtime.renderSteps = {}
	runtime.tagged = {}
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
	globals.type = type
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

	return runtime
end

return {
	createCache = createCache,
	resolveAlias = resolveAlias,
	create = create,
}
