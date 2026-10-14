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
	rect: Rect,
}

export type Text = {
	content: string,
	size: number,
	bounds: { width: number, height: number },
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

export type Dump = {
	schemaVersion: number,
	screen: Screen,
	roots: { Root },
	elements: { Element },
	selected: number?,
	instances: number,
	truncated: boolean,
}

export type Severity = "high" | "medium" | "low"

export type Violation = {
	rule: string,
	severity: Severity,
	path: string,
	detail: string,
	value: number?,
}

export type RuleSummary = { count: number, severity: Severity, penalty: number }

export type Metrics = {
	elements: number,
	visible: number,
	interactive: number,
	texts: number,
	instances: number,
	typeSizes: number,
	spacingValues: number,
	contrastUnknown: number,
	selectable: number,
	reachable: number,
}

export type Report = {
	schemaVersion: number,
	score: number,
	device: string?,
	rules: { [string]: RuleSummary },
	violations: { Violation },
	omitted: number,
	metrics: Metrics,
	options: ResolvedOptions,
}

export type Options = {
	minTouchTarget: number?,
	touch: boolean?,
	gamepad: boolean?,
	contrast: number?,
	largeContrast: number?,
	largeTextSize: number?,
	largeBoldTextSize: number?,
	maxTypeSizes: number?,
	maxSpacingValues: number?,
	maxInstances: number?,
	pressFeedback: boolean?,
	weights: { high: number?, medium: number?, low: number? }?,
	ruleCap: number?,
	maxViolations: number?,
}

export type ResolvedOptions = {
	minTouchTarget: number,
	touch: boolean,
	gamepad: boolean,
	contrast: number,
	largeContrast: number,
	largeTextSize: number,
	largeBoldTextSize: number,
	maxTypeSizes: number,
	maxSpacingValues: number,
	maxInstances: number,
	pressFeedback: boolean,
	weights: { high: number, medium: number, low: number },
	ruleCap: number,
	maxViolations: number,
}

local SCHEMA_VERSION = 1
local EDGE = 1
local DIRECTIONS = { "up", "down", "left", "right" }

local RULES: { [string]: Severity } = {
	["text-truncated"] = "high",
	["text-clipped"] = "high",
	["contrast-low"] = "high",
	["offscreen"] = "high",
	["outside-safe-area"] = "medium",
	["touch-target-small"] = "medium",
	["interactive-overlap"] = "medium",
	["gamepad-unreachable"] = "medium",
	["focus-hidden"] = "medium",
	["selection-link-broken"] = "low",
	["press-feedback-missing"] = "low",
	["type-scale"] = "low",
	["spacing-scale"] = "low",
	["instance-count"] = "low",
}

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
	if not finite(value) then
		fail(label, "must be a finite number")
	end
	return value :: number
end

local function optionalNumber(value: unknown, label: string): number?
	if not present(value) then
		return nil
	end
	return number(value, label)
end

local function text(value: unknown, label: string): string
	if type(value) ~= "string" then
		fail(label, "must be a string")
	end
	return value :: string
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
		fail(label, "must be a boolean")
	end
	return value :: boolean
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
				selectionImage = image :: "default" | "visible" | "hidden",
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
	return {
		schemaVersion = SCHEMA_VERSION,
		screen = screen,
		roots = roots,
		elements = elements,
		selected = optionalNumber(raw.selected, "selected"),
		instances = optionalNumber(raw.instances, "instances") or #elements,
		truncated = boolean(raw.truncated, "truncated", false),
	}
end

local function resolve(options: Options?, screen: Screen): ResolvedOptions
	local given: Options = options or {}
	local input = screen.input
	local weights: { high: number?, medium: number?, low: number? } = given.weights or {}
	return {
		minTouchTarget = given.minTouchTarget or 44,
		touch = if given.touch ~= nil then given.touch else (#input == 0 or table.find(input, "touch") ~= nil),
		gamepad = if given.gamepad ~= nil then given.gamepad else (#input == 0 or table.find(input, "gamepad") ~= nil),
		contrast = given.contrast or 4.5,
		largeContrast = given.largeContrast or 3,
		largeTextSize = given.largeTextSize or 24,
		largeBoldTextSize = given.largeBoldTextSize or 18.66,
		maxTypeSizes = given.maxTypeSizes or 6,
		maxSpacingValues = given.maxSpacingValues or 8,
		maxInstances = given.maxInstances or 3000,
		pressFeedback = given.pressFeedback == true,
		weights = { high = weights.high or 6, medium = weights.medium or 3, low = weights.low or 1 },
		ruleCap = given.ruleCap or 20,
		maxViolations = given.maxViolations or 200,
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

local function area(value: Rect): number
	return value.width * value.height
end

local function inside(value: Rect, bounds: Rect, tolerance: number): boolean
	return value.x >= bounds.x - tolerance
		and value.y >= bounds.y - tolerance
		and value.x + value.width <= bounds.x + bounds.width + tolerance
		and value.y + value.height <= bounds.y + bounds.height + tolerance
end

local function luminance(value: Color): number
	local function channel(c: number): number
		if c <= 0.03928 then
			return c / 12.92
		end
		return ((c + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(value.r) + 0.7152 * channel(value.g) + 0.0722 * channel(value.b)
end

local function ratio(left: Color, right: Color): number
	local a = luminance(left)
	local b = luminance(right)
	local light = math.max(a, b)
	local dark = math.min(a, b)
	return (light + 0.05) / (dark + 0.05)
end

local function blend(top: Color, alpha: number, bottom: Color): Color
	return {
		r = top.r * alpha + bottom.r * (1 - alpha),
		g = top.g * alpha + bottom.g * (1 - alpha),
		b = top.b * alpha + bottom.b * (1 - alpha),
	}
end

local function round(value: number): number
	return math.floor(value + 0.5)
end

local function analyze(dump: Dump, options: Options?): Report
	local resolved = resolve(options, dump.screen)
	local violations: { Violation } = {}
	local counts: { [string]: number } = {}
	local penalties: { [string]: number } = {}
	local function add(rule: string, element: Element?, detail: string, value: number?)
		local severity: Severity = RULES[rule]
		counts[rule] = (counts[rule] or 0) + 1
		penalties[rule] = (penalties[rule] or 0) + resolved.weights[severity]
		table.insert(violations, {
			rule = rule,
			severity = severity,
			path = if element ~= nil then element.path else "",
			detail = detail,
			value = value,
		})
	end

	local roots: { [number]: Root } = {}
	for _, root in dump.roots do
		roots[root.index] = root
	end
	local screenRect: Rect = { x = 0, y = 0, width = dump.screen.width, height = dump.screen.height }
	local visibleRects: { [number]: Rect? } = {}
	local metrics: Metrics = {
		elements = #dump.elements,
		visible = 0,
		interactive = 0,
		texts = 0,
		instances = dump.instances,
		typeSizes = 0,
		spacingValues = 0,
		contrastUnknown = 0,
		selectable = 0,
		reachable = 0,
	}

	local function onScreen(element: Element): boolean
		local root = roots[element.root]
		return root == nil or not root.world
	end

	for _, element in dump.elements do
		local root = roots[element.root]
		if not element.visible or (root ~= nil and not root.enabled) then
			continue
		end
		local shown = intersect(intersect(element.rect, element.clip), element.scrollClip) :: Rect
		if area(shown) <= 0 then
			continue
		end
		visibleRects[element.index] = shown
		metrics.visible += 1
		if element.interactive then
			metrics.interactive += 1
		end
		if element.text ~= nil and element.text.content ~= "" then
			metrics.texts += 1
		end
	end

	local function ancestorOf(candidate: number, element: Element): boolean
		local cursor = element.parent
		while cursor ~= nil do
			if cursor == candidate then
				return true
			end
			cursor = dump.elements[cursor].parent
		end
		return false
	end

	local function background(element: Element): (Color?, Color?)
		local layers: { { color: Color, alpha: number } } = {}
		local cursor: Element? = element
		local unknown = false
		while cursor ~= nil do
			local alpha = 1 - cursor.background.transparency
			if cursor.image ~= nil and cursor.image.transparency < 1 then
				unknown = true
				break
			end
			if alpha > 0 then
				table.insert(layers, { color = cursor.background.color, alpha = alpha })
			end
			if alpha >= 1 then
				break
			end
			cursor = if cursor.parent ~= nil then dump.elements[cursor.parent] else nil
		end
		if unknown then
			return nil, nil
		end
		local overBlack: Color = { r = 0, g = 0, b = 0 }
		local overWhite: Color = { r = 1, g = 1, b = 1 }
		for index = #layers, 1, -1 do
			overBlack = blend(layers[index].color, layers[index].alpha, overBlack)
			overWhite = blend(layers[index].color, layers[index].alpha, overWhite)
		end
		return overBlack, overWhite
	end

	local typeSizes: { [number]: boolean } = {}
	local spacing: { [number]: boolean } = {}
	local function spacingValue(value: number?)
		if value ~= nil and value >= 1 then
			spacing[round(value)] = true
		end
	end

	for _, element in dump.elements do
		local shown = visibleRects[element.index]
		if shown == nil then
			continue
		end
		local screenSpace = onScreen(element)
		local textValue = element.text
		if textValue ~= nil and textValue.content ~= "" then
			local overflows = not textValue.scaled
				and (
					textValue.bounds.width > element.rect.width + EDGE
					or textValue.bounds.height > element.rect.height + EDGE
				)
			if textValue.fits == false or overflows then
				add(
					"text-truncated",
					element,
					("text needs %dx%d but has %dx%d"):format(
						round(textValue.bounds.width),
						round(textValue.bounds.height),
						round(element.rect.width),
						round(element.rect.height)
					),
					textValue.bounds.width - element.rect.width
				)
			end
			if element.clip ~= nil and not inside(element.rect, element.clip :: Rect, EDGE) then
				add("text-clipped", element, "an ancestor that clips its descendants cuts the text", nil)
			end
			if not textValue.scaled then
				typeSizes[round(textValue.size)] = true
			end
			local overBlack, overWhite = background(element)
			if overBlack == nil or overWhite == nil then
				metrics.contrastUnknown += 1
			else
				local alpha = 1 - textValue.transparency
				local lowBlack = ratio(blend(textValue.color, alpha, overBlack :: Color), overBlack :: Color)
				local lowWhite = ratio(blend(textValue.color, alpha, overWhite :: Color), overWhite :: Color)
				local large = textValue.size >= resolved.largeTextSize * dump.screen.scale
					or (textValue.bold and textValue.size >= resolved.largeBoldTextSize * dump.screen.scale)
				local required = if large then resolved.largeContrast else resolved.contrast
				local worst = math.min(lowBlack, lowWhite)
				local best = math.max(lowBlack, lowWhite)
				if best < required then
					add(
						"contrast-low",
						element,
						("contrast %.2f:1 is below %.1f:1"):format(worst, required),
						math.floor(worst * 100) / 100
					)
				elseif worst < required then
					metrics.contrastUnknown += 1
				end
			end
		end
		if screenSpace and (element.interactive or (textValue ~= nil and textValue.content ~= "")) then
			if not inside(shown, screenRect, EDGE) then
				add("offscreen", element, "the element extends past the screen edge", nil)
			elseif dump.screen.safeArea ~= nil and not inside(shown, dump.screen.safeArea :: Rect, EDGE) then
				add("outside-safe-area", element, "the element extends past the safe area", nil)
			end
		end
		if element.interactive and screenSpace and resolved.touch then
			local minimum = resolved.minTouchTarget * dump.screen.scale
			local smaller = math.min(element.rect.width, element.rect.height)
			if smaller < minimum then
				add(
					"touch-target-small",
					element,
					("touch target %dx%d is below %d"):format(
						round(element.rect.width),
						round(element.rect.height),
						round(minimum)
					),
					smaller
				)
			end
		end
		if element.interactive and element.focus ~= nil then
			local focus = element.focus :: Focus
			if element.selectable and focus.selectionImage == "hidden" then
				add("focus-hidden", element, "the selection image is invisible", nil)
			end
			if
				resolved.pressFeedback
				and focus.autoButtonColor == false
				and not focus.hoverImage
				and not focus.pressedImage
				and not focus.stateStyled
			then
				add("press-feedback-missing", element, "the button shows no hover or press state", nil)
			end
		end
		if element.padding ~= nil then
			local padding = element.padding :: Insets
			spacingValue(padding.left)
			spacingValue(padding.top)
			spacingValue(padding.right)
			spacingValue(padding.bottom)
		end
		if element.layout ~= nil then
			spacingValue((element.layout :: Layout).padding)
		end
	end

	local children: { [number]: { Element } } = {}
	for _, element in dump.elements do
		if visibleRects[element.index] ~= nil and element.parent ~= nil then
			local list = children[element.parent :: number]
			if list == nil then
				list = {}
				children[element.parent :: number] = list
			end
			table.insert(list, element)
		end
	end
	for _, list in children do
		for leftIndex = 1, #list do
			local left = list[leftIndex].rect
			for rightIndex = 1, #list do
				if leftIndex == rightIndex then
					continue
				end
				local right = list[rightIndex].rect
				local verticalOverlap = math.min(left.y + left.height, right.y + right.height)
					- math.max(left.y, right.y)
				local horizontalOverlap = math.min(left.x + left.width, right.x + right.width)
					- math.max(left.x, right.x)
				if verticalOverlap > 0.5 * math.min(left.height, right.height) then
					local gap = right.x - (left.x + left.width)
					if gap >= 1 and gap <= 128 then
						local nearer = false
						for _, other in list do
							local o = other.rect
							if o ~= left and o ~= right and o.x >= left.x + left.width and o.x < right.x then
								nearer = true
							end
						end
						if not nearer then
							spacingValue(gap)
						end
					end
				end
				if horizontalOverlap > 0.5 * math.min(left.width, right.width) then
					local gap = right.y - (left.y + left.height)
					if gap >= 1 and gap <= 128 then
						local nearer = false
						for _, other in list do
							local o = other.rect
							if o ~= left and o ~= right and o.y >= left.y + left.height and o.y < right.y then
								nearer = true
							end
						end
						if not nearer then
							spacingValue(gap)
						end
					end
				end
			end
		end
	end

	local interactive: { Element } = {}
	for _, element in dump.elements do
		if element.interactive and visibleRects[element.index] ~= nil and onScreen(element) then
			table.insert(interactive, element)
		end
	end
	for leftIndex = 1, #interactive do
		for rightIndex = leftIndex + 1, #interactive do
			local left = interactive[leftIndex]
			local right = interactive[rightIndex]
			if left.root ~= right.root or ancestorOf(left.index, right) or ancestorOf(right.index, left) then
				continue
			end
			local shared = intersect(visibleRects[left.index], visibleRects[right.index]) :: Rect
			if shared.width > EDGE and shared.height > EDGE then
				add(
					"interactive-overlap",
					right,
					("overlaps %s by %dx%d"):format(left.path, round(shared.width), round(shared.height)),
					area(shared)
				)
			end
		end
	end

	if resolved.gamepad then
		local nodes: { Element } = {}
		local isNode: { [number]: boolean } = {}
		for _, element in interactive do
			if element.selectable and element.interactable then
				table.insert(nodes, element)
				isNode[element.index] = true
			elseif element.interactable then
				add("gamepad-unreachable", element, "the control is not selectable", nil)
			end
		end
		metrics.selectable = #nodes
		local function groupOf(element: Element): Element?
			local cursor: Element? = element
			while cursor ~= nil do
				if cursor.selectionGroup then
					return cursor
				end
				cursor = if cursor.parent ~= nil then dump.elements[cursor.parent] else nil
			end
			return nil
		end
		local function center(element: Element): (number, number)
			return element.rect.x + element.rect.width / 2, element.rect.y + element.rect.height / 2
		end
		local function geometric(from: Element, direction: string): Element?
			local fromX, fromY = center(from)
			local group = groupOf(from)
			local bounded = group ~= nil and table.find(group.stops, direction) ~= nil
			local bestScore = math.huge
			local best: Element? = nil
			for _, candidate in nodes do
				if candidate == from then
					continue
				end
				if bounded and groupOf(candidate) ~= group then
					continue
				end
				local x, y = center(candidate)
				local primary = 0
				local cross = 0
				if direction == "up" then
					primary, cross = fromY - y, math.abs(x - fromX)
				elseif direction == "down" then
					primary, cross = y - fromY, math.abs(x - fromX)
				elseif direction == "left" then
					primary, cross = fromX - x, math.abs(y - fromY)
				else
					primary, cross = x - fromX, math.abs(y - fromY)
				end
				if primary > EDGE then
					local score = primary + 2 * cross
					if score < bestScore or (score == bestScore and best ~= nil and candidate.index < best.index) then
						bestScore = score
						best = candidate
					end
				end
			end
			return best
		end
		if #nodes > 0 then
			local start: Element = nodes[1]
			if dump.selected ~= nil and isNode[dump.selected :: number] then
				start = dump.elements[dump.selected :: number]
			else
				for _, node in nodes do
					if
						node.rect.y < start.rect.y - EDGE
						or (math.abs(node.rect.y - start.rect.y) <= EDGE and node.rect.x < start.rect.x)
					then
						start = node
					end
				end
			end
			local reached: { [number]: boolean } = { [start.index] = true }
			local queue: { Element } = { start }
			while #queue > 0 do
				local current = table.remove(queue, 1) :: Element
				for _, direction in DIRECTIONS do
					local target: Element? = nil
					local explicit: Link? = nil
					for _, link in current.next do
						if link.direction == direction then
							explicit = link
						end
					end
					if explicit ~= nil then
						if explicit.index ~= nil and isNode[explicit.index :: number] then
							target = dump.elements[explicit.index :: number]
						end
					else
						target = geometric(current, direction)
					end
					if target ~= nil and not reached[target.index] then
						reached[target.index] = true
						table.insert(queue, target)
					end
				end
			end
			for _, node in nodes do
				if reached[node.index] then
					metrics.reachable += 1
				else
					add("gamepad-unreachable", node, "no selection path reaches the control", nil)
				end
			end
		end
		for _, element in dump.elements do
			for _, link in element.next do
				if link.index == nil or not isNode[link.index :: number] then
					if visibleRects[element.index] ~= nil then
						add(
							"selection-link-broken",
							element,
							("NextSelection%s names %s, which is not a visible selectable control"):format(
								string.upper(string.sub(link.direction, 1, 1)) .. string.sub(link.direction, 2),
								link.path
							),
							nil
						)
					end
				end
			end
		end
	end

	local sizes: { number } = {}
	for size in typeSizes do
		table.insert(sizes, size)
	end
	table.sort(sizes)
	metrics.typeSizes = #sizes
	for index = resolved.maxTypeSizes + 1, #sizes do
		add("type-scale", nil, ("%d distinct text sizes exceed %d"):format(#sizes, resolved.maxTypeSizes), sizes[index])
	end
	local gaps: { number } = {}
	for gap in spacing do
		table.insert(gaps, gap)
	end
	table.sort(gaps)
	metrics.spacingValues = #gaps
	for index = resolved.maxSpacingValues + 1, #gaps do
		add(
			"spacing-scale",
			nil,
			("%d distinct spacing values exceed %d"):format(#gaps, resolved.maxSpacingValues),
			gaps[index]
		)
	end
	if dump.instances > resolved.maxInstances then
		add(
			"instance-count",
			nil,
			("%d interface instances exceed %d"):format(dump.instances, resolved.maxInstances),
			dump.instances
		)
	end

	local rules: { [string]: RuleSummary } = {}
	local totalPenalty = 0
	for rule, ruleCount in counts do
		local penalty = math.min(resolved.ruleCap, penalties[rule])
		totalPenalty += penalty
		rules[rule] = { count = ruleCount, severity = RULES[rule], penalty = penalty }
	end
	local rank: { [Severity]: number } = { high = 1, medium = 2, low = 3 }
	table.sort(violations, function(left, right)
		if rank[left.severity] ~= rank[right.severity] then
			return rank[left.severity] < rank[right.severity]
		end
		if left.rule ~= right.rule then
			return left.rule < right.rule
		end
		return left.path < right.path
	end)
	local kept: { Violation } = {}
	for index = 1, math.min(#violations, resolved.maxViolations) do
		table.insert(kept, violations[index])
	end
	return {
		schemaVersion = SCHEMA_VERSION,
		score = math.max(0, math.floor((100 - totalPenalty) * 10 + 0.5) / 10),
		device = dump.screen.device,
		rules = rules,
		violations = kept,
		omitted = #violations - #kept,
		metrics = metrics,
		options = resolved,
	}
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	RULES = RULES,
	decode = decode,
	analyze = analyze,
	contrastRatio = ratio,
	intersect = intersect,
}
