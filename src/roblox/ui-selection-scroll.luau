--!strict

local Environment = require "./environment"
local Values = require "./ui-values"
local Float = require "./datatypes/float"

type Instance = Environment.Instance

local function attach(
	environment: Environment.Environment,
	read: (Instance, string) -> unknown,
	vector: (number, number) -> unknown,
	measured: (Instance) -> boolean
)
	local connections: { [Instance]: Environment.Connection } = {}
	local closed = false
	local function reveal(service: Instance)
		local selected = environment.propertyOf(service, "SelectedObject")
		if not Environment.isInstance(selected) then
			return
		end
		local target = Environment.assertInstance(selected)
		if not measured(target) then
			return
		end
		local at, size = Values.vector(read(target, "AbsolutePosition")), Values.vector(read(target, "AbsoluteSize"))
		local x, y = at.X, at.Y
		local parent = target.Parent
		while parent do
			if parent:IsA "ScrollingFrame" and read(parent, "ScrollingEnabled") ~= false and measured(parent) then
				local origin = Values.vector(read(parent, "AbsolutePosition"))
				local window = Values.vector(read(parent, "AbsoluteWindowSize"))
				local canvas = Values.vector(read(parent, "AbsoluteCanvasSize"))
				local extent = Values.vector(read(parent, "AbsoluteSize"))
				local position = Values.vector(read(parent, "CanvasPosition"))
				local function shift(start: number, width: number, edge: number, length: number): number
					if width > length then
						return if start >= edge + length then width elseif start + width <= edge then -width else 0
					end
					return if start < edge then start - edge else math.max(0, Float.f32(start + width) - edge - length)
				end
				local visibleX = if Values.enumName(read(parent, "VerticalScrollBarInset"), "ScrollBarInset")
						== "None"
					then extent.X
					else window.X
				local visibleY = if Values.enumName(read(parent, "HorizontalScrollBarInset"), "ScrollBarInset")
						== "None"
					then extent.Y
					else window.Y
				local nextX = math.clamp(
					Float.f32(position.X + shift(x, size.X, origin.X, window.X)),
					0,
					math.max(0, canvas.X - visibleX)
				)
				local nextY = math.clamp(
					Float.f32(position.Y + shift(y, size.Y, origin.Y, window.Y)),
					0,
					math.max(0, canvas.Y - visibleY)
				)
				environment.poke(parent, "CanvasPosition", vector(nextX, nextY))
			end
			parent = parent.Parent
		end
	end
	local function watch(object: Instance)
		if not closed and object:IsA "GuiService" and connections[object] == nil then
			connections[object] = object:GetPropertyChangedSignal("SelectedObject"):Connect(function()
				reveal(object)
			end)
		end
	end
	local created = environment.onCreate(function(object)
		if Environment.isInstance(object) then
			watch(Environment.assertInstance(object))
		end
	end)
	return {
		watch = function(root: Instance)
			local game = if root:IsA "DataModel" then root else root:FindFirstAncestorWhichIsA "DataModel"
			local service = if game then game:FindFirstChildOfClass "GuiService" else nil
			if service then
				watch(service)
			end
		end,
		close = function()
			closed = true
			created:Disconnect()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
		end,
	}
end

return { attach = attach }
