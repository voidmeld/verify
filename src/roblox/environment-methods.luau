--!strict

local Types = require "./environment-types"
local Scheduler = require "./scheduler"
local Datatypes = require "./datatypes"
type Instance = Types.Instance
type State = Types.State
type Signal = Types.Signal
type Connection = Types.Connection
local ATTRIBUTE_NAME_LIMIT = 100

export type Dependencies = {
	settings: Types.Options,
	limits: Types.Limits,
	scheduler: Scheduler.Scheduler,
	instances: { [unknown]: Instance },
	cloneHooks: { { callback: Types.CloneHook, connected: boolean } },
	root: () -> Instance,
	stateOf: (unknown) -> State,
	isObject: (unknown) -> boolean,
	signalFor: (State, string) -> Signal,
	fireSignal: (State, string, ...unknown) -> (),
	injecting: (Types.Operation) -> boolean,
	inject: (Types.Operation, State?, string?, Instance, string?, unknown) -> (),
	memberError: (State, string) -> never,
	changed: (Instance, State, string) -> (),
	destroy: (Instance, State) -> (),
	move: (Instance, State, Instance?) -> (),
	isA: (string, string) -> boolean,
	computedFor: (string, string) -> ((Instance) -> unknown)?,
	writableComputed: (string, string) -> boolean,
	defaultOf: (string, Types.Resolved, string) -> unknown,
	newObject: (string, { [unknown]: unknown }?, boolean, boolean?) -> Instance,
	setTag: (Instance, string, boolean) -> (),
}
local function create(dependencies: Dependencies)
	local settings = dependencies.settings
	local limits = dependencies.limits
	local scheduler = dependencies.scheduler
	local instances = dependencies.instances
	local cloneHooks = dependencies.cloneHooks
	local stateOf = dependencies.stateOf
	local isObject = dependencies.isObject
	local signalFor = dependencies.signalFor
	local fireSignal = dependencies.fireSignal
	local injecting = dependencies.injecting
	local inject = dependencies.inject
	local memberError = dependencies.memberError
	local changed = dependencies.changed
	local destroy = dependencies.destroy
	local move = dependencies.move
	local isA = dependencies.isA
	local computedFor = dependencies.computedFor
	local writableComputed = dependencies.writableComputed
	local defaultOf = dependencies.defaultOf
	local newObject = dependencies.newObject
	local setTag = dependencies.setTag
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

	local COMMON: { [string]: boolean } = table.freeze { IsA = true, GetPropertyChangedSignal = true }
	local function universal(object: Instance, state: State, key: string): unknown
		if not state.class.instance and COMMON[key] ~= true then
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
		elseif key == "FindFirstChild" or key == "FindFirstChildOfClass" or key == "FindFirstChildWhichIsA" then
			return function(_self: Instance, name: string, recursive: boolean?): Instance?
				local function search(parent: Instance): Instance?
					for _, child in stateOf(parent).children do
						local candidate = stateOf(child)
						if
							(key == "FindFirstChild" and candidate.values.Name == name)
							or (key ~= "FindFirstChild" and candidate.className == name)
							or (key == "FindFirstChildWhichIsA" and isA(candidate.className, name))
						then
							return child
						end
					end
					if key ~= "FindFirstChildOfClass" and recursive == true then
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
									then copies[instances[value]] or value
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
								entry.callback(original, copy, remap)
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
				setTag(object, tag, key == "AddTag")
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
				while walk ~= nil and walk ~= dependencies.root() do
					table.insert(parts, 1, tostring(stateOf(walk).values.Name))
					walk = stateOf(walk).parent
				end
				return table.concat(parts, ".")
			end
		elseif key == "IsA" then
			return function(_self: Instance, className: string): boolean
				return isA(state.className, className)
			end
		elseif key == "IsDescendantOf" or key == "IsAncestorOf" then
			return function(_self: Instance, target: unknown): boolean
				local walk = if key == "IsDescendantOf" then state.parent else stateOf(instances[target]).parent
				local ancestor = if key == "IsDescendantOf" then target else object
				while walk ~= nil do
					if walk == ancestor then
						return true
					end
					walk = stateOf(walk).parent
				end
				return false
			end
		elseif key == "SetAttribute" then
			return function(_self: Instance, name: string, value: unknown)
				if injecting "setAttribute" then
					inject("setAttribute", state, nil, object, name, value)
				end
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
				if injecting "setProperty" then
					inject("setProperty", state, nil, object, property, value)
				end
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

	return universal
end

return create
