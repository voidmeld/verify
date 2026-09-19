--!strict

export type Host = {
	readFile: (path: string) -> string,
	compile: (source: string) -> any,
	load: (bytecode: any, chunkName: string, environment: { [string]: any }) -> any,
	encodeJson: (value: any) -> string,
	decodeJson: (text: string) -> any,
}

export type Cache = {
	read: (path: string) -> string,
	bytecode: (path: string) -> any,
	load: (path: string, environment: { [string]: any }) -> any,
}

export type Mounted = {
	root: any,
	scripts: { any },
	sources: { [any]: string },
}

export type Options = {
	aliases: { [string]: string },
	cache: Cache,
	host: Host,
}

local function createCache(host: Host): Cache
	local texts: { [string]: string } = {}
	local bytecodes: { [string]: any } = {}

	local cache = {}

	function cache.read(path: string): string
		local existing = texts[path]
		if existing == nil then
			existing = host.readFile(path)
			texts[path] = existing
		end
		return existing
	end

	function cache.bytecode(path: string): any
		local existing = bytecodes[path]
		if existing == nil then
			existing = host.compile(cache.read(path))
			bytecodes[path] = existing
		end
		return existing
	end

	function cache.load(path: string, environment: { [string]: any }): any
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

local function create(engine: any, mounted: Mounted, options: Options): any
	local aliases = options.aliases
	local cache = options.cache
	local host = options.host
	local runtime: any = {}
	local scheduler = engine.scheduler
	local modules: { [string]: { [any]: any } } = { server = {}, client = {} }
	local fileModules: { [string]: any } = {}
	local globals: { [string]: any } = {}

	local function context(): string
		local tag = scheduler.context()
		return if type(tag) == "table" then tag.context else "server"
	end

	local function source(): string
		local tag = scheduler.context()
		return if type(tag) == "table" then tag.source else "engine"
	end

	engine.setSourceResolver(source)
	scheduler.onFailure(function(message: string)
		engine.record("error", message, source())
	end)

	local function loadSource(path: string, _chunkName: string, environment: { [string]: any }): any
		return cache.load(path, environment)
	end

	local resolveInstanceRequire: (any, string) -> any

	local function environmentFor(scriptInstance: any): { [string]: any }
		local environment: any = setmetatable({}, { __index = globals })
		environment.script = scriptInstance
		environment.getfenv = function(): any
			return environment
		end
		environment.setfenv = function(_level: any, replacement: any): any
			return replacement
		end
		environment.require = function(target: any): any
			if type(target) == "string" then
				return resolveInstanceRequire(scriptInstance, target)
			end
			return (globals.require :: any)(target)
		end
		return environment
	end

	local requireInstance: (any) -> any
	local requirePath: (string) -> any

	local function awaitEntry(entry: any): any
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

	local function settle(entry: any, status: string, value: any)
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

	function requirePath(path: string): any
		local cached = fileModules[path]
		if cached ~= nil then
			return awaitEntry(cached)
		end
		local environment: any = setmetatable({}, { __index = globals })
		environment.script = nil
		environment.getfenv = function(): any
			return environment
		end
		local entry = { status = "loading", waiters = {} }
		fileModules[path] = entry
		local chunk = loadSource(path, "@" .. path, environment)
		local ok, value = pcall(chunk)
		settle(entry, if ok then "done" else "failed", value)
		if not ok then
			error(value, 0)
		end
		return value
	end

	function resolveInstanceRequire(scriptInstance: any, target: string): any
		local selfPath = string.match(target, "^@self/(.+)$")
		local base: any = nil
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
				base = container.Parent
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

	function requireInstance(target: any): any
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
		if target.ClassName ~= "ModuleScript" then
			error(("Attempted to require a %s"):format(target.ClassName), 2)
		end
		local moduleCache = modules[context()]
		local cached = moduleCache[target]
		if cached ~= nil then
			return awaitEntry(cached)
		end
		local path = mounted.sources[target]
		if path == nil then
			error(("place runtime has no source for %s"):format(target:GetFullName()), 2)
		end
		local entry = { status = "loading", waiters = {} }
		moduleCache[target] = entry
		local chunk = loadSource(path, "@" .. path, environmentFor(target))
		local ok, value = pcall(chunk)
		settle(entry, if ok then "done" else "failed", value)
		if not ok then
			error(value, 0)
		end
		return value
	end

	local contextActionGui: any = nil
	local contextActionButtons: { [string]: any } = {}

	local function contextActionButton(name: string): any?
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
		button.Parent = contextActionGui:FindFirstChild "ContextButtonFrame"
		local title = engine.newInstance "TextLabel"
		title.Name = "ActionTitle"
		title.Parent = button
		contextActionButtons[name] = button
		return button
	end

	local function serviceOverrides()
		local overrides = engine.serviceMethods
		overrides.ContextActionService = {
			BindAction = function(_service: any, name: string, _handler: any, createTouchButton: any)
				if createTouchButton == true then
					contextActionButton(name)
				end
			end,
			BindActionAtPriority = function(_service: any, name: string, _handler: any, createTouchButton: any)
				if createTouchButton == true then
					contextActionButton(name)
				end
			end,
			UnbindAction = function(_service: any, name: string)
				local button = contextActionButtons[name]
				if button ~= nil then
					contextActionButtons[name] = nil
					button:Destroy()
				end
			end,
			GetButton = function(_service: any, name: string): any
				return contextActionButtons[name]
			end,
			SetTitle = function(_service: any, name: string, title: string)
				local button = contextActionButtons[name]
				local label = if button ~= nil then button:FindFirstChild "ActionTitle" else nil
				if label ~= nil then
					label.Text = title
				end
			end,
			SetPosition = function(_service: any, name: string, position: any)
				local button = contextActionButtons[name]
				if button ~= nil then
					button.Position = position
				end
			end,
			SetImage = function() end,
		}
		overrides.DataModel = {
			GetService = function(_self: any, name: string): any
				return engine.service(name)
			end,
			FindService = function(_self: any, name: string): any
				return engine.service(name)
			end,
			BindToClose = function(_self: any, callback: any)
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
			BindToRenderStep = function(_service: any, name: string, _priority: number, callback: any)
				runtime.renderSteps[name] = callback
			end,
			UnbindFromRenderStep = function(_service: any, name: string)
				runtime.renderSteps[name] = nil
			end,
		}
		overrides.Players = {
			GetPlayers = function(service: any): { any }
				local out: { any } = {}
				for _, child in service:GetChildren() do
					if child.ClassName == "Player" then
						out[#out + 1] = child
					end
				end
				return out
			end,
			GetPlayerFromCharacter = function(service: any, character: any): any
				for _, player in service:GetPlayers() do
					if player.Character == character then
						return player
					end
				end
				return nil
			end,
			GetPlayerByUserId = function(service: any, userId: number): any
				for _, player in service:GetPlayers() do
					if player.UserId == userId then
						return player
					end
				end
				return nil
			end,
		}
		local function signalOn(object: any, name: string): any
			local state = engine.stateOf(object)
			local existing = state.signals[name]
			if existing == nil then
				existing = engine.signal()
				state.signals[name] = existing
			end
			return existing
		end
		local function callbackOf(object: any, name: string): any
			return engine.stateOf(object).values[name]
		end
		overrides.RemoteEvent = {
			FireServer = function(object: any, ...: any)
				engine.fire(signalOn(object, "OnServerEvent"), runtime.localPlayer, ...)
			end,
			FireClient = function(object: any, _player: any, ...: any)
				engine.fire(signalOn(object, "OnClientEvent"), ...)
			end,
			FireAllClients = function(object: any, ...: any)
				engine.fire(signalOn(object, "OnClientEvent"), ...)
			end,
		}
		overrides.UnreliableRemoteEvent = overrides.RemoteEvent
		overrides.RemoteFunction = {
			InvokeServer = function(object: any, ...: any): ...any
				local callback = callbackOf(object, "OnServerInvoke")
				if callback == nil then
					error(
						("Attempt to call a RemoteFunction %s with no OnServerInvoke"):format(object:GetFullName()),
						2
					)
				end
				return callback(runtime.localPlayer, ...)
			end,
			InvokeClient = function(object: any, _player: any, ...: any): ...any
				local callback = callbackOf(object, "OnClientInvoke")
				if callback == nil then
					error(
						("Attempt to call a RemoteFunction %s with no OnClientInvoke"):format(object:GetFullName()),
						2
					)
				end
				return callback(...)
			end,
		}
		overrides.BindableEvent = {
			Fire = function(object: any, ...: any)
				engine.fire(signalOn(object, "Event"), ...)
			end,
		}
		overrides.BindableFunction = {
			Invoke = function(object: any, ...: any): ...any
				local callback = callbackOf(object, "OnInvoke")
				if callback == nil then
					error(("Attempt to call a BindableFunction %s with no OnInvoke"):format(object:GetFullName()), 2)
				end
				return callback(...)
			end,
		}
		overrides.HttpService = {
			GenerateGUID = function(_service: any, wrapInCurlyBraces: boolean?): string
				runtime.guidCount += 1
				local body = ("%08x-0000-4000-8000-%012x"):format(runtime.guidCount, runtime.guidCount)
				if wrapInCurlyBraces == false then
					return body
				end
				return "{" .. body .. "}"
			end,
			JSONEncode = function(_service: any, value: any): string
				return host.encodeJson(value)
			end,
			JSONDecode = function(_service: any, text: string): any
				return host.decodeJson(text)
			end,
		}
		overrides.CollectionService = {
			AddTag = function(_service: any, object: any, tag: string)
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
			RemoveTag = function(_service: any, object: any, tag: string)
				object:RemoveTag(tag)
			end,
			HasTag = function(_service: any, object: any, tag: string): boolean
				return object:HasTag(tag)
			end,
			GetTagged = function(_service: any, tag: string): { any }
				local out: { any } = {}
				for _, object in runtime.tagged[tag] or {} do
					if object:HasTag(tag) then
						out[#out + 1] = object
					end
				end
				return out
			end,
			GetInstanceAddedSignal = function(_service: any, tag: string): any
				local existing = runtime.tagAdded[tag]
				if existing == nil then
					existing = engine.signal()
					runtime.tagAdded[tag] = existing
				end
				return existing
			end,
			GetInstanceRemovedSignal = function(_service: any, tag: string): any
				local existing = runtime.tagRemoved[tag]
				if existing == nil then
					existing = engine.signal()
					runtime.tagRemoved[tag] = existing
				end
				return existing
			end,
		}
		overrides.TweenService = {
			Create = function(_service: any, target: any, _info: any, goal: { [string]: any }): any
				local tween = engine.newInstance("Tween", true)
				engine.stateOf(tween).values.Instance = target
				local completed = engine.signal()
				engine.stateOf(tween).signals.Completed = completed
				engine.serviceMethods.Tween = engine.serviceMethods.Tween or {}
				engine.serviceMethods.Tween.Play = function(instance: any)
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
				engine.serviceMethods.Tween.Destroy = function(instance: any)
					engine.methods.Destroy(instance)
				end
				return tween
			end,
			GetValue = function(_service: any, alpha: number): number
				return alpha
			end,
		}
		overrides.Debris = {
			AddItem = function(_service: any, object: any, lifetime: number?)
				scheduler.delay(lifetime or 10, function()
					object:Destroy()
				end)
			end,
		}
		overrides.ContentProvider = {
			PreloadAsync = function(_service: any, instances: { any }, callback: any?)
				for _, object in instances do
					if callback ~= nil then
						callback(object, engine.datatypes.Enum.AssetFetchStatus.Success)
					end
				end
			end,
		}
		overrides.AssetService = {
			CreateMeshPartAsync = function(_service: any, content: any): any
				local part = engine.newInstance("MeshPart", true)
				engine.stateOf(part).values.MeshId = if type(content) == "table" then content.Uri else tostring(content)
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
			GetCore = function(): any
				return nil
			end,
		}
		overrides.DataStoreService = {
			GetDataStore = function(): any
				return runtime.dataStore
			end,
			GetOrderedDataStore = function(): any
				return runtime.dataStore
			end,
			GetGlobalDataStore = function(): any
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
		GetAsync = function(): any
			return nil
		end,
		SetAsync = function(): any
			return nil
		end,
		UpdateAsync = function(_self: any, _key: string, transform: any): any
			return transform(nil)
		end,
		RemoveAsync = function(): any
			return nil
		end,
		OnUpdate = function(): any
			return { Disconnect = function() end }
		end,
	}

	serviceOverrides()

	globals.game = engine.game
	globals.workspace = engine.service "Workspace"
	globals.Workspace = globals.workspace
	globals.require = requireInstance
	globals.Instance = {
		new = function(className: string, parent: any?): any
			local object = engine.newInstance(className)
			if parent ~= nil then
				object.Parent = parent
			end
			return object
		end,
		fromExisting = function(template: any): any
			return template:Clone()
		end,
	}
	for name, value in engine.datatypes do
		globals[name] = value
	end
	globals.typeof = engine.typeName
	globals.print = function(...: any)
		local parts: { string } = {}
		for index = 1, select("#", ...) do
			parts[#parts + 1] = tostring((select(index, ...)))
		end
		engine.record("print", table.concat(parts, " "), engine.currentSource())
	end
	globals.warn = function(...: any)
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
	globals.delay = function(seconds: number, callback: any)
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

	function runtime.runScript(scriptInstance: any, scriptContext: string)
		local path = mounted.sources[scriptInstance]
		if path == nil then
			return
		end
		local name = scriptInstance:GetFullName()
		local thread = coroutine.create(function()
			local ok, failure = xpcall(function()
				local chunk = loadSource(path, "@" .. path, environmentFor(scriptInstance))
				chunk()
			end, function(message: any): string
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
