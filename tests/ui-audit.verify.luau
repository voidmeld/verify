--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local function asString(value: unknown): string
	assert(type(value) == "string")
	return value
end

local Audit = require "../src/roblox/ui-audit"
local Collect = require "../src/roblox/ui-audit-collect"

type Object = { [string]: unknown }

local WHITE = { r = 1, g = 1, b = 1 }
local BLACK = { r = 0, g = 0, b = 0 }

local function rect(x: number, y: number, width: number, height: number): Object
	return { x = x, y = y, width = width, height = height }
end

local function button(index: number, x: number, y: number, extra: Object): Object
	local value: Object = {
		index = index,
		root = 1,
		class = "TextButton",
		path = "Gui.Button" .. index,
		rect = rect(x, y, 60, 48),
		visible = true,
		interactive = true,
		selectable = true,
		active = true,
		background = { color = BLACK, transparency = 0 },
		text = {
			content = "Go",
			size = 18,
			bounds = { width = 20, height = 18 },
			fits = true,
			color = WHITE,
		},
		focus = { selectionImage = "default", autoButtonColor = true },
	}
	local additions: Object = extra
	for key, item in additions do
		value[key] = item
	end
	return value
end

local function label(index: number, extra: Object): Object
	local value: Object = {
		index = index,
		root = 1,
		class = "TextLabel",
		path = "Gui.Label" .. index,
		rect = rect(100, 300, 200, 30),
		visible = true,
		background = { color = BLACK, transparency = 0 },
		text = { content = "Coins", size = 16, bounds = { width = 50, height = 16 }, fits = true, color = WHITE },
	}
	local additions: Object = extra
	for key, item in additions do
		value[key] = item
	end
	return value
end

local function dump(elements: { Object }, screen: Object): Audit.Dump
	local screenValue: Object = { width = 800, height = 400, scale = 1, input = { "touch", "gamepad" } }
	local additions: Object = screen
	for key, item in additions do
		screenValue[key] = item
	end
	return Audit.decode {
		schemaVersion = 1,
		screen = screenValue,
		roots = {
			{
				index = 1,
				class = "ScreenGui",
				path = "Gui",
				enabled = true,
				world = false,
				rect = rect(0, 0, 800, 400),
			},
			{
				index = 2,
				class = "ScreenGui",
				path = "Overlay",
				enabled = true,
				world = false,
				rect = rect(0, 0, 800, 400),
			},
		},
		elements = elements,
		instances = #elements + 2,
	}
end

local function count(report: Audit.Report, rule: string): number
	local summary = report.rules[rule]
	return if summary ~= nil then summary.count else 0
end

local function paths(report: Audit.Report, rule: string): { string }
	local result: { string } = {}
	for _, violation in report.violations do
		if violation.rule == rule then
			table.insert(result, violation.path)
		end
	end
	table.sort(result)
	return result
end

type Fake = { [string]: unknown, Parent: Fake? }

local HIERARCHY: { [string]: { string } } = {
	ScreenGui = { "ScreenGui", "LayerCollector", "GuiBase2d", "Instance" },
	Frame = { "Frame", "GuiObject", "GuiBase2d", "Instance" },
	TextLabel = { "TextLabel", "GuiObject", "GuiBase2d", "Instance" },
	TextButton = { "TextButton", "GuiButton", "GuiObject", "GuiBase2d", "Instance" },
	ScrollingFrame = { "ScrollingFrame", "GuiObject", "GuiBase2d", "Instance" },
	UIPadding = { "UIPadding", "UIComponent", "Instance" },
	UIListLayout = { "UIListLayout", "UIGridStyleLayout", "UILayout", "UIComponent", "Instance" },
	UIStroke = { "UIStroke", "UIComponent", "Instance" },
	Folder = { "Folder", "Instance" },
	PlayerGui = { "PlayerGui", "BasePlayerGui", "Instance" },
}

local function instance(class: string, name: string, properties: Fake, children: { Fake }?): Fake
	local object: Fake = { ClassName = class, Name = name }
	for key, value in properties do
		object[key] = value
	end
	local list: { Fake } = children or {}
	for _, child in list do
		child.Parent = object
	end
	object.IsA = function(_self: Fake, query: string): boolean
		return table.find(HIERARCHY[class], query) ~= nil
	end
	object.GetChildren = function(_self: Fake): { Fake }
		return table.clone(list)
	end
	object.GetFullName = function(self: Fake): string
		local names: { string } = {}
		local cursor: Fake? = self
		while cursor ~= nil do
			table.insert(names, 1, asString(cursor.Name))
			cursor = cursor.Parent
		end
		return table.concat(names, ".")
	end
	object.FindFirstChildOfClass = function(_self: Fake, query: string): Fake?
		for _, child in list do
			if child.ClassName == query then
				return child
			end
		end
		return nil
	end
	return object
