--!strict

local Environment = require "./environment"
local Enum = require "./datatypes/enum"
local Datatypes = require "./datatypes"
local Grid = require "./ui-grid-layout"
local List = require "./ui-list-layout"
local Float = require "./datatypes/float"
local Values = require "./ui-values"
local SelectionScroll = require "./ui-selection-scroll"
local Projection = require "./ui-projection"

type Instance = Environment.Instance
type Vector = { X: number, Y: number }
type TextMeasurement = { X: number, Y: number, intrinsicX: number, intrinsicY: number, fits: boolean }
type Rectangle = List.Rectangle
type Turn = { x: number, y: number, angle: number }
export type ProjectionHost = Projection.Host
export type Options = {
	roots: () -> { Instance },
	viewport: () -> Vector,
	origin: (() -> Vector)?,
	screenArea: ((Instance) -> { x: number, y: number, width: number, height: number })?,
	projection: Projection.Host?,
	ignoreDecorativeWorldGui: boolean?,
	read: ((Instance, string) -> unknown)?,
	component: ((Instance, string, string) -> unknown)?,
	vector: ((number, number) -> unknown)?,
	measureBounds: ((Values.TextParameters, number?) -> unknown)?,
	measureLineHeight: ((Values.TextParameters, number, number) -> number)?,
	truncateBounds: ((Values.TextParameters, string, number, boolean) -> number?)?,
}
export type Controller = {
	step: () -> (),
	flush: (Instance) -> (),
	busy: (() -> boolean)?,
	objectsAtPosition: (root: Instance, x: number, y: number, candidates: { Instance }?) -> { Instance },
	close: () -> (),
}

