--!strict

local Environment = require "./environment"
local Datatypes = require "./datatypes"

type Instance = Environment.Instance
type Vector = { X: number, Y: number }
type Dimension = { Scale: number, Offset: number }
type Dimensions = { X: Dimension, Y: Dimension }
type Rectangle = { x: number, y: number, width: number, height: number, scale: number }
export type Options = {
	roots: () -> { Instance },
	viewport: () -> Vector,
	origin: (() -> Vector)?,
	read: ((Instance, string) -> unknown)?,
	vector: ((number, number) -> unknown)?,
}
export type Controller = {
	step: () -> (),
	objectsAtPosition: (root: Instance, x: number, y: number) -> { Instance },
}

local function attach(environment: Environment.Environment, options: Options): Controller
	local read: (Instance, string) -> unknown = options.read or environment.propertyOf
	local vector: (number, number) -> unknown = options.vector
		or function(x: number, y: number): unknown
			return Datatypes.Vector2.new(x, y)
		end
	local function optional(object: Instance, property: string): unknown
		return read(object, property)
	end
	local function enum(object: Instance, property: string, fallback: string): string
		local value = optional(object, property)
		return if value == nil then fallback else tostring(value):match "([^%.]+)$" or fallback
	end
	local function number(object: Instance, property: string, fallback: number): number
		local value = optional(object, property)
		return if type(value) == "number" then value else fallback
	end
	local function dimension(value: unknown, extent: number, scale: number): number
		local unit = value :: Dimension
		return unit.Scale * extent + unit.Offset * scale
	end
	local function unsupported(object: Instance, mechanism: string)
		error("unsupported_ui_layout: " .. object:GetFullName() .. " requires " .. mechanism, 0)
	end
	local function validate(object: Instance)
		if object:IsA "LayerCollector" and not object:IsA "ScreenGui" then
			unsupported(object, object.ClassName)
		end
		if object:IsA "GuiObject" then
			if enum(object, "AutomaticSize", "None") ~= "None" then
				if object:IsA "TextLabel" or object:IsA "TextButton" or object:IsA "TextBox" then
					unsupported(object, "AutomaticSize text measurement")
				end
				if object:FindFirstChildWhichIsA "UISizeConstraint" then
					unsupported(object, "AutomaticSize with UISizeConstraint")
				end
			end
			if number(object, "Rotation", 0) ~= 0 then
				unsupported(object, "Rotation")
			end
			if enum(object, "SizeConstraint", "RelativeXY") ~= "RelativeXY" then
				unsupported(object, "SizeConstraint")
			end
		end
		if object:IsA "StyleLink" and options.read == nil then
			unsupported(object, "StyleLink without a styled property reader")
		end
		if object:IsA "UIListLayout" then
			if optional(object, "Wraps") == true then
				unsupported(object, "UIListLayout.Wraps")
			end
			for _, property in { "HorizontalFlex", "VerticalFlex" } do
				if enum(object, property, "None") ~= "None" then
					unsupported(object, "UIListLayout." .. property)
				end
			end
		elseif object:IsA "UIGridLayout" or object:IsA "UITableLayout" or object:IsA "UIPageLayout" then
			unsupported(object, object.ClassName)
		elseif object:IsA "UIAspectRatioConstraint" or object:IsA "UIFlexItem" then
			unsupported(object, object.ClassName)
		end
		for _, child in object:GetChildren() do
			validate(child)
		end
	end
	local function inset(object: Instance, rectangle: Rectangle): Rectangle
		local padding = object:FindFirstChildWhichIsA "UIPadding"
		if padding == nil then
			return rectangle
		end
		local left = dimension(read(padding, "PaddingLeft"), rectangle.width, rectangle.scale)
		local right = dimension(read(padding, "PaddingRight"), rectangle.width, rectangle.scale)
		local top = dimension(read(padding, "PaddingTop"), rectangle.height, rectangle.scale)
		local bottom = dimension(read(padding, "PaddingBottom"), rectangle.height, rectangle.scale)
		return {
			x = rectangle.x + left,
			y = rectangle.y + top,
			width = math.max(0, rectangle.width - left - right),
			height = math.max(0, rectangle.height - top - bottom),
			scale = rectangle.scale,
		}
	end
	local size: (Instance, Rectangle) -> Rectangle
	size = function(object: Instance, parent: Rectangle): Rectangle
		local authored = read(object, "Size") :: Dimensions
		local scale = parent.scale
		local modifier = object:FindFirstChildWhichIsA "UIScale"
		if modifier then
			scale *= number(modifier, "Scale", 1)
		end
		local width = dimension(authored.X, parent.width, parent.scale)
		local height = dimension(authored.Y, parent.height, parent.scale)
		local constraint = object:FindFirstChildWhichIsA "UISizeConstraint"
		if constraint then
			local minimum = read(constraint, "MinSize") :: Vector
			local maximum = read(constraint, "MaxSize") :: Vector
			width = math.clamp(width, minimum.X * parent.scale, maximum.X * parent.scale)
			height = math.clamp(height, minimum.Y * parent.scale, maximum.Y * parent.scale)
		end
		local factor = if parent.scale == 0 then 0 else scale / parent.scale
		local rectangle: Rectangle = {
			x = 0,
			y = 0,
			width = math.max(0, width * factor),
			height = math.max(0, height * factor),
			scale = scale,
		}
		local automatic = enum(object, "AutomaticSize", "None")
		if automatic == "None" then
			return rectangle
		end
		local autoX, autoY = automatic == "X" or automatic == "XY", automatic == "Y" or automatic == "XY"
		local padding = object:FindFirstChildWhichIsA "UIPadding"
		local paddingX, paddingY = 0, 0
		if padding then
			for _, property in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
				local unit = read(padding, property) :: Dimension
				if unit.Scale ~= 0 then
					unsupported(object, "AutomaticSize with scaled padding")
				end
			end
			paddingX = (
				(read(padding, "PaddingLeft") :: Dimension).Offset + (read(padding, "PaddingRight") :: Dimension).Offset
			) * scale
			paddingY = (
				(read(padding, "PaddingTop") :: Dimension).Offset + (read(padding, "PaddingBottom") :: Dimension).Offset
			) * scale
		end
		local content = inset(object, rectangle)
		local list = object:FindFirstChildWhichIsA "UIListLayout"
		local horizontal = list ~= nil and enum(list, "FillDirection", "Vertical") == "Horizontal"
		local gap = 0
		if list then
			local unit = read(list, "Padding") :: Dimension
			if unit.Scale ~= 0 then
				unsupported(object, "AutomaticSize with scaled list padding")
			end
			gap = unit.Offset * scale
		end
		local intrinsicWidth, intrinsicHeight, count = 0, 0, 0
		for _, child in object:GetChildren() do
			if child:IsA "GuiObject" and optional(child, "Visible") ~= false then
				local authoredChild = read(child, "Size") :: Dimensions
				local position = read(child, "Position") :: Dimensions
				local anchor = read(child, "AnchorPoint") :: Vector
				if (autoX and authoredChild.X.Scale ~= 0) or (autoY and authoredChild.Y.Scale ~= 0) then
					unsupported(child, "size relative to an automatic parent axis")
				end
				if
					list == nil
					and (
						(autoX and (position.X.Scale ~= 0 or anchor.X ~= 0))
						or (autoY and (position.Y.Scale ~= 0 or anchor.Y ~= 0))
					)
				then
					unsupported(child, "position relative to an automatic parent axis")
				end
				local childSize = size(child, content)
				if list then
					intrinsicWidth = if horizontal
						then intrinsicWidth + childSize.width
						else math.max(intrinsicWidth, childSize.width)
					intrinsicHeight = if horizontal
						then math.max(intrinsicHeight, childSize.height)
						else intrinsicHeight + childSize.height
				else
					intrinsicWidth = math.max(intrinsicWidth, position.X.Offset * scale + childSize.width)
					intrinsicHeight = math.max(intrinsicHeight, position.Y.Offset * scale + childSize.height)
				end
				count += 1
			end
		end
		if list then
			if horizontal then
				intrinsicWidth += math.max(0, count - 1) * gap
			else
				intrinsicHeight += math.max(0, count - 1) * gap
			end
		end
		if autoX then
			rectangle.width = math.max(rectangle.width, intrinsicWidth + paddingX)
		end
		if autoY then
			rectangle.height = math.max(rectangle.height, intrinsicHeight + paddingY)
		end
		return rectangle
	end
	local function alignment(value: string, available: number, used: number): number
		return if value == "Center"
			then (available - used) / 2
			else if value == "Right" or value == "Bottom" then available - used else 0
	end
	local function step()
		local roots = options.roots()
		for _, root in roots do
			validate(root)
		end
		local viewport = options.viewport()
		local origin = if options.origin then options.origin() else { X = 0, Y = 0 }
		local screen: Rectangle = { x = origin.X, y = origin.Y, width = viewport.X, height = viewport.Y, scale = 1 }
		local measureTree: (Instance, Rectangle) -> ()
		measureTree = function(object: Instance, parent: Rectangle)
			local rectangle = if object:IsA "GuiObject" then size(object, parent) else parent
			local content = inset(object, rectangle)
			for _, child in object:GetChildren() do
				measureTree(child, content)
			end
		end
		for _, root in roots do
			measureTree(root, screen)
		end
		local function publish(object: Instance, rectangle: Rectangle)
			environment.poke(object, "AbsolutePosition", vector(rectangle.x, rectangle.y))
			environment.poke(object, "AbsoluteSize", vector(rectangle.width, rectangle.height))
		end
		local visit: (Instance, Rectangle, Rectangle?) -> ()
		visit = function(object: Instance, parent: Rectangle, placed: Rectangle?)
			local rectangle = parent
			if object:IsA "GuiObject" then
				rectangle = placed or size(object, parent)
				if placed == nil then
					local position = read(object, "Position") :: Dimensions
					local anchor = read(object, "AnchorPoint") :: Vector
					rectangle.x = parent.x
						+ dimension(position.X, parent.width, parent.scale)
						- anchor.X * rectangle.width
					rectangle.y = parent.y
						+ dimension(position.Y, parent.height, parent.scale)
						- anchor.Y * rectangle.height
				end
				publish(object, rectangle)
			elseif object:IsA "ScreenGui" then
				publish(object, rectangle)
			end
			local content = inset(object, rectangle)
			if object:IsA "ScrollingFrame" then
				local canvas = read(object, "CanvasPosition") :: Vector
				content = table.clone(content)
				content.x -= canvas.X * content.scale
				content.y -= canvas.Y * content.scale
			end
			local list = object:FindFirstChildWhichIsA "UIListLayout"
			local children = object:GetChildren()
			local placements: { [Instance]: Rectangle } = {}
			if list then
				local items: { { object: Instance, rectangle: Rectangle, index: number } } = {}
				for index, child in children do
					if child:IsA "GuiObject" and optional(child, "Visible") ~= false then
						table.insert(items, { object = child, rectangle = size(child, content), index = index })
					end
				end
				local order = enum(list, "SortOrder", "Name")
				table.sort(items, function(left, right): boolean
					if order == "LayoutOrder" then
						local a, b = number(left.object, "LayoutOrder", 0), number(right.object, "LayoutOrder", 0)
						return if a == b then left.index < right.index else a < b
					end
					local a, b = tostring(left.object.Name), tostring(right.object.Name)
					return if a == b then left.index < right.index else a < b
				end)
				local horizontal = enum(list, "FillDirection", "Vertical") == "Horizontal"
				local gap = dimension(
					read(list, "Padding"),
					if horizontal then content.width else content.height,
					content.scale
				)
				local main, cross = 0, 0
				for _, item in items do
					main += if horizontal then item.rectangle.width else item.rectangle.height
					cross = math.max(cross, if horizontal then item.rectangle.height else item.rectangle.width)
				end
				main += math.max(0, #items - 1) * gap
				local xAlignment = enum(list, "HorizontalAlignment", "Left")
				local yAlignment = enum(list, "VerticalAlignment", "Top")
				local cursor = alignment(
					if horizontal then xAlignment else yAlignment,
					if horizontal then content.width else content.height,
					main
				)
				for _, item in items do
					local result = item.rectangle
					result.x = content.x
						+ (if horizontal then cursor else alignment(xAlignment, content.width, result.width))
					result.y = content.y
						+ (if horizontal then alignment(yAlignment, content.height, result.height) else cursor)
					placements[item.object] = result
					cursor += (if horizontal then result.width else result.height) + gap
				end
				environment.poke(
					list,
					"AbsoluteContentSize",
					vector(if horizontal then main else cross, if horizontal then cross else main)
				)
			end
			for _, child in children do
				visit(child, content, placements[child])
			end
		end
		for _, root in roots do
			visit(root, screen, nil)
		end
	end
	local function objectsAtPosition(root: Instance, x: number, y: number): { Instance }
		assert(
			x == math.floor(x) and y == math.floor(y) and math.abs(x) < math.huge and math.abs(y) < math.huge,
			"hit testing requires finite integer coordinates"
		)
		validate(root)
		type Order = { z: number, index: number }
		type Hit = {
			object: Instance,
			screen: Instance,
			display: number,
			mode: string,
			z: number,
			index: number,
			path: { Order },
		}
		local hits: { Hit } = {}
		local index = 0
		local displays: { [number]: Instance } = {}
		local function contains(object: Instance): boolean
			local at = environment.propertyOf(object, "AbsolutePosition") :: Vector
			local size = environment.propertyOf(object, "AbsoluteSize") :: Vector
			assert(at ~= nil and size ~= nil, "hit testing requires published layout")
			return size.X > 0 and size.Y > 0 and x >= at.X and y >= at.Y and x <= at.X + size.X and y <= at.Y + size.Y
		end
		local visit: (Instance, Instance?, { Order }, number, boolean) -> ()
		visit = function(object: Instance, screen: Instance?, path: { Order }, sibling: number, clipped: boolean)
			if object:IsA "ScreenGui" then
				if optional(object, "Enabled") == false then
					return
				end
				screen = object
				path = {}
				local display = number(object, "DisplayOrder", 0)
				local prior = displays[display]
				if prior and prior ~= object then
					unsupported(object, "equal DisplayOrder across ScreenGuis")
				end
				displays[display] = object
			elseif object:IsA "LayerCollector" then
				unsupported(object, object.ClassName .. " hit testing")
			end
			if object:IsA "GuiObject" then
				if optional(object, "Visible") == false then
					return
				end
				if screen == nil then
					unsupported(object, "hit testing outside ScreenGui")
				end
				index += 1
				local branch = table.clone(path)
				table.insert(branch, { z = number(object, "ZIndex", 1), index = sibling })
				path = branch
				local inside = contains(object)
				if inside and not clipped then
					local mode = enum(screen :: Instance, "ZIndexBehavior", "Sibling")
					if mode ~= "Sibling" and mode ~= "Global" then
						unsupported(object, "ZIndexBehavior." .. mode)
					end
					table.insert(hits, {
						object = object,
						screen = screen :: Instance,
						display = number(screen :: Instance, "DisplayOrder", 0),
						mode = mode,
						z = number(object, "ZIndex", 1),
						index = index,
						path = path,
					})
				end
				clipped = clipped or optional(object, "ClipsDescendants") == true and not inside
			end
			for ordinal, child in object:GetChildren() do
				if child:IsA "GuiObject" and not object:IsA "GuiObject" and not object:IsA "ScreenGui" then
					unsupported(child, "non-GuiObject hit-testing parent")
				end
				visit(child, screen, path, ordinal, clipped)
			end
		end
		visit(root, nil, {}, 1, false)
		table.sort(hits, function(a: Hit, b: Hit): boolean
			if a.display ~= b.display then
				return a.display > b.display
			end
			if a.screen ~= b.screen then
				unsupported(a.screen, "equal DisplayOrder across ScreenGuis")
			end
			if a.mode == "Global" then
				return if a.z ~= b.z then a.z > b.z else a.index > b.index
			end
			for ordinal = 1, math.min(#a.path, #b.path) do
				local first, second = a.path[ordinal], b.path[ordinal]
				if first.z ~= second.z then
					return first.z > second.z
				end
				if first.index ~= second.index then
					return first.index > second.index
				end
			end
			return #a.path > #b.path
		end)
		local result: { Instance } = {}
		for _, hit in hits do
			table.insert(result, hit.object)
		end
		return result
	end
	return { step = step, objectsAtPosition = objectsAtPosition }
end

return { attach = attach }
