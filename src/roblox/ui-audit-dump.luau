--!strict

export type Rect = { x: number, y: number, width: number, height: number }
export type Color = { r: number, g: number, b: number }
export type Insets = { left: number, top: number, right: number, bottom: number }

export type Screen = {
	width: number,
	height: number,
	scale: number,
	guiInset: Insets,
	safeArea: Rect?,
	topbarSafeArea: Rect?,
	input: { string },
	device: string?,
}

export type Root = {
	index: number,
	class: string,
	path: string,
	enabled: boolean,
	displayOrder: number,
	world: boolean,
	screenInsets: string?,
	ignoreGuiInset: boolean?,
	zIndexBehavior: string?,
	rect: Rect,
}

export type Text = {
	content: string,
	size: number,
	bounds: { width: number, height: number },
	xAlignment: string?,
	yAlignment: string?,
	fits: boolean?,
	scaled: boolean,
	wrapped: boolean,
	truncate: string?,
	font: string?,
	bold: boolean,
	color: Color,
	transparency: number,
}

export type Focus = {
	selectionImage: "default" | "visible" | "hidden",
	autoButtonColor: boolean?,
	hoverImage: boolean,
	pressedImage: boolean,
	stateStyled: boolean,
}

export type Link = { direction: string, index: number?, path: string }

export type Layout = { kind: string, padding: number?, direction: string? }

export type Element = {
	index: number,
	parent: number?,
	root: number,
	class: string,
	path: string,
	rect: Rect,
	rotation: number,
	visible: boolean,
	clip: Rect?,
	scrollClip: Rect?,
	zIndex: number,
	order: number,
	interactive: boolean,
	selectable: boolean,
	active: boolean,
	interactable: boolean,
	guiState: string?,
	next: { Link },
	selectionGroup: boolean,
	stops: { string },
	background: { color: Color, transparency: number },
	image: { transparency: number }?,
	text: Text?,
	focus: Focus?,
	padding: Insets?,
	layout: Layout?,
}

export type Failure = { path: string, attribute: string, message: string }

export type Dump = {
	schemaVersion: number,
	screen: Screen,
	roots: { Root },
	elements: { Element },
	selected: number?,
	instances: number,
	truncated: boolean,
	failures: { Failure }?,
}

local SCHEMA_VERSION = 1
local DIRECTIONS = { "up", "down", "left", "right" }

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function fail(label: string, message: string): never
	error(("ui dump %s %s"):format(label, message), 0)
end

local function object(value: unknown, label: string): { [string]: unknown }
	if type(value) ~= "table" then
		fail(label, "must be an object")
	end
	return value :: { [string]: unknown }
end

local function present(value: unknown): boolean
	return value ~= nil and type(value) ~= "userdata"
end

local function number(value: unknown, label: string): number
	if type(value) ~= "number" or not finite(value) then
		return fail(label, "must be a finite number")
	end
	return value
end

local function optionalNumber(value: unknown, label: string): number?
	if not present(value) then
		return nil
	end
	return number(value, label)
end

local function text(value: unknown, label: string): string
	if type(value) ~= "string" then
		return fail(label, "must be a string")
	end
	return value
end

local function optionalText(value: unknown, label: string): string?
	if not present(value) then
		return nil
	end
	return text(value, label)
end

local function boolean(value: unknown, label: string, default: boolean?): boolean
	if not present(value) and default ~= nil then
		return default
	end
	if type(value) ~= "boolean" then
		return fail(label, "must be a boolean")
	end
	return value
end

local function optionalBoolean(value: unknown, label: string): boolean?
	if not present(value) then
		return nil
	end
	return boolean(value, label)
end

local function array(value: unknown, label: string): { unknown }
	if not present(value) then
		return {}
	end
	if type(value) ~= "table" then
		fail(label, "must be an array")
	end
	local result: { unknown } = {}
	for index, item in ipairs(value :: { unknown }) do
		result[index] = item
	end
	return result
end

local function rect(value: unknown, label: string): Rect
	local raw = object(value, label)
	return {
		x = number(raw.x, label .. ".x"),
		y = number(raw.y, label .. ".y"),
		width = math.max(0, number(raw.width, label .. ".width")),
		height = math.max(0, number(raw.height, label .. ".height")),
	}
end

local function optionalRect(value: unknown, label: string): Rect?
	if not present(value) then
		return nil
	end
	return rect(value, label)
end

local function color(value: unknown, label: string): Color
	local raw = object(value, label)
	return {
		r = math.clamp(number(raw.r, label .. ".r"), 0, 1),
		g = math.clamp(number(raw.g, label .. ".g"), 0, 1),
		b = math.clamp(number(raw.b, label .. ".b"), 0, 1),
	}
