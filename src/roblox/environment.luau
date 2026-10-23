--!strict

local Datatypes = require "./datatypes"
local Names = require "./datatypes/names"
local Classes = require "./environment-classes"
local Scheduler = require "./scheduler"
local Types = require "./environment-types"
local SpatialFakes = require "./spatial-fakes"
local AudioFakes = require "./audio-fakes"
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
local ATTRIBUTE_NAME_LIMIT = 100
local metatableOf = (getmetatable :: unknown) :: (unknown) -> unknown

local UNIVERSAL_EVENTS: { string } = {
	"Changed",
	"ChildAdded",
	"ChildRemoved",
	"Destroying",
	"AttributeChanged",
	"DescendantAdded",
	"DescendantRemoving",
	"AncestryChanged",
}

local BASIC_CLASSES = Classes

local function create<P, M, F>(options: Options<P, M, F>?): Environment
	local settings: Options = ((options or {}) :: unknown) :: Options
	local limits: Limits = settings.limits or {}
	local specs: { [string]: ClassSpec } = {}
	local fakes: { [string]: unknown } = {}
	local initialFakes: { [string]: unknown } = settings.fakes or {}
	for member, handler in initialFakes do
		fakes[member] = handler
	end
	local resolved: { [string]: Resolved } = {}
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
	local running = setmetatable({} :: { [thread]: boolean }, { __mode = "k" })
	local scheduler = Scheduler.create()
	local connections = 0
	local alive = 0

	local environment = {} :: Environment
	type MethodOverride = { handler: unknown, previous: unknown, active: boolean }
	local function doubleHandler(value: unknown): unknown
		return if type(value) == "table" then (value :: MethodOverride).handler else value
	end
	local newObject: (className: string, props: { [unknown]: unknown }?, isRoot: boolean, engineOwned: boolean?) -> Instance

	local function defineClass<P, M>(className: string, spec: ClassSpec<P, M>, defineOptions: DefineOptions?)
		if type(className) ~= "string" or className == "" then
			error("class name must be a non-empty string", 2)
		end
		if specs[className] ~= nil and not (defineOptions ~= nil and defineOptions.replace == true) then
			error(("class %q is already defined"):format(className), 2)
		end
		specs[className] = (spec :: unknown) :: ClassSpec
		table.clear(resolved)
	end

	if settings.builtins ~= false then
		for className, spec in BASIC_CLASSES do
			specs[className] = spec
		end
	end
	local extraClasses: { [string]: ClassSpec } = settings.classes or {}
	for className, spec in extraClasses do
		specs[className] = spec
	end

	local function resolve(className: string): Resolved?
		local cached = resolved[className]
		if cached ~= nil then
			return cached
		end
		local spec = specs[className]
		if spec == nil then
			return nil
		end
		local parent: Resolved? = if spec.super ~= nil then resolve(spec.super) else nil
		if spec.super ~= nil and parent == nil then
			error(("class %q extends undefined class %q"):format(className, spec.super), 3)
		end
		local result: Resolved = {
			instance = className == "Instance" or (if parent ~= nil then parent.instance else className ~= "Object"),
			creatable = if spec.creatable ~= nil then spec.creatable else true,
			access = if parent ~= nil then table.clone(parent.access) else {},
			properties = if parent ~= nil then table.clone(parent.properties) else {},
			events = if parent ~= nil then table.clone(parent.events) else {},
			methods = if parent ~= nil then table.clone(parent.methods) else {},
		}
		if (parent == nil and result.instance) or className == "Instance" then
			result.properties.Name = false
			result.properties.Archivable = true
			for _, event in UNIVERSAL_EVENTS do
				result.events[event] = true
			end
		elseif parent == nil then
			result.events.Changed = true
		end
		local declared: { [string]: unknown } = spec.properties or {}
		for key, default in declared do
			result.properties[key] = default
		end
		local declaredEvents: { string } = spec.events or {}
		for _, event in declaredEvents do
			result.events[event] = true
		end
		local declaredMethods: { [string]: unknown } = spec.methods or {}
		local declaredAccess: { [string]: "read" | "write" | "none" | "callback" } = spec.access or {}
		for key in declaredAccess do
			result.access[key] = declaredAccess[key]
		end
		for key, method in declaredMethods do
			result.methods[key] = method
		end
		resolved[className] = result
		return result
	end

	local function isA(className: string, target: string): boolean
		local walk: string? = className
		while walk ~= nil do
			if walk == target then
				return true
			end
			local spec = specs[walk]
			walk = if spec ~= nil then spec.super else nil
		end
		return false
	end

	local observers: { { listener: (event: Event) -> (), connected: boolean } } = {}
	local cloneHooks: { { hook: CloneHook, connected: boolean } } = {}
	local createHooks: { { hook: CreateHook, connected: boolean } } = {}

	local function inject(operation: Operation, subject: string, object: Instance, member: string?, value: unknown)
		local remaining = failures[operation]
		local failing = remaining ~= nil and remaining > 0
		for _, observer in table.clone(observers) do
			if observer.connected then
				observer.listener {
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
			failures[operation] = (remaining :: number) - 1
			error(("environment: injected failure in %s"):format(operation), 0)
		end
	end

	local meters =
		setmetatable({} :: { [unknown]: { connections: () -> number, fires: () -> number } }, { __mode = "k" })

	local function guarded(body: (...unknown) -> ...unknown): (...unknown) -> ...unknown
		if not raising then
			return body
		end
		return function(...: unknown): ...unknown
			local thread = coroutine.running()
			if running[thread] then
				return body(...)
			end
			running[thread] = true
			local start = #errors
			local packed = table.pack(pcall(body, ...))
			running[thread] = nil
			if not packed[1] then
				error(packed[2], 0)
			end
			if #errors > start then
				local parts: { string } = {}
				for index = start + 1, #errors do
					table.insert(parts, errors[index])
					errors[index] = nil
				end
				error(table.concat(parts, "\n"), 0)
			end
			return table.unpack(packed, 2, packed.n)
		end
	end

	local function operation(body: unknown): unknown
		return guarded((body :: unknown) :: (...unknown) -> ...unknown)
	end

	local function newSignal<A...>(initialFires: number?): Signal<A...>
		local live: { { handler: (A...) -> (), connected: boolean, connection: Connection } } = {}
		local fired = initialFires or 0
		local signal = {} :: Signal<A...>
		Names.register(signal, "RBXScriptSignal")
		function signal:Connect(handler: (A...) -> ()): Connection
			local connection = { Connected = true } :: Connection
			Names.register(connection, "RBXScriptConnection")
			local record = { handler = handler, connected = true, connection = connection }
			table.insert(live, record)
			connections += 1
			function connection:Disconnect()
				if not record.connected then
					return
				end
				record.connected = false
				connection.Connected = false
				connections -= 1
				local index = table.find(live, record)
				if index ~= nil then
					table.remove(live, index)
				end
			end
			return connection :: Connection
		end
		local function wait(_self: Signal<A...>): ...unknown
			return scheduler.block(function(waiter: thread)
				local connection: Connection?
				local function cleanup()
					if connection then
						connection:Disconnect()
						connection = nil
					end
				end
				local function resume(...: unknown)
					cleanup()
					if coroutine.status(waiter) ~= "dead" then
						scheduler.resume(waiter, ...)
					end
				end
				connection = signal:Connect((resume :: unknown) :: (A...) -> ())
				return cleanup
			end)
		end
		signal.Wait = (wait :: unknown) :: (Signal<A...>) -> A...
		local function dispatch(_self: Signal<A...>, ...: A...)
			fired += 1
			if #live == 0 then
				return
			end
			for _, record in table.clone(live) do
				if record.connected then
					scheduler.spawn(function(...: A...)
						local ok, thrown: unknown = pcall(record.handler, ...)
						if not ok then
							table.insert(errors, tostring(thrown))
						end
					end, ...)
				end
			end
		end
		signal.Fire = (operation(dispatch) :: unknown) :: (Signal<A...>, A...) -> ()
		function signal:DisconnectAll()
			for _, record in table.clone(live) do
				record.connection:Disconnect()
			end
			table.clear(live)
		end
		meters[signal] = {
			connections = function(): number
				return #live
			end,
			fires = function(): number
				return fired
			end,
		}
		return signal :: Signal<A...>
	end

	local function stateOf(object: Object): State
		return rawget((object :: unknown) :: { [string]: unknown }, "__state") :: State
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

	local function computedEntry(className: string, key: string): (((object: Instance) -> unknown)?, boolean)
		local getters = settings.computed
		if getters == nil or (next(getters) == nil and metatableOf(getters) == nil) then
			return nil, false
		end
		local walk: string? = className
		while walk ~= nil do
			local entry = getters[walk .. "." .. key]
			if entry ~= nil then
				if type(entry) == "function" then
					return entry, false
				end
				return entry.get, entry.writable == true
			end
			local spec = specs[walk]
			walk = if spec ~= nil then spec.super else nil
		end
		return nil, false
	end
	local function computedFor(className: string, key: string): ((object: Instance) -> unknown)?
		local getter = computedEntry(className, key)
		return getter
	end
	local function writableComputed(className: string, key: string): boolean
		local _, writable = computedEntry(className, key)
		return writable
	end

	local function defaultOf(className: string, class: Resolved, key: string): unknown
		local declared = class.properties[key]
		local fallback = if key == "Name" then className elseif declared == false then nil else declared
		return if settings.defaultProperty ~= nil then settings.defaultProperty(className, key, fallback) else fallback
	end

	local function memberError(state: State, key: string): never
		error(("%s is not a valid member of %s"):format(key, describe(state)), 3)
	end

	local function changed(object: Instance, state: State, property: string)
		fireSignal(state, "prop:" .. property)
		fireSignal(state, "Changed", property)
	end

	local function assign(object: Instance, state: State, key: string, value: unknown)
		local coupled: string? = nil
		if isA(state.className, "BasePart") then
			if key == "CFrame" and Names.of(value) == "CFrame" and state.class.properties.Position ~= nil then
				local position = (value :: Datatypes.CFrameValue).Position
				if (state.values.Position :: Datatypes.Vector3Value?) ~= position then
					state.values.Position = position
					coupled = "Position"
				end
			elseif key == "Position" and Names.of(value) == "Vector3" and Names.of(state.values.CFrame) == "CFrame" then
				local frame = state.values.CFrame :: Datatypes.CFrameValue
				state.values.CFrame = frame + ((value :: Datatypes.Vector3Value) - frame.Position)
				coupled = "CFrame"
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
		for _, descendant in objects do
			for _, ancestor in before do
				if table.find(after, ancestor) == nil then
					fireSignal(stateOf(ancestor), "DescendantRemoving", descendant)
				end
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
		for _, descendant in objects do
			for _, ancestor in after do
				if table.find(before, ancestor) == nil then
					fireSignal(stateOf(ancestor), "DescendantAdded", descendant)
				end
			end
		end
		changed(object, state, "Parent")
		for _, descendant in objects do
			fireSignal(stateOf(descendant), "AncestryChanged", object, parent)
		end
	end

	local function setParent(object: Instance, state: State, parent: Instance?)
		inject("setParent", describe(state), object, nil, parent)
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
		inject("destroy", describe(state), object, nil, nil)
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

	local function validAttribute(name: unknown, value: unknown)
		local nameLimit = limits.attributeNameLength or ATTRIBUTE_NAME_LIMIT
		if type(name) ~= "string" or name == "" or string.match(name, "^[%w_]+$") == nil then
			error("attribute names must be non-empty alphanumeric or underscore strings", 4)
		end
		if #name > nameLimit then
			error(("attribute name %q is longer than %d characters"):format(name, nameLimit), 4)
		end
		if string.sub(name, 1, 3) == "RBX" then
			error("attribute names must not start with RBX", 4)
		end
		local kind = type(value)
		if kind ~= "string" and kind ~= "number" and kind ~= "boolean" and value ~= nil then
			local described = if kind == "table" and isObject(value)
				then "Instance"
				else Datatypes.typeName(value) or typeof(value)
			if not Datatypes.isAttributeType(described) then
				error(("attribute %q cannot hold a %s"):format(name, described), 4)
			end
		end
		if
			type(value) == "string"
			and limits.attributeStringLength ~= nil
			and #value > limits.attributeStringLength
		then
			error(("attribute %q string is longer than %d characters"):format(name, limits.attributeStringLength), 4)
		end
	end

	local function memberMethod(object: Instance, state: State, key: string): unknown
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

	local function universal(object: Instance, state: State, key: string): unknown
		local common = { IsA = true, GetPropertyChangedSignal = true }
		if not state.class.instance and common[key] ~= true then
			return nil
		end
		if key == "Destroy" then
			return function()
				destroy(object, state)
			end
		elseif key == "ClearAllChildren" then
			return function()
				for _, child in table.clone(state.children) do
					destroy(child, stateOf(child))
				end
			end
		elseif key == "GetChildren" then
			return function()
				return table.clone(state.children)
			end
		elseif key == "GetDescendants" then
			return function()
				local out: { Instance } = {}
				local function walk(parent: Instance)
					for _, child in stateOf(parent).children do
						table.insert(out, child)
						walk(child)
					end
				end
				walk(object)
				return out
			end
		elseif key == "WaitForChild" then
			return function(_self: Instance, name: string, timeout: number?): Instance?
				if timeout ~= nil and timeout <= 0 then
					error("illegal argument #2 (timeOut must be greater than 0)", 2)
				end
				for _, child in state.children do
					if stateOf(child).values.Name == name then
						return child
					end
				end
				return (
					scheduler.block(function(waiter: thread)
						local finished = false
						local added: Connection?
						local removed: Connection?
						local names: { [Instance]: Connection } = {}
						local timer: thread?
						local function cleanup()
							if finished then
								return
							end
							finished = true
							if added then
								added:Disconnect()
							end
							if removed then
								removed:Disconnect()
							end
							for _, connection in names do
								connection:Disconnect()
							end
							table.clear(names)
							if timer then
								scheduler.cancel(timer)
							end
						end
						local function finish(child: Instance?)
							if finished then
								return
							end
							cleanup()
							if coroutine.status(waiter) ~= "dead" then
								scheduler.resume(waiter, child)
							end
						end
						local function watch(child: Instance)
							names[child] = child:GetPropertyChangedSignal("Name"):Connect(function()
								if stateOf(child).parent == object and stateOf(child).values.Name == name then
									finish(child)
								end
							end)
						end
						for _, child in state.children do
							watch(child)
						end
						added = signalFor(state, "ChildAdded"):Connect(function(value: unknown)
							local child = value :: Instance
							if stateOf(child).values.Name == name then
								finish(child)
							else
								watch(child)
							end
						end)
						removed = signalFor(state, "ChildRemoved"):Connect(function(value: unknown)
							local child = value :: Instance
							local connection = names[child]
							if connection then
								connection:Disconnect()
								names[child] = nil
							end
						end)
						if timeout ~= nil then
							timer = scheduler.delay(timeout, function()
								finish(nil)
							end)
						end
						return cleanup
					end) :: unknown
				) :: Instance?
			end
		elseif key == "FindFirstChild" then
			return function(_self: Instance, name: string, recursive: boolean?): unknown
				local function search(parent: Instance): Instance?
					for _, child in stateOf(parent).children do
						if stateOf(child).values.Name == name then
							return child
						end
					end
					if recursive == true then
						for _, child in stateOf(parent).children do
							local found = search(child)
							if found ~= nil then
								return found
							end
						end
					end
					return nil
				end
				return search(object)
			end
		elseif key == "FindFirstChildOfClass" or key == "FindFirstChildWhichIsA" then
			return function(_self: Instance, className: string, recursive: boolean?): Instance?
				local function search(parent: Instance): Instance?
					for _, child in stateOf(parent).children do
						local childClass = stateOf(child).className
						if
							childClass == className or (key == "FindFirstChildWhichIsA" and isA(childClass, className))
						then
							return child
						end
					end
					if key == "FindFirstChildWhichIsA" and recursive == true then
						for _, child in stateOf(parent).children do
							local found = search(child)
							if found then
								return found
							end
						end
					end
					return nil
				end
				return search(object)
			end
		elseif
			key == "FindFirstAncestor"
			or key == "FindFirstAncestorOfClass"
			or key == "FindFirstAncestorWhichIsA"
		then
			return function(_self: Instance, name: string): Instance?
				local walk = state.parent
				while walk ~= nil do
					local candidate = stateOf(walk)
					if
						(key == "FindFirstAncestor" and candidate.values.Name == name)
						or (key == "FindFirstAncestorOfClass" and candidate.className == name)
						or (key == "FindFirstAncestorWhichIsA" and isA(candidate.className, name))
					then
						return walk
					end
					walk = candidate.parent
				end
				return nil
			end
		elseif key == "Clone" then
			return function(): Instance?
				if state.values.Archivable == false then
					return nil
				end
				local copies: { [Instance]: Instance } = {}
				local originals: { Instance } = {}
				local function copyTree(original: Instance): Instance
					local source = stateOf(original)
					local copy = newObject(source.className, nil, false)
					copies[original] = copy
					table.insert(originals, original)
					for _, child in source.children do
						if stateOf(child).values.Archivable ~= false then
							local childCopy = copyTree(child)
							move(childCopy, stateOf(childCopy), copy)
						end
					end
					return copy
				end
				local ok, result = pcall(function(): Instance
					local rootCopy = copyTree(object)
					for original, copy in copies do
						local source, target = stateOf(original), stateOf(copy)
						target.worldPivotSet = source.worldPivotSet
						for property, value in source.values do
							if
								computedFor(source.className, property) == nil
								or writableComputed(source.className, property)
							then
								target.values[property] = if isObject(value)
									then copies[value :: Instance] or value
									else value
							end
						end
						target.extras = table.clone(source.extras)
						target.attributes = table.clone(source.attributes)
						target.tags = table.clone(source.tags)
					end
					local function remap(value: Instance): Instance
						return copies[value] or value
					end
					for _, original in originals do
						local copy = copies[original]
						for _, entry in table.clone(cloneHooks) do
							if entry.connected then
								entry.hook(original, copy, remap)
							end
						end
					end
					return rootCopy
				end)
				if not ok then
					for _, copy in copies do
						destroy(copy, stateOf(copy))
					end
					error(result, 0)
				end
				return result
			end
		elseif key == "AddTag" or key == "RemoveTag" or key == "HasTag" then
			return function(_self: Instance, tag: string): boolean?
				assert(type(tag) == "string", "tag must be a string")
				if key == "HasTag" then
					return state.tags[tag] == true
				end
				environment.setTag(object, tag, key == "AddTag")
				return nil
			end
		elseif key == "GetTags" then
			return function(): { string }
				local tags: { string } = {}
				for tag in state.tags do
					table.insert(tags, tag)
				end
				table.sort(tags)
				return tags
			end
		elseif key == "GetFullName" then
			return function(): string
				local parts: { string } = {}
				local walk: Instance? = object
				while walk ~= nil and walk ~= environment.root do
					table.insert(parts, 1, tostring(stateOf(walk).values.Name))
					walk = stateOf(walk).parent
				end
				return table.concat(parts, ".")
			end
		elseif key == "IsA" then
			return function(_self: Instance, className: string): boolean
				return isA(state.className, className)
			end
		elseif key == "IsDescendantOf" then
			return function(_self: Instance, ancestor: unknown): boolean
				local walk = state.parent
				while walk ~= nil do
					if walk == ancestor then
						return true
					end
					walk = stateOf(walk).parent
				end
				return false
			end
		elseif key == "IsAncestorOf" then
			return function(_self: Instance, descendant: unknown): boolean
				local walk = stateOf(descendant :: Instance).parent
				while walk ~= nil do
					if walk == object then
						return true
					end
					walk = stateOf(walk).parent
				end
				return false
			end
		elseif key == "SetAttribute" then
			return function(_self: Instance, name: string, value: unknown)
				inject("setAttribute", describe(state), object, name, value)
				validAttribute(name, value)
				if state.attributes[name] == value then
					return
				end
				state.attributes[name] = value
				fireSignal(state, "attr:" .. name)
				fireSignal(state, "AttributeChanged", name)
			end
		elseif key == "GetAttribute" then
			return function(_self: Instance, name: string): unknown
				return state.attributes[name]
			end
		elseif key == "GetAttributes" then
			return function(): { [string]: unknown }
				return table.clone(state.attributes)
			end
		elseif key == "GetPropertyChangedSignal" then
			return function(_self: Instance, property: string): Signal
				if
					state.class.properties[property] == nil
					and property ~= "ClassName"
					and not (property == "Parent" and state.class.instance)
					and not state.extras[property]
					and settings.undeclaredWrites ~= true
					and computedFor(state.className, property) == nil
				then
					memberError(state, property)
				end
				return signalFor(state, "prop:" .. property)
			end
		elseif key == "IsPropertyModified" then
			return function(_self: Instance, property: string): boolean
				if state.class.properties[property] == nil then
					memberError(state, property)
				end
				return state.values[property] ~= defaultOf(state.className, state.class, property)
			end
		elseif key == "ResetPropertyToDefault" then
			return function(_self: Instance, property: string)
				if state.class.properties[property] == nil then
					memberError(state, property)
				end
				local value = defaultOf(state.className, state.class, property)
				inject("setProperty", describe(state), object, property, value)
				if state.values[property] == value then
					return
				end
				state.values[property] = value
				changed(object, state, property)
			end
		elseif key == "GetAttributeChangedSignal" then
			return function(_self: Instance, name: string): Signal
				return signalFor(state, "attr:" .. name)
			end
		end
		return nil
	end

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
		local double = doubleHandler(state.doubles[key])
		if double ~= nil then
			return operation(function(_self: Instance, ...: unknown): ...unknown
				return (double :: Method)(object, ...)
			end)
		end
		if state.class.events[key] then
			return signalFor(state, key)
		end
		if type(state.class.methods[key]) == "function" then
			return operation(memberMethod(object, state, key))
		end
		local builtin = universal(object, state, key)
		if builtin ~= nil then
			return operation(builtin)
		end
		local method = memberMethod(object, state, key)
		if method ~= nil then
			return operation(method)
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
			setParent(object, state, value :: Instance?)
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
		inject("setProperty", describe(state), object, key, value)
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
		__newindex = (operation(writeMember) :: unknown) :: typeof(writeMember),
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
		local values: { [string]: unknown } = {}
		for key, default in class.properties do
			values[key] = defaultOf(className, class, key)
		end
		local object = (setmetatable({} :: { [string]: unknown }, objectMetatable) :: unknown) :: Instance
		Names.register(object, if class.instance then "Instance" else "Object")
		rawset(
			object,
			"__state",
			{
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
			} :: State
		)
		inject("create", className, object, nil, nil)
		if not isRoot then
			alive += 1
		end
		for _, entry in table.clone(createHooks) do
			if entry.connected then
				entry.hook(object)
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
				((child :: unknown) :: Instance).Parent = object
			end
		end
		if props ~= nil and props.Parent ~= nil then
			object.Parent = props.Parent :: Instance
		end
		return object
	end

	if settings.builtins ~= false then
		specs.Animator = (
			{
				super = "Instance",
				methods = {
					LoadAnimation = function(_self: Instance, animation: unknown): unknown
						return newObject("AnimationTrack", { Animation = animation }, false)
					end,
				},
			} :: unknown
		) :: ClassSpec
		local track = table.clone(specs.AnimationTrack)
		specs.AnimationTrack = track
		track.methods = (
			{
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
			} :: unknown
		) :: { [string]: unknown }
		table.clear(resolved)
	end

	local heartbeat: Signal<number> = newSignal()
	local root: Instance
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
			destroy(object :: Instance, state)
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
	environment.tagsOf = function(object: Instance): { string }
		local tags: { string } = {}
		for tag in stateOf(object).tags do
			table.insert(tags, tag)
		end
		table.sort(tags)
		return tags
	end
	environment.setTag = function(object: Instance, tag: string, present: boolean)
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
		return connections
	end
	environment.poke = (
		operation(function(object: Instance, key: string, value: unknown)
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
		end) :: unknown
	) :: (object: Instance, key: string, value: unknown) -> ()
	environment.fire = (
		operation(function(object: Instance, event: string, ...: unknown)
			local state = stateOf(object)
			if not state.class.events[event] then
				memberError(state, event)
			end
			fireSignal(state, event, ...)
		end) :: unknown
	) :: (object: Instance, event: string, ...unknown) -> ()
	environment.fakeOn = function<O, A..., R...>(object: O, name: string, handler: (O, A...) -> R...)
		local state = stateOf((object :: unknown) :: Object)
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
	environment.observe = function(listener: (event: Event) -> ()): Connection
		local entry = { listener = listener, connected = true }
		table.insert(observers, entry)
		local connection = { Connected = true } :: Connection
		function connection:Disconnect()
			entry.connected = false
			connection.Connected = false
			local index = table.find(observers, entry)
			if index ~= nil then
				table.remove(observers, index)
			end
		end
		return connection
	end
	environment.onClone = function(hook: CloneHook): Connection
		local entry = { hook = hook, connected = true }
		table.insert(cloneHooks, entry)
		local connection = { Connected = true } :: Connection
		function connection:Disconnect()
			entry.connected = false
			connection.Connected = false
			local index = table.find(cloneHooks, entry)
			if index ~= nil then
				table.remove(cloneHooks, index)
			end
		end
		return connection
	end
	environment.onCreate = function(hook: CreateHook): Connection
		local entry = { hook = hook, connected = true }
		table.insert(createHooks, entry)
		local connection = { Connected = true } :: Connection
		function connection:Disconnect()
			entry.connected = false
			connection.Connected = false
			local index = table.find(createHooks, entry)
			if index ~= nil then
				table.remove(createHooks, index)
			end
		end
		return connection
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
	SpatialQueryFakes.attach(environment)
	for member, handler in initialFakes do
		fakes[member] = handler
	end
	return environment :: Environment
end

local function isInstance(value: unknown): boolean
	return Names.registered(value) == "Instance"
end

local function typeName(value: unknown): string
	return Names.kind(value)
end

return {
	create = create,
	isInstance = isInstance,
	typeName = typeName,
	BASIC_CLASSES = BASIC_CLASSES,
}
