--!strict

local Dump = require "./ui-audit-dump"

export type Rect = Dump.Rect
export type Color = Dump.Color
export type Insets = Dump.Insets
export type Screen = Dump.Screen
export type Root = Dump.Root
export type Text = Dump.Text
export type Focus = Dump.Focus
export type Link = Dump.Link
export type Layout = Dump.Layout
export type Element = Dump.Element
export type Dump = Dump.Dump

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

local EDGE = 1
local RULES: { [string]: Severity } = {
	["control-failed"] = "high",
	["text-truncated"] = "high",
	["text-clipped"] = "high",
	["contrast-low"] = "high",
	["offscreen"] = "high",
	["outside-safe-area"] = "medium",
	["touch-target-small"] = "medium",
	["interactive-overlap"] = "medium",
	["text-overlap"] = "high",
	["action-covered"] = "high",
	["gamepad-unreachable"] = "medium",
	["focus-hidden"] = "medium",
	["selection-link-broken"] = "low",
	["press-feedback-missing"] = "low",
	["type-scale"] = "low",
	["spacing-scale"] = "low",
	["instance-count"] = "low",
}

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

local function orderedAbove(roots: { [number]: Root }, elements: { Element }, left: Element, right: Element): boolean
	if left.root ~= right.root then
		return (roots[left.root].displayOrder or 0) > (roots[right.root].displayOrder or 0)
	end
	if roots[left.root].zIndexBehavior == "Global" then
		return if left.zIndex ~= right.zIndex then left.zIndex > right.zIndex else left.order > right.order
	end
	local leftBranch, rightBranch = { left }, { right }
	local function parents(branch: { Element })
		local parent = branch[1].parent
		while parent do
			table.insert(branch, 1, elements[parent])
			parent = elements[parent].parent
		end
	end
	parents(leftBranch)
	parents(rightBranch)
	for index = 1, math.min(#leftBranch, #rightBranch) do
		local a, b = leftBranch[index], rightBranch[index]
		if a.index ~= b.index then
			return if a.zIndex ~= b.zIndex then a.zIndex > b.zIndex else a.order > b.order
		end
	end
	return false
end

local function isAbove(dump: Dump, left: Element, right: Element): boolean
	local roots: { [number]: Root } = {}
	for _, root in dump.roots do
		roots[root.index] = root
	end
	return orderedAbove(roots, dump.elements, left, right)
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
		local violation: Violation = {
			rule = rule,
			severity = severity,
			path = if element ~= nil then element.path else "",
			detail = detail,
			value = value,
		}
		table.insert(violations, violation)
	end

	local failures: { Dump.Failure } = dump.failures or {}
	for _, failure in failures do
		counts["control-failed"] = (counts["control-failed"] or 0) + 1
		penalties["control-failed"] = (penalties["control-failed"] or 0) + resolved.weights.high
		local violation: Violation = {
			rule = "control-failed",
			severity = "high",
			path = failure.path,
			detail = `{failure.attribute}: {failure.message}`,
		}
		table.insert(violations, violation)
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
		local shown = Dump.intersect(Dump.intersect(element.rect, element.clip), element.scrollClip) or element.rect
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
	local function above(left: Element, right: Element): boolean
		return orderedAbove(roots, dump.elements, left, right)
	end
	local function canInteract(element: Element): boolean
		local cursor: Element? = element
		while cursor do
			if not cursor.interactable then
				return false
			end
			cursor = if cursor.parent then dump.elements[cursor.parent] else nil
		end
		return true
	end
	local backdrops: { [number]: boolean } = {}
	for _, element in dump.elements do
		local shown = visibleRects[element.index]
		if
			shown == nil
			or not element.interactive
			or not element.active
			or not canInteract(element)
			or element.selectable
			or not onScreen(element)
			or not inside(roots[element.root].rect, shown, EDGE)
			or (element.text ~= nil and element.text.content ~= "")
			or (element.image ~= nil and element.image.transparency < 1)
		then
			continue
		end
		local content = false
		for _, child in dump.elements do
			if
				ancestorOf(element.index, child)
				and child.visible
				and (
					(child.text ~= nil and child.text.content ~= "")
					or (child.image ~= nil and child.image.transparency < 1)
				)
			then
				content = true
				break
			end
		end
		if not content then
			backdrops[element.index] = true
		end
	end
	for _, element in dump.elements do
		if visibleRects[element.index] == nil then
			continue
		end
		for index in backdrops do
			if above(dump.elements[index], element) then
				if element.interactive and canInteract(element) and not backdrops[element.index] then
					add(
						"action-covered",
						element,
						"an active backdrop covers the control: " .. dump.elements[index].path,
						nil
					)
				end
				visibleRects[element.index] = nil
				metrics.visible -= 1
				if element.interactive then
					metrics.interactive -= 1
				end
				if element.text ~= nil and element.text.content ~= "" then
					metrics.texts -= 1
				end
				break
			end
		end
	end

	local function within(element: Element, ancestor: number): boolean
		local cursor = element.parent
		while cursor ~= nil do
			if cursor == ancestor then
				return true
			end
			cursor = dump.elements[cursor].parent
		end
		return false
	end

	local function behind(element: Element, cursor: Element): Element?
		local parent = cursor.parent
		if parent == nil then
			return nil
		end
		local rect = element.rect
		local x, y = rect.x + rect.width / 2, rect.y + rect.height / 2
		local found: Element? = nil
		for _, other in dump.elements do
			if
				(other.zIndex < element.zIndex or (other.zIndex == element.zIndex and other.order < element.order))
				and other.background.transparency < 1
				and visibleRects[other.index] ~= nil
				and other.index ~= cursor.index
				and not within(element, other.index)
				and within(other, parent)
				and x >= other.rect.x
				and x <= other.rect.x + other.rect.width
				and y >= other.rect.y
				and y <= other.rect.y + other.rect.height
				and (
					found == nil
					or other.zIndex > found.zIndex
					or (other.zIndex == found.zIndex and other.order > found.order)
				)
			then
				found = other
			end
		end
		return found
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
			local fill = behind(element, cursor)
			if fill ~= nil then
				table.insert(layers, { color = fill.background.color, alpha = 1 - fill.background.transparency })
				if fill.background.transparency <= 0 then
					break
				end
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
			local truncated = textValue.fits == false and textValue.truncate ~= nil and textValue.truncate ~= "None"
			if truncated or overflows then
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
			local expected = Dump.intersect(element.rect, element.scrollClip) or element.rect
			if element.clip ~= nil and area(expected) > 0 and not inside(expected, element.clip, EDGE) then
				add("text-clipped", element, "an ancestor that clips its descendants cuts the text", nil)
			end
			if not textValue.scaled then
				typeSizes[round(textValue.size)] = true
			end
			local overBlack, overWhite = background(element)
			local inactive = element.interactive and not canInteract(element)
			if overBlack == nil or overWhite == nil then
				metrics.contrastUnknown += 1
			elseif not inactive then
				local alpha = 1 - textValue.transparency
				local lowBlack = ratio(blend(textValue.color, alpha, overBlack), overBlack)
				local lowWhite = ratio(blend(textValue.color, alpha, overWhite), overWhite)
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
			elseif
				not backdrops[element.index]
				and dump.screen.safeArea ~= nil
				and not inside(shown, dump.screen.safeArea, EDGE)
				and not (dump.screen.topbarSafeArea ~= nil and inside(shown, dump.screen.topbarSafeArea, EDGE))
			then
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
			local focus = element.focus
			if resolved.gamepad and element.selectable and focus.selectionImage == "hidden" then
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
			local padding = element.padding
			spacingValue(padding.left)
			spacingValue(padding.top)
			spacingValue(padding.right)
			spacingValue(padding.bottom)
		end
		if element.layout ~= nil then
			spacingValue(element.layout.padding)
		end
	end

	local children: { [number]: { Element } } = {}
	for _, element in dump.elements do
		if visibleRects[element.index] ~= nil and element.parent ~= nil then
			local list = children[element.parent]
			if list == nil then
				list = {}
				children[element.parent] = list
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
	local function ink(element: Element): Rect?
		local text = element.text
		if text == nil or text.content == "" or text.transparency >= 1 then
			return nil
		end
		local box = element.rect
		local width, height = text.bounds.width, text.bounds.height
		local x = if text.xAlignment == "Left"
			then box.x
			elseif text.xAlignment == "Right" then box.x + box.width - width
			else box.x + (box.width - width) / 2
		local y = if text.yAlignment == "Top"
			then box.y
			elseif text.yAlignment == "Bottom" then box.y + box.height - height
			else box.y + (box.height - height) / 2
		return Dump.intersect({ x = x, y = y, width = width, height = height }, visibleRects[element.index])
	end
	for leftIndex, left in dump.elements do
		if visibleRects[left.index] == nil then
			continue
		end
		local textRect = ink(left)
		if textRect == nil then
			continue
		end
		for _, right in dump.elements do
			if
				left == right
				or visibleRects[right.index] == nil
				or ancestorOf(left.index, right)
				or ancestorOf(right.index, left)
				or (left.root ~= right.root and not (onScreen(left) and onScreen(right)))
			then
				continue
			end
			local other = ink(right)
			if other ~= nil and right.index < leftIndex then
				continue
			end
			if
				other == nil
				and right.interactive
				and canInteract(right)
				and not backdrops[right.index]
				and (right.background.transparency < 1 or (right.image ~= nil and right.image.transparency < 1))
			then
				other = visibleRects[right.index]
			end
			if other then
				local shared = Dump.intersect(textRect, other) or textRect
				if shared.width > EDGE and shared.height > EDGE then
					add("text-overlap", left, "text overlaps " .. right.path, area(shared))
				end
			end
		end
	end
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
			local leftRect = visibleRects[left.index]
			local rightRect = visibleRects[right.index]
			if leftRect == nil or rightRect == nil then
				continue
			end
			if inside(leftRect, rightRect, EDGE) or inside(rightRect, leftRect, EDGE) then
				continue
			end
			local shared = Dump.intersect(leftRect, rightRect) or leftRect
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
		for _, element in dump.elements do
			if backdrops[element.index] or visibleRects[element.index] == nil or not onScreen(element) then
				continue
			end
			if element.selectable and canInteract(element) then
				table.insert(nodes, element)
				isNode[element.index] = true
			elseif element.interactive and canInteract(element) then
				add("gamepad-unreachable", element, "the control is not selectable", nil)
			end
		end
		for _, node in nodes do
			if node.interactive then
				metrics.selectable += 1
			end
		end
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
				if bounded and group ~= nil and not ancestorOf(group.index, candidate) then
					continue
				end
				local x, y = center(candidate)
				local primary = 0
				local cross = 0
				if direction == "up" then
					primary = fromY - y
					cross = math.abs(x - fromX)
				elseif direction == "down" then
					primary = y - fromY
					cross = math.abs(x - fromX)
				elseif direction == "left" then
					primary = fromX - x
					cross = math.abs(y - fromY)
				else
					primary = x - fromX
					cross = math.abs(y - fromY)
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
			if dump.selected ~= nil and isNode[dump.selected] then
				start = dump.elements[dump.selected]
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
				local current = table.remove(queue, 1)
				if current == nil then
					break
				end
				for _, direction in Dump.DIRECTIONS do
					local target: Element? = nil
					local explicit: Link? = nil
					for _, link in current.next do
						if link.direction == direction then
							explicit = link
						end
					end
					if explicit ~= nil then
						if explicit.index ~= nil and isNode[explicit.index] then
							target = dump.elements[explicit.index]
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
				if not node.interactive then
					continue
				end
				if reached[node.index] then
					metrics.reachable += 1
				else
					add("gamepad-unreachable", node, "no selection path reaches the control", nil)
				end
			end
		end
		for _, element in dump.elements do
			for _, link in element.next do
				if link.index == nil or not isNode[link.index] then
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
	table.sort(violations, function(left: Violation, right: Violation)
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
		schemaVersion = Dump.SCHEMA_VERSION,
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
	SCHEMA_VERSION = Dump.SCHEMA_VERSION,
	RULES = RULES,
	decode = Dump.decode,
	analyze = analyze,
	contrastRatio = ratio,
	intersect = Dump.intersect,
	isAbove = isAbove,
}
