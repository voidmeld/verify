--!strict

export type Connection = {
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, listener: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
}

export type ClassDefinition = {
	properties: { string },
	events: { string }?,
	methods: { string }?,
}

export type ApiDump = { [string]: ClassDefinition }

export type Options = {
	api: ApiDump,
	clock: (() -> number)?,
	rootClass: string?,
}

export type Layer = {
	new: (className: string) -> any,
	destroy: (object: any) -> (),
	typeName: (value: any) -> string,
	childrenOf: (object: any) -> { any },
	propertyOf: (object: any, key: string) -> any,
	propertyChanged: (object: any, property: string) -> Signal,
	heartbeat: Signal,
	clock: () -> number,
	root: any,
}

type Members = {
	properties: { [string]: true },
	events: { [string]: true },
	methods: { [string]: true },
}

type State = {
	className: string,
	name: string,
	members: Members,
	values: { [string]: any },
	changed: { [string]: Signal },
	children: { any },
	parent: any,
}

local UNIVERSAL_PROPERTIES: { string } = { "Name" }

local UNIVERSAL_METHODS: { string } = {
	"ClearAllChildren",
	"Destroy",
	"FindFirstChild",
	"GetAttribute",
	"GetChildren",
	"GetPropertyChangedSignal",
	"IsA",
	"SetAttribute",
}

local function signal(): Signal
	local listeners: { (...any) -> () } = {}
	local value: any = {}
	function value:Connect(listener: (...any) -> ()): Connection
		table.insert(listeners, listener)
		local disconnected = false
		local connection: any = {}
		function connection:Disconnect()
			if disconnected then
				return
			end
			disconnected = true
			for index, candidate in listeners do
				if candidate == listener then
					table.remove(listeners, index)
					break
				end
			end
		end
		return connection :: Connection
	end
	function value:Fire(...: any)
		for _, listener in table.clone(listeners) do
			listener(...)
		end
	end
	return value :: Signal
end

local function nameSet(names: { string }?, label: string): { [string]: true }
	local result: { [string]: true } = {}
	if names == nil then
		return result
	end
	if type(names) ~= "table" then
		error(label .. " must be an array of member names", 3)
	end
	for index, name in names do
		if type(index) ~= "number" or type(name) ~= "string" or name == "" then
			error(label .. " must be a dense array of non-empty member names", 3)
		end
		result[name] = true
	end
	return result
end

local function compile(api: ApiDump): { [string]: Members }
	if type(api) ~= "table" then
		error("api must be a table of class definitions", 3)
	end
	local compiled: { [string]: Members } = {}
	for className, definition in api do
		if type(className) ~= "string" or className == "" then
			error("api class names must be non-empty strings", 3)
		end
		if type(definition) ~= "table" then
			error(("api class %q must be a table"):format(className), 3)
		end
		local properties = nameSet(definition.properties, ("api class %q properties"):format(className))
		for _, name in UNIVERSAL_PROPERTIES do
			properties[name] = true
		end
		local methods = nameSet(definition.methods, ("api class %q methods"):format(className))
		for _, name in UNIVERSAL_METHODS do
			methods[name] = true
		end
		compiled[className] = {
			properties = properties,
			events = nameSet(definition.events, ("api class %q events"):format(className)),
			methods = methods,
		}
	end
	return compiled
end

