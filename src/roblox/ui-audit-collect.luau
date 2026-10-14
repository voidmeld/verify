--!strict
--!nolint DeprecatedApi

local Audit = require "./ui-audit"

export type Options = {
	game: unknown?,
	roots: { unknown }?,
	world: boolean?,
	device: string?,
	scale: number?,
	input: { string }?,
	safeArea: Audit.Rect?,
	safeAreaRoot: unknown?,
	maxElements: number?,
	stateStyled: ((instance: unknown) -> boolean)?,
}

type Object = { [string]: unknown }

local DIRECTIONS = { "Up", "Down", "Left", "Right" }

local function read(object: unknown, key: string): unknown
	if object == nil then
		return nil
	end
	local ok, value = pcall(function(): unknown
		return (object :: Object)[key]
	end)
	if ok then
		return value
	end
	return nil
end

local function call(object: unknown, method: string, ...: unknown): (boolean, unknown, unknown)
	local callback = read(object, method)
	if type(callback) ~= "function" then
		return false, nil, nil
	end
	local fn = callback :: (...unknown) -> (unknown, unknown)
	local ok, first, second = pcall(fn, object, ...)
	if not ok then
		return false, nil, nil
	end
	return true, first, second
end

local function isA(object: unknown, class: string): boolean
	local ok, answer = call(object, "IsA", class)
	return ok and answer == true
end

local function numberOf(value: unknown, fallback: number): number
	if type(value) == "number" and value == value and math.abs(value) ~= math.huge then
		return value
	end
	return fallback
end

local function vector(value: unknown): (number, number)
	return numberOf(read(value, "X"), 0), numberOf(read(value, "Y"), 0)
end

local function colorOf(value: unknown): Audit.Color
	return {
		r = numberOf(read(value, "R"), 0),
		g = numberOf(read(value, "G"), 0),
		b = numberOf(read(value, "B"), 0),
	}
end

local function enumName(value: unknown): string?
	local name = read(value, "Name")
	if type(name) == "string" then
		return name
	end
	return nil
end

local function textOf(value: unknown): string?
	if type(value) == "string" then
		return value
	end
	return nil
end

local function children(object: unknown): { unknown }
	local ok, list = call(object, "GetChildren")
	if ok and type(list) == "table" then
		return list :: { unknown }
	end
	return {}
end

local function fullName(object: unknown): string
	local ok, name = call(object, "GetFullName")
	if ok and type(name) == "string" then
		return name
	end
	return textOf(read(object, "Name")) or "?"
end

local function intersect(left: Audit.Rect?, right: Audit.Rect?): Audit.Rect?
	return Audit.intersect(left, right)
end

local function offsetOf(udim: unknown, size: number): number
	return numberOf(read(udim, "Offset"), 0) + numberOf(read(udim, "Scale"), 0) * size
end

local function rendersSomething(object: unknown, depth: number): boolean
	if object == nil or depth > 3 then
		return false
	end
	if isA(object, "GuiObject") then
		if read(object, "Visible") == false then
			return false
		end
		if numberOf(read(object, "BackgroundTransparency"), 1) < 1 then
			return true
		end
		local image = textOf(read(object, "Image"))
		if image ~= nil and image ~= "" and numberOf(read(object, "ImageTransparency"), 0) < 1 then
			return true
		end
	end
	for _, child in children(object) do
		if isA(child, "UIStroke") then
			if
				read(child, "Enabled") ~= false
				and numberOf(read(child, "Transparency"), 0) < 1
				and numberOf(read(child, "Thickness"), 1) > 0
			then
				return true
			end
		elseif rendersSomething(child, depth + 1) then
			return true
		end
	end
	return false
end

local function service(game: unknown, name: string): unknown
	local ok, found = call(game, "GetService", name)
	if ok then
		return found
	end
	return nil
end