end

local function insets(value: unknown, label: string): Insets
	local raw = object(value, label)
	return {
		left = number(raw.left, label .. ".left"),
		top = number(raw.top, label .. ".top"),
		right = number(raw.right, label .. ".right"),
		bottom = number(raw.bottom, label .. ".bottom"),
	}
end

local function decode(value: unknown): Dump
	local raw = object(value, "")
	if raw.schemaVersion ~= SCHEMA_VERSION then
		fail("schemaVersion", ("must be %d"):format(SCHEMA_VERSION))
	end
	local screenRaw = object(raw.screen, "screen")
	local input: { string } = {}
	for index, item in array(screenRaw.input, "screen.input") do
		table.insert(input, text(item, ("screen.input[%d]"):format(index)))
	end
	local screen: Screen = {
		width = number(screenRaw.width, "screen.width"),
		height = number(screenRaw.height, "screen.height"),
		scale = optionalNumber(screenRaw.scale, "screen.scale") or 1,
		guiInset = if present(screenRaw.guiInset)
			then insets(screenRaw.guiInset, "screen.guiInset")
			else { left = 0, top = 0, right = 0, bottom = 0 },
		safeArea = optionalRect(screenRaw.safeArea, "screen.safeArea"),
		topbarSafeArea = optionalRect(screenRaw.topbarSafeArea, "screen.topbarSafeArea"),
		input = input,
		device = optionalText(screenRaw.device, "screen.device"),
	}
	local roots: { Root } = {}
	for index, item in array(raw.roots, "roots") do
		local where = ("roots[%d]"):format(index)
		local entry = object(item, where)
		table.insert(roots, {
			index = number(entry.index, where .. ".index"),
			class = text(entry.class, where .. ".class"),
			path = text(entry.path, where .. ".path"),
			enabled = boolean(entry.enabled, where .. ".enabled", true),
			displayOrder = optionalNumber(entry.displayOrder, where .. ".displayOrder") or 0,
			world = boolean(entry.world, where .. ".world", false),
			screenInsets = optionalText(entry.screenInsets, where .. ".screenInsets"),
			ignoreGuiInset = optionalBoolean(entry.ignoreGuiInset, where .. ".ignoreGuiInset"),
			zIndexBehavior = optionalText(entry.zIndexBehavior, where .. ".zIndexBehavior"),
			rect = rect(entry.rect, where .. ".rect"),
		})
	end
	local elements: { Element } = {}
	for index, item in array(raw.elements, "elements") do
		local where = ("elements[%d]"):format(index)
		local entry = object(item, where)
		if entry.index ~= index then
			fail(where .. ".index", "must equal its position")
		end
		local links: { Link } = {}
		for linkIndex, link in array(entry.next, where .. ".next") do
			local linkWhere = ("%s.next[%d]"):format(where, linkIndex)
			local linkRaw = object(link, linkWhere)
			local direction = text(linkRaw.direction, linkWhere .. ".direction")
			if table.find(DIRECTIONS, direction) == nil then
				fail(linkWhere .. ".direction", "must be up, down, left or right")
			end
			table.insert(links, {
				direction = direction,
				index = optionalNumber(linkRaw.index, linkWhere .. ".index"),
				path = text(linkRaw.path, linkWhere .. ".path"),
			})
		end
		local stops: { string } = {}
		for stopIndex, stop in array(entry.stops, where .. ".stops") do
			table.insert(stops, text(stop, ("%s.stops[%d]"):format(where, stopIndex)))
		end
		local backgroundRaw = object(entry.background, where .. ".background")
		local textValue: Text? = nil
		if present(entry.text) then
			local t = object(entry.text, where .. ".text")
			local bounds = object(t.bounds, where .. ".text.bounds")
			textValue = {
				content = text(t.content, where .. ".text.content"),
				xAlignment = optionalText(t.xAlignment, where .. ".text.xAlignment"),
				yAlignment = optionalText(t.yAlignment, where .. ".text.yAlignment"),
				size = number(t.size, where .. ".text.size"),
				bounds = {
					width = number(bounds.width, where .. ".text.bounds.width"),
					height = number(bounds.height, where .. ".text.bounds.height"),
				},
				fits = optionalBoolean(t.fits, where .. ".text.fits"),
				scaled = boolean(t.scaled, where .. ".text.scaled", false),
				wrapped = boolean(t.wrapped, where .. ".text.wrapped", false),
				truncate = optionalText(t.truncate, where .. ".text.truncate"),
				font = optionalText(t.font, where .. ".text.font"),
				bold = boolean(t.bold, where .. ".text.bold", false),
				color = color(t.color, where .. ".text.color"),
				transparency = math.clamp(optionalNumber(t.transparency, where .. ".text.transparency") or 0, 0, 1),
			}
		end
		local focus: Focus? = nil
		if present(entry.focus) then
			local f = object(entry.focus, where .. ".focus")
			local image = text(f.selectionImage, where .. ".focus.selectionImage")
			if image ~= "default" and image ~= "visible" and image ~= "hidden" then
				fail(where .. ".focus.selectionImage", "must be default, visible or hidden")
			end
			focus = {
				selectionImage = if image == "default"
					then "default"
					elseif image == "visible" then "visible"
					else "hidden",
				autoButtonColor = optionalBoolean(f.autoButtonColor, where .. ".focus.autoButtonColor"),
				hoverImage = boolean(f.hoverImage, where .. ".focus.hoverImage", false),
				pressedImage = boolean(f.pressedImage, where .. ".focus.pressedImage", false),
				stateStyled = boolean(f.stateStyled, where .. ".focus.stateStyled", false),
			}
		end
		local layout: Layout? = nil
		if present(entry.layout) then
			local l = object(entry.layout, where .. ".layout")
			layout = {
				kind = text(l.kind, where .. ".layout.kind"),
				padding = optionalNumber(l.padding, where .. ".layout.padding"),
				direction = optionalText(l.direction, where .. ".layout.direction"),
			}
		end
		local imageValue: { transparency: number }? = nil
		if present(entry.image) then
			local i = object(entry.image, where .. ".image")
			imageValue = { transparency = math.clamp(number(i.transparency, where .. ".image.transparency"), 0, 1) }
		end
		local parent = optionalNumber(entry.parent, where .. ".parent")
		if parent ~= nil and (parent < 1 or parent >= index or parent % 1 ~= 0) then
			fail(where .. ".parent", "must name an earlier element")
		end
		table.insert(elements, {
			index = index,
			parent = parent,
			root = number(entry.root, where .. ".root"),
			class = text(entry.class, where .. ".class"),
			path = text(entry.path, where .. ".path"),
			rect = rect(entry.rect, where .. ".rect"),
			rotation = optionalNumber(entry.rotation, where .. ".rotation") or 0,
			visible = boolean(entry.visible, where .. ".visible", true),
			clip = optionalRect(entry.clip, where .. ".clip"),
			scrollClip = optionalRect(entry.scrollClip, where .. ".scrollClip"),
			zIndex = optionalNumber(entry.zIndex, where .. ".zIndex") or 1,
			order = optionalNumber(entry.order, where .. ".order") or index,
			interactive = boolean(entry.interactive, where .. ".interactive", false),
			selectable = boolean(entry.selectable, where .. ".selectable", false),
			active = boolean(entry.active, where .. ".active", false),
			interactable = boolean(entry.interactable, where .. ".interactable", true),
			guiState = optionalText(entry.guiState, where .. ".guiState"),
			next = links,
			selectionGroup = boolean(entry.selectionGroup, where .. ".selectionGroup", false),
			stops = stops,
			background = {
				color = color(backgroundRaw.color, where .. ".background.color"),
				transparency = math.clamp(
					number(backgroundRaw.transparency, where .. ".background.transparency"),
					0,
					1
				),
			},
			image = imageValue,
			text = textValue,
			focus = focus,
			padding = if present(entry.padding) then insets(entry.padding, where .. ".padding") else nil,
			layout = layout,
		})
	end
	local failures: { Failure } = {}
	if present(raw.failures) then
		for index, item in array(raw.failures, "failures") do
			local where = ("failures[%d]"):format(index)
			local entry = object(item, where)
			table.insert(failures, {
				path = text(entry.path, where .. ".path"),
				attribute = text(entry.attribute, where .. ".attribute"),
				message = text(entry.message, where .. ".message"),
			})
		end
	end
	return {
		schemaVersion = SCHEMA_VERSION,
		screen = screen,
		roots = roots,
		elements = elements,
		selected = optionalNumber(raw.selected, "selected"),
		instances = optionalNumber(raw.instances, "instances") or #elements,
		truncated = boolean(raw.truncated, "truncated", false),
		failures = if present(raw.failures) then failures else nil,
	}
end

local function intersect(left: Rect?, right: Rect?): Rect?
	if left == nil then
		return right
	end
	if right == nil then
		return left
	end
	local x1 = math.max(left.x, right.x)
	local y1 = math.max(left.y, right.y)
	local x2 = math.min(left.x + left.width, right.x + right.width)
	local y2 = math.min(left.y + left.height, right.y + right.height)
	return { x = x1, y = y1, width = math.max(0, x2 - x1), height = math.max(0, y2 - y1) }
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	DIRECTIONS = DIRECTIONS,
	decode = decode,
	intersect = intersect,
}
