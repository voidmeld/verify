--!strict

local D = require "./datatypes"
local Environment = require "./environment-types"
local Geometry = require "./query-geometry"

type Instance = Environment.Instance
type Vector = D.Vector3Value
type Shape = Geometry.Shape
type Bounds = { low: { number }, high: { number } }
type Node = {
	bounds: Bounds,
	part: Instance?,
	order: number,
	parent: Node?,
	left: Node?,
	right: Node?,
}
type World = { root: Node?, leaves: { [Instance]: Node }, dirty: { [Instance]: boolean } }
export type Select = (Instance, Shape, Vector) -> { Instance }

local function bounds(shape: Shape): Bounds
	local cf, h = shape.frame, shape.half
	local p, x, y, z = cf.Position, cf.RightVector, cf.UpVector, cf.ZVector
	local extent = {
		math.abs(x.X) * h.X + math.abs(y.X) * h.Y + math.abs(z.X) * h.Z,
		math.abs(x.Y) * h.X + math.abs(y.Y) * h.Y + math.abs(z.Y) * h.Z,
		math.abs(x.Z) * h.X + math.abs(y.Z) * h.Y + math.abs(z.Z) * h.Z,
	}
	local low: { number } = {}
	local high: { number } = {}
	for i, center in { p.X, p.Y, p.Z } do
		extent[i] = math.max(extent[i], shape.radius or 0)
		local padding = math.abs(center) * 1e-6 + (extent[i] + 1) * 1e-3
		low[i], high[i] = center - extent[i] - padding, center + extent[i] + padding
	end
	return { low = low, high = high }
end

local function union(a: Bounds, b: Bounds): Bounds
	local low: { number } = {}
	local high: { number } = {}
	for i = 1, 3 do
		low[i], high[i] = math.min(a.low[i], b.low[i]), math.max(a.high[i], b.high[i])
	end
	return { low = low, high = high }
end

local function build(nodes: { Node }): Node?
	if #nodes == 0 then
		return nil
	elseif #nodes == 1 then
		return nodes[1]
	end
	local enclosing = nodes[1].bounds
	for i = 2, #nodes do
		enclosing = union(enclosing, nodes[i].bounds)
	end
	local axis = 1
	for i = 2, 3 do
		if enclosing.high[i] - enclosing.low[i] > enclosing.high[axis] - enclosing.low[axis] then
			axis = i
		end
	end
	table.sort(nodes, function(a: Node, b: Node): boolean
		local ac, bc = a.bounds.low[axis] + a.bounds.high[axis], b.bounds.low[axis] + b.bounds.high[axis]
		ac, bc = if ac == ac then ac else 0, if bc == bc then bc else 0
		return if ac == bc then a.order < b.order else ac < bc
	end)
	local first, last = {}, {}
	for i, node in nodes do
		table.insert(if i <= math.floor(#nodes / 2) then first else last, node)
	end
	local left, right = assert(build(first)), assert(build(last))
	local node: Node = { bounds = enclosing, order = 0, left = left, right = right }
	left.parent, right.parent = node, node
	return node
end

local function touches(target: Bounds, source: Bounds, direction: { number }): boolean
	local near: number = 0
	local far: number = 1
	for i = 1, 3 do
		local low, high, speed = target.low[i] - source.high[i], target.high[i] - source.low[i], direction[i]
		if speed == 0 then
			if low > 0 or high < 0 then
				return false
			end
		else
			local first, last = low / speed, high / speed
			near = math.max(near, math.min(first, last))
			far = math.min(far, math.max(first, last))
			if near > far then
				return false
			end
		end
	end
	return true
end

local function attach(
	environment: Environment.Environment,
	shape: (Instance) -> Shape,
	owningWorld: (Instance) -> Instance?
): Select
	local worlds: { [Instance]: World } = setmetatable({}, { __mode = "ks" })
	local moving: { [Instance]: { parent: Instance? } } = setmetatable({}, { __mode = "ks" })
	local function invalidate()
		table.clear(worlds)
	end
	environment.observe(function(event: Environment.Event)
		local parent = event.object.Parent
		if not event.injected and (if event.operation == "destroy" then parent ~= nil else event.value ~= parent) then
			moving[event.object] = { parent = parent }
		end
	end, { operations = { "setParent", "destroy" } })
	environment.onMemberWrite({ "Parent" }, function(object: Instance)
		moving[object] = nil
		invalidate()
	end)
	environment.onClone(invalidate)
	environment.onMemberWrite({ "CFrame", "Position", "Size", "Shape" }, function(part: Instance)
		for _, world in worlds do
			if world.leaves[part] then
				world.dirty[part] = true
			end
		end
	end)
	local function partBounds(part: Instance): Bounds
		if not part:IsA "Terrain" then
			local ok, value = pcall(shape, part)
			if ok then
				return bounds(value)
			end
		end
		return { low = { -math.huge, -math.huge, -math.huge }, high = { math.huge, math.huge, math.huge } }
	end
	return function(owner: Instance, source: Shape, direction: Vector): { Instance }
		for object, previous in moving do
			if object.Parent ~= previous.parent then
				previous.parent = object.Parent
				invalidate()
			end
		end
		local world = worlds[owner]
		if world == nil then
			local leaves, nodes = {}, {}
			for order, part in owner:GetDescendants() do
				if (part:IsA "BasePart" or part:IsA "Terrain") and owningWorld(part) == owner then
					local node: Node = { bounds = partBounds(part), part = part, order = order }
					leaves[part] = node
					table.insert(nodes, node)
				end
			end
			world = { root = build(nodes), leaves = leaves, dirty = {} }
			worlds[owner] = world
		end
		for part in world.dirty do
			local leaf = world.leaves[part]
			leaf.bounds = partBounds(part)
			local node = leaf.parent
			while node do
				node.bounds = union(assert(node.left).bounds, assert(node.right).bounds)
				node = node.parent
			end
		end
		table.clear(world.dirty)
		local query = bounds(source)
		local delta = { direction.X, direction.Y, direction.Z }
		local found: { Node } = {}
		local function visit(node: Node?)
			if node == nil or not touches(node.bounds, query, delta) then
				return
			end
			if node.part then
				table.insert(found, node)
			else
				visit(node.left)
				visit(node.right)
			end
		end
		visit(world.root)
		table.sort(found, function(a: Node, b: Node): boolean
			return a.order < b.order
		end)
		local parts = {}
		for _, node in found do
			table.insert(parts, assert(node.part))
		end
		return parts
	end
end

return { attach = attach }