local function create(options: Options): Layer
	local classes = compile(options.api)
	local rootClass = options.rootClass or "Folder"
	local clock = options.clock or function(): number
		return 0
	end

	local objectMetatable: any
	local instance: (className: string) -> any

	local function stateOf(object: any): State
		return rawget(object, "__state") :: State
	end

	local function isObject(value: any): boolean
		return type(value) == "table" and rawget(value, "__state") ~= nil
	end

	local function memberError(state: State, key: string): never
		error(("%s is not a valid member of %s %q"):format(key, state.className, state.name), 3)
	end

	local function removeChild(parent: any, child: any)
		if parent == nil then
			return
		end
		local children = stateOf(parent).children
		for index, candidate in children do
			if candidate == child then
				table.remove(children, index)
				return
			end
		end
	end

	local function setParent(object: any, parent: any)
		local state = stateOf(object)
		if parent ~= nil and not isObject(parent) then
			error(("Parent of %s %q must be an object of this layer"):format(state.className, state.name), 4)
		end
		removeChild(state.parent, object)
		state.parent = parent
		if parent ~= nil then
			table.insert(stateOf(parent).children, object)
		end
	end

	local function changedSignal(state: State, property: string): Signal
		local existing = state.changed[property]
		if existing == nil then
			existing = signal()
			state.changed[property] = existing
		end
		return existing
	end

	local function method(object: any, state: State, key: string): (...any) -> ...any
		if key == "Destroy" then
			return function()
				for _, child in table.clone(state.children) do
					child:Destroy()
				end
				setParent(object, nil)
			end
		end
		if key == "ClearAllChildren" then
			return function()
				for _, child in table.clone(state.children) do
					child:Destroy()
				end
			end
		end
		if key == "GetChildren" then
			return function()
				return table.clone(state.children)
			end
		end
		if key == "FindFirstChild" then
			return function(_self: any, name: string): any
				for _, child in state.children do
					if stateOf(child).name == name then
						return child
					end
				end
				return nil
			end
		end
		if key == "GetPropertyChangedSignal" then
			return function(_self: any, property: string): Signal
				if not state.members.properties[property] then
					memberError(state, property)
				end
				return changedSignal(state, property)
			end
		end
		if key == "IsA" then
			return function(_self: any, className: string): boolean
				return className == state.className
			end
		end
		if key == "SetAttribute" then
			return function(_self: any, attribute: string, value: any)
				state.values["@" .. attribute] = value
			end
		end
		if key == "GetAttribute" then
			return function(_self: any, attribute: string): any
				return state.values["@" .. attribute]
			end
		end
		return memberError(state, key)
	end

	objectMetatable = {
		__index = function(object: any, key: string): any
			local state = stateOf(object)
			if key == "ClassName" then
				return state.className
			end
			if key == "Parent" then
				return state.parent
			end
			if state.members.events[key] then
				local existing = state.values[key]
				if existing == nil then
					existing = signal()
					state.values[key] = existing
				end
				return existing
			end
			if state.members.methods[key] then
				return method(object, state, key)
			end
			if not state.members.properties[key] then
				memberError(state, key)
			end
			return state.values[key]
		end,
		__newindex = function(object: any, key: string, value: any)
			local state = stateOf(object)
			if key == "Parent" then
				setParent(object, value)
				return
			end
			if not state.members.properties[key] then
				memberError(state, key)
			end
			state.values[key] = value
			if key == "Name" then
				state.name = value
			end
			local changed = state.changed[key]
			if changed ~= nil then
				changed:Fire()
			end
		end,
	}

	function instance(className: string): any
		local members = classes[className]
		if members == nil then
			error(("Unable to create an Instance of type %q"):format(className), 2)
		end
		local object: any = setmetatable({} :: { [string]: any }, objectMetatable)
		rawset(
			object,
			"__state",
			{
				className = className,
				name = className,
				members = members,
				values = { Name = className },
				changed = {},
				children = {},
				parent = nil,
			} :: State
		)
		return object
	end

	local heartbeat = signal()

	return {
		new = instance,
		destroy = function(object: any)
			object:Destroy()
		end,
		typeName = function(value: any): string
			return if isObject(value) then "Instance" else typeof(value)
		end,
		childrenOf = function(object: any): { any }
			return table.clone(stateOf(object).children)
		end,
		propertyOf = function(object: any, key: string): any
			return object[key]
		end,
		propertyChanged = function(object: any, property: string): Signal
			return object:GetPropertyChangedSignal(property)
		end,
		heartbeat = heartbeat,
		clock = clock,
		root = instance(rootClass),
	}
end

return {
	UNIVERSAL_PROPERTIES = UNIVERSAL_PROPERTIES,
	UNIVERSAL_METHODS = UNIVERSAL_METHODS,
	create = create,
}
