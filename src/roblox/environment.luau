--!strict

local createModel = require "./environment-model"
local createMethods = require "./environment-methods"
local Names = require "./datatypes/names"
local FrameTypes = require "./datatypes/cframe"
local VectorTypes = require "./datatypes/vector"
local EnumTypes = require "./datatypes/enum"
local Classes = require "./environment-classes"
local Scheduler = require "./scheduler"
local createSignals = require "./environment-signals"
local Types = require "./environment-types"
local SpatialFakes = require "./spatial-fakes"
local AudioFakes = require "./audio-fakes"
local InputActionFakes = require "./input-action-fakes"
local TweenFakes = require "./tween-fakes"
local SpatialQueryFakes = require "./spatial-query-fakes"

export type Connection = Types.Connection
export type Signal<A... = ...unknown> = Types.Signal<A...>
export type Method<A... = ...unknown, R... = ...unknown> = Types.Method<A..., R...>
export type Instance = Types.Instance
export type Object = Types.Object
export type Snapshot = Types.Snapshot
export type ClassSpec<P = { [string]: unknown }, M = { [string]: unknown }> = Types.ClassSpec<P, M>
export type DefineOptions = Types.DefineOptions
export type Limits = Types.Limits
export type HandlerErrors = Types.HandlerErrors
export type Options<P = { [string]: unknown }, M = { [string]: unknown }, F = { [string]: unknown }> = Types.Options<
	P,
	M,
	F
>
export type Computed = Types.Computed
export type Operation = Types.Operation
export type Event = Types.Event
export type CloneHook = Types.CloneHook
export type CreateHook = Types.CreateHook
export type SignalHandle = Types.SignalHandle
export type Environment = Types.Environment
type Resolved = Types.Resolved
type State = Types.State
local metatableOf = (getmetatable :: unknown) :: (unknown) -> unknown

local instances: { [unknown]: Instance } = {}
Names.weak(instances)