local function collect(options: Options?): Audit.Dump
	local given: Options = options or {}
	local game = given.game
	if game == nil then
		game = (getfenv(0) :: { [string]: unknown }).game
	end
	local guiService = service(game, "GuiService")
	local players = service(game, "Players")
	local workspace = service(game, "Workspace")
	local player = read(players, "LocalPlayer")
	local _, playerGui = call(player, "FindFirstChildOfClass", "PlayerGui")
	local camera = read(workspace, "CurrentCamera")
	local width, height = vector(read(camera, "ViewportSize"))
	local insetOk, topLeft, bottomRight = call(guiService, "GetGuiInset")
	local insetLeft, insetTop = 0, 0
	local insetRight, insetBottom = 0, 0
	if insetOk then
		insetLeft, insetTop = vector(topLeft)
		insetRight, insetBottom = vector(bottomRight)
	end
	local maxElements = given.maxElements or 5000
	local defaultSelection = read(playerGui, "SelectionImageObject")

	local roots: { unknown } = {}
	if given.roots ~= nil then
		roots = table.clone(given.roots :: { unknown })
	else
		local sources: { unknown } = {}
		for _, child in children(playerGui) do
			if isA(child, "LayerCollector") then
				table.insert(sources, child)
			end
		end
		if #sources == 0 then
			for _, child in children(service(game, "StarterGui")) do
				if isA(child, "LayerCollector") then
					table.insert(sources, child)
				end
			end
		end
		roots = sources
		if given.world == true then
			local ok, descendants = call(workspace, "GetDescendants")
			if ok and type(descendants) == "table" then
				for _, item in descendants :: { unknown } do
					if isA(item, "SurfaceGui") or isA(item, "BillboardGui") then
						table.insert(roots, item)
					end
				end
			end
		end
	end

	local dumpRoots: { Audit.Root } = {}
	local elements: { Audit.Element } = {}
	local indexOf: { [unknown]: number } = {}
	local pending: { { element: Audit.Element, instance: unknown } } = {}
	local instances = 0
	local truncated = false

	local function rectOf(object: unknown, world: boolean): Audit.Rect
		local x, y = vector(read(object, "AbsolutePosition"))
		local w, h = vector(read(object, "AbsoluteSize"))
		if world then
			return { x = x, y = y, width = w, height = h }
		end
		return { x = x + insetLeft, y = y + insetTop, width = w, height = h }
	end

	local function visit(
		object: unknown,
		rootIndex: number,
		world: boolean,
		parent: number?,
		shown: boolean,
		clip: Audit.Rect?,
		scrollClip: Audit.Rect?
	)
		for _, child in children(object) do
			instances += 1
			if isA(child, "GuiObject") then
				if #elements >= maxElements then
					truncated = true
					continue
				end
				local rect = rectOf(child, world)
				local visible = shown and read(child, "Visible") ~= false
				local element: Audit.Element = {
					index = #elements + 1,
					parent = parent,
					root = rootIndex,
					class = textOf(read(child, "ClassName")) or "GuiObject",
					path = fullName(child),
					rect = rect,
					rotation = numberOf(read(child, "AbsoluteRotation"), numberOf(read(child, "Rotation"), 0)),
					visible = visible,
					clip = clip,
					scrollClip = scrollClip,
					zIndex = numberOf(read(child, "ZIndex"), 1),
					order = #elements + 1,
					interactive = isA(child, "GuiButton") or isA(child, "TextBox"),
					selectable = read(child, "Selectable") == true,
					active = read(child, "Active") == true,
					interactable = read(child, "Interactable") ~= false,
					guiState = enumName(read(child, "GuiState")),
					next = {},
					selectionGroup = read(child, "SelectionGroup") == true,
					stops = {},
					background = {
						color = colorOf(read(child, "BackgroundColor3")),
						transparency = math.clamp(numberOf(read(child, "BackgroundTransparency"), 1), 0, 1),
					},
					image = nil,
					text = nil,
					focus = nil,
					padding = nil,
					layout = nil,
				}
				for _, direction in DIRECTIONS do
					if enumName(read(child, "SelectionBehavior" .. direction)) == "Stop" then
						table.insert(element.stops, string.lower(direction))
					end
				end
				if isA(child, "ImageLabel") or isA(child, "ImageButton") then
					local image = textOf(read(child, "Image"))
					if image ~= nil and image ~= "" then
						element.image = {
							transparency = math.clamp(numberOf(read(child, "ImageTransparency"), 0), 0, 1),
						}
					end
				end
				if isA(child, "TextLabel") or isA(child, "TextButton") or isA(child, "TextBox") then
					local boundsX, boundsY = vector(read(child, "TextBounds"))
					local face = read(child, "FontFace")
					local weight = numberOf(read(read(face, "Weight"), "Value"), 400)
					local fits = read(child, "TextFits")
					element.text = {
						content = textOf(read(child, "ContentText")) or textOf(read(child, "Text")) or "",
						size = numberOf(read(child, "TextSize"), 14),
						bounds = { width = boundsX, height = boundsY },
						fits = if type(fits) == "boolean" then fits else nil,
						scaled = read(child, "TextScaled") == true,
						wrapped = read(child, "TextWrapped") == true,
						truncate = enumName(read(child, "TextTruncate")),
						font = textOf(read(face, "Family")),
						bold = weight >= 600,
						color = colorOf(read(child, "TextColor3")),
						transparency = math.clamp(numberOf(read(child, "TextTransparency"), 0), 0, 1),
					}
				end
				if element.interactive then
					local selection = read(child, "SelectionImageObject")
					if selection == nil then
						selection = defaultSelection
					end
					local state = "default"
					if selection ~= nil then
						state = if rendersSomething(selection, 0) then "visible" else "hidden"
					end
					local hover = textOf(read(child, "HoverImage"))
					local pressed = textOf(read(child, "PressedImage"))
					local auto = read(child, "AutoButtonColor")
					element.focus = {
						selectionImage = state :: "default" | "visible" | "hidden",
						autoButtonColor = if type(auto) == "boolean" then auto else nil,
						hoverImage = hover ~= nil and hover ~= "",
						pressedImage = pressed ~= nil and pressed ~= "",
						stateStyled = given.stateStyled ~= nil and given.stateStyled(child) == true,
					}
				end
				table.insert(elements, element)
				indexOf[child] = element.index
				table.insert(pending, { element = element, instance = child })
				local innerClip = clip
				local innerScroll = scrollClip
				if isA(child, "ScrollingFrame") then
					local windowX, windowY = vector(read(child, "AbsoluteWindowSize"))
					local window: Audit.Rect = {
						x = rect.x,
						y = rect.y,
						width = if windowX > 0 then windowX else rect.width,
						height = if windowY > 0 then windowY else rect.height,
					}
					innerScroll = intersect(scrollClip, window)
				elseif read(child, "ClipsDescendants") == true or isA(child, "CanvasGroup") then
					innerClip = intersect(clip, rect)
				end
				visit(child, rootIndex, world, element.index, visible, innerClip, innerScroll)
			elseif parent ~= nil and isA(child, "UIPadding") then
				local owner = elements[parent]
				owner.padding = {
					left = offsetOf(read(child, "PaddingLeft"), owner.rect.width),
					top = offsetOf(read(child, "PaddingTop"), owner.rect.height),
					right = offsetOf(read(child, "PaddingRight"), owner.rect.width),
					bottom = offsetOf(read(child, "PaddingBottom"), owner.rect.height),
				}
			elseif parent ~= nil and isA(child, "UIListLayout") then
				local owner = elements[parent]
				local direction = enumName(read(child, "FillDirection"))
				local extent = if direction == "Horizontal" then owner.rect.width else owner.rect.height
				owner.layout = {
					kind = "list",
					padding = offsetOf(read(child, "Padding"), extent),
					direction = direction,
				}
			elseif parent ~= nil and isA(child, "UIGridLayout") then
				local owner = elements[parent]
				owner.layout = {
					kind = "grid",
					padding = offsetOf(read(read(child, "CellPadding"), "X"), owner.rect.width),
					direction = enumName(read(child, "FillDirection")),
				}
			elseif not isA(child, "UIComponent") then
				visit(child, rootIndex, world, parent, shown, clip, scrollClip)
			end
		end
	end

	for _, root in roots do
		local world = not isA(root, "ScreenGui")
		local index = #dumpRoots + 1
		local enabled = read(root, "Enabled") ~= false
		local rect = rectOf(root, world)
		table.insert(dumpRoots, {
			index = index,
			class = textOf(read(root, "ClassName")) or "LayerCollector",
			path = fullName(root),
			enabled = enabled,
			displayOrder = numberOf(read(root, "DisplayOrder"), 0),
			world = world,
			screenInsets = enumName(read(root, "ScreenInsets")),
			ignoreGuiInset = if type(read(root, "IgnoreGuiInset")) == "boolean"
				then read(root, "IgnoreGuiInset") :: boolean
				else nil,
			rect = rect,
		})
		instances += 1
		visit(root, index, world, nil, enabled, nil, nil)
	end

	for _, entry in pending do
		for _, direction in DIRECTIONS do
			local target = read(entry.instance, "NextSelection" .. direction)
			if target ~= nil then
				table.insert(entry.element.next, {
					direction = string.lower(direction),
					index = indexOf[target],
					path = fullName(target),
				})
			end
		end
	end

	local selectedObject = read(guiService, "SelectedObject")
	return {
		schemaVersion = Audit.SCHEMA_VERSION,
		screen = {
			width = width,
			height = height,
			scale = given.scale or 1,
			guiInset = { left = insetLeft, top = insetTop, right = insetRight, bottom = insetBottom },
			safeArea = if given.safeArea ~= nil
				then given.safeArea
				elseif given.safeAreaRoot ~= nil then rectOf(given.safeAreaRoot, false)
				else nil,
			input = given.input or {},
			device = given.device,
		},
		roots = dumpRoots,
		elements = elements,
		selected = if selectedObject ~= nil then indexOf[selectedObject] else nil,
		instances = instances,
		truncated = truncated,
	}
end

return {
	collect = collect,
}
