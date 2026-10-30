--!strict

local Environment = require "./environment"
local Values = require "./ui-values"

type Instance = Environment.Instance
type Vector = { X: number, Y: number }
type Dimension = { Scale: number, Offset: number }
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
export type Result = { items: { Item }, width: number, height: number }
type Flex = { basis: number, value: number, grow: number, shrink: number, minimum: number, maximum: number }

local function alignment(value: string, available: number, used: number): number
	return if value == "Center"
		then (available - used) / 2
		elseif value == "Right" or value == "Bottom" or value == "End" then available - used
		else 0
end

local function distribute(items: { Flex }, available: number): boolean
	local total = 0
	for _, item in items do
		total += item.value
	end
	local growing = available > total
	local active: { Flex } = {}
	for _, item in items do
		table.insert(active, item)
	end
	local changed = false
	while #active > 0 do
		local remaining, weight = available, 0
		for _, item in items do
			remaining -= item.value
		end
		for _, item in active do
			weight += if growing then item.grow else item.shrink * item.basis
		end
		if weight == 0 or math.abs(remaining) < 0.000001 then
			break
		end
		local clamped = false
		for index = #active, 1, -1 do
			local item = active[index]
			local ratio = if growing then item.grow else item.shrink * item.basis
			local value = item.value + remaining * ratio / weight
			local bounded = math.clamp(value, item.minimum, item.maximum)
			if bounded ~= value then
				changed = changed or bounded ~= item.value
				item.value = bounded
				table.remove(active, index)
				clamped = true
			end
		end
		if not clamped then
			for _, item in active do
				local ratio = if growing then item.grow else item.shrink * item.basis
				local value = item.value + remaining * ratio / weight
				changed = changed or value ~= item.value
				item.value = value
			end
			break
		end
	end
	return changed
end

local function wrappedAutomaticText(object: Instance, read: (Instance, string) -> unknown): boolean
	if
		not (object:IsA "TextLabel" or object:IsA "TextButton" or object:IsA "TextBox")
		or read(object, "TextWrapped") ~= true
	then
		return false
	end
	local automatic = tostring(read(object, "AutomaticSize")):match "([^%.]+)$"
	return automatic == "Y" or automatic == "XY"
end

