--!strict

local Environment = require "./environment"
local Float = require "./datatypes/float"
local Values = require "./ui-values"

type Instance = Environment.Instance
type Dimension = { Scale: number, Offset: number }
type Dimensions = { X: Dimension, Y: Dimension }
export type Rectangle = {
	x: number,
	y: number,
	width: number,
	height: number,
	scale: number,
	flexWidth: number?,
	flexHeight: number?,
}
export type Item = { object: Instance, rectangle: Rectangle, index: number }
export type Result = {
	items: { Item },
	columns: number,
	rows: number,
	cellWidth: number,
	cellHeight: number,
	width: number,
	height: number,
}

local function measure(grid: Instance, content: Rectangle, read: (Instance, string) -> unknown): Result
	local function enum(property: string, fallback: string): string
		local value = read(grid, property)
		return if value == nil then fallback else tostring(value):match "([^%.]+)$" or fallback
	end
	local function unsupported(mechanism: string): never
		error("unsupported_ui_layout: " .. grid:GetFullName() .. " requires " .. mechanism, 0)
	end
	local function dimension(unit: Dimension, extent: number): number
		return Float.f32(Float.f32(unit.Scale * extent) + Float.f32(unit.Offset * content.scale))
	end
	local authored = Values.dimensions(read(grid, "CellSize"))
	local padding = Values.dimensions(read(grid, "CellPadding"))
	local cellWidth, cellHeight = dimension(authored.X, content.width), dimension(authored.Y, content.height)
	local gapX, gapY = dimension(padding.X, content.width), dimension(padding.Y, content.height)
	local aspect = grid:FindFirstChildWhichIsA "UIAspectRatioConstraint"
	if aspect then
		local ratio = Values.number(read(aspect, "AspectRatio"))
		if ratio <= 0 or ratio >= math.huge then
			unsupported "invalid grid aspect ratio"
		end
		local kind = tostring(read(aspect, "AspectType")):match "([^%.]+)$"
		local axis = tostring(read(aspect, "DominantAxis")):match "([^%.]+)$"
		if kind == "FitWithinMaxSize" then
			cellWidth = math.min(cellWidth, cellHeight * ratio)
			cellHeight = cellWidth / ratio
		elseif kind == "ScaleWithParentSize" then
			if axis == "Width" then
				cellHeight = cellWidth / ratio
			else
				cellWidth = cellHeight * ratio
			end
		else
			unsupported "grid aspect type"
		end
	end
	if cellWidth <= 0 or cellHeight <= 0 or gapX < 0 or gapY < 0 then
		unsupported "non-positive grid cells or negative grid padding"
	end
	local horizontal = enum("FillDirection", "Horizontal") == "Horizontal"
	local capacity = math.max(
		1,
		math.floor(
			(if horizontal then content.width + gapX else content.height + gapY)
				/ (if horizontal then cellWidth + gapX else cellHeight + gapY)
		)
	)
	local limit = Values.number(read(grid, "FillDirectionMaxCells"))
	if limit > 0 then
		capacity = math.min(capacity, limit)
	end
	local items: { Item } = {}
	for index, child in assert(grid.Parent):GetChildren() do
		if child:IsA "GuiObject" and read(child, "Visible") ~= false then
			if child:FindFirstChildWhichIsA "UIAspectRatioConstraint" then
				unsupported "aspect-constrained grid cells"
			end
			if child:FindFirstChildWhichIsA "UISizeConstraint" or child:FindFirstChildWhichIsA "UIScale" then
				unsupported "constrained or scaled grid cells"
			end
			table.insert(items, {
				object = child,
				rectangle = { x = 0, y = 0, width = cellWidth, height = cellHeight, scale = content.scale },
				index = index,
			})
		end
	end
	local order = enum("SortOrder", "Name")
	table.sort(items, function(left: Item, right: Item): boolean
		if order == "LayoutOrder" then
			local a, b =
				Values.number(read(left.object, "LayoutOrder")), Values.number(read(right.object, "LayoutOrder"))
			return if a == b then left.index < right.index else a < b
		end
		local a, b = tostring(left.object.Name), tostring(right.object.Name)
		return if a == b then left.index < right.index else a < b
	end)
	local main = math.min(capacity, #items)
	local cross = math.ceil(#items / capacity)
	local columns, rows = if horizontal then main else cross, if horizontal then cross else main
	local width = columns * cellWidth + math.max(0, columns - 1) * gapX
	local height = rows * cellHeight + math.max(0, rows - 1) * gapY
	local xAlignment, yAlignment = enum("HorizontalAlignment", "Left"), enum("VerticalAlignment", "Top")
	local x = if xAlignment == "Center"
		then (content.width - width) / 2
		elseif xAlignment == "Right" then content.width - width
		else 0
	local y = if yAlignment == "Center"
		then (content.height - height) / 2
		elseif yAlignment == "Bottom" then content.height - height
		else 0
	local corner = enum("StartCorner", "TopLeft")
	for index, item in items do
		local mainIndex, crossIndex = (index - 1) % capacity, math.floor((index - 1) / capacity)
		local column, row = if horizontal then mainIndex else crossIndex, if horizontal then crossIndex else mainIndex
		if corner == "TopRight" or corner == "BottomRight" then
			column = columns - column - 1
		end
		if corner == "BottomLeft" or corner == "BottomRight" then
			row = rows - row - 1
		end
		item.rectangle.x = content.x + x + column * (cellWidth + gapX)
		item.rectangle.y = content.y + y + row * (cellHeight + gapY)
	end
	return {
		items = items,
		columns = columns,
		rows = rows,
		cellWidth = cellWidth,
		cellHeight = cellHeight,
		width = width,
		height = height,
	}
end

return { measure = measure }
