--!strict

local Types = require "./place-types"
local installServices = require "./place-services"
local Scheduler = require "./scheduler"
local Environment = require "./environment"

export type Chunk = Types.Chunk
export type Instance = Types.Instance
export type Diagnostic = Types.Diagnostic
export type Engine = Types.Engine
export type Runtime = Types.Runtime
export type Host<B = unknown, C = Chunk> = Types.Host<B, C>
export type Cache<B = unknown, C = Chunk> = Types.Cache<B, C>
export type Mounted = Types.Mounted
export type Client = Types.Client
export type Options<B = unknown> = Types.Options<B>
type Entry = { status: string, waiters: { thread }, value: unknown, failure: unknown }

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
	local root = aliases[alias]
	if root == nil then
		return nil
	end
	return root .. "/" .. (rest or "")
end

local function create<B>(engine: Engine, mounted: Mounted, options: Options<B>): Runtime
	local aliases = options.aliases
	local cache = options.cache
	local initialPlayer: Instance? = nil
	local initialAdded: { [string]: Environment.Signal } = {}
	local initialRemoved: { [string]: Environment.Signal } = {}
	local runtime = { localPlayer = initialPlayer, tagAdded = initialAdded, tagRemoved = initialRemoved }
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

	local resolveInstanceRequire: (Instance, string) -> unknown

	local function inherit(values: { [string]: unknown })
		setmetatable(values, { __index = globals })
	end

	local function environmentFor(scriptInstance: Instance): { [string]: unknown }
		local environment: { [string]: unknown } = {}
		inherit(environment)
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
		local environment: { [string]: unknown } = {}
		inherit(environment)
		environment.script = nil
		environment.getfenv = function(): unknown
			return environment
		end
		local entry: Entry = { status = "loading", waiters = {}, value = nil, failure = nil }
		fileModules[path] = entry
		local ok, value = pcall(function(): unknown
			return cache.load(path, environment)()
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
			local child = if segment == ".."
				then walk.Parent
				elseif segment == "." then walk
				else walk:FindFirstChild(segment)
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
				return error(("place runtime cannot resolve require(%q)"):format(target), 2)
			end
			return requirePath(resolved)
		end
		if not engine.isInstance(target) then
			error("Attempted to call require with invalid argument(s).", 2)
		end
		local object = Environment.assertInstance(target)
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
			return cache.load(path, environmentFor(object))()
		end)
		local failure = "Requested module experienced an error while loading"
		settle(entry, if ok then "done" else "failed", if ok then value else failure)
		if not ok then
			engine.record("error", tostring(value), path)
			error(failure, 0)
		end
		return value
	end

	runtime.localPlayer = nil
	runtime.closeHandlers = {}
	runtime.renderSteps = {} :: { [string]: (number) -> () }
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

	runtime.device, runtime.screenArea = installServices(engine, runtime, options, context)

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
	local function logger(kind: string): (...unknown) -> ()
		return function(...: unknown)
			local parts: { string } = {}
			for index = 1, select("#", ...) do
				parts[#parts + 1] = tostring((select(index, ...)))
			end
			engine.record(kind, table.concat(parts, " "), engine.currentSource())
		end
	end
	globals.print = logger "print"
	globals.warn = logger "warn"
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
	local runtimeDebug: { [string]: unknown } = {}
	for name, value in debug do
		assert(type(name) == "string")
		runtimeDebug[name] = value
	end
	runtimeDebug.profilebegin = function(label: string)
		assert(type(label) == "string", "profile label must be a string")
	end
	runtimeDebug.profileend = function() end
	runtimeDebug.setmemorycategory = function(category: string)
		assert(type(category) == "string", "memory category must be a string")
	end
	globals.debug = table.freeze(runtimeDebug)
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

	function runtime.runScript(scriptInstance: Instance, scriptContext: string): thread?
		local path = mounted.sources[scriptInstance]
		if path == nil then
			return
		end
		local name = scriptInstance:GetFullName()
		local thread = coroutine.create(function()
			local failure = ""
			local ok = xpcall(function()
				local chunk = cache.load(path, environmentFor(scriptInstance))
				chunk()
			end, function(message: unknown)
				failure = tostring(message)
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