local function measure(
	list: Instance,
	content: Rectangle,
	read: (Instance, string) -> unknown,
	size: (Instance, Rectangle) -> Rectangle,
	reflow: ((Instance, Rectangle, number) -> Rectangle)?
): Result
	local function enum(object: Instance, property: string, fallback: string): string
		local value = read(object, property)
		return if value == nil then fallback else tostring(value):match "([^%.]+)$" or fallback
	end
	local function number(object: Instance, property: string): number
		local value = read(object, property)
		return if type(value) == "number" then value else 0
	end
	local function bounds(object: Instance, horizontal: boolean): (number, number)
		local constraint = object:FindFirstChildWhichIsA "UISizeConstraint"
		if constraint == nil then
			return 0, math.huge
		end
		local minimum, maximum = Values.vector(read(constraint, "MinSize")), Values.vector(read(constraint, "MaxSize"))
		return (if horizontal then minimum.X else minimum.Y) * content.scale,
			(if horizontal then maximum.X else maximum.Y) * content.scale
	end
	local horizontal = enum(list, "FillDirection", "Vertical") == "Horizontal"
	local crossFlex = enum(list, if horizontal then "VerticalFlex" else "HorizontalFlex", "None")
	local wrapped = read(list, "Wraps") == true
	local items: { Item } = {}
	for index, child in assert(list.Parent):GetChildren() do
		if child:IsA "GuiObject" and read(child, "Visible") ~= false then
			local item = child:FindFirstChildWhichIsA "UIFlexItem"
			local itemAlignment = if item then enum(item, "ItemLineAlignment", "Automatic") else "Automatic"
			if itemAlignment == "Automatic" then
				itemAlignment = enum(list, "ItemLineAlignment", "Automatic")
			end
			local rectangle: Rectangle
			if
				not horizontal
				and not wrapped
				and crossFlex == "Fill"
				and reflow
				and (itemAlignment == "Automatic" or itemAlignment == "Stretch")
			then
				local minimum, maximum = bounds(child, true)
				rectangle = reflow(child, content, math.clamp(content.width, minimum, maximum))
			else
				rectangle = size(child, content)
			end
			table.insert(items, { object = child, rectangle = rectangle, index = index })
		end
	end
	local order = enum(list, "SortOrder", "Name")
	table.sort(items, function(left: Item, right: Item): boolean
		if order == "LayoutOrder" then
			local a, b = number(left.object, "LayoutOrder"), number(right.object, "LayoutOrder")
			return if a == b then left.index < right.index else a < b
		end
		local a, b = tostring(left.object.Name), tostring(right.object.Name)
		return if a == b then left.index < right.index else a < b
	end)
	local mainFlex = enum(list, if horizontal then "HorizontalFlex" else "VerticalFlex", "None")
	local mainAlignment = enum(
		list,
		if horizontal then "HorizontalAlignment" else "VerticalAlignment",
		if horizontal then "Left" else "Top"
	)
	local crossAlignment = enum(
		list,
		if horizontal then "VerticalAlignment" else "HorizontalAlignment",
		if horizontal then "Top" else "Left"
	)
	local available = if horizontal then content.width else content.height
	local availableCross = if horizontal then content.height else content.width
	local padding = Values.dimension(read(list, "Padding"))
	local gap = padding.Scale * available + padding.Offset * content.scale
	local crossGap = padding.Scale * availableCross + padding.Offset * content.scale
	local flexAvailable = (if horizontal then content.flexWidth else content.flexHeight) or available
	local function preferredCross(item: Item): number
		local dimensions = Values.dimensions(read(item.object, "Size"))
		local unit = if horizontal then dimensions.Y else dimensions.X
		local parentExtent = if horizontal then content.height else content.width
		local factor = if content.scale == 0 then 0 else item.rectangle.scale / content.scale
		local minimum, maximum = bounds(item.object, not horizontal)
		return math.clamp(unit.Scale * parentExtent + unit.Offset * content.scale, minimum, maximum) * factor
	end
	local function aspectSize(object: Instance, main: number, cross: number, scale: number): (number, number)
		local aspect = object:FindFirstChildWhichIsA "UIAspectRatioConstraint"
		if aspect == nil then
			return main, cross
		end
		local ratio = number(aspect, "AspectRatio")
		ratio = if horizontal then ratio else 1 / ratio
		local factor = if content.scale == 0 then 0 else scale / content.scale
		local maximumMain = available * factor
		local maximumCross = (if horizontal then content.height else content.width) * factor
		if enum(aspect, "AspectType", "FitWithinMaxSize") == "FitWithinMaxSize" then
			main = math.min(main, cross * ratio)
		elseif (enum(aspect, "DominantAxis", "Width") == "Width") == horizontal then
			main = math.min(main, maximumMain, maximumCross * ratio)
		else
			cross = math.min(cross, maximumCross, maximumMain / ratio)
			main = cross * ratio
		end
		return main, main / ratio
	end
	local function measureLine(items: { Item }, availableCross: number): (number, number)
		local gap = gap
		local gaps = math.max(0, #items - 1) * gap
		local flex: { Flex } = {}
		local cross = 0
		local enabled = mainFlex ~= "None"
			or crossFlex ~= "None"
			or enum(list, "ItemLineAlignment", "Automatic") ~= "Automatic"
			or wrapped
		for _, item in items do
			cross = math.max(cross, if horizontal then item.rectangle.height else item.rectangle.width)
		end
		local line = if crossFlex == "Fill" then availableCross else cross
		for _, item in items do
			local basis = if horizontal then item.rectangle.width else item.rectangle.height
			local child = item.object:FindFirstChildWhichIsA "UIFlexItem"
			enabled = enabled or child ~= nil
			local mode = if child then enum(child, "FlexMode", "None") elseif mainFlex == "Fill" then "Fill" else "None"
			local minimum, maximum = bounds(item.object, horizontal)
			local aspect = item.object:FindFirstChildWhichIsA "UIAspectRatioConstraint"
			if aspect then
				local itemAlignment = if child then enum(child, "ItemLineAlignment", "Automatic") else "Automatic"
				if itemAlignment == "Automatic" then
					itemAlignment = enum(list, "ItemLineAlignment", "Automatic")
				end
				local extent = preferredCross(item)
				local maximumMain = math.huge
				if itemAlignment == "Stretch" or (itemAlignment == "Automatic" and crossFlex == "Fill") then
					extent = line
					maximumMain = if content.scale == 0 then 0 else available * item.rectangle.scale / content.scale
					basis = aspectSize(item.object, maximumMain, extent, item.rectangle.scale)
					basis = math.clamp(basis, minimum, maximum)
				end
				local limit = aspectSize(item.object, maximumMain, extent, item.rectangle.scale)
				if
					enum(aspect, "AspectType", "FitWithinMaxSize") == "ScaleWithParentSize"
					and (enum(aspect, "DominantAxis", "Width") == "Width") ~= horizontal
				then
					minimum, maximum, basis = limit, limit, limit
				else
					maximum = math.min(maximum, limit)
					minimum = math.min(minimum, maximum)
				end
			end
			table.insert(flex, {
				basis = basis,
				value = basis,
				minimum = minimum,
				maximum = maximum,
				grow = if mode == "Fill" or mode == "Grow"
					then 1
					elseif mode == "Custom" and child then number(child, "GrowRatio")
					else 0,
				shrink = if mode == "Fill" or mode == "Shrink"
					then 1
					elseif mode == "Custom" and child then number(child, "ShrinkRatio")
					else 0,
			})
		end
		local changed = distribute(flex, flexAvailable - gaps)
		if horizontal and reflow then
			local reflowed = false
			for index, item in items do
				local child = item.object:FindFirstChildWhichIsA "UIFlexItem"
				local itemAlignment = if child then enum(child, "ItemLineAlignment", "Automatic") else "Automatic"
				if itemAlignment == "Automatic" then
					itemAlignment = enum(list, "ItemLineAlignment", "Automatic")
				end
				if
					flex[index].value ~= flex[index].basis
					and itemAlignment ~= "Stretch"
					and not (itemAlignment == "Automatic" and crossFlex == "Fill")
					and wrappedAutomaticText(item.object, read)
				then
					local measured = reflow(item.object, content, flex[index].value)
					item.rectangle = table.clone(item.rectangle)
					item.rectangle.height = measured.height
					reflowed = true
				end
			end
			if reflowed and crossFlex ~= "Fill" then
				line = 0
				for _, item in items do
					line = math.max(line, item.rectangle.height)
				end
			end
		end
		local main = gaps
		for _, item in flex do
			main += item.value
		end
		local cursor = alignment(mainAlignment, available, main)
		local spacing = mainFlex == "SpaceBetween" or mainFlex == "SpaceAround" or mainFlex == "SpaceEvenly"
		if spacing and not changed and #items > 0 then
			if main - gaps > available then
				error("unsupported_ui_layout: " .. list:GetFullName() .. " requires overflowing list spacing", 0)
			end
			cursor = 0
			local spaces = if mainFlex == "SpaceBetween"
				then #items - 1
				elseif mainFlex == "SpaceAround" then #items
				else #items + 1
			local extra = math.max(0, available - main + gaps)
			gap = if spaces > 0 then extra / spaces else 0
			cursor = if mainFlex == "SpaceAround" then gap / 2 elseif mainFlex == "SpaceEvenly" then gap else 0
		end
		local alignments: { string } = {}
		for index, item in items do
			local rectangle = item.rectangle
			local aspect = item.object:FindFirstChildWhichIsA "UIAspectRatioConstraint"
			local extent = if aspect
				then preferredCross(item)
				elseif horizontal then rectangle.height
				else rectangle.width
			local child = item.object:FindFirstChildWhichIsA "UIFlexItem"
			local itemAlignment = if child then enum(child, "ItemLineAlignment", "Automatic") else "Automatic"
			if itemAlignment == "Automatic" then
				itemAlignment = enum(list, "ItemLineAlignment", "Automatic")
			end
			if itemAlignment == "Automatic" then
				itemAlignment = if crossFlex == "Fill" then "Stretch" else crossAlignment
			end
			if itemAlignment == "Stretch" then
				extent = line
			end
			local mainExtent
			mainExtent, extent = aspectSize(item.object, flex[index].value, extent, rectangle.scale)
			local mainDominant = aspect ~= nil
				and enum(aspect, "AspectType", "FitWithinMaxSize") == "ScaleWithParentSize"
				and (enum(aspect, "DominantAxis", "Width") == "Width") == horizontal
			if itemAlignment == "Stretch" and not mainDominant then
				local minimum, maximum = bounds(item.object, not horizontal)
				extent = math.clamp(extent, minimum, maximum)
			end
			rectangle.width = if horizontal then mainExtent else extent
			rectangle.height = if horizontal then extent else mainExtent
			alignments[index] = itemAlignment
			if crossFlex ~= "Fill" then
				line = math.max(line, extent)
			end
		end
		local lineOffset = alignment(crossAlignment, availableCross, line)
		if crossFlex == "SpaceAround" or crossFlex == "SpaceEvenly" then
			lineOffset = (availableCross - line) / 2
		elseif crossFlex == "SpaceBetween" then
			lineOffset = 0
		end
		if wrapped then
			lineOffset = 0
		end
		for index, item in items do
			local rectangle = item.rectangle
			local extent = if horizontal then rectangle.height else rectangle.width
			local offset = if enabled
				then lineOffset + alignment(alignments[index], line, extent)
				else alignment(crossAlignment, availableCross, extent)
			rectangle.x = content.x + (if horizontal then cursor else offset)
			rectangle.y = content.y + (if horizontal then offset else cursor)
			cursor += flex[index].value + gap
		end
		return main, line
	end
	if not wrapped then
		local main, cross = measureLine(items, availableCross)
		return { items = items, width = if horizontal then main else cross, height = if horizontal then cross else main }
	end
	type Line = { items: { Item }, main: number, cross: number }
	local lines: { Line } = {}
	local current: Line = { items = {}, main = 0, cross = 0 }
	for _, item in items do
		local aspect = item.object:FindFirstChildWhichIsA "UIAspectRatioConstraint"
		local flexItem = item.object:FindFirstChildWhichIsA "UIFlexItem"
		local itemAlignment = if flexItem then enum(flexItem, "ItemLineAlignment", "Automatic") else "Automatic"
		if itemAlignment == "Automatic" then
			itemAlignment = enum(list, "ItemLineAlignment", "Automatic")
		end
		if
			aspect
			and enum(aspect, "AspectType", "FitWithinMaxSize") == "ScaleWithParentSize"
			and (enum(aspect, "DominantAxis", "Width") == "Width") == horizontal
			and (itemAlignment == "Stretch" or (itemAlignment == "Automatic" and crossFlex == "Fill"))
		then
			local main = aspectSize(item.object, math.huge, availableCross, item.rectangle.scale)
			local minimum, maximum = bounds(item.object, horizontal)
			local adjustedMain, adjustedCross =
				aspectSize(item.object, math.clamp(main, minimum, maximum), availableCross, item.rectangle.scale)
			item.rectangle.width = if horizontal then adjustedMain else adjustedCross
			item.rectangle.height = if horizontal then adjustedCross else adjustedMain
		end
		local main = if horizontal then item.rectangle.width else item.rectangle.height
		local cross = if horizontal then item.rectangle.height else item.rectangle.width
		if #current.items > 0 and current.main + gap + main > available then
			table.insert(lines, current)
			current = { items = {}, main = 0, cross = 0 }
		end
		current.main += (if #current.items > 0 then gap else 0) + main
		current.cross = math.max(current.cross, cross)
		table.insert(current.items, item)
	end
	if #current.items > 0 then
		table.insert(lines, current)
	end
	local total = math.max(0, #lines - 1) * crossGap
	for _, line in lines do
		total += line.cross
	end
	local extra = math.max(0, availableCross - total)
	local main = 0
	total = math.max(0, #lines - 1) * crossGap
	for _, line in lines do
		local cross = line.cross + (if crossFlex == "Fill" and #lines > 0 then extra / #lines else 0)
		local measuredMain, measuredCross = measureLine(line.items, cross)
		line.cross = measuredCross
		main = math.max(main, measuredMain)
		total += measuredCross
	end
	extra = math.max(0, availableCross - total)
	local cursor = alignment(crossAlignment, availableCross, total)
	local lineGap = crossGap
	local spacing = crossFlex == "SpaceBetween" or crossFlex == "SpaceAround" or crossFlex == "SpaceEvenly"
	if spacing then
		local spaces = if crossFlex == "SpaceBetween"
			then #lines - 1
			elseif crossFlex == "SpaceAround" then #lines
			else #lines + 1
		lineGap = if spaces > 0 then (extra + math.max(0, #lines - 1) * crossGap) / spaces else 0
		cursor = if crossFlex == "SpaceAround" then lineGap / 2 elseif crossFlex == "SpaceEvenly" then lineGap else 0
	elseif crossFlex == "Fill" then
		cursor = 0
	end
	for _, line in lines do
		for _, item in line.items do
			if horizontal then
				item.rectangle.y += cursor
			else
				item.rectangle.x += cursor
			end
		end
		cursor += line.cross + lineGap
	end
	return { items = items, width = if horizontal then main else total, height = if horizontal then total else main }
end

return table.freeze { measure = measure }