local function attach(environment: Environment.Environment, options: Options): Controller
	local originalRead: (Instance, string) -> unknown = options.read or environment.propertyOf
	local function interactive(object: Instance): boolean
		if object:IsA "GuiObject" then
			if originalRead(object, "Visible") == false then
				return false
			end
			if
				object:IsA "GuiButton"
				or originalRead(object, "Active") == true
				or originalRead(object, "Selectable") == true
			then
				return true
			end
		elseif object:IsA "UIDragDetector" and originalRead(object, "Enabled") ~= false then
			return true
		end
		for _, child in object:GetChildren() do
			if interactive(child) then
				return true
			end
		end
		return false
	end
	local function read(object: Instance, property: string): unknown
		if
			property == "Enabled"
			and options.ignoreDecorativeWorldGui == true
			and object:IsA "LayerCollector"
			and not object:IsA "ScreenGui"
			and not interactive(object)
		then
			return false
		end
		return originalRead(object, property)
	end
	local vector: (number, number) -> unknown = options.vector or Datatypes.Vector2.new
	local function enum(object: Instance, property: string, fallback: string): string
		local value = read(object, property)
		local item = Enum.itemValue(value)
		return if item
			then item.Name
			elseif value == nil then fallback
			else tostring(value):match "([^%.]+)$" or fallback
	end
	local function number(object: Instance, property: string, fallback: number): number
		local value = read(object, property)
		return if type(value) == "number" then value else fallback
	end
	local function dimension(unit: Values.Dimension, extent: number, scale: number): number
		return unit.Scale * extent + unit.Offset * scale
	end
	local function paddingValue(object: Instance, property: string): unknown
		if options.component then
			return options.component(object, "UIPadding", property)
		end
		local padding = object:FindFirstChildWhichIsA "UIPadding"
		return if padding then read(padding, property) else nil
	end
	local function unsupported(object: Instance, mechanism: string): never
		error("unsupported_ui_layout: " .. object:GetFullName() .. " requires " .. mechanism, 0)
	end
	local function isText(object: Instance): boolean
		return object:IsA "TextLabel" or object:IsA "TextButton" or object:IsA "TextBox"
	end
	local projected: { [Instance]: Projection.Area | false } = {}
	setmetatable(projected, { __mode = "ks" })
	local validated: { [Instance]: { stamp: number, epoch: number, automatic: string, projected: boolean, projection: number? } } =
		{}
	local validationProjection: number? = nil
	setmetatable(validated, { __mode = "ks" })
	local function validate(object: Instance, automatic: string)
		local stamp, epoch = environment.layoutStamp(object), environment.layoutEpoch()
		local previous = validated[object]
		if
			previous
			and previous.stamp == stamp
			and previous.epoch == epoch
			and previous.automatic == automatic
			and (not previous.projected or previous.projection == validationProjection)
		then
			return
		end
		if object:IsA "BillboardGui" then
			projected[object] = Projection.resolve(object, read, options.projection) or false
		elseif object:IsA "LayerCollector" and not object:IsA "ScreenGui" then
			unsupported(object, object.ClassName)
		end
		if object:IsA "GuiObject" then
			number(object, "Rotation", 0)
			local parent = object.Parent
			if
				enum(object, "SizeConstraint", "RelativeXY") ~= "RelativeXY"
				and parent ~= nil
				and parent:IsA "GuiObject"
				and automatic ~= "None"
			then
				local authored = Values.dimensions(read(object, "Size"))
				if authored.X.Scale ~= 0 or authored.Y.Scale ~= 0 then
					unsupported(object, "SizeConstraint under automatic size")
				end
			end
			if enum(object, "AutomaticSize", "None") ~= "None" then
				if isText(object) then
					if options.measureBounds == nil then
						unsupported(object, "AutomaticSize text measurement")
					end
				end
			end
		end
		if object:IsA "StyleLink" and options.read == nil then
			unsupported(object, "StyleLink without a styled property reader")
		end
		if object:IsA "UITableLayout" or object:IsA "UIPageLayout" then
			unsupported(object, object.ClassName)
		end
		if object:IsA "UIAspectRatioConstraint" then
			local ratio = number(object, "AspectRatio", 1)
			if ratio <= 0 or ratio >= math.huge or ratio ~= ratio then
				unsupported(object, "invalid aspect ratio")
			end
			local parent = object.Parent
			if parent and parent:IsA "GuiObject" and enum(parent, "AutomaticSize", "None") ~= "None" then
				unsupported(parent, "aspect constraint with automatic size")
			end
		end
		local hasProjection = object:IsA "BillboardGui"
		local childAutomatic = if object:IsA "GuiObject" then enum(object, "AutomaticSize", "None") else "None"
		for _, child in object:GetChildren() do
			validate(child, childAutomatic)
			hasProjection = hasProjection or validated[child].projected
		end
		validated[object] = {
			stamp = stamp,
			epoch = epoch,
			automatic = automatic,
			projected = hasProjection,
			projection = validationProjection,
		}
	end
	local function validateRoot(root: Instance)
		local parent = environment.parentOf(root)
		validate(
			root,
			if parent and environment.isA(parent, "GuiObject") then enum(parent, "AutomaticSize", "None") else "None"
		)
	end
	local function inset(object: Instance, rectangle: Rectangle): Rectangle
		if not object:IsA "GuiObject" and not object:IsA "LayerCollector" then
			return rectangle
		end
		local padding = paddingValue(object, "PaddingLeft")
		if padding == nil then
			return rectangle
		end
		local left = dimension(Values.dimension(padding), rectangle.width, rectangle.scale)
		local right =
			dimension(Values.dimension(paddingValue(object, "PaddingRight")), rectangle.width, rectangle.scale)
		local top = dimension(Values.dimension(paddingValue(object, "PaddingTop")), rectangle.height, rectangle.scale)
		local bottom =
			dimension(Values.dimension(paddingValue(object, "PaddingBottom")), rectangle.height, rectangle.scale)
		local automatic = enum(object, "AutomaticSize", "None")
		local scrolling = object:IsA "ScrollingFrame"
		return {
			x = rectangle.x + left,
			y = rectangle.y + top,
			width = math.max(0, rectangle.width - left - right),
			height = math.max(0, rectangle.height - top - bottom),
			scale = rectangle.scale,
			flexWidth = if scrolling and (automatic == "X" or automatic == "XY") then rectangle.width else nil,
			flexHeight = if scrolling and (automatic == "Y" or automatic == "XY") then rectangle.height else nil,
		}
	end
	local function scaledBounds(object: Instance, rectangle: Rectangle): TextMeasurement
		local measure = assert(options.measureBounds)
		local automatic = enum(object, "AutomaticSize", "None")
		local autoX, autoY = automatic == "X" or automatic == "XY", automatic == "Y" or automatic == "XY"
		local content = inset(object, rectangle)
		local smallest, largest = 1, 100
		local limit = object:FindFirstChildWhichIsA "UITextSizeConstraint"
		if limit then
			smallest = math.clamp(math.floor(number(limit, "MinTextSize", 1)), 1, 100)
			largest = math.clamp(math.floor(number(limit, "MaxTextSize", 100)), smallest, 100)
		end
		local text, font = Values.string(read(object, "Text")), Values.font(read(object, "FontFace"))
		local spacing = Float.f32(number(object, "LineHeight", 1))
		for points = largest, smallest, -1 do
			local fitted, measured = pcall(function(): Vector
				for word in text:gmatch "[^ \n]+" do
					local bounds =
						Values.vector(measure { Text = word, Font = font, Size = points, Width = 0, Gui = true })
					if not autoX and bounds.X > content.width then
						return { X = bounds.X, Y = math.huge }
					end
				end
				return Values.vector(measure {
					Text = text,
					Font = font,
					Size = points,
					Width = if autoX then 0 else content.width,
					Gui = true,
				})
			end)
			if fitted and measured.Y < math.huge then
				local strut = Values.vector(measure { Text = "", Font = font, Size = points, Width = 0, Gui = true }).Y
				local lines = math.round(measured.Y / strut)
				local height = if options.measureLineHeight
					then options.measureLineHeight(
						{ Text = text, Font = font, Size = points, Width = content.width, Gui = true },
						lines,
						spacing
					)
					else Float.f32(strut + Float.f32(spacing * strut) * (lines - 1))
				if (autoX or measured.X <= content.width) and (autoY or height <= content.height) then
					return { X = measured.X, Y = height, intrinsicX = measured.X, intrinsicY = height, fits = true }
				end
			end
		end
		return unsupported(object, "TextScaled text that does not fit at its smallest size")
	end
	local function textBounds(
		object: Instance,
		rectangle: Rectangle,
		intrinsic: boolean?,
		fixedWidth: boolean?
	): TextMeasurement?
		if options.measureBounds == nil or not (isText(object)) then
			return nil
		end
		if read(object, "TextScaled") == true and read(object, "TextWrapped") == true then
			return scaledBounds(object, rectangle)
		end
		local size = number(object, "TextSize", 14)
		local rendered = math.floor(size * rectangle.scale)
		if rendered < 1 or rendered > 100 then
			unsupported(object, "out-of-range rendered text size")
		end
		local content = inset(object, rectangle)
		local automatic = enum(object, "AutomaticSize", "None")
		local autoX, autoY =
			(automatic == "X" or automatic == "XY") and not fixedWidth, automatic == "Y" or automatic == "XY"
		local maximumX, maximumY = math.huge, math.huge
		local constraint = object:FindFirstChildWhichIsA "UISizeConstraint"
		if constraint then
			local maximum = Values.vector(read(constraint, "MaxSize"))
			maximumX = math.max(0, maximum.X * rectangle.scale - rectangle.width + content.width)
			maximumY = math.max(0, maximum.Y * rectangle.scale - rectangle.height + content.height)
		end
		local wrapped = read(object, "TextWrapped") == true
		local parameters: Values.TextParameters = {
			Text = Values.string(read(object, "Text")),
			Font = Values.font(read(object, "FontFace")),
			Size = rendered,
			Width = if wrapped then content.width else 0,
			RichText = read(object, "RichText") == true,
			Gui = true,
		}
		local intrinsicX = content.width
		if intrinsic and autoX then
			parameters.Width = 0
			local unwrapped = Values.vector(options.measureBounds(parameters))
			intrinsicX = math.min(math.max(content.width, unwrapped.X), maximumX)
			parameters.Width = if wrapped then intrinsicX else 0
		end
		local strut = Values.vector(
			options.measureBounds { Text = "", Font = parameters.Font, Size = rendered, Width = 0, Gui = true }
		)
		local truncation = enum(object, "TextTruncate", "None")
		local fitted, attempt =
			pcall(options.measureBounds, parameters, if not wrapped and not intrinsic then content.width else nil)
		if
			not fitted
			and wrapped
			and truncation ~= "None"
			and not intrinsic
			and tostring(attempt):find("word exceeds wrap width", 1, true)
			and content.height < strut.Y + Float.f32(Float.f32(number(object, "LineHeight", 1)) * strut.Y)
		then
			local truncate = options.truncateBounds
			local shown = if truncate
				then truncate({
					Text = parameters.Text,
					Font = parameters.Font,
					Size = parameters.Size,
					Width = content.width,
					RichText = parameters.RichText,
					Gui = true,
				}, truncation, 1, true)
				else nil
			if shown == nil then
				unsupported(object, "TextTruncate on text that does not fit")
			end
			return { X = assert(shown), Y = strut.Y, intrinsicX = assert(shown), intrinsicY = strut.Y, fits = false }
		elseif not fitted then
			error(attempt, 0)
		end
		local measured = Values.vector(attempt)
		local lines = math.round(measured.Y / strut.Y)
		local step = Float.f32(Float.f32(number(object, "LineHeight", 1)) * strut.Y)
		local function height(count: number): number
			if options.measureLineHeight then
				return options.measureLineHeight(parameters, count, number(object, "LineHeight", 1))
			end
			return Float.f32(strut.Y + step * (count - 1))
		end
		local fullHeight = height(lines)
		local availableHeight = if intrinsic and autoY then maximumY else content.height
		local visible = lines
		if wrapped then
			local low, high = 1, lines
			while low < high do
				local middle = math.ceil((low + high) / 2)
				if height(middle) <= availableHeight then
					low = middle
				else
					high = middle - 1
				end
			end
			visible = low
		elseif not intrinsic and lines > 1 and fullHeight > content.height then
			unsupported(object, "unwrapped multiline text exceeds available height")
		end
		local shownX = measured.X
		local overflowing = if wrapped then visible < lines else lines == 1 and measured.X > content.width
		if truncation ~= "None" and not intrinsic and overflowing then
			local truncate = options.truncateBounds
			local shown = if truncate
				then truncate({
					Text = parameters.Text,
					Font = parameters.Font,
					Size = parameters.Size,
					Width = content.width,
					RichText = parameters.RichText,
					Gui = true,
				}, truncation, visible, wrapped)
				else nil
			if shown == nil then
				unsupported(object, "TextTruncate on text that does not fit")
			end
			shownX = assert(shown)
		end
		return {
			X = shownX,
			Y = if wrapped and parameters.RichText and truncation == "None" then fullHeight else height(visible),
			intrinsicX = if intrinsic and autoX then intrinsicX else measured.X,
			intrinsicY = fullHeight,
			fits = measured.X <= content.width
				and (not wrapped and not parameters.RichText and automatic == "None" or fullHeight <= content.height),
		}
	end
	local bases: { [Instance]: { width: number, height: number } } = {}
	setmetatable(bases, { __mode = "ks" })
	type BasisWrite = { object: Instance, value: { width: number, height: number }? }
	type Measurement = {
		width: number,
		height: number,
		scale: number,
		override: number?,
		value: Rectangle,
		first: number,
		last: number,
	}
	local measurements: { [Instance]: { Measurement } }? = nil
	local basisWrites: { BasisWrite } = {}
	local function setBasis(object: Instance, width: number, height: number)
		local value = { width = width, height = height }
		bases[object] = value
		if measurements then
			table.insert(basisWrites, { object = object, value = value })
		end
	end
	local size: (Instance, Rectangle, number?) -> Rectangle
	local function measuredSize(object: Instance, parent: Rectangle): Rectangle
		return size(object, parent, nil)
	end
	local function reflowSize(object: Instance, parent: Rectangle, width: number): Rectangle
		return size(object, parent, width)
	end
	size = function(object: Instance, parent: Rectangle, widthOverride: number?): Rectangle
		bases[object] = nil
		if measurements then
			table.insert(basisWrites, { object = object })
		end
		local authored = Values.dimensions(read(object, "Size"))
		local scale = parent.scale
		local modifier = object:FindFirstChildWhichIsA "UIScale"
		if modifier then
			scale *= number(modifier, "Scale", 1)
		end
		local sizeConstraint = enum(object, "SizeConstraint", "RelativeXY")
		local width =
			dimension(authored.X, if sizeConstraint == "RelativeYY" then parent.height else parent.width, parent.scale)
		local height =
			dimension(authored.Y, if sizeConstraint == "RelativeXX" then parent.width else parent.height, parent.scale)
		local constraint = object:FindFirstChildWhichIsA "UISizeConstraint"
		if constraint then
			local minimum = Values.vector(read(constraint, "MinSize"))
			local maximum = Values.vector(read(constraint, "MaxSize"))
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
		if widthOverride ~= nil then
			rectangle.width = widthOverride
		end
		local aspect = object:FindFirstChildWhichIsA "UIAspectRatioConstraint"
		if aspect then
			local ratio = number(aspect, "AspectRatio", 1)
			if ratio <= 0 or ratio >= math.huge then
				unsupported(aspect, "invalid aspect ratio")
			end
			if enum(aspect, "AspectType", "FitWithinMaxSize") == "FitWithinMaxSize" then
				rectangle.width = math.min(rectangle.width, rectangle.height * ratio)
				rectangle.height = rectangle.width / ratio
			elseif enum(aspect, "DominantAxis", "Width") == "Width" then
				rectangle.width = math.min(rectangle.width, parent.width * factor, parent.height * ratio * factor)
				rectangle.height = rectangle.width / ratio
			else
				rectangle.height = math.min(rectangle.height, parent.height * factor, parent.width / ratio * factor)
				rectangle.width = rectangle.height * ratio
			end
		end
		local automatic = enum(object, "AutomaticSize", "None")
		if automatic == "None" then
			return rectangle
		end
		local autoX, autoY =
			(automatic == "X" or automatic == "XY") and widthOverride == nil, automatic == "Y" or automatic == "XY"
		local padding = paddingValue(object, "PaddingLeft")
		local paddingX, paddingY = 0, 0
		local scaledPadding = false
		if padding then
			for _, property in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
				local unit = Values.dimension(paddingValue(object, property))
				if unit.Scale ~= 0 then
					scaledPadding = true
				end
			end
			paddingX = (
				(Values.dimension(padding)).Offset + (Values.dimension(paddingValue(object, "PaddingRight"))).Offset
			) * scale
			paddingY = (
				(Values.dimension(paddingValue(object, "PaddingTop"))).Offset
				+ (Values.dimension(paddingValue(object, "PaddingBottom"))).Offset
			) * scale
		end
		local content = inset(object, rectangle)
		local grid = object:FindFirstChildWhichIsA "UIGridLayout"
		if grid and scaledPadding then
			unsupported(object, "AutomaticSize with scaled padding around a grid")
		end
		if grid then
			local cell = Values.dimensions(read(grid, "CellSize"))
			if (autoX and cell.X.Scale ~= 0) or (autoY and cell.Y.Scale ~= 0) then
				unsupported(grid, "grid cells relative to an automatic parent axis")
			end
			local measured = Grid.measure(grid, content, read)
			if autoX then
				rectangle.width = math.max(rectangle.width, measured.width + paddingX)
			end
			if autoY then
				rectangle.height = math.max(rectangle.height, measured.height + paddingY)
			end
			return rectangle
		end
		local list = object:FindFirstChildWhichIsA "UIListLayout"
		local horizontal = list ~= nil and enum(list, "FillDirection", "Vertical") == "Horizontal"
		local relativeX: Instance? = nil
		local relativeY: Instance? = nil
		for _, child in object:GetChildren() do
			if child:IsA "GuiObject" and read(child, "Visible") ~= false then
				local authoredChild = Values.dimensions(read(child, "Size"))
				local position = Values.dimensions(read(child, "Position"))
				local anchor = Values.vector(read(child, "AnchorPoint"))
				if
					autoX and (authoredChild.X.Scale ~= 0 or (list == nil and (position.X.Scale ~= 0 or anchor.X ~= 0)))
				then
					relativeX = child
				end
				if
					autoY and (authoredChild.Y.Scale ~= 0 or (list == nil and (position.Y.Scale ~= 0 or anchor.Y ~= 0)))
				then
					relativeY = child
				end
			end
		end
		local function firstSize(child: Instance, frame: Rectangle, alongX: boolean, alongY: boolean): Rectangle
			local dimensions = Values.dimensions(read(child, "Size"))
			local automatic = enum(child, "AutomaticSize", "None")
			local reference = table.clone(frame)
			if alongX and dimensions.X.Scale ~= 0 and (automatic == "X" or automatic == "XY") then
				reference.width = 0
			end
			if alongY and dimensions.Y.Scale ~= 0 and (automatic == "Y" or automatic == "XY") then
				reference.height = 0
			end
			return size(child, reference)
		end

		local function limited(frame: Rectangle): Rectangle
			if constraint == nil then
				return table.clone(frame)
			end
			local minimum = Values.vector(read(constraint, "MinSize"))
			local maximum = Values.vector(read(constraint, "MaxSize"))
			local result = table.clone(frame)
			result.width = math.clamp(frame.width, minimum.X * scale, math.max(minimum.X, maximum.X) * scale)
			result.height = math.clamp(frame.height, minimum.Y * scale, math.max(minimum.Y, maximum.Y) * scale)
			return result
		end
		local function requireStable(width: number, height: number)
			if autoX and relativeX and Float.f32(width) > Float.f32(rectangle.width) then
				unsupported(relativeX, "size relative to a growing automatic parent X axis")
			end
			if autoY and relativeY and Float.f32(height) > Float.f32(rectangle.height) then
				unsupported(relativeY, "size relative to a growing automatic parent Y axis")
			end
		end
		local function grow(width: number, height: number)
			if list then
				requireStable(width, height)
			end
			if autoX and (list == nil or relativeX == nil) then
				rectangle.width = math.max(rectangle.width, width)
			end
			if autoY and (list == nil or relativeY == nil) then
				rectangle.height = math.max(rectangle.height, height)
			end
		end
		if list and (relativeX or relativeY) and read(list, "Wraps") ~= true then
			local projected = table.clone(rectangle)
			if autoX and relativeX then
				projected.width = math.max(projected.width, parent.width * factor)
			end
			if autoY and relativeY then
				projected.height = math.max(projected.height, parent.height * factor)
			end
			local first = List.measure(list, inset(object, limited(projected)), read, function(child, frame)
				return firstSize(child, frame, not horizontal, horizontal)
			end, reflowSize)
			local basis: Rectangle = table.clone(rectangle)
			if autoX then
				basis.width = math.max(rectangle.width, first.width + paddingX)
			end
			if autoY then
				basis.height = math.max(rectangle.height, first.height + paddingY)
			end
			local reference = limited(basis)
			local second = List.measure(list, inset(object, table.clone(reference)), read, measuredSize, reflowSize)
			if autoX then
				rectangle.width = math.max(basis.width, second.width + paddingX)
			end
			if autoY then
				rectangle.height = math.max(basis.height, second.height + paddingY)
			end
			if rectangle.width ~= reference.width or rectangle.height ~= reference.height then
				setBasis(object, reference.width, reference.height)
			end
			return rectangle
		end
		if list and read(list, "Wraps") == true and not (if horizontal then autoX else autoY) then
			local measured = List.measure(list, content, read, measuredSize, reflowSize)
			grow(measured.width + paddingX, measured.height + paddingY)
			return rectangle
		end
		local gap = 0
		if list then
			local unit = Values.dimension(read(list, "Padding"))
			if unit.Scale ~= 0 then
				unsupported(object, "AutomaticSize with scaled list padding")
			end
			gap = unit.Offset * scale
		end
		local bounds = textBounds(object, rectangle, true, widthOverride ~= nil)
		local intrinsicWidth, intrinsicHeight, count =
			if bounds then bounds.intrinsicX else 0,
			if bounds then (if widthOverride ~= nil and autoY then bounds.intrinsicY else bounds.Y) else 0,
			0
		if list == nil and (relativeX or relativeY) then
			local function reach(frame: Rectangle, padded: boolean): (number, number)
				local inner = if padded then inset(object, frame) else table.clone(frame)
				local farX, farY = 0, 0
				for _, child in object:GetChildren() do
					if child:IsA "GuiObject" and read(child, "Visible") ~= false then
						local measured = if padded then size(child, inner) else firstSize(child, inner, true, true)
						local position = Values.dimensions(read(child, "Position"))
						local anchor = Values.vector(read(child, "AnchorPoint"))
						local x = dimension(position.X, inner.width, scale) - anchor.X * measured.width
						local y = dimension(position.Y, inner.height, scale) - anchor.Y * measured.height
						farX = math.max(farX, x + measured.width)
						farY = math.max(farY, y + measured.height)
					end
				end
				return farX + paddingX, farY + paddingY
			end
			local start: Rectangle = {
				x = 0,
				y = 0,
				width = if autoX then math.max(rectangle.width, intrinsicWidth + paddingX) else rectangle.width,
				height = if autoY then math.max(rectangle.height, intrinsicHeight + paddingY) else rectangle.height,
				scale = scale,
			}
			local firstX, firstY = reach(
				limited {
					x = 0,
					y = 0,
					width = if autoX then authored.X.Offset * scale else rectangle.width,
					height = if autoY then authored.Y.Offset * scale else rectangle.height,
					scale = scale,
				},
				false
			)
			local basis: Rectangle = {
				x = 0,
				y = 0,
				width = if autoX then math.max(start.width, firstX) else start.width,
				height = if autoY then math.max(start.height, firstY) else start.height,
				scale = scale,
			}
			local reference = limited(basis)
			local secondX, secondY = reach(reference, true)
			rectangle.width = if autoX then math.max(basis.width, secondX) else basis.width
			rectangle.height = if autoY then math.max(basis.height, secondY) else basis.height
			setBasis(object, reference.width, reference.height)
			return rectangle
		end
		for _, child in object:GetChildren() do
			if child:IsA "GuiObject" and read(child, "Visible") ~= false then
				local position = Values.dimensions(read(child, "Position"))
				local anchor = Values.vector(read(child, "AnchorPoint"))
				local childSize = size(child, content)
				if list then
					intrinsicWidth = if horizontal
						then intrinsicWidth + childSize.width
						else math.max(intrinsicWidth, childSize.width)
					intrinsicHeight = if horizontal
						then math.max(intrinsicHeight, childSize.height)
						else intrinsicHeight + childSize.height
				else
					intrinsicWidth =
						math.max(intrinsicWidth, position.X.Offset * scale + (1 - anchor.X) * childSize.width)
					intrinsicHeight =
						math.max(intrinsicHeight, position.Y.Offset * scale + (1 - anchor.Y) * childSize.height)
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
			if horizontal and autoY and not autoX and read(list, "Wraps") ~= true then
				intrinsicHeight = List.measure(list, content, read, measuredSize, reflowSize).height
			end
		end
		grow(intrinsicWidth + paddingX, intrinsicHeight + paddingY)
		if autoY then
			if widthOverride ~= nil and isText(object) and constraint then
				rectangle.height = math.min(rectangle.height, (Values.vector(read(constraint, "MaxSize"))).Y * scale)
			end
		end
		return rectangle
	end
	local calculateSize = size
	type KeptSize = {
		width: number,
		height: number,
		scale: number,
		override: number?,
		value: Rectangle,
		writes: { BasisWrite },
	}
	local keptSizes: { [Instance]: { stamp: number, epoch: number, entries: { KeptSize } } } = {}
	setmetatable(keptSizes, { __mode = "ks" })
	local measuredTrees: { [Instance]: { unknown } } = {}
	setmetatable(measuredTrees, { __mode = "ks" })
	local placedTrees: { [Instance]: { unknown } } = {}
	setmetatable(placedTrees, { __mode = "ks" })
	local function unchangedSince(
		store: { [Instance]: { unknown } },
		object: Instance,
		parent: Rectangle,
		placed: Rectangle?,
		around: { Turn }?
	): boolean
		local key: { unknown } = {
			environment.layoutStamp(object),
			environment.layoutEpoch(),
			if validated[object] and validated[object].projected then validationProjection or false else false,
			parent.x,
			parent.y,
			parent.width,
			parent.height,
			parent.scale,
			if placed then placed.x else false,
			if placed then placed.y else false,
			if placed then placed.width else false,
			if placed then placed.height else false,
			if placed then placed.scale else false,
		}
		if around then
			for _, turn in around do
				table.insert(key, turn.x)
				table.insert(key, turn.y)
				table.insert(key, turn.angle)
			end
		end
		local previous = store[object]
		store[object] = key
		if previous == nil or #previous ~= #key then
			return false
		end
		for index, value in key do
			if previous[index] ~= value then
				return false
			end
		end
		return true
	end
	size = function(object: Instance, parent: Rectangle, widthOverride: number?): Rectangle
		local cache = measurements
		if cache == nil then
			local kept = keptSizes[object]
			if
				kept ~= nil
				and kept.stamp == environment.layoutStamp(object)
				and kept.epoch == environment.layoutEpoch()
			then
				for _, entry in kept.entries do
					if
						entry.width == parent.width
						and entry.height == parent.height
						and entry.scale == parent.scale
						and entry.override == widthOverride
					then
						for _, write in entry.writes do
							bases[write.object] = write.value
						end
						return table.clone(entry.value)
					end
				end
			end
			return calculateSize(object, parent, widthOverride)
		end
		local entries = cache[object]
		if entries then
			for _, entry in entries do
				if
					entry.width == parent.width
					and entry.height == parent.height
					and entry.scale == parent.scale
					and entry.override == widthOverride
				then
					for index = entry.first, entry.last do
						local write = basisWrites[index]
						bases[write.object] = write.value
						table.insert(basisWrites, write)
					end
					return table.clone(entry.value)
				end
			end
		else
			entries = {}
			cache[object] = entries
		end
		local stamp, epoch = environment.layoutStamp(object), environment.layoutEpoch()
		local kept = keptSizes[object]
		if kept == nil or kept.stamp ~= stamp or kept.epoch ~= epoch then
			kept = { stamp = stamp, epoch = epoch, entries = {} }
			keptSizes[object] = kept
		end
		local first = #basisWrites + 1
		for _, entry in kept.entries do
			if
				entry.width == parent.width
				and entry.height == parent.height
				and entry.scale == parent.scale
				and entry.override == widthOverride
			then
				for _, write in entry.writes do
					bases[write.object] = write.value
					table.insert(basisWrites, write)
				end
				table.insert(entries, {
					width = parent.width,
					height = parent.height,
					scale = parent.scale,
					override = widthOverride,
					value = entry.value,
					first = first,
					last = #basisWrites,
				})
				return table.clone(entry.value)
			end
		end
		local value = calculateSize(object, parent, widthOverride)
		local writes = table.move(basisWrites, first, #basisWrites, 1, {})
		table.insert(entries, {
			width = parent.width,
			height = parent.height,
			scale = parent.scale,
			override = widthOverride,
			value = table.clone(value),
			first = first,
			last = #basisWrites,
		})
		table.insert(kept.entries, {
			width = parent.width,
			height = parent.height,
			scale = parent.scale,
			override = widthOverride,
			value = table.clone(value),
			writes = writes,
		})
		return value
	end
	local turns: { [Instance]: { Turn } } = {}
	setmetatable(turns, { __mode = "ks" })
	local frames: { [Instance]: Rectangle } = {}
	local step: (Instance?) -> ()
	local attached: Controller
	local selectionScroll = SelectionScroll.attach(environment, read, vector, function(object)
		return frames[object] ~= nil
	end, function()
		step()
	end)
	setmetatable(frames, { __mode = "ks" })
	local scrollingProperties = { "AbsoluteSize", "AbsoluteWindowSize", "AbsoluteCanvasSize" }
	local scrollingGeometry: { [Instance]: { [string]: Vector } } = {}
	setmetatable(scrollingGeometry, { __mode = "ks" })
	local function scrollingBounds(object: Instance): { [string]: Vector }
		local bounds: { [string]: Vector } = {}
		for _, property in scrollingProperties do
			local value = environment.propertyOf(object, property)
			bounds[property] = if value == nil then { X = 0, Y = 0 } else Values.vector(value)
		end
		return bounds
	end
	local function rotate(x: number, y: number, turn: Turn, sign: number): (number, number)
		local radians = math.rad(turn.angle) * sign
		local cosine, sine = math.cos(radians), math.sin(radians)
		local dx, dy = x - turn.x, y - turn.y
		return turn.x + dx * cosine - dy * sine, turn.y + dx * sine + dy * cosine
	end
	local function measure(target: Instance?)
		local roots = options.roots()
		if target then
			local ancestry: { [Instance]: boolean } = {}
			local current: Instance? = target
			while current do
				ancestry[current] = true
				current = environment.parentOf(current)
			end
			local affected: { Instance } = {}
			for _, root in roots do
				if ancestry[root] then
					table.insert(affected, root)
				end
			end
			roots = affected
		end
		for _, root in roots do
			selectionScroll.watch(root)
		end
		validationProjection = if options.projection then options.projection.revision() else nil
		for _, root in roots do
			validateRoot(root)
		end
		local viewport = options.viewport()
		local origin = if options.origin then options.origin() else { X = 0, Y = 0 }
		local screen: Rectangle = { x = origin.X, y = origin.Y, width = viewport.X, height = viewport.Y, scale = 1 }
		local function area(object: Instance, parent: Rectangle): Rectangle
			local projection = projected[object]
			if projection then
				return {
					x = projection.x,
					y = projection.y,
					width = projection.width,
					height = projection.height,
					scale = 1,
				}
			end
			local screenArea = options.screenArea
			if screenArea and object:IsA "ScreenGui" then
				local found = screenArea(object)
				return { x = found.x, y = found.y, width = found.width, height = found.height, scale = 1 }
			end
			return parent
		end
		type Canvas = { content: Rectangle, window: Vector, canvas: Vector, position: Vector }
		local function canvasOf(object: Instance, rectangle: Rectangle, parent: Rectangle): Canvas
			local scale = rectangle.scale
			local thickness = (number(object, "ScrollBarThickness", 12) + number(object, "BorderSizePixel", 1)) * scale
			local direction = enum(object, "ScrollingDirection", "XY")
			local alongX, alongY = direction ~= "Y", direction ~= "X"
			local authored = Values.dimensions(read(object, "CanvasSize"))
			local authoredX = dimension(authored.X, parent.width, parent.scale)
				* scale
				/ math.max(parent.scale, 0.000001)
			local authoredY = dimension(authored.Y, parent.height, parent.scale)
				* scale
				/ math.max(parent.scale, 0.000001)
			local automatic = enum(object, "AutomaticCanvasSize", "None")
			local insetX = enum(object, "VerticalScrollBarInset", "None")
			local insetY = enum(object, "HorizontalScrollBarInset", "None")
			local function reserve(inset: string, shown: boolean): number
				return if inset == "Always" or (inset == "ScrollBar" and shown) then thickness else 0
			end
			local function extent(width: number, height: number): (number, number)
				if automatic == "None" then
					return 0, 0
				end
				local probe: Rectangle = { x = 0, y = 0, width = width, height = height, scale = scale }
				local inner = inset(object, probe)
				local padX, padY = width - inner.width, height - inner.height
				local list = object:FindFirstChildWhichIsA "UIListLayout"
				local grid = object:FindFirstChildWhichIsA "UIGridLayout"
				if grid then
					local measured = Grid.measure(grid, inner, read)
					return measured.width + padX, measured.height + padY
				elseif list then
					local measured = List.measure(list, inner, read, measuredSize, reflowSize)
					return measured.width + padX, measured.height + padY
				end
				local farX, farY = 0, 0
				for _, child in object:GetChildren() do
					if child:IsA "GuiObject" and read(child, "Visible") ~= false then
						local measured = size(child, inner)
						local position = Values.dimensions(read(child, "Position"))
						local anchor = Values.vector(read(child, "AnchorPoint"))
						farX =
							math.max(farX, dimension(position.X, inner.width, scale) + (1 - anchor.X) * measured.width)
						farY = math.max(
							farY,
							dimension(position.Y, inner.height, scale) + (1 - anchor.Y) * measured.height
						)
					end
				end
				return farX + padX, farY + padY
			end
			local showX, showY = false, false
			local canvasX: number = 0
			local canvasY: number = 0
			for _ = 1, 3 do
				local baseX = rectangle.width - reserve(insetX, showY)
				local baseY = rectangle.height - reserve(insetY, showX)
				canvasX = math.max(authoredX, baseX)
				canvasY = math.max(authoredY, baseY)
				local contentX, contentY = extent(canvasX, canvasY)
				if automatic == "X" or automatic == "XY" then
					canvasX = math.max(canvasX, contentX)
				end
				if automatic == "Y" or automatic == "XY" then
					canvasY = math.max(canvasY, contentY)
				end
				local nextY = alongY and canvasY > rectangle.height - reserve(insetY, showX)
				local nextX = alongX and canvasX > rectangle.width - reserve(insetX, showY)
				if nextX == showX and nextY == showY then
					break
				end
				showX, showY = nextX, nextY
			end
			local windowX = rectangle.width - (if showY then thickness else 0)
			local windowY = rectangle.height - (if showX then thickness else 0)
			local maxX = math.max(0, canvasX - (rectangle.width - reserve(insetX, showY)))
			local maxY = math.max(0, canvasY - (rectangle.height - reserve(insetY, showX)))
			local requested = Values.vector(read(object, "CanvasPosition"))
			local position = {
				X = math.clamp(requested.X, 0, maxX),
				Y = math.clamp(requested.Y, 0, maxY),
			}
			local content = inset(object, {
				x = rectangle.x - position.X,
				y = rectangle.y - position.Y,
				width = canvasX,
				height = canvasY,
				scale = scale,
			})
			return {
				content = content,
				window = { X = windowX, Y = windowY },
				canvas = { X = canvasX, Y = canvasY },
				position = position,
			}
		end
		local function validateScrollingGeometry(object: Instance, rectangle: Rectangle, scrolled: Canvas)
			local requested = Values.vector(read(object, "CanvasPosition"))
			local position = scrolled.position
			if position.X ~= requested.X or position.Y ~= requested.Y then
				local supplied = scrollingBounds(object)
				local previous = scrollingGeometry[object]
				local computed = {
					AbsoluteSize = { X = rectangle.width, Y = rectangle.height },
					AbsoluteWindowSize = scrolled.window,
					AbsoluteCanvasSize = scrolled.canvas,
				}
				local stale: { string } = {}
				local details: { string } = {}
				for _, property in scrollingProperties do
					local value = supplied[property]
					local measured = if previous then previous[property] else { X = 0, Y = 0 }
					if value.X ~= measured.X or value.Y ~= measured.Y then
						table.insert(stale, property)
					end
					local nextValue = computed[property]
					table.insert(details, `{property}=({value.X}, {value.Y}), computed=({nextValue.X}, {nextValue.Y})`)
				end
				if #stale > 0 then
					unsupported(
						object,
						"layout-owned scrolling geometry before clamping CanvasPosition; stale/poked "
							.. table.concat(stale, ", ")
							.. "; "
							.. table.concat(details, "; ")
							.. `; CanvasPosition=({requested.X}, {requested.Y}), computed=({position.X}, {position.Y}); author Size and CanvasSize or exclude the poked frame from layout roots`
					)
				end
			end
		end
		local measureTree: (Instance, Rectangle, Rectangle?) -> ()
		measureTree = function(object: Instance, parent: Rectangle, placed: Rectangle?)
			if projected[object] == false then
				return
			end
			if unchangedSince(measuredTrees, object, parent, placed, nil) then
				return
			end
			local rectangle = if object:IsA "GuiObject" then placed or size(object, parent) else area(object, parent)
			if
				placed
				and (isText(object))
				and read(object, "TextWrapped") == true
				and enum(object, "AutomaticSize", "None") ~= "None"
				and not (object.Parent and object.Parent:FindFirstChildWhichIsA "UIGridLayout")
			then
				local list = if object.Parent then object.Parent:FindFirstChildWhichIsA "UIListLayout" else nil
				local reflowed = list ~= nil
					and (
						(
							enum(list, "FillDirection", "Vertical") == "Vertical"
							and read(list, "Wraps") ~= true
							and enum(list, "HorizontalFlex", "None") == "Fill"
						) or enum(list, "FillDirection", "Vertical") == "Horizontal"
					)
				if not reflowed and placed.width ~= size(object, parent).width then
					unsupported(object, "wrapped automatic text with an unmodeled flexed width")
				end
			end
			textBounds(object, rectangle)
			local basis = bases[object]
			local scrolled = if object:IsA "ScrollingFrame" then canvasOf(object, rectangle, parent) else nil
			if scrolled then
				validateScrollingGeometry(object, rectangle, scrolled)
			end
			local content = if scrolled
				then scrolled.content
				else inset(
					object,
					if basis
						then {
							x = rectangle.x,
							y = rectangle.y,
							width = basis.width,
							height = basis.height,
							scale = rectangle.scale,
						}
						else rectangle
				)
			local placements: { [Instance]: Rectangle } = {}
			local grid = object:FindFirstChildWhichIsA "UIGridLayout"
			local list = object:FindFirstChildWhichIsA "UIListLayout"
			if grid then
				for _, item in Grid.measure(grid, content, read).items do
					placements[item.object] = item.rectangle
				end
			elseif list then
				for _, item in List.measure(list, content, read, measuredSize, reflowSize).items do
					placements[item.object] = item.rectangle
				end
			end
			for _, child in object:GetChildren() do
				measureTree(child, content, placements[child])
			end
		end
		measurements = {}
		local measured, failure = pcall(function()
			for _, root in roots do
				measureTree(root, screen, nil)
			end
		end)
		measurements = nil
		table.clear(basisWrites)
		if not measured then
			error(failure, 0)
		end
		local function publish(object: Instance, rectangle: Rectangle, around: { Turn })
			local bounds = textBounds(object, rectangle)
			if bounds then
				environment.publish(object, "TextBounds", vector(bounds.X, bounds.Y))
				environment.publish(object, "TextFits", bounds.fits)
			end
			local x, y = rectangle.x + rectangle.width / 2, rectangle.y + rectangle.height / 2
			local angle = 0
			for _, turn in around do
				x, y = rotate(x, y, turn, 1)
				angle += turn.angle
			end
			frames[object], turns[object] = rectangle, around
			environment.publish(object, "AbsolutePosition", vector(x - rectangle.width / 2, y - rectangle.height / 2))
			environment.publish(object, "AbsoluteSize", vector(rectangle.width, rectangle.height))
			if object:IsA "GuiObject" then
				environment.publish(object, "AbsoluteRotation", angle + number(object, "Rotation", 0))
			end
		end
		local visit: (Instance, Rectangle, Rectangle?, { Turn }) -> ()
		visit = function(object: Instance, parent: Rectangle, placed: Rectangle?, around: { Turn })
			if projected[object] == false then
				return
			end
			if object:IsA "LayerCollector" then
				around = {}
			end
			if unchangedSince(placedTrees, object, parent, placed, around) then
				return
			end
			local rectangle = area(object, parent)
			if object:IsA "GuiObject" then
				rectangle = placed or size(object, parent)
				if placed == nil then
					local position = Values.dimensions(read(object, "Position"))
					local anchor = Values.vector(read(object, "AnchorPoint"))
					rectangle.x = parent.x
						+ dimension(position.X, parent.width, parent.scale)
						- anchor.X * rectangle.width
					rectangle.y = parent.y
						+ dimension(position.Y, parent.height, parent.scale)
						- anchor.Y * rectangle.height
				end
				publish(object, rectangle, around)
				local angle = number(object, "Rotation", 0)
				if angle ~= 0 then
					local inner = table.clone(around)
					table.insert(inner, 1, {
						x = rectangle.x + rectangle.width / 2,
						y = rectangle.y + rectangle.height / 2,
						angle = angle,
					})
					around = inner
				end
			elseif object:IsA "ScreenGui" or object:IsA "BillboardGui" then
				publish(object, rectangle, around)
			end
			local basis = bases[object]
			local content = inset(
				object,
				if basis
					then {
						x = rectangle.x,
						y = rectangle.y,
						width = basis.width,
						height = basis.height,
						scale = rectangle.scale,
					}
					else rectangle
			)
			if object:IsA "ScrollingFrame" then
				local scrolled = canvasOf(object, rectangle, parent)
				content = scrolled.content
				environment.publish(object, "AbsoluteWindowSize", vector(scrolled.window.X, scrolled.window.Y))
				environment.publish(object, "AbsoluteCanvasSize", vector(scrolled.canvas.X, scrolled.canvas.Y))
				local requested = Values.vector(read(object, "CanvasPosition"))
				if requested.X ~= scrolled.position.X or requested.Y ~= scrolled.position.Y then
					environment.publish(object, "CanvasPosition", vector(scrolled.position.X, scrolled.position.Y))
				end
				scrollingGeometry[object] = scrollingBounds(object)
			end
			local list = object:FindFirstChildWhichIsA "UIListLayout"
			local grid = object:FindFirstChildWhichIsA "UIGridLayout"
			local children = object:GetChildren()
			local placements: { [Instance]: Rectangle } = {}
			if grid then
				local measured = Grid.measure(grid, content, read)
				for _, item in measured.items do
					placements[item.object] = item.rectangle
				end
				environment.publish(grid, "AbsoluteContentSize", vector(measured.width, measured.height))
				environment.publish(grid, "AbsoluteCellSize", vector(measured.cellWidth, measured.cellHeight))
				environment.publish(grid, "AbsoluteCellCount", vector(measured.columns, measured.rows))
			elseif list then
				local measured = List.measure(list, content, read, measuredSize, reflowSize)
				for _, item in measured.items do
					placements[item.object] = item.rectangle
				end
				environment.publish(list, "AbsoluteContentSize", vector(measured.width, measured.height))
			end
			for _, child in children do
				visit(child, content, placements[child], around)
			end
		end
		for _, root in roots do
			visit(root, screen, nil, {})
		end
	end
	local measuring = false
	local pending = false
	local pendingAll = false
	local settledAt: number? = nil
	local settledX, settledY, settledRoots = 0, 0, 0
	local settledProjection: number? = nil
	step = function(target: Instance?)
		pending = true
		if measuring then
			pendingAll = true
			return
		end
		local viewport = options.viewport()
		local rootCount = #options.roots()
		local projectionRevision = if options.projection then options.projection.revision() else nil
		local before, publishedBefore = environment.revision()
		local busy = attached.busy ~= nil and attached.busy()
		if
			not busy
			and settledAt == before
			and settledX == viewport.X
			and settledY == viewport.Y
			and settledRoots == rootCount
			and settledProjection == projectionRevision
		then
			pending = false
			return
		end
		settledAt = nil
		measuring = true
		repeat
			pending = false
			if pendingAll then
				target = nil
				pendingAll = false
			end
			local ok, problem = pcall(measure, target)
			if not ok then
				measuring = false
				error(problem, 0)
			end
		until not pending
		measuring = false
		local after, publishedAfter = environment.revision()
		if target == nil and not busy and after == before and publishedAfter == publishedBefore then
			settledAt, settledX, settledY, settledRoots = after, viewport.X, viewport.Y, rootCount
			settledProjection = projectionRevision
		end
	end
	local function objectsAtPosition(
		root: Instance,
		rawX: number,
		rawY: number,
		candidates: { Instance }?
	): { Instance }
		assert(
			rawX == rawX and rawY == rawY and math.abs(rawX) < math.huge and math.abs(rawY) < math.huge,
			"hit testing requires finite coordinates"
		)
		local x, y = math.floor(rawX + 0.5), math.floor(rawY + 0.5)
		local wanted: { [Instance]: boolean }? = nil
		if candidates then
			local nodes: { [Instance]: boolean } = {}
			for _, candidate in candidates do
				if not environment.isAlive(candidate) then
					continue
				end
				local current: Instance? = candidate
				while current and not nodes[current] do
					nodes[current] = true
					current = environment.parentOf(current)
				end
			end
			if not nodes[root] then
				return {}
			end
			wanted = nodes
		else
			validationProjection = if options.projection then options.projection.revision() else nil
			validateRoot(root)
		end
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
		local function contains(object: Instance): boolean
			local frame = frames[object]
			local around = turns[object]
			if frame and around and (#around > 0 or number(object, "Rotation", 0) ~= 0) then
				local own = number(object, "Rotation", 0)
				local chain = table.clone(around)
				if own ~= 0 then
					table.insert(
						chain,
						1,
						{ x = frame.x + frame.width / 2, y = frame.y + frame.height / 2, angle = own }
					)
				end
				local px, py = x, y
				for ordinal = #chain, 1, -1 do
					px, py = rotate(px, py, chain[ordinal], -1)
				end
				return frame.width > 0
					and frame.height > 0
					and px >= frame.x
					and py >= frame.y
					and px <= frame.x + frame.width
					and py <= frame.y + frame.height
			end
			local at = Values.vector(environment.propertyOf(object, "AbsolutePosition"))
			local size = Values.vector(environment.propertyOf(object, "AbsoluteSize"))
			assert(at ~= nil and size ~= nil, "hit testing requires published layout")
			return size.X > 0 and size.Y > 0 and x >= at.X and y >= at.Y and x <= at.X + size.X and y <= at.Y + size.Y
		end
		local visit: (Instance, Instance?, { Order }, number, boolean) -> ()

		visit = function(object: Instance, screen: Instance?, path: { Order }, sibling: number, clipped: boolean)
			if object:IsA "ScreenGui" then
				if read(object, "Enabled") == false then
					return
				end
				screen = object
				path = {}
			elseif object:IsA "LayerCollector" then
				if read(object, "Enabled") == false then
					return
				end
				unsupported(object, object.ClassName .. " hit testing")
			end
			if object:IsA "GuiObject" then
				if read(object, "Visible") == false then
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
				if inside and not clipped and (candidates == nil or table.find(candidates, object)) then
					local mode = enum(assert(screen), "ZIndexBehavior", "Sibling")
					if mode ~= "Sibling" and mode ~= "Global" then
						unsupported(object, "ZIndexBehavior." .. mode)
					end
					table.insert(hits, {
						object = object,
						screen = assert(screen),
						display = number(assert(screen), "DisplayOrder", 0),
						mode = mode,
						z = number(object, "ZIndex", 1),
						index = index,
						path = path,
					})
				end
				local around = turns[object]
				local rotated = number(object, "Rotation", 0) ~= 0 or around ~= nil and #around > 0
				clipped = clipped or read(object, "ClipsDescendants") == true and not rotated and not inside
			end
			local folder = object:IsA "Folder"
			local required = wanted
			for ordinal, child in object:GetChildren() do
				if required and not required[child] then
					continue
				end
				if
					child:IsA "GuiObject"
					and not object:IsA "GuiObject"
					and not object:IsA "ScreenGui"
					and not folder
				then
					unsupported(child, "non-GuiObject hit-testing parent")
				end
				visit(child, screen, path, if folder then sibling + ordinal / 1000 else ordinal, clipped)
			end
		end
		visit(root, nil, {}, 1, false)
		table.sort(hits, function(a: Hit, b: Hit): boolean
			if a.display ~= b.display then
				return a.display > b.display
			end
			if a.screen ~= b.screen then
				return assert(environment.descendantOrderOf(root, a.screen))
					> assert(environment.descendantOrderOf(root, b.screen))
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
	local controller: Controller = {
		step = function()
			step(nil)
		end,
		flush = function(object: Instance)
			step(object)
		end,
		busy = nil,
		objectsAtPosition = objectsAtPosition,
		close = selectionScroll.close,
	}
	attached = controller
	return attached
end

return { attach = attach }
