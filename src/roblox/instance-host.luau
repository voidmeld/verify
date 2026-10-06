--!strict
--!nolint DeprecatedApi

local Operations = require "../core/operations"
local Environment = require "./environment"
local Native = require "./experience-host"

export type Node = Environment.Instance
export type Member = { id: string, key: string }
export type Write = { id: string, key: string, value: unknown }
export type Creation = { id: string, className: string, parent: string? }
export type Parent = { id: string, parent: string? }
export type View = { className: string, name: string, children: { string } }
export type Codec = { encode: (unknown) -> unknown, decode: (unknown) -> unknown }
export type Options = {
	actor: string,
	createInstance: (string) -> Node,
	borrowed: { [string]: Node }?,
	codec: Codec?,
}
export type Registry = { operations: Native.Registry, close: () -> (), get: (string) -> Node }
export type Host = { host: Operations.Host, registry: Registry }
export type Simulated = Host & { environment: Environment.Environment }

local function record(value: unknown): { [string]: unknown }
	assert(type(value) == "table", "expected instance operation record")
	return value :: { [string]: unknown }
end
local function stringValue(value: unknown): string
	assert(type(value) == "string" and value ~= "", "expected nonempty string")
	return value
end
local function optionalString(value: unknown): string?
	if value == nil then
		return nil
	end
	return stringValue(value)
end
local function nothing(value: unknown): nil
	assert(value == nil, "expected no result")
	return nil
end
local function member(value: unknown): Member
	local row = record(value)
	return { id = stringValue(row.id), key = stringValue(row.key) }
end
local function write(value: unknown): Write
	local row = record(value)
	return { id = stringValue(row.id), key = stringValue(row.key), value = Operations.snapshot(row.value) }
end

local create = Operations.operation {
	kind = "action",
	name = "instance.create",
	output = nothing,
	input = function(value: unknown): Creation
		local row = record(value)
		return { id = stringValue(row.id), className = stringValue(row.className), parent = optionalString(row.parent) }
	end,
}
local parent = Operations.operation {
	kind = "action",
	name = "instance.parent",
	output = nothing,
	input = function(value: unknown): Parent
		local row = record(value)
		return { id = stringValue(row.id), parent = optionalString(row.parent) }
	end,
}
local destroy =
	Operations.operation { kind = "action", name = "instance.destroy", input = stringValue, output = nothing }
local setProperty =
	Operations.operation { kind = "action", name = "instance.setProperty", input = write, output = nothing }
local setAttribute =
	Operations.operation { kind = "action", name = "instance.setAttribute", input = write, output = nothing }