local function create<P, M, F>(options: Options<P, M, F>?): Environment
	local settings: Options = ((options or {}) :: unknown) :: Options
	local limits: Limits = settings.limits or {}
	local fakes: { [string]: unknown } = {}
	local initialFakes: { [string]: unknown } = settings.fakes or {}
	for member, handler in initialFakes do
		fakes[member] = handler
	end
	local failures: { [string]: number } = {}
	local errors: { string } = {}
	local handlerErrors: HandlerErrors = settings.handlerErrors or "collect"
	if handlerErrors ~= "collect" and handlerErrors ~= "raise" then
		error('handlerErrors must be "collect" or "raise"', 2)
	end
	if
		settings.undeclaredReads ~= nil
		and settings.undeclaredReads ~= "raise"
		and settings.undeclaredReads ~= "nil"
	then
		error('undeclaredReads must be "raise" or "nil"', 2)
	end
	local raising = handlerErrors == "raise"
	local scheduler = Scheduler.create()
	local alive = 0

	local environment = {}
	local inputActions: InputActionFakes.Controller? = nil
	local root: Instance
	local setTag: (Instance, string, boolean) -> ()
	local states: { [unknown]: State } = {}
	Names.weak(states)
	type MethodOverride = { handler: unknown, previous: unknown, active: boolean }
	local function doubleHandler(value: unknown): unknown
		return if type(value) == "table" then (value :: MethodOverride).handler else value
	end
	local newObject: (className: string, props: { [unknown]: unknown }?, isRoot: boolean, engineOwned: boolean?) -> Instance

	local model = createModel(settings)
	local specs = model.specs
	local resolved = model.resolved
	local defineClass = model.defineClass
	local resolve = model.resolve
	local isA = model.isA
	local computedEntry = model.computedEntry
	local computedFor = model.computedFor
	local writableComputed = model.writableComputed
	local defaultOf = model.defaultOf
	local defaultsOf = model.defaultsOf

	local observers: { { callback: (event: Event) -> (), connected: boolean } } = {}
	local cloneHooks: { { callback: CloneHook, connected: boolean } } = {}
	local createHooks: { { callback: CreateHook, connected: boolean } } = {}

	local function injecting(operation: Operation): boolean
		return #observers > 0 or (failures[operation] or 0) > 0
	end

	local function inject(operation: Operation, subject: string, object: Instance, member: string?, value: unknown)
		local remaining = failures[operation]
		local failing = remaining ~= nil and remaining > 0
		local current: typeof(observers) = if #observers > 1 then table.clone(observers) else observers
		for _, observer in current do
			if observer.connected then
				observer.callback {
					operation = operation,
					subject = subject,
					member = member,
					injected = failing,
					object = object,
					value = value,
				}
			end
		end
		if failing then
			failures[operation] = (remaining or 0) - 1
			error(("environment: injected failure in %s"):format(operation), 0)
		end
	end

	local signals = createSignals(scheduler, errors, raising)
	local newSignal = signals.newSignal
	local operation = signals.operation
	local meters = signals.meters

	local function stateOf(object: unknown): State
		return states[object]
	end

	local function isObject(value: unknown): boolean
		return type(value) == "table" and rawget(value :: { [string]: unknown }, "__state") ~= nil
	end

	local function signalFor(state: State, key: string): Signal
		local existing = state.signals[key]
		if existing == nil then
			existing = newSignal(state.signalFires[key])
			state.signals[key] = existing
			state.signalFires[key] = nil
		end
		return existing
	end

	local function fireSignal(state: State, key: string, ...: unknown)
		local signal = state.signals[key]
		if signal ~= nil then
			signal:Fire(...)
		else
			state.signalFires[key] = (state.signalFires[key] or 0) + 1
		end
	end

	local function describe(state: State): string
		return ("%s %q"):format(state.className, tostring(state.values.Name))
	end

	local function memberError(state: State, key: string): never
		error(("%s is not a valid member of %s"):format(key, describe(state)), 3)
	end

	local function changed(object: Instance, state: State, property: string)
		if inputActions then
			inputActions.changed(object, property)
		end
		fireSignal(state, "prop:" .. property)
		fireSignal(state, "Changed", property)
	end

	local function assign(object: Instance, state: State, key: string, value: unknown)
		local coupled: string? = nil
		if isA(state.className, "BasePart") then
			if key == "CFrame" and Names.of(value) == "CFrame" and state.class.properties.Position ~= nil then
				local position = FrameTypes.expect(value, 1).Position
				if VectorTypes.find3(state.values.Position) ~= position then
					state.values.Position = position
					coupled = "Position"
				end
			elseif key == "Position" and Names.of(value) == "Vector3" and Names.of(state.values.CFrame) == "CFrame" then
				local frame = FrameTypes.expect(state.values.CFrame, 1)
				state.values.CFrame = frame + (VectorTypes.expect3(value, 1) - frame.Position)
				coupled = "CFrame"
			end
		end
		if key == "IgnoreGuiInset" and type(value) == "boolean" and isA(state.className, "ScreenGui") then
			local insets = EnumTypes.itemValue(state.values.ScreenInsets)
			local family = if insets then insets.EnumType else nil
			local replacement = if family
				then family:FromName(if value then "DeviceSafeInsets" else "CoreUISafeInsets")
				else nil
			if replacement and replacement ~= insets then
				state.values.ScreenInsets = replacement
				coupled = "ScreenInsets"
			end
		end
		state.values[key] = value
		changed(object, state, key)
		if coupled then
			changed(object, state, coupled)
		end
	end

	local function subtree(object: Instance): { Instance }
		local objects: { Instance } = {}
		local function visit(current: Instance)
			table.insert(objects, current)
			for _, child in stateOf(current).children do
				visit(child)
			end
		end
		visit(object)
		return objects
	end

	local function ancestors(parent: Instance?): { Instance }
		local objects: { Instance } = {}
		local walk = parent
		while walk ~= nil do
			table.insert(objects, walk)
			walk = stateOf(walk).parent
		end
		return objects
	end

	local function without(list: { Instance }, removed: { Instance }): { Instance }
		local excluded: { [Instance]: true } = {}
		for _, item in removed do
			excluded[item] = true
		end
		local kept: { Instance } = {}
		for _, item in list do
			if not excluded[item] then
				table.insert(kept, item)
			end
		end
		return kept
	end

	local function move(object: Instance, state: State, parent: Instance?)
		local previous = state.parent
		if previous == parent then
			return
		end
		local objects = subtree(object)
		local before = ancestors(previous)
		local after = ancestors(parent)
		for _, descendant in objects do
			stateOf(descendant).removing = true
		end
		local leaving = without(before, after)
		for _, descendant in objects do
			for _, ancestor in leaving do
				fireSignal(stateOf(ancestor), "DescendantRemoving", descendant)
			end
		end
		if previous ~= nil then
			local siblings = stateOf(previous).children
			local index = table.find(siblings, object)
			if index ~= nil then
				table.remove(siblings, index)
			end
		end
		state.parent = parent
		if parent ~= nil then
			table.insert(stateOf(parent).children, object)
		end
		for _, descendant in objects do
			stateOf(descendant).removing = false
		end
		if previous ~= nil then
			fireSignal(stateOf(previous), "ChildRemoved", object)
		end
		if parent ~= nil then
			fireSignal(stateOf(parent), "ChildAdded", object)
		end
		local joining = without(after, before)
		for _, descendant in objects do
			for _, ancestor in joining do
				fireSignal(stateOf(ancestor), "DescendantAdded", descendant)
			end
		end
		changed(object, state, "Parent")
		for _, descendant in objects do
			fireSignal(stateOf(descendant), "AncestryChanged", object, parent)
		end
	end

	local function setParent(object: Instance, state: State, parent: Instance?)
		if injecting "setParent" then
			inject("setParent", describe(state), object, nil, parent)
		end
		if state.destroyed or state.destroying or state.removing then
			error(("The Parent property of %s is locked"):format(describe(state)), 4)
		end
		if parent ~= nil and (not isObject(parent) or not stateOf(parent).class.instance) then
			error(("Parent of %s must be an Instance of this environment"):format(describe(state)), 4)
		end
		local walk = parent
		while walk ~= nil do
			if walk == object then
				error(("Attempt to set %s as its own ancestor"):format(describe(state)), 4)
			end
			walk = stateOf(walk).parent
		end
		if
			settings.validateProperty ~= nil
			and settings.validateProperty(state.className, "Parent", parent, "set") == false
		then
			return
		end
		move(object, state, parent)
	end

	local function destroy(object: Instance, state: State)
		if state.destroyed or state.destroying then
			return
		end
		if state.removing then
			error(("The Parent property of %s is locked"):format(describe(state)), 4)
		end
		if injecting "destroy" then
			inject("destroy", describe(state), object, nil, nil)
		end
		state.destroying = true
		fireSignal(state, "Destroying")
		move(object, state, nil)
		for _, child in table.clone(state.children) do
			destroy(child, stateOf(child))
		end
		state.destroyed = true
		alive -= 1
		for _, signal in state.signals do
			signal:DisconnectAll()
		end
	end

	local function memberMethod(object: Instance, state: State, key: string): ((Instance, ...unknown) -> ...unknown)?
		local method = state.class.methods[key]
		if method == nil then
			return nil
		end
		local implementation: unknown = if method == true then fakes[state.className .. "." .. key] else method
		if implementation == nil then
			local walk: string? = specs[state.className].super
			while implementation == nil and walk ~= nil do
				implementation = fakes[walk .. "." .. key]
				local spec = specs[walk]
				walk = if spec ~= nil then spec.super else nil
			end
		end
		if implementation == nil then
			error(
				("unsupported_method: %s.%s is declared but has no simulation or configured fake"):format(
					state.className,
					key
				),
				3
			)
		end
		return function(_self: Instance, ...: unknown): ...unknown
			return (implementation :: Method)(object, ...)
		end
	end

	local universal = createMethods {
		settings = settings,
		limits = limits,
		scheduler = scheduler,
		instances = instances,
		cloneHooks = cloneHooks,
		stateOf = stateOf,
		isObject = isObject,
		signalFor = signalFor,
		fireSignal = fireSignal,
		describe = describe,
		injecting = injecting,
		inject = inject,
		memberError = memberError,
		changed = changed,
		destroy = destroy,
		move = move,
		isA = isA,
		computedFor = computedFor,
		writableComputed = writableComputed,
		defaultOf = defaultOf,
		newObject = function(...)
			return newObject(...)
		end,
		setTag = function(...)
			return setTag(...)
		end,
		root = function()
			return root
		end,
	}

	local function readMember(object: Instance, key: string): unknown
		local state = stateOf(object)
		if not state.class.instance and (key == "Name" or key == "Archivable") then
			memberError(state, key)
		end
		local access = state.class.access[key]
		if access == "callback" then
			error(
				("%s is a callback member of %s; you can only set the callback value, get is not available"):format(
					key,
					state.className
				),
				2
			)
		elseif access == "write" or access == "none" then
			error(("%s cannot be read on %s"):format(key, describe(state)), 2)
		end
		if key == "ClassName" then
			return state.className
		elseif key == "Parent" and state.class.instance then
			return state.parent
		end
		local class = state.class
		if
			class.properties[key] ~= nil
			and state.doubles[key] == nil
			and not class.events[key]
			and class.methods[key] == nil
			and computedFor(state.className, key) == nil
		then
			return state.values[key]
		end
		local double = doubleHandler(state.doubles[key])
		if double ~= nil then
			return operation(function(_self: Instance, ...: unknown): ...unknown
				return (double :: Method)(object, ...)
			end)
		end
		if state.class.events[key] then
			return signalFor(state, key)
		end
		local property = class.methods[key] == nil
			and (class.properties[key] ~= nil or computedFor(state.className, key) ~= nil)
		if not property then
			local bound = state.bound
			local cached = if bound ~= nil then bound[key] else nil
			if cached ~= nil then
				return cached
			end
			local resolved: unknown = nil
			if type(state.class.methods[key]) == "function" then
				local method = memberMethod(object, state, key)
				assert(method ~= nil)
				resolved = operation(method)
			else
				local builtin = universal(object, state, key)
				if type(builtin) == "function" then
					resolved = operation(builtin :: Method)
				else
					local method = memberMethod(object, state, key)
					if method ~= nil then
						resolved = operation(method)
					end
				end
			end
			if resolved ~= nil then
				local store = bound or {}
				state.bound = store
				store[key] = resolved
				return resolved
			end
		end
		local getter = computedFor(state.className, key)
		if getter ~= nil then
			local computed = getter(object)
			if computed ~= nil or not writableComputed(state.className, key) then
				return computed
			end
			return state.values[key]
		end
		if state.class.properties[key] ~= nil or state.extras[key] then
			return state.values[key]
		end
		for _, child in state.children do
			if stateOf(child).values.Name == key then
				return child
			end
		end
		if settings.undeclaredReads == "nil" then
			return nil
		end
		memberError(state, key)
		return nil
	end

	local function writeMember(object: Instance, key: string, value: unknown)
		local state = stateOf(object)
		if not state.class.instance and (key == "Name" or key == "Archivable") then
			memberError(state, key)
		end
		local access = state.class.access[key]
		if access == "callback" then
			state.doubles[key] = if value == nil then nil else { handler = value, previous = nil, active = true }
			return
		elseif access == "read" or access == "none" then
			error("read-only property: " .. key, 3)
		end
		if key == "Parent" then
			if not state.class.instance then
				memberError(state, key)
			end
			setParent(object, state, instances[value])
			return
		end
		local getter, writable = computedEntry(state.className, key)
		if not writable and getter ~= nil then
			error(("%s is read-only on %s"):format(key, describe(state)), 3)
		end
		local declared = state.class.properties[key] ~= nil
		if not declared and not writable then
			local isEvent = state.class.events[key] == true
			if
				type(value) == "function"
				and settings.functionDoubles == true
				and not isEvent
				and key ~= "ClassName"
			then
				state.doubles[key] = value
				return
			end
			if settings.undeclaredWrites ~= true or isEvent or key == "ClassName" or type(value) == "function" then
				memberError(state, key)
			end
		end
		if injecting "setProperty" then
			inject("setProperty", describe(state), object, key, value)
		end
		if
			settings.validateProperty ~= nil
			and settings.validateProperty(state.className, key, value, "set") == false
		then
			return
		end
		if key == "WorldPivot" and isA(state.className, "Model") then
			state.worldPivotSet = true
		end
		if state.values[key] == value then
			return
		end
		if not declared then
			state.extras[key] = true
		end
		assign(object, state, key, value)
	end

	local objectMetatable = {
		__index = readMember,
		__newindex = operation(writeMember),
	}

	function newObject(
		className: string,
		props: { [unknown]: unknown }?,
		isRoot: boolean,
		engineOwned: boolean?
	): Instance
		local class = resolve(className)
		if class == nil then
			error(("Unable to create an Instance of type %q"):format(className), 3)
		end
		if (not class.creatable or not class.instance) and not isRoot and engineOwned ~= true then
			error(("Unable to create an Instance of type %q"):format(className), 3)
		end
		local values: { [string]: unknown } = defaultsOf(className, class)
		local object = (setmetatable({} :: { [string]: unknown }, objectMetatable) :: unknown) :: Instance
		Names.register(object, if class.instance then "Instance" else "Object")
		if class.instance then
			instances[object] = object
		end
		local state: State = {
			className = className,
			class = class,
			values = values,
			children = {},
			attributes = {},
			tags = {},
			signals = {},
			signalFires = {},
			extras = {},
			doubles = {},
			destroyed = false,
			destroying = false,
			removing = false,
		}
		states[object] = state
		rawset(object, "__state", state)
		if injecting "create" then
			inject("create", className, object, nil, nil)
		end
		if not isRoot then
			alive += 1
		end
		for _, entry in table.clone(createHooks) do
			if entry.connected then
				entry.callback(object)
			end
		end
		local initial: { [unknown]: unknown } = props or {}
		for key, value in initial do
			if type(key) == "string" and key ~= "Parent" then
				object[key] = value
			end
		end
		for index = 1, #initial do
			local child = initial[index]
			if isObject(child) then
				instances[child].Parent = object
			end
		end
		if props ~= nil and props.Parent ~= nil then
			object.Parent = instances[props.Parent]
		end
		return object
	end

	if settings.builtins ~= false then
		local animatorMethods: { [string]: unknown } = {
			LoadAnimation = function(_self: Instance, animation: unknown): unknown
				return newObject("AnimationTrack", { Animation = animation }, false)
			end,
		}
		local animator: ClassSpec = { super = "Instance", methods = animatorMethods }
		specs.Animator = animator
		local track = table.clone(specs.AnimationTrack)
		specs.AnimationTrack = track
		local trackMethods: { [string]: unknown } = {
			Play = function(self: Instance, _fade: number?, _weight: number?, speed: number?)
				self.IsPlaying = true
				self.TimePosition = 0
				if speed ~= nil then
					self.Speed = speed
				end
			end,
			Stop = function(self: Instance)
				if not self.IsPlaying then
					return
				end
				self.IsPlaying = false
				local stopped = self.Stopped :: Signal<()>
				local ended = self.Ended :: Signal<()>
				stopped:Fire()
				ended:Fire()
			end,
			AdjustSpeed = function(self: Instance, speed: number)
				self.Speed = speed
			end,
			AdjustWeight = function(self: Instance, weight: number)
				self.Weight = weight
			end,
		}
		track.methods = trackMethods
		table.clear(resolved)
	end

	local heartbeat: Signal<number> = newSignal()
	if specs.Folder ~= nil then
		root = newObject("Folder", nil, true)
	else
		defineClass("Folder", { super = if specs.Instance ~= nil then "Instance" else nil })
		root = newObject("Folder", nil, true)
	end

	environment.root = root
	environment.heartbeat = heartbeat
	environment.tagChanged = newSignal()
	environment.scheduler = scheduler
	environment.task = {
		spawn = scheduler.spawn,
		defer = scheduler.defer,
		delay = scheduler.delay,
		wait = scheduler.wait,
		cancel = scheduler.cancel,
	}
	environment.errors = errors
	environment.defineClass = defineClass
	environment.fake = function<A..., R...>(member: string, handler: (Instance, A...) -> R...)
		fakes[member] = handler
	end
	environment.hasFake = function(object: Instance, member: string): boolean
		local state = stateOf(object)
		if doubleHandler(state.doubles[member]) ~= nil or type(state.class.methods[member]) == "function" then
			return true
		end
		local className: string? = state.className
		while className do
			if fakes[className .. "." .. member] ~= nil then
				return true
			end
			className = specs[className].super
		end
		return false
	end
	environment.createInstance = function(className: string, props: { [unknown]: unknown }?): Instance
		return newObject(className, props, false)
	end
	environment.createEngineInstance = function(className: string, props: { [unknown]: unknown }?): Instance
		local class = resolve(className)
		assert(class ~= nil and class.instance, "engine Instance creation requires an Instance class: " .. className)
		return newObject(className, props, false, true)
	end
	environment.createEngineObject = function(className: string, props: { [unknown]: unknown }?): Object
		return newObject(className, props, false, true)
	end
	environment.releaseObject = function(object: Object)
		assert(metatableOf(object) == objectMetatable, "object must belong to this environment")
		local state = stateOf(object)
		if state.class.instance then
			destroy(instances[object], state)
		elseif not state.destroyed then
			state.destroyed = true
			alive -= 1
			for _, signal in state.signals do
				signal:DisconnectAll()
			end
			table.clear(state.doubles)
		end
	end
	environment.newSignal = newSignal
	environment.step = function(seconds: number)
		scheduler.advance(seconds)
		scheduler.drain(100000)
		heartbeat:Fire(seconds)
	end
	environment.now = scheduler.clock
	environment.childrenOf = function(object: Instance): { Instance }
		return table.clone(stateOf(object).children)
	end
	environment.parentOf = function(object: Instance): Instance?
		return stateOf(object).parent
	end
	environment.propertyOf = function(object: Object, key: string): unknown
		local state = stateOf(object)
		return if state.class.access[key] == "callback" then doubleHandler(state.doubles[key]) else state.values[key]
	end
	environment.defaultPropertyOf = function(object: Instance, key: string): unknown
		local state = stateOf(object)
		if state.class.properties[key] == nil then
			memberError(state, key)
		end
		return defaultOf(state.className, state.class, key)
	end
	environment.defaultClassProperty = function(className: string, key: string): unknown
		local class = resolve(className)
		assert(class ~= nil and class.properties[key] ~= nil, "unknown class property: " .. className .. "." .. key)
		return defaultOf(className, class, key)
	end
	environment.tagsOf = function(object: Instance): { string }
		local tags: { string } = {}
		for tag in stateOf(object).tags do
			table.insert(tags, tag)
		end
		table.sort(tags)
		return tags
	end
	setTag = function(object: Instance, tag: string, present: boolean)
		local state = stateOf(object)
		assert(type(tag) == "string" and type(present) == "boolean", "invalid tag mutation")
		if (state.tags[tag] == true) == present then
			return
		end
		if present then
			state.tags[tag] = true
		else
			state.tags[tag] = nil
		end
		environment.tagChanged:Fire(object, tag, present)
	end
	environment.setTag = setTag
	environment.attributeOf = function(object: Instance, name: string): unknown
		return stateOf(object).attributes[name]
	end
	environment.isAlive = function(object: Object): boolean
		return not stateOf(object).destroyed
	end
	environment.liveObjects = function(): number
		return alive
	end
	environment.liveConnections = function(): number
		return signals.liveConnections()
	end
	environment.poke = operation(function(object: Instance, key: string, value: unknown)
		local state = stateOf(object)
		local declared = state.class.properties[key] ~= nil
		local getter, writable = computedEntry(state.className, key)
		if not writable and getter ~= nil then
			error(("%s is computed on %s"):format(key, describe(state)), 3)
		end
		if not declared and not writable and settings.undeclaredWrites ~= true then
			memberError(state, key)
		end
		if
			settings.validateProperty ~= nil
			and settings.validateProperty(state.className, key, value, "poke") == false
		then
			return
		end
		if key == "WorldPivot" and isA(state.className, "Model") then
			state.worldPivotSet = true
		end
		if state.values[key] == value then
			return
		end
		if not declared then
			state.extras[key] = true
		end
		assign(object, state, key, value)
	end)
	environment.fire = operation(function(object: Instance, event: string, ...: unknown)
		local state = stateOf(object)
		if not state.class.events[event] then
			memberError(state, event)
		end
		fireSignal(state, event, ...)
	end)
	environment.fakeOn = function<O, A..., R...>(object: O, name: string, handler: (O, A...) -> R...)
		local state = stateOf(object)
		if
			state.class.properties[name] ~= nil
			or state.class.events[name] == true
			or name == "ClassName"
			or name == "Parent"
			or state.extras[name]
		then
			error(("%s of %s is a property or event and cannot be a method double"):format(name, describe(state)), 2)
		end
		local entry: MethodOverride = { handler = handler, previous = state.doubles[name], active = true }
		state.doubles[name] = entry
		return function()
			if not entry.active then
				return
			end
			entry.active = false
			entry.handler = nil
			if state.doubles[name] == entry then
				local previous = entry.previous
				while type(previous) == "table" and not (previous :: MethodOverride).active do
					previous = (previous :: MethodOverride).previous
				end
				state.doubles[name] = previous
				entry.previous = nil
			end
		end
	end
	environment.snapshot = function(object: Instance): Snapshot
		local function walk(current: Instance): Snapshot
			local state = stateOf(current)
			local properties: { [string]: unknown } = {}
			for key, value in state.values do
				if key ~= "Name" then
					properties[key] = value
				end
			end
			local children: { Snapshot } = {}
			for _, child in state.children do
				table.insert(children, walk(child))
			end
			return {
				className = state.className,
				name = state.values.Name,
				properties = properties,
				attributes = table.clone(state.attributes),
				children = children,
			}
		end
		return walk(object)
	end
	environment.failNext = function(operation: Operation, times: number?)
		failures[operation] = (failures[operation] or 0) + (times or 1)
	end
	environment.clearFailures = function()
		table.clear(failures)
	end
	environment.pendingFailures = function(): number
		local total = 0
		for _, remaining in failures do
			total += remaining
		end
		return total
	end
	local function subscribe<T>(entries: { { callback: T, connected: boolean } }, callback: T): Connection
		local entry = { callback = callback, connected = true }
		table.insert(entries, entry)
		local connection = { Connected = true }
		function connection.Disconnect(_self: Connection)
			entry.connected = false
			connection.Connected = false
			local index = table.find(entries, entry)
			if index ~= nil then
				table.remove(entries, index)
			end
		end
		return connection
	end
	environment.observe = function(listener: (event: Event) -> ()): Connection
		return subscribe(observers, listener)
	end
	environment.onClone = function(hook: CloneHook): Connection
		return subscribe(cloneHooks, hook)
	end
	environment.onCreate = function(hook: CreateHook): Connection
		return subscribe(createHooks, hook)
	end

	environment.signalOf = function(object: Instance, event: string): SignalHandle
		local state = stateOf(object)
		if not state.class.events[event] then
			memberError(state, event)
		end
		local signal = signalFor(state, event)
		local meter = meters[signal]
		return {
			fire = function(...: unknown)
				signal:Fire(...)
			end,
			connections = meter.connections,
			fires = meter.fires,
		}
	end
	environment.connectionsOf = function(signal: Signal): number
		local meter = meters[signal]
		if meter == nil then
			error("signal was not created by this environment", 2)
		end
		return meter.connections()
	end
	environment.firesOf = function(signal: Signal): number
		local meter = meters[signal]
		if meter == nil then
			error("signal was not created by this environment", 2)
		end
		return meter.fires()
	end
	environment.connectionsOfInstance = function(object: Instance): number
		local total = 0
		for _, signal in stateOf(object).signals do
			total += meters[signal].connections()
		end
		return total
	end
	SpatialFakes.attach(environment, function(object: Instance): boolean
		return stateOf(object).worldPivotSet == true
	end)
	AudioFakes.attach(environment)
	inputActions = InputActionFakes.attach(environment)
	TweenFakes.attach(environment)
	SpatialQueryFakes.attach(environment)
	for member, handler in initialFakes do
		fakes[member] = handler
	end
	return environment
end

local function isInstance(value: unknown): boolean
	return Names.registered(value) == "Instance"
end

local function assertInstance(value: unknown): Instance
	local instance = instances[value]
	assert(instance ~= nil, "expected a simulated Instance")
	return instance
end

return {
	create = create,
	isInstance = isInstance,
	assertInstance = assertInstance,
	typeName = Names.kind,
	BASIC_CLASSES = Classes,
}