end

local function vector(x: number, y: number): Fake
	return { X = x, Y = y }
end

local function color(r: number, g: number, b: number): Fake
	return { R = r, G = g, B = b }
end

local function udim(scale: number, offset: number): Fake
	return { Scale = scale, Offset = offset }
end

local function gui(x: number, y: number, width: number, height: number, extra: Object): Fake
	local value: Fake = {
		AbsolutePosition = vector(x, y),
		AbsoluteSize = vector(width, height),
		Visible = true,
		BackgroundColor3 = color(0, 0, 0),
		BackgroundTransparency = 0,
		ZIndex = 1,
	}
	local additions: Object = extra
	for key, item in additions do
		value[key] = item
	end
	return value
end

describe("ui audit analyzer", function()
	it("reports each named failure attribute as a high control-failed finding", function()
		local value = dump({}, {})
		value.failures = { { path = "Gui.Shop", attribute = "Failure", message = "the grid needs a horizontal list" } }
		local report = Audit.analyze(value)
		expect(paths(report, "control-failed")):toEqual { "Gui.Shop" }
		expect(report.violations[1].detail):toBe "Failure: the grid needs a horizontal list"
		expect(count(Audit.analyze(dump({}, {})), "control-failed")):toBe(0)
	end)

	it("compares paint branches by root order and native ZIndex behavior", function()
		local value = dump({
			label(1, { class = "Frame", zIndex = 1, order = 1 }),
			label(2, { parent = 1, zIndex = 50, order = 2 }),
			label(3, { class = "Frame", zIndex = 100, order = 3 }),
			label(4, { parent = 3, zIndex = 1, order = 4 }),
		}, {})
		local left, right = value.elements[4], value.elements[2]
		value.roots[1].zIndexBehavior = "Sibling"
		expect(Audit.isAbove(value, left, right)):toBe(true)
		expect(Audit.isAbove(value, right, left)):toBe(false)
		expect(Audit.isAbove(value, left, value.elements[3])):toBe(false)
		expect(Audit.isAbove(value, left, left)):toBe(false)
		value.elements[3].zIndex = 1
		expect(Audit.isAbove(value, left, right)):toBe(true)
		value.elements[3].order = 0
		expect(Audit.isAbove(value, left, right)):toBe(false)
		value.roots[1].zIndexBehavior = "Global"
		expect(Audit.isAbove(value, left, right)):toBe(false)
		left.zIndex = right.zIndex
		expect(Audit.isAbove(value, left, right)):toBe(true)
		left.order = right.order
		expect(Audit.isAbove(value, left, right)):toBe(false)
		left.root = 2
		value.roots[2].displayOrder = 2
		expect(Audit.isAbove(value, left, right)):toBe(true)
		value.roots[2].displayOrder = -1
		expect(Audit.isAbove(value, left, right)):toBe(false)
		value.roots[2].displayOrder = value.roots[1].displayOrder
		expect(Audit.isAbove(value, left, right)):toBe(false)
	end)

	it("reports text intersections without treating label boxes as ink", function()
		local a = label(1, { rect = rect(100, 100, 200, 30) })
		local b = label(2, { rect = rect(120, 100, 200, 30) })
		expect(count(Audit.analyze(dump({ a, b }, {})), "text-overlap")):toBe(1)
		b.rect = rect(180, 100, 200, 30)
		expect(count(Audit.analyze(dump({ a, b }, {})), "text-overlap")):toBe(0)
		local target = button(2, 190, 100, {})
		expect(count(Audit.analyze(dump({ a, target }, {})), "text-overlap")):toBe(1)
		target.parent = 1
		expect(count(Audit.analyze(dump({ a, target }, {})), "text-overlap")):toBe(0)
		target.parent = nil
		target.background = { color = BLACK, transparency = 1 }
		target.text = { content = "", size = 18, bounds = { width = 0, height = 0 }, color = WHITE }
		expect(count(Audit.analyze(dump({ a, target }, {})), "text-overlap")):toBe(0)
	end)
	it("reports active controls under a backdrop and accepts disabled controls", function()
		local target = button(1, 100, 100, {})
		local backdrop = button(2, 0, 0, {
			rect = rect(0, 0, 800, 400),
			selectable = false,
			zIndex = 10,
			text = { content = "", size = 18, bounds = { width = 0, height = 0 }, color = WHITE },
		})
		expect(count(Audit.analyze(dump({ target, backdrop }, {})), "action-covered")):toBe(1)
		target.interactable = false
		target.selectable = false
		expect(count(Audit.analyze(dump({ target, backdrop }, {})), "action-covered")):toBe(0)
	end)
	it("inactive ancestors suppress child backdrops without changing raw evidence", function()
		local evidence = dump({
			button(1, 100, 100, {}),
			{
				index = 2,
				root = 1,
				class = "Frame",
				path = "Gui.Modal",
				rect = rect(0, 0, 800, 400),
				visible = true,
				background = { color = BLACK, transparency = 1 },
				interactable = false,
				zIndex = 10,
			},
			{
				index = 3,
				root = 1,
				class = "Frame",
				path = "Gui.Modal.Group",
				parent = 2,
				rect = rect(0, 0, 800, 400),
				visible = true,
				background = { color = BLACK, transparency = 1 },
				interactable = true,
			},
			button(4, 0, 0, {
				parent = 3,
				rect = rect(0, 0, 800, 400),
				interactable = true,
				selectable = false,
				text = { content = "", size = 18, bounds = { width = 0, height = 0 }, color = WHITE },
			}),
		}, {})
		expect(count(Audit.analyze(evidence), "action-covered")):toBe(0)
		expect(evidence.elements[2].interactable):toBe(false)
		expect(evidence.elements[4].interactable):toBe(true)
		evidence.elements[2].interactable = true
		expect(count(Audit.analyze(evidence), "action-covered")):toBe(1)
		evidence.elements[2].interactable = false
		local sibling = dump({
			button(1, 100, 100, {}),
			button(2, 0, 0, {
				rect = rect(0, 0, 800, 400),
				selectable = false,
				zIndex = 20,
				text = { content = "", size = 18, bounds = { width = 0, height = 0 }, color = WHITE },
			}),
		}, {})
		table.insert(evidence.elements, sibling.elements[2])
		evidence.elements[5].index = 5
		expect(count(Audit.analyze(evidence), "action-covered")):toBe(1)
	end)
	it("ancestor interactivity controls disabled contrast and gamepad eligibility", function()
		local evidence = dump({
			label(1, { class = "Frame", interactable = false }),
			button(2, 100, 100, {
				parent = 1,
				text = { content = "Go", size = 18, bounds = { width = 20, height = 18 }, color = BLACK },
			}),
		}, {})
		evidence.elements[1].text = nil
		local inactive = Audit.analyze(evidence)
		expect(inactive.metrics.selectable):toBe(0)
		expect(count(inactive, "contrast-low")):toBe(0)
		evidence.elements[1].interactable = true
		local active = Audit.analyze(evidence)
		expect(active.metrics.selectable):toBe(1)
		expect(count(active, "contrast-low")):toBe(1)
	end)
	it("recognizes a backdrop clipped to its root's inset viewport", function()
		local inset = rect(0, 58, 800, 342)
		local evidence = dump({
			button(1, 100, 100, {}),
			button(2, 0, 0, {
				rect = rect(0, 0, 800, 400),
				clip = inset,
				selectable = false,
				zIndex = 10,
				text = { content = "", size = 18, bounds = { width = 0, height = 0 }, color = WHITE },
			}),
			button(3, 100, 200, { zIndex = 11 }),
		}, {})
		evidence.roots[1].rect = { x = 0, y = 58, width = 800, height = 342 }
		local report = Audit.analyze(evidence)
		expect(count(report, "action-covered")):toBe(1)
		expect(count(report, "gamepad-unreachable")):toBe(0)
		expect(count(report, "text-overlap")):toBe(0)
	end)
	it("a stopped group can enter its nested selection group", function()
		local outer = label(1, { selectionGroup = true, stops = { "up", "down", "left", "right" }, text = nil })
		local inner = label(3, { parent = 1, selectionGroup = true })
		local report = Audit.analyze(dump({
			outer,
			button(2, 100, 100, { parent = 1 }),
			inner,
			button(4, 100, 200, { parent = 3 }),
		}, {}))
		expect(count(report, "gamepad-unreachable")):toBe(0)
	end)
	it("keeps modal content rules and excludes a full viewport dismiss target", function()
		local scrim = button(3, 0, 0, {
			rect = rect(0, 0, 800, 400),
			selectable = false,
			zIndex = 10,
			text = { content = "", size = 18, bounds = { width = 0, height = 0 }, color = WHITE },
		})
		local report = Audit.analyze(dump({
			button(1, 100, 100, {}),
			button(2, 130, 100, {}),
			scrim,
			button(4, 10, 30, { zIndex = 11 }),
			button(5, 40, 30, { zIndex = 11 }),
		}, { safeArea = rect(20, 20, 760, 360) }))
		expect(count(report, "interactive-overlap")):toBe(1)
		expect(paths(report, "outside-safe-area")):toEqual { "Gui.Button4" }
		expect(report.metrics.interactive):toBe(3)
		expect(count(report, "gamepad-unreachable")):toBe(0)
		local unselectable = button(4, 100, 100, { selectable = false, zIndex = 11 })
		local blocked = Audit.analyze(dump({
			button(1, 100, 100, {}),
			button(2, 130, 100, {}),
			scrim,
			unselectable,
		}, {}))
		expect(paths(blocked, "gamepad-unreachable")):toEqual { "Gui.Button4" }
		expect(blocked.metrics.selectable):toBe(0)
		scrim.selectable = true
		scrim.index = 1
		local content = Audit.analyze(dump({ scrim }, { safeArea = rect(20, 20, 760, 360) }))
		expect(count(content, "outside-safe-area")):toBe(1)
	end)
	it("reads styled paint and typography with a native property fallback", function()
		local text = instance(
			"TextLabel",
			"Styled",
			gui(30, 30, 100, 30, {
				Text = "Coins",
				TextSize = 8,
				TextColor3 = color(0, 0, 0),
				TextBounds = vector(40, 18),
				TextFits = true,
			})
		)
		text.GetStyled = function(_self: unknown, key: string): unknown
			if key == "TextSize" then
				return 18
			end
			if key == "TextColor3" then
				return color(1, 1, 1)
			end
			error "unstyled"
		end
		local root = instance("ScreenGui", "Gui", gui(0, 0, 800, 400, {}), { text })
		local collected = Collect.collect { roots = { root }, game = {} }
		expect(assert(collected.elements[1].text).size):toBe(18)
		expect(assert(collected.elements[1].text).color.r):toBe(1)
	end)
	it("scores a clean interface at 100", function()
		local report = Audit.analyze(dump({ button(1, 100, 100, {}), button(2, 200, 100, {}), label(3, {}) }, {}))
		expect(report.score):toBe(100)
		expect(#report.violations):toBe(0)
		expect(report.metrics.visible):toBe(3)
		expect(report.metrics.interactive):toBe(2)
		expect(report.metrics.texts):toBe(3)
		expect(report.metrics.selectable):toBe(2)
		expect(report.metrics.reachable):toBe(2)
	end)

	it("trusts a false TextFits only for text that truncates", function()
		local report = Audit.analyze(dump({
			label(1, {
				path = "Gui.Rounded",
				rect = rect(100, 300, 28, 16),
				text = {
					content = "NEW",
					size = 16,
					bounds = { width = 28, height = 16 },
					fits = false,
					truncate = "None",
					color = WHITE,
				},
			}),
			label(2, {
				path = "Gui.Ellipsis",
				rect = rect(100, 340, 60, 16),
				text = {
					content = "A long name",
					size = 16,
					bounds = { width = 60, height = 16 },
					fits = false,
					truncate = "AtEnd",
					color = WHITE,
				},
			}),
		}, {}))
		expect(paths(report, "text-truncated")):toEqual { "Gui.Ellipsis" }
	end)

	it("finds truncated text and text cut by a clipping ancestor", function()
		local report = Audit.analyze(dump({
			label(1, {
				text = {
					content = "A long label",
					size = 16,
					bounds = { width = 300, height = 16 },
					fits = false,
					color = WHITE,
				},
			}),
			label(2, { clip = rect(100, 300, 100, 30), path = "Gui.Clipped" }),
			label(3, { scrollClip = rect(100, 300, 100, 30), path = "Gui.Scrolled" }),
			label(4, {
				path = "Gui.Scaled",
				text = {
					content = "Scaled",
					size = 40,
					bounds = { width = 400, height = 40 },
					scaled = true,
					color = WHITE,
				},
			}),
		}, {}))
		expect(paths(report, "text-truncated")):toEqual { "Gui.Label1" }
		expect(paths(report, "text-clipped")):toEqual { "Gui.Clipped" }
		expect(count(report, "text-overlap")):toBe(6)
		expect(report.score):toBe(68)
	end)
	it("allows the scroll viewport edge but detects a smaller content clip", function()
		local text = label(1, { clip = rect(100, 300, 100, 30), scrollClip = rect(100, 300, 90, 30) })
		expect(count(Audit.analyze(dump({ text }, {})), "text-clipped")):toBe(0)
		text.clip = rect(100, 300, 80, 30)
		expect(count(Audit.analyze(dump({ text }, {})), "text-clipped")):toBe(1)
	end)

	it("measures contrast against the composited background", function()
		local gray = { r = 0.5, g = 0.5, b = 0.5 }
		local report = Audit.analyze(dump({
			label(1, {
				path = "Gui.Low",
				background = { color = gray, transparency = 0 },
				text = {
					content = "Low",
					size = 16,
					bounds = { width = 30, height = 16 },
					color = { r = 0.6, g = 0.6, b = 0.6 },
				},
			}),
			label(2, {
				path = "Gui.Large",
				background = { color = BLACK, transparency = 0 },
				text = {
					content = "Large",
					size = 30,
					bounds = { width = 60, height = 30 },
					color = { r = 0.35, g = 0.35, b = 0.35 },
				},
			}),
			label(3, {
				path = "Gui.Small",
				background = { color = BLACK, transparency = 0 },
				text = {
					content = "Small",
					size = 14,
					bounds = { width = 40, height = 14 },
					color = { r = 0.35, g = 0.35, b = 0.35 },
				},
			}),
			label(4, {
				path = "Gui.OverImage",
				background = { color = BLACK, transparency = 1 },
				image = { transparency = 0 },
			}),
			label(5, { path = "Gui.OverWorld", background = { color = BLACK, transparency = 0.5 } }),
			label(6, {
				path = "Gui.Disabled",
				interactive = true,
				interactable = false,
				background = { color = BLACK, transparency = 0 },
				text = {
					content = "Buy",
					size = 14,
					bounds = { width = 30, height = 14 },
					color = { r = 0.2, g = 0.2, b = 0.2 },
				},
			}),
		}, {}))
		expect(paths(report, "contrast-low")):toEqual { "Gui.Low", "Gui.Small" }
		local host = label(
			1,
			{ path = "Gui.Host", class = "Frame", background = { color = BLACK, transparency = 0 }, order = 1 }
		)
		host.text = nil
		local fill = label(2, {
			path = "Gui.Host.Fill",
			class = "Frame",
			parent = 1,
			order = 2,
			background = { color = WHITE, transparency = 0 },
		})
		fill.text = nil
		local over = label(3, {
			path = "Gui.Host.OverFill",
			parent = 1,
			order = 3,
			background = { color = BLACK, transparency = 1 },
			text = { content = "All", size = 14, bounds = { width = 20, height = 14 }, color = BLACK },
		})
		expect(count(Audit.analyze(dump({ host, fill, over }, {})), "contrast-low")):toBe(0)
		local alone = label(2, {
			path = "Gui.Host.Alone",
			parent = 1,
			order = 2,
			background = { color = BLACK, transparency = 1 },
			text = { content = "All", size = 14, bounds = { width = 20, height = 14 }, color = BLACK },
		})
		expect(count(Audit.analyze(dump({ host, alone }, {})), "contrast-low")):toBe(1)
		expect(report.metrics.contrastUnknown):toBe(2)
		expect(Audit.contrastRatio(WHITE, BLACK)):toBeCloseTo(21)
	end)

	it("accepts content inside the top-bar safe area and flags content over core buttons", function()
		local report = Audit.analyze(dump({
			button(1, 700, 4, { path = "Gui.TopbarAction" }),
			button(2, 20, 4, { path = "Gui.OverCoreButtons" }),
			button(3, 300, 100, { path = "Gui.Content" }),
		}, { safeArea = rect(0, 58, 800, 342), topbarSafeArea = rect(164, 0, 636, 58) }))
		expect(paths(report, "outside-safe-area")):toEqual { "Gui.OverCoreButtons" }
		local without = Audit.analyze(dump({
			button(1, 700, 4, { path = "Gui.TopbarAction" }),
		}, { safeArea = rect(0, 58, 800, 342) }))
		expect(paths(without, "outside-safe-area")):toEqual { "Gui.TopbarAction" }
	end)

	it("flags off-screen, unsafe, small and overlapping controls", function()
		local report = Audit.analyze(dump({
			button(1, 780, 100, { path = "Gui.Edge" }),
			button(2, 100, 2, { path = "Gui.Notch" }),
			button(3, 300, 100, { path = "Gui.Tiny", rect = rect(300, 100, 30, 30) }),
			button(4, 500, 100, { path = "Gui.Under" }),
			button(5, 520, 110, { path = "Gui.Over" }),
			button(6, 520, 110, { path = "Overlay.Other", root = 2 }),
		}, { safeArea = rect(0, 30, 800, 370) }))
		expect(paths(report, "offscreen")):toEqual { "Gui.Edge" }
		expect(paths(report, "outside-safe-area")):toEqual { "Gui.Notch" }
		expect(paths(report, "touch-target-small")):toEqual { "Gui.Tiny" }
		expect(paths(report, "interactive-overlap")):toEqual { "Gui.Over" }
		local layered = Audit.analyze(dump({
			button(1, 0, 0, { path = "Gui.Scrim", rect = rect(0, 0, 800, 400) }),
			button(2, 300, 150, { path = "Gui.Close" }),
			button(3, 320, 160, { path = "Gui.Partial" }),
		}, {}))
		expect(paths(layered, "interactive-overlap")):toEqual { "Gui.Partial" }
		local scaled = Audit.analyze(dump({ button(1, 100, 100, {}) }, { scale = 2 }))
		expect(count(scaled, "touch-target-small")):toBe(1)
		local mouse =
			Audit.analyze(dump({ button(1, 100, 100, { rect = rect(100, 100, 20, 20) }) }, { input = { "mouse" } }))
		expect(count(mouse, "touch-target-small")):toBe(0)
		expect(count(mouse, "gamepad-unreachable")):toBe(0)
	end)

	it("uses selectable containers as transit without adding action obligations", function()
		local function links(index: number): { Object }
			local result: { Object } = {}
			for _, direction in { "up", "down", "left", "right" } do
				local link: Object = { direction = direction, index = index, path = "Gui.Node" .. index }
				table.insert(result, link)
			end
			return result
		end
		for _, class in { "Frame", "ScrollingFrame" } do
			local function analyze(extra: Object): Audit.Report
				local container: Object = {
					index = 2,
					root = 1,
					class = class,
					path = "Gui.Node2",
					rect = rect(200, 100, 60, 48),
					visible = true,
					interactive = false,
					selectable = true,
					interactable = true,
					next = links(3),
					background = { color = BLACK, transparency = 1 },
				}
				for key, value in extra do
					container[key] = value
				end
				return Audit.analyze(dump({
					button(1, 100, 100, { next = links(2) }),
					container,
					button(3, 300, 100, { next = links(1) }),
				}, {}))
			end
			local valid = analyze {}
			expect(count(valid, "selection-link-broken")):toBe(0)
			expect(count(valid, "gamepad-unreachable")):toBe(0)
			expect(valid.metrics.selectable):toBe(2)
			expect(valid.metrics.reachable):toBe(2)
			local invalidContainers: { Object } =
				{ { selectable = false }, { visible = false }, { interactable = false } }
			for _, invalid in invalidContainers do
				local blocked = analyze(invalid)
				expect(paths(blocked, "gamepad-unreachable")):toEqual { "Gui.Button3" }
				expect(count(blocked, "selection-link-broken")):toBe(4)
			end
		end
	end)

	it("follows gamepad selection paths and refuses broken links", function()
		local links = function(target: number, path: string): { Object }
			local list: { Object } = {}
			for _, direction in { "up", "down", "left", "right" } do
				local link: Object = { direction = direction, index = target, path = path }
				table.insert(list, link)
			end
			return list
		end
		local report = Audit.analyze(dump({
			button(1, 100, 100, { next = links(3, "Gui.Button3") }),
			button(2, 200, 100, {}),
			button(3, 300, 100, { next = links(1, "Gui.Button1") }),
			button(4, 100, 250, { selectable = false, path = "Gui.Mouse" }),
			button(5, 400, 250, {
				next = { { direction = "left", path = "Hidden.Thing" } },
				path = "Gui.Broken",
			}),
		}, {}))
		expect(paths(report, "gamepad-unreachable")):toEqual { "Gui.Broken", "Gui.Button2", "Gui.Mouse" }
		expect(paths(report, "selection-link-broken")):toEqual { "Gui.Broken" }
		expect(report.metrics.reachable):toBe(2)
		local grouped = Audit.analyze(dump({
			{
				index = 1,
				root = 1,
				class = "Frame",
				path = "Gui.Group",
				rect = rect(0, 0, 400, 200),
				visible = true,
				selectionGroup = true,
				stops = { "right" },
				background = { color = BLACK, transparency = 0 },
			},
			button(2, 100, 100, { parent = 1 }),
			button(3, 600, 100, {}),
		}, {}))
		expect(paths(grouped, "gamepad-unreachable")):toEqual { "Gui.Button3" }
	end)

	it("reports hidden focus and, when asked, missing press feedback", function()
		local plain = button(2, 300, 100, {
			focus = { selectionImage = "default", autoButtonColor = false },
			path = "Gui.Flat",
		})
		local elements = {
			button(1, 100, 100, { focus = { selectionImage = "hidden" }, path = "Gui.NoFocus" }),
			plain,
		}
		local report = Audit.analyze(dump(elements, {}))
		expect(paths(report, "focus-hidden")):toEqual { "Gui.NoFocus" }
		expect(count(report, "press-feedback-missing")):toBe(0)
		local pointer = Audit.analyze(dump(elements, {}), { gamepad = false })
		expect(count(pointer, "focus-hidden")):toBe(0)
		local strict = Audit.analyze(dump(elements, {}), { pressFeedback = true })
		expect(paths(strict, "press-feedback-missing")):toEqual { "Gui.Flat" }
	end)

	it("counts type sizes, spacing values and instances", function()
		local elements: { Object } = {}
		for index = 1, 8 do
			table.insert(
				elements,
				label(index, {
					rect = rect(10, 40 * index, 200, 30),
					text = {
						content = "Row",
						size = 10 + index,
						bounds = { width = 30, height = 10 + index },
						color = WHITE,
					},
					padding = { left = index, top = 0, right = 0, bottom = 0 },
				})
			)
		end
		local report = Audit.analyze(dump(elements, {}), { maxTypeSizes = 6, maxSpacingValues = 4, maxInstances = 5 })
		expect(report.metrics.typeSizes):toBe(8)
		expect(count(report, "type-scale")):toBe(2)
		expect(report.metrics.spacingValues):toBe(8)
		expect(count(report, "spacing-scale")):toBe(4)
		expect(count(report, "instance-count")):toBe(1)
		expect(report.score):toBe(100 - 2 - 4 - 1)
	end)

	it("caps the penalty of one rule and limits the violation list", function()
		local elements: { Object } = {}
		for index = 1, 12 do
			table.insert(elements, button(index, 60 * index - 50, 100, { rect = rect(60 * index - 50, 100, 20, 20) }))
		end
		local report = Audit.analyze(dump(elements, {}), { gamepad = false, maxViolations = 5 })
		expect(count(report, "touch-target-small")):toBe(12)
		expect(report.rules["touch-target-small"].penalty):toBe(20)
		expect(report.score):toBe(80)
		expect(#report.violations):toBe(5)
		expect(report.omitted):toBe(7)
	end)

	it("refuses a malformed dump", function()
		local function refuses(value: unknown, part: string)
			local ok, problem = pcall(Audit.decode, value)
			expect(ok):toBe(false)
			expect(tostring(problem)):toContain(part)
		end
		refuses({ schemaVersion = 2 }, "schemaVersion")
		local base: Object = {
			schemaVersion = 1,
			screen = { width = 10, height = 10 },
			roots = {},
			elements = { label(2, {}) },
		}
		refuses(base, "must equal its position")
		base.elements = { label(1, { parent = 1 }) }
		refuses(base, "must name an earlier element")
		base.elements = { button(1, 0, 0, { next = { { direction = "sideways", path = "x" } } }) }
		refuses(base, "up, down, left or right")
	end)
end)

describe("ui audit collector", function()
	it("dumps an injected instance tree with screen-space geometry", function()
		local other =
			instance("TextButton", "Other", gui(300, 60, 60, 48, { Selectable = true, AutoButtonColor = true }))
		local primary = instance(
			"TextButton",
			"Primary",
			gui(120, 60, 100, 48, {
				Selectable = true,
				Active = true,
				AutoButtonColor = false,
				Text = "Buy",
				ContentText = "Buy",
				TextSize = 18,
				TextBounds = vector(30, 18),
				TextFits = true,
				TextColor3 = color(1, 1, 1),
				TextTransparency = 0,
				FontFace = { Family = "rbxasset://fonts/families/Inter.json", Weight = { Value = 700 } },
				GuiState = { Name = "Idle" },
				NextSelectionRight = other,
				SelectionImageObject = instance(
					"Frame",
					"Invisible",
					gui(0, 0, 10, 10, { BackgroundTransparency = 1 })
				),
			})
		)
		local inner = instance("TextButton", "Inner", gui(110, 300, 60, 48, { Selectable = true }))
		local scroller = instance(
			"ScrollingFrame",
			"List",
			gui(100, 200, 200, 100, { AbsoluteWindowSize = vector(190, 100) }),
			{ inner }
		)
		local panel = instance("Frame", "Panel", gui(100, 50, 400, 300, { ClipsDescendants = true }), {
			instance("UIPadding", "Padding", {
				PaddingLeft = udim(0, 8),
				PaddingTop = udim(0.1, 0),
				PaddingRight = udim(0, 8),
				PaddingBottom = udim(0, 0),
			}),
			instance("UIListLayout", "Layout", { Padding = udim(0, 6), FillDirection = { Name = "Vertical" } }),
			primary,
			other,
			scroller,
		})
		local hidden = instance("Frame", "Hidden", gui(0, 0, 50, 50, { Visible = false }), {
			instance("TextLabel", "Ghost", gui(0, 0, 50, 20, { Text = "ghost" })),
		})
		local folder = instance("Folder", "Group", {}, { instance("Frame", "Loose", gui(600, 10, 40, 40, {})) })
		local screen = instance(
			"ScreenGui",
			"Shop",
			gui(0, -36, 800, 436, { Enabled = true, DisplayOrder = 3, ScreenInsets = { Name = "CoreUISafeInsets" } }),
			{ panel, hidden, folder }
		)
		local safe = instance("ScreenGui", "Probe", gui(44, 0, 712, 400, {}))
		local topbar = instance("ScreenGui", "TopbarProbe", gui(164, -36, 636, 36, {}))
		local playerGui = instance("PlayerGui", "PlayerGui", { SelectionImageObject = nil }, { screen })
		local player: Fake = {
			Name = "Player",
			FindFirstChildOfClass = function(_self: Fake, class: string): Fake?
				return if class == "PlayerGui" then playerGui else nil
			end,
		}
		local services: { [string]: Fake } = {
			GuiService = {
				SelectedObject = primary,
				GetGuiInset = function(_self: Fake): (Fake, Fake)
					return vector(0, 36), vector(0, 0)
				end,
			},
			Players = { LocalPlayer = player },
			Workspace = { CurrentCamera = { ViewportSize = vector(800, 436) } },
			StarterGui = instance("Folder", "StarterGui", {}),
		}
		local game: Fake = {
			GetService = function(_self: Fake, name: string): Fake
				return services[name]
			end,
		}
		local collected = Collect.collect {
			game = game,
			device = "tablet",
			input = { "touch", "gamepad" },
			safeAreaRoot = safe,
			topbarSafeAreaRoot = topbar,
		}
		expect(collected.screen):toEqual {
			width = 800,
			height = 436,
			scale = 1,
			guiInset = { left = 0, top = 36, right = 0, bottom = 0 },
			safeArea = { x = 44, y = 36, width = 712, height = 400 },
			topbarSafeArea = { x = 164, y = 0, width = 636, height = 36 },
			input = { "touch", "gamepad" },
			device = "tablet",
		}
		expect(#collected.roots):toBe(1)
		expect(collected.roots[1].displayOrder):toBe(3)
		expect(collected.roots[1].screenInsets):toBe "CoreUISafeInsets"
		local byPath: { [string]: Audit.Element } = {}
		for _, element in collected.elements do
			byPath[element.path] = element
		end
		local panelEntry = byPath["PlayerGui.Shop.Panel"]
		expect(panelEntry.rect):toEqual { x = 100, y = 86, width = 400, height = 300 }
		expect(panelEntry.padding):toEqual { left = 8, top = 30, right = 8, bottom = 0 }
		expect(panelEntry.layout):toEqual { kind = "list", padding = 6, direction = "Vertical" }
		local primaryEntry = byPath["PlayerGui.Shop.Panel.Primary"]
		expect(primaryEntry.parent):toBe(panelEntry.index)
		expect(primaryEntry.clip):toEqual(panelEntry.rect)
		expect(primaryEntry.interactive):toBe(true)
		expect(primaryEntry.selectable):toBe(true)
		expect(primaryEntry.guiState):toBe "Idle"
		expect((assert(primaryEntry.text)).bold):toBe(true)
		expect((assert(primaryEntry.focus)).selectionImage):toBe "hidden"
		expect((assert(primaryEntry.focus)).autoButtonColor):toBe(false)
		expect(primaryEntry.next):toEqual {
			{
				direction = "right",
				index = byPath["PlayerGui.Shop.Panel.Other"].index,
				path = "PlayerGui.Shop.Panel.Other",
			},
		}
		expect(collected.selected):toBe(primaryEntry.index)
		local innerEntry = byPath["PlayerGui.Shop.Panel.List.Inner"]
		expect(innerEntry.scrollClip):toEqual { x = 100, y = 236, width = 190, height = 100 }
		expect(byPath["PlayerGui.Shop.Hidden.Ghost"].visible):toBe(false)
		expect(byPath["PlayerGui.Shop.Group.Loose"].parent):toBe(nil)
		expect(collected.instances):toBe(12)
		local report = Audit.analyze(Audit.decode(collected))
		expect(paths(report, "focus-hidden")):toEqual { "PlayerGui.Shop.Panel.Primary" }
		expect(report.metrics.visible > 0):toBe(true)
	end)
end)

return nil