local inspect = Operations.operation {
	kind = "query",
	name = "instance.inspect",
	input = stringValue,
	output = function(value: unknown): View
		local row = record(value)
		assert(type(row.children) == "table", "expected child names")
		local children: { string } = {}
		for index, child in row.children :: { unknown } do
			assert(index == #children + 1, "expected dense child names")
			table.insert(children, stringValue(child))
		end
		return { className = stringValue(row.className), name = stringValue(row.name), children = children }
	end,
}
local function property<T>(decode: (unknown) -> T): Operations.Operation<Member, T>
	return Operations.operation { kind = "query", name = "instance.property", input = member, output = decode }
end
local function attribute<T>(decode: (unknown) -> T): Operations.Operation<Member, T>
	return Operations.operation { kind = "query", name = "instance.attribute", input = member, output = decode }
end

local function registry(options: Options): Registry
	assert(options.actor ~= "", "instance registry needs actor")
	local nodes: { [string]: Node } = table.clone(options.borrowed or {})
	local borrowed: { { node: Node, parent: Node? } } = {}
	for _, node in nodes do
		table.insert(borrowed, { node = node, parent = node.Parent })
	end
	local owned: { Node } = {}
	local ownedIds: { [string]: boolean } = {}
	local closed = false
	local codec: Codec = options.codec or { encode = Operations.snapshot, decode = Operations.snapshot }
	local function get(id: string): Node
		assert(not closed, "instance registry is closed")
		local node = nodes[id]
		assert(node ~= nil, "unknown instance id: " .. id)
		return node
	end
	local function endpoint<I, O>(operation: Operations.Operation<I, O>, body: (I) -> O): Operations.Endpoint
		return Operations.bind(operation, function(input: I, request: Operations.Request): O
			assert(not closed and request.actor == options.actor, "wrong or closed instance actor")
			return body(input)
		end)
	end
	local operations: Native.Registry = { actions = {}, queries = {} }
	operations.actions[create.name] = endpoint(create, function(input): nil
		assert(nodes[input.id] == nil, "instance id already bound")
		local destination = if input.parent then get(input.parent) else nil
		local node = options.createInstance(input.className)
		table.insert(owned, node)
		nodes[input.id], ownedIds[input.id] = node, true
		node.Name = input.id
		node.Parent = destination
		return nil
	end)
	operations.actions[parent.name] = endpoint(parent, function(input): nil
		get(input.id).Parent = if input.parent then get(input.parent) else nil
		return nil
	end)
	operations.actions[destroy.name] = endpoint(destroy, function(id): nil
		assert(ownedIds[id], "cannot destroy a borrowed instance")
		local target = get(id)
		for _, item in borrowed do
			assert(not item.node:IsDescendantOf(target), "cannot destroy a borrowed descendant")
		end
		target:Destroy()
		nodes[id], ownedIds[id] = nil, nil
		return nil
	end)
	operations.actions[setProperty.name] = endpoint(setProperty, function(input): nil
		assert(input.key ~= "Parent", "use instance.parent for references")
		get(input.id)[input.key] = codec.decode(input.value)
		return nil
	end)
	operations.actions[setAttribute.name] = endpoint(setAttribute, function(input): nil
		get(input.id):SetAttribute(input.key, codec.decode(input.value))
		return nil
	end)
	local getProperty = property(Operations.snapshot)
	operations.queries[getProperty.name] = endpoint(getProperty, function(input): unknown
		assert(input.key ~= "Parent", "inspect hierarchy through instance operations")
		return codec.encode(get(input.id)[input.key])
	end)
	local getAttribute = attribute(Operations.snapshot)
	operations.queries[getAttribute.name] = endpoint(getAttribute, function(input): unknown
		return codec.encode(get(input.id):GetAttribute(input.key))
	end)
	operations.queries[inspect.name] = endpoint(inspect, function(id): View
		local node = get(id)
		local children: { string } = {}
		for _, child in node:GetChildren() do
			table.insert(children, stringValue(child.Name))
		end
		table.sort(children)
		return { name = stringValue(node.Name), className = node.ClassName, children = children }
	end)
	return {
		operations = operations,
		get = get,
		close = function()
			if closed then
				return
			end
			closed = true
			local failures: { string } = {}
			for _, item in borrowed do
				for _, owner in owned do
					if item.node:IsDescendantOf(owner) then
						local ok, problem = pcall(function()
							item.node.Parent = item.parent
						end)
						if not ok then
							table.insert(failures, tostring(problem))
						end
						break
					end
				end
			end
			for index = #owned, 1, -1 do
				local ok, problem = pcall(function()
					for _, item in borrowed do
						assert(not item.node:IsDescendantOf(owned[index]), "borrowed instance could not be restored")
					end
					owned[index]:Destroy()
				end)
				if not ok then
					table.insert(failures, tostring(problem))
				end
			end
			table.clear(nodes)
			table.clear(owned)
			assert(#failures == 0, table.concat(failures, "; "))
		end,
	}
end

local function simulated(actor: string, environment: Environment.Environment?): Simulated
	local env = environment or Environment.create()
	local bound = registry {
		actor = actor,
		createInstance = function(className)
			return env.createInstance(className)
		end,
	}
	local capabilities: { string } = { "roblox-simulated" }
	for name in bound.operations.actions do
		table.insert(capabilities, "action:" .. name)
	end
	for name in bound.operations.queries do
		table.insert(capabilities, "query:" .. name)
	end
	local host: Operations.Host = {
		name = "roblox-simulated",
		capabilities = capabilities,
		environment = { runtime = "simulation" },
		now = env.now,
		sleep = env.step,
		close = bound.close,
		invoke = function(request): unknown
			assert(request.actor == actor, "unknown simulated actor")
			assert(env.now() < request.deadline, "operation deadline exceeded")
			local entries = if request.kind == "action" then bound.operations.actions else bound.operations.queries
			local endpoint = entries[request.name]
			assert(endpoint ~= nil, "unknown instance operation")
			return endpoint.run(request.payload, request)
		end,
	}
	return { host = host, registry = bound, environment = env }
end

type NativeGlobals = { Instance: { new: (string) -> Node }, task: { wait: (number) -> number } }
local function native(actor: string, borrowed: { [string]: Node }?, codec: Codec?): Host
	local engine = Native.nativeEngine()
	local globals = (getfenv(0) :: unknown) :: NativeGlobals
	local bound = registry { actor = actor, createInstance = globals.Instance.new, borrowed = borrowed, codec = codec }
	local host = Native.create {
		engine = engine,
		actor = actor,
		actors = { [actor] = engine.context },
		registry = bound.operations,
		sleep = function(seconds)
			globals.task.wait(seconds)
		end,
	}
	local close = host.close
	host.close = function()
		bound.close()
		if close then
			close()
		end
	end
	return { host = host, registry = bound }
end

return {
	create = create,
	parent = parent,
	destroy = destroy,
	setProperty = setProperty,
	setAttribute = setAttribute,
	inspect = inspect,
	property = property,
	attribute = attribute,
	registry = registry,
	simulated = simulated,
	native = native,
}
