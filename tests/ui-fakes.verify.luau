--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect
local Environment = require "../src/roblox/environment"
local UI = require "../src/roblox/ui-fakes"
local Datatypes = require "../src/roblox/datatypes"
local Transition = require "../src/roblox/ui-style-transition"
local Frames = require "../src/roblox/datatypes/cframe"
local Enum = Datatypes.Enum
local function invoke(object: Environment.Instance, name: string, ...: unknown): unknown
	return (object[name] :: Environment.Method)(object, ...)
end
local function create(): Environment.Environment
	return Environment.create { classes = UI.classes, validateProperty = UI.validateProperty }
end
describe("explicit UI fakes", function()
	it("GUI insets require an explicit provider and retain both current values", function()
		local env = create()
		UI.attach(env)
		local service = env.createInstance "GuiService"
		expect(pcall(function()
			invoke(service, "GetGuiInset")
		end)):toEqual(false)
		local topLeft, bottomRight = { X = 7, Y = 11 }, { X = 13, Y = 17 }
		UI.attach(env, {
			methods = {
				["GuiService.GetGuiInset"] = function(_object: Environment.Instance): (unknown, unknown)
					return topLeft, bottomRight
				end,
			},
		})
		local method = service.GetGuiInset :: Environment.Method
		local first, second = method(service)
		expect(first == topLeft):toEqual(true)
		expect(second == bottomRight):toEqual(true)
		topLeft, bottomRight = { X = 19, Y = 23 }, { X = 29, Y = 31 }
		first, second = method(service)
		expect(first == topLeft):toEqual(true)
		expect(second == bottomRight):toEqual(true)
	end)
	it("scroll velocity resets without moving the canvas because the double has no momentum", function()
		local env = create()
		UI.attach(env)
		local frame = env.createInstance "ScrollingFrame"
		local position = { X = 0, Y = 40 }
		frame.CanvasPosition = position
		expect((pcall(invoke, frame, "ResetScrollVelocity"))):toEqual(true)
		expect(frame.CanvasPosition == position):toEqual(true)
	end)
	it("focus transfers and destruction cleans connections", function()
		local env = create()
		local controller = UI.attach(env)
		local first = env.createInstance("TextBox", { Text = "before" })
		local second = env.createInstance "TextBox"
		invoke(first, "CaptureFocus")
		expect(first.Text):toEqual ""
		expect(invoke(first, "IsFocused")):toEqual(true)
		invoke(second, "CaptureFocus")
		expect(invoke(first, "IsFocused")):toEqual(false)
		expect(controller.focused() == second):toEqual(true)
		second:Destroy()
		expect(controller.focused()):toEqual(nil)
		controller.close()
		expect(env.liveConnections()):toEqual(0)
	end)
	it("hidden ancestor rejects focus and selection before mutation", function()
		local env = create()
		UI.attach(env)
		local panel = env.createInstance("Frame", { Visible = false })
		local textbox = env.createInstance("TextBox", { Parent = panel })
		local service = env.createInstance "GuiService"
		expect(pcall(function()
			invoke(textbox, "CaptureFocus")
		end)):toEqual(false)
		expect(pcall(function()
			service.SelectedObject = textbox
		end)):toEqual(false)
		expect(service.SelectedObject):toEqual(nil)
		panel.Visible = true
		service.SelectedObject = textbox
		expect(service.SelectedObject == textbox):toEqual(true)
	end)
	it("measurement requires an explicit provider", function()
		local env = create()
		UI.attach(env)
		local service = env.createInstance "TextService"
		expect(pcall(function()
			invoke(service, "GetTextSize", "x", 12)
		end)):toEqual(false)
		UI.attach(env, {
			measureText = function(text: string, size: number): unknown
				return #text * size
			end,
		})
		expect(invoke(service, "GetTextSize", "abc", 12)):toEqual(36)
	end)
	it("style property and transition maps are copied", function()
		local env = create()
		UI.attach(env)
		local rule = env.createInstance "StyleRule"
		local values: { [string]: unknown } = { TextSize = 16 }
		invoke(rule, "SetProperties", values)
		values.TextSize = 30
		expect(invoke(rule, "GetProperty", "TextSize")):toEqual(16)
		local read = invoke(rule, "GetProperties") :: { [string]: unknown }
		read.TextSize = 90
		expect(invoke(rule, "GetProperty", "TextSize")):toEqual(16)
		invoke(rule, "SetProperty", "TextSize", nil)
		expect(invoke(rule, "GetProperty", "TextSize")):toEqual(nil)
		invoke(rule, "SetPropertyTransition", "TextSize", "injected")
		expect((invoke(rule, "GetPropertyTransitions") :: { [string]: unknown }).TextSize):toEqual "injected"
	end)
	it("fires StyledPropertiesChanged on GuiObjects when a read styled property changes", function()
		local env = create()
		local ui = UI.attach(env)
		local root = env.createInstance "Folder"
		local label = env.createInstance("Frame", { Parent = root })
		local padding = env.createInstance("UIPadding", { Parent = label })
		local sheet = env.createInstance "StyleSheet"
		local rule = env.createInstance("StyleRule", { Selector = "Frame", Parent = sheet })
		invoke(rule, "SetProperty", "BackgroundTransparency", 0.25)
		local inset = env.createInstance("StyleRule", { Selector = "UIPadding", Parent = sheet })
		invoke(inset, "SetProperty", "PaddingLeft", Datatypes.UDim.new(0, 4))
		env.createInstance("StyleLink", { StyleSheet = sheet, Parent = root })
		local labelFires, paddingFires = 0, 0
		label.StyledPropertiesChanged:Connect(function()
			labelFires += 1
		end)
		padding.StyledPropertiesChanged:Connect(function()
			paddingFires += 1
		end)
		expect(ui.styled(label, "BackgroundTransparency")):toEqual(0.25)
		expect(ui.styled(padding, "PaddingLeft")):toEqual(Datatypes.UDim.new(0, 4))
		ui.step()
		expect(labelFires):toEqual(0)
		invoke(rule, "SetProperty", "BackgroundTransparency", 0.5)
		ui.step()
		expect(labelFires):toEqual(1)
		expect(paddingFires):toEqual(0)
		invoke(inset, "SetProperty", "PaddingLeft", Datatypes.UDim.new(0, 12))
		ui.step()
		expect(labelFires):toEqual(1)
		expect(paddingFires):toEqual(0)
		ui.step()
		expect(labelFires):toEqual(1)
	end)
	it("unstyled reads add no connections and still notice a later StyleLink", function()
		local env = create()
		local ui = UI.attach(env)
		local root = env.createInstance "Folder"
		local frame = env.createInstance("Frame", { Parent = root })
		local sheet = env.createInstance "StyleSheet"
		local rule = env.createInstance("StyleRule", { Selector = "Frame", Parent = sheet })
		invoke(rule, "SetProperty", "BackgroundTransparency", 0.25)
		local fires = 0
		frame.StyledPropertiesChanged:Connect(function()
			fires += 1
		end)
		local connections = env.liveConnections()
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0)
		ui.step()
		expect(env.liveConnections()):toEqual(connections)
		env.createInstance("StyleLink", { StyleSheet = sheet, Parent = root })
		ui.step()
		expect(fires):toEqual(1)
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.25)
	end)
	it("native flat style cascade retains raw overrides and effective notifications", function()
		local env = create()
		local ui = UI.attach(env)
		local root = env.createInstance "Folder"
		local frame = env.createInstance("Frame", { Parent = root })
		local sheet = env.createInstance "StyleSheet"
		sheet:SetAttribute("Alpha", 0.6)
		sheet:SetAttribute("Alias", "$Alpha")
		local rule = env.createInstance("StyleRule", { Selector = "Frame", Priority = 10, Parent = sheet })
		invoke(rule, "SetProperty", "BackgroundTransparency", "$Alias")
		local signal =
			invoke(frame, "GetStyledPropertyChangedSignal", "BackgroundTransparency") :: Environment.Signal<()>
		local fired = 0
		signal:Connect(function()
			fired += 1
		end)
		frame.BackgroundTransparency = 0.3
		ui.step()
		expect(fired):toEqual(0)
		local link = env.createInstance("StyleLink", { StyleSheet = sheet, Parent = root })
		ui.step()
		expect(fired):toEqual(1)
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.3)
		frame:ResetPropertyToDefault "BackgroundTransparency"
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.6)
		ui.step()
		expect(fired):toEqual(1)
		frame.BackgroundTransparency = 0.7
		sheet:SetAttribute("Alpha", 0.2)
		ui.step()
		expect(fired):toEqual(2)
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.7)
		frame.BackgroundTransparency = 0
		expect(frame:IsPropertyModified "BackgroundTransparency"):toEqual(false)
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.2)
		local hot = env.createInstance("StyleRule", { Selector = ".Hot", Priority = 20, Parent = sheet })
		invoke(hot, "SetProperty", "BackgroundTransparency", 0.8)
		frame:AddTag "Hot"
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.8)
		local nested = env.createInstance "StyleSheet"
		local nestedLink = env.createInstance("StyleLink", { Parent = frame })
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.8)
		nestedLink.StyleSheet = nested
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0)
		link:Destroy()
		nestedLink:Destroy()
		env.createInstance("StyleLink", { StyleSheet = sheet, Parent = root })
		ui.step()
		invoke(
			hot,
			"SetPropertyTransition",
			"BackgroundTransparency",
			Datatypes.TweenInfo.new(0.2, Enum.EasingStyle.Linear)
		)
		invoke(hot, "SetProperty", "BackgroundTransparency", 0.4)
		frame.BackgroundTransparency = 0.7
		ui.step()
		local before = fired
		env.step(0.1)
		ui.step()
		expect(fired):toEqual(before + 1)
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.7)
		ui.close()
		expect(env.liveConnections()):toEqual(0)
	end)
	it("native selector lists match independently and validate every branch", function()
		local env = create()
		local ui = UI.attach(env)
		local root = env.createInstance "Folder"
		local frame = env.createInstance("Frame", { Parent = root })
		frame:AddTag "Hot"
		local other = env.createInstance("TextLabel", { Parent = root })
		local sheet = env.createInstance "StyleSheet"
		env.createInstance("StyleLink", { StyleSheet = sheet, Parent = root })
		local rule = env.createInstance("StyleRule", { Selector = "Frame, TextLabel", Priority = 10, Parent = sheet })
		invoke(rule, "SetProperty", "BackgroundTransparency", 0.6)
		local higher = env.createInstance("StyleRule", { Selector = ".Hot", Priority = 20, Parent = sheet })
		invoke(higher, "SetProperty", "BackgroundTransparency", 0.8)
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.8)
		expect(ui.styled(other, "BackgroundTransparency")):toEqual(0.6)
		rule.Selector = "  .Missing , .Hot  "
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.8)
		expect(ui.styled(other, "BackgroundTransparency")):toEqual(0)
		higher:Destroy()
		rule.Selector = "Frame, .Hot, Frame"
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.6)
		rule.Selector = ".Missing, TextLabel"
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0)
		expect(ui.styled(other, "BackgroundTransparency")):toEqual(0.6)
		for _, selector in { "Frame,", ",Frame", "Frame,,TextLabel", "Frame, .Hot > > Frame", "Frame, .Hot:Hover" } do
			rule.Selector = selector
			expect((pcall(ui.styled, frame, "BackgroundTransparency"))):toEqual(false)
		end
	end)
	it("unsupported selectors only block properties that their rules can affect", function()
		local env = create()
		local ui = UI.attach(env)
		local root = env.createInstance "Folder"
		local frame = env.createInstance("Frame", { Parent = root })
		local sheet = env.createInstance "StyleSheet"
		env.createInstance("StyleLink", { StyleSheet = sheet, Parent = root })
		local rule = env.createInstance("StyleRule", { Selector = ".Card::UICorner", Parent = sheet })
		invoke(rule, "SetProperty", "CornerRadius", "unmodeled")
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0)
		local signal =
			invoke(frame, "GetStyledPropertyChangedSignal", "BackgroundTransparency") :: Environment.Signal<()>
		local fired = 0
		signal:Connect(function()
			fired += 1
		end)
		ui.step()
		expect(fired):toEqual(0)
		invoke(rule, "SetProperty", "BackgroundTransparency", 0.5)
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0)
		invoke(rule, "SetProperty", "BackgroundTransparency", nil)
		local child = env.createInstance("StyleRule", { Selector = "Frame", Parent = rule })
		invoke(child, "SetProperty", "BackgroundTransparency", 0.5)
		expect((pcall(ui.styled, frame, "BackgroundTransparency"))):toEqual(false)
		invoke(child, "SetProperty", "BackgroundTransparency", nil)
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0)
		ui.close()
		expect(env.liveConnections()):toEqual(0)
	end)
	it("unsupported styling fails before exposing raw fallback", function()
		local env = create()
		local ui = UI.attach(env)
		local root = env.createInstance "Folder"
		local frame = env.createInstance("Frame", { Parent = root })
		local sheet = env.createInstance "StyleSheet"
		env.createInstance("StyleLink", { StyleSheet = sheet, Parent = root })
		local rule = env.createInstance("StyleRule", { Selector = "Frame:hover", Parent = sheet })
		invoke(rule, "SetProperty", "BackgroundTransparency", 0.5)
		expect((pcall(ui.styled, frame, "BackgroundTransparency"))):toEqual(false)
		rule.Selector = "Frame"
		invoke(rule, "SetPropertyTransition", "BackgroundTransparency", { Time = 1 })
		local ok, detail = pcall(ui.styled, frame, "BackgroundTransparency")
		expect(ok):toEqual(false)
		expect(string.find(tostring(detail), "transition requires TweenInfo", 1, true) ~= nil):toEqual(true)
		invoke(rule, "SetPropertyTransition", "BackgroundTransparency", Datatypes.TweenInfo.new(0))
		expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.5)
		invoke(sheet, "SetDerives", { env.createInstance "StyleSheet" })
		expect((pcall(ui.styled, frame, "BackgroundTransparency"))):toEqual(false)
	end)
	it("release emits submission state and media records explicit playback state", function()
		local env = create()
		local controller = UI.attach(env)
		local textbox = env.createInstance "TextBox"
		local submitted = false
		local connection = (textbox.FocusLost :: Environment.Signal<boolean, unknown>):Connect(function(value: boolean)
			submitted = value
		end)
		invoke(textbox, "CaptureFocus")
		invoke(textbox, "ReleaseFocus", true)
		expect(submitted):toEqual(true)
		expect(controller.focused()):toEqual(nil)
		connection:Disconnect()
		local video = env.createInstance "VideoFrame"
		invoke(video, "Play")
		expect(video.Playing):toEqual(true)
		invoke(video, "Pause")
		expect(video.Playing):toEqual(false)
		expect(env.liveConnections()):toEqual(0)
	end)
	it("style derivations copy lists and reject unrelated objects", function()
		local env = create()
		UI.attach(env)
		local sheet = env.createInstance "StyleSheet"
		local base = env.createInstance "StyleSheet"
		local values = { base }
		invoke(sheet, "SetDerives", values)
		table.clear(values)
		local read = invoke(sheet, "GetDerives") :: { Environment.Instance }
		expect(read[1] == base):toEqual(true)
		table.clear(read)
		expect(#(invoke(sheet, "GetDerives") :: { Environment.Instance })):toEqual(1)
		expect(pcall(function()
			invoke(sheet, "SetDerives", { env.createInstance "Folder" })
		end)):toEqual(false)
	end)
	it("path storage copies arrays and instant page jumps emit state changes", function()
		local env = create()
		UI.attach(env)
		local path = env.createInstance "Path2D"
		local values: { unknown } = { "explicit-point" }
		invoke(path, "SetControlPoints", values)
		table.clear(values)
		expect((invoke(path, "GetControlPoints") :: { unknown })[1]):toEqual "explicit-point"
		local container = env.createInstance "Frame"
		local layout = env.createInstance("UIPageLayout", { Parent = container })
		local page = env.createInstance("Frame", { Parent = container })
		local entered = false
		local connection = (layout.PageEnter :: Environment.Signal<Environment.Instance>):Connect(function(value)
			entered = value == page
		end)
		invoke(layout, "JumpTo", page)
		expect(layout.CurrentPage == page and entered):toEqual(true)
		page.Visible = false
		expect(pcall(function()
			invoke(layout, "JumpTo", page)
		end)):toEqual(false)
		connection:Disconnect()
	end)
	it("path and page refuse behavior until explicitly injected", function()
		local env = create()
		UI.attach(env)
		local path = env.createInstance "Path2D"
		local page = env.createInstance "UIPageLayout"
		expect(pcall(function()
			invoke(path, "GetLength")
		end)):toEqual(false)
		expect(pcall(function()
			invoke(page, "Next")
		end)):toEqual(false)
		env.fake("Path2D.GetLength", function(_object: Environment.Instance): number
			return 42
		end)
		expect(invoke(path, "GetLength")):toEqual(42)
	end)
end)

local function number(value: unknown): number
	assert(type(value) == "number")
	return value
end

local function near(value: unknown, expected: number)
	expect(math.abs(number(value) - expected) < 0.00001):toBe(true)
end

local function fixture(own: (() -> ()) -> ())
	local env = Environment.create { classes = UI.classes }
	local ui = UI.attach(env)
	own(ui.close)
	local root = env.createInstance "Folder"
	local frame = env.createInstance("Frame", { Parent = root })
	local sheet = env.createInstance "StyleSheet"
	local link = env.createInstance("StyleLink", { Parent = root, StyleSheet = sheet })
	local base = env.createInstance("StyleRule", { Selector = "Frame", Parent = sheet, Priority = 1 })
	local hot = env.createInstance("StyleRule", { Selector = ".Hot", Parent = sheet, Priority = 2 })
	invoke(base, "SetProperty", "BackgroundTransparency", 0)
	invoke(hot, "SetProperty", "BackgroundTransparency", 1)
	return env, ui, frame, base, hot, sheet, link
end

it("hover tags interpolate for 0.2 seconds on virtual frames and return through the base transition", function(own)
	local env, ui, frame, base = fixture(own)
	invoke(base, "SetDefaultPropertyTransition", Datatypes.TweenInfo.new(0.2, Enum.EasingStyle.Linear))
	expect(ui.styled(frame, "BackgroundTransparency")):toBe(0)
	frame:AddTag "Hot"
	expect(ui.styled(frame, "BackgroundTransparency")):toBe(0)
	for index = 1, 4 do
		env.step(0.05)
		ui.step()
		near(ui.styled(frame, "BackgroundTransparency"), index / 4)
	end
	frame:RemoveTag "Hot"
	env.step(0.1)
	near(ui.styled(frame, "BackgroundTransparency"), 0.5)
	env.step(0.11)
	expect(ui.styled(frame, "BackgroundTransparency")):toBe(0)
	expect(frame.BackgroundTransparency):toBe(0)
end)

it("retargeting samples the current interpolation even without an intervening read", function(own)
	local env, ui, frame, base, hot = fixture(own)
	invoke(base, "SetDefaultPropertyTransition", Datatypes.TweenInfo.new(0.2, Enum.EasingStyle.Linear))
	ui.styled(frame, "BackgroundTransparency")
	frame:AddTag "Hot"
	env.step(0.1)
	invoke(hot, "SetProperty", "BackgroundTransparency", 0.25)
	near(ui.styled(frame, "BackgroundTransparency"), 0.5)
	env.step(0.1)
	near(ui.styled(frame, "BackgroundTransparency"), 0.375)
	env.step(0.11)
	expect(ui.styled(frame, "BackgroundTransparency")):toBe(0.25)
end)

it("zero duration overrides the default and takes effect immediately", function(own)
	local _, ui, frame, base, hot = fixture(own)
	invoke(base, "SetDefaultPropertyTransition", Datatypes.TweenInfo.new(0.2))
	invoke(hot, "SetPropertyTransition", "BackgroundTransparency", Datatypes.TweenInfo.new(0))
	ui.styled(frame, "BackgroundTransparency")
	frame:AddTag "Hot"
	expect(ui.styled(frame, "BackgroundTransparency")):toBe(1)
end)

it("delay holds the current value and repeats and reverses are ignored", function(own)
	local env, ui, frame, base = fixture(own)
	invoke(
		base,
		"SetDefaultPropertyTransition",
		Datatypes.TweenInfo.new(0.2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, true, 0.1)
	)
	ui.styled(frame, "BackgroundTransparency")
	frame:AddTag "Hot"
	env.step(0.05)
	expect(ui.styled(frame, "BackgroundTransparency")):toBe(0)
	env.step(0.15)
	near(ui.styled(frame, "BackgroundTransparency"), 0.5)
	env.step(1)
	expect(ui.styled(frame, "BackgroundTransparency")):toBe(1)
end)

it("transition tokens retarget styled theme values and preserve raw overrides", function(own)
	local env, ui, frame, base, _, sheet = fixture(own)
	sheet:SetAttribute("Motion", Datatypes.TweenInfo.new(0.2, Enum.EasingStyle.Linear))
	sheet:SetAttribute("Alpha", 0)
	invoke(base, "SetProperty", "BackgroundTransparency", "$Alpha")
	invoke(base, "SetPropertyTransition", "BackgroundTransparency", "$Motion")
	ui.styled(frame, "BackgroundTransparency")
	sheet:SetAttribute("Alpha", 1)
	env.step(0.1)
	near(ui.styled(frame, "BackgroundTransparency"), 0.5)
	frame.BackgroundTransparency = 0.8
	sheet:SetAttribute("Alpha", 0)
	env.step(0.1)
	expect(ui.styled(frame, "BackgroundTransparency")):toBe(0.8)
	frame:ResetPropertyToDefault "BackgroundTransparency"
	near(ui.styled(frame, "BackgroundTransparency"), 0.25)
end)

it("removing rules uses the surviving transition and removing its scope snaps to the default", function(own)
	local env, ui, frame, base, hot, _, link = fixture(own)
	invoke(base, "SetDefaultPropertyTransition", Datatypes.TweenInfo.new(0.2, Enum.EasingStyle.Linear))
	frame:AddTag "Hot"
	ui.styled(frame, "BackgroundTransparency")
	hot:Destroy()
	env.step(0.1)
	near(ui.styled(frame, "BackgroundTransparency"), 0.5)
	link:Destroy()
	expect(ui.styled(frame, "BackgroundTransparency")):toBe(0)
	ui.close()
	expect(env.liveConnections()):toBe(0)
end)

it("default transition accessors share the star entry and replacement clears it", function(own)
	local _, _, _, base = fixture(own)
	local timing = Datatypes.TweenInfo.new(0.2)
	invoke(base, "SetDefaultPropertyTransition", timing)
	expect(invoke(base, "GetDefaultPropertyTransition")):toBe(timing)
	expect(invoke(base, "GetPropertyTransitions")):toEqual { ["*"] = timing }
	invoke(base, "SetPropertyTransitions", {})
	expect(invoke(base, "GetDefaultPropertyTransition")):toBe(nil)
	invoke(base, "SetPropertyTransition", "*", timing)
	expect(invoke(base, "GetDefaultPropertyTransition")):toBe(timing)
end)

it("all easing styles and directions map to reference sample points", function()
	local samples: { [string]: number } = {
		Linear = 0.25,
		Sine = 0.0761204675,
		Quad = 0.0625,
		Cubic = 0.015625,
		Quart = 0.00390625,
		Quint = 0.0009765625,
		Exponential = 0.00552427173,
		Circular = 0.0317541634,
		Back = -0.0641365625,
		Bounce = 0.02734375,
		Elastic = -0.00552427173,
	}
	for style, expected in pairs(samples) do
		near(Transition.ease(0.25, style, "In"), expected)
		near(Transition.ease(0.75, style, "Out"), 1 - expected)
		for _, direction in { "In", "Out", "InOut" } do
			expect(Transition.ease(0, style, direction)):toBe(0)
			expect(Transition.ease(1, style, direction)):toBe(1)
		end
		near(Transition.ease(0.5, style, "InOut"), 0.5)
	end
	near(Transition.ease(0.25, "Quad", "InOut"), 0.125)
	near(Transition.ease(0.25, "Back", "InOut"), -0.09968184375)
	near(Transition.ease(0.25, "Elastic", "InOut"), 0.0119694444)
end)

it("styled properties interpolate every tweenable datatype and switch discrete values", function(own)
	local cases: { { unknown } } = {
		{ 0, 8, 4 },
		{ Datatypes.Color3.new(), Datatypes.Color3.new(1, 0.5, 0.25), Datatypes.Color3.new(0.5, 0.25, 0.125) },
		{ Datatypes.UDim.new(0, 0), Datatypes.UDim.new(1, 20), Datatypes.UDim.new(0.5, 10) },
		{ Datatypes.UDim2.new(), Datatypes.UDim2.new(1, 20, 0.5, 40), Datatypes.UDim2.new(0.5, 10, 0.25, 20) },
		{ Datatypes.Vector2.new(), Datatypes.Vector2.new(8, 4), Datatypes.Vector2.new(4, 2) },
		{ Datatypes.Vector2int16.new(), Datatypes.Vector2int16.new(8, 4), Datatypes.Vector2int16.new(4, 2) },
		{ Datatypes.Vector3.new(), Datatypes.Vector3.new(8, 4, 2), Datatypes.Vector3.new(4, 2, 1) },
		{ Datatypes.Rect.new(), Datatypes.Rect.new(2, 4, 8, 12), Datatypes.Rect.new(1, 2, 4, 6) },
		{ Datatypes.CFrame.new(), Datatypes.CFrame.new(8, 4, 2), Datatypes.CFrame.new(4, 2, 1) },
		{ false, true, true },
		{ Enum.AutomaticSize.None, Enum.AutomaticSize.X, Enum.AutomaticSize.X },
		{ "before", "after", "after" },
	}
	for index, row in cases do
		local env, ui, frame, base = fixture(own)
		local timing = Datatypes.TweenInfo.new(0.2, Enum.EasingStyle.Linear)
		invoke(base, "SetDefaultPropertyTransition", timing)
		local property = "Value" .. index
		env.defineClass("Styled" .. index, { super = "Frame", properties = { [property] = row[1] } })
		local object = env.createInstance("Styled" .. index, { Parent = frame })
		invoke(base, "SetProperty", property, row[1])
		expect(ui.styled(object, property)):toBe(row[1])
		invoke(base, "SetProperty", property, row[2])
		env.step(timing.Time / 2)
		expect(ui.styled(object, property)):toEqual(row[3])
		env.step(0.11)
		expect(ui.styled(object, property)):toEqual(row[2])
	end
end)

it("CFrame transitions interpolate rotation on the place scheduler clock", function(own)
	local env, ui, frame, base = fixture(own)
	env.defineClass("StyledTransform", { super = "Frame", properties = { Transform = Datatypes.CFrame.new() } })
	local object = env.createInstance("StyledTransform", { Parent = frame })
	local timing = Datatypes.TweenInfo.new(0.2, Enum.EasingStyle.Linear)
	invoke(base, "SetDefaultPropertyTransition", timing)
	ui.styled(object, "Transform")
	invoke(base, "SetProperty", "Transform", Datatypes.CFrame.Angles(0, math.pi / 2, 0))
	env.scheduler.advance(timing.Time / 2)
	ui.step()
	local value = Frames.expect(ui.styled(object, "Transform"), 1)
	local _, y = value:ToOrientation()
	near(y, math.pi / 4)
end)

it("retargeting during delay holds the current value and restarts the delay", function(own)
	local env, ui, frame, base, hot = fixture(own)
	invoke(
		base,
		"SetDefaultPropertyTransition",
		Datatypes.TweenInfo.new(0.2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0.1)
	)
	ui.styled(frame, "BackgroundTransparency")
	frame:AddTag "Hot"
	env.step(0.05)
	invoke(hot, "SetProperty", "BackgroundTransparency", 0.5)
	env.step(0.075)
	expect(ui.styled(frame, "BackgroundTransparency")):toBe(0)
	env.step(0.125)
	near(ui.styled(frame, "BackgroundTransparency"), 0.25)
end)

it("invalid and unresolved transition tokens retain precise refusals", function(own)
	local _, ui, frame, base, _, sheet = fixture(own)
	for _, entry in { { "$Missing", "missing token Missing" }, { "$Invalid", "transition requires TweenInfo" } } do
		sheet:SetAttribute("Invalid", 1)
		invoke(base, "SetDefaultPropertyTransition", entry[1])
		local ok, detail = pcall(ui.styled, frame, "BackgroundTransparency")
		expect(ok):toBe(false)
		expect(string.find(tostring(detail), entry[2], 1, true) ~= nil):toBe(true)
	end
end)

it("ancestor tag and parent changes retarget descendant transitions", function(own)
	local env, ui, frame, base, _, sheet = fixture(own)
	invoke(base, "SetDefaultPropertyTransition", Datatypes.TweenInfo.new(0.2, Enum.EasingStyle.Linear))
	local lit = env.createInstance("StyleRule", { Selector = ".Lit > Frame", Parent = sheet, Priority = 3 })
	invoke(lit, "SetProperty", "BackgroundTransparency", 1)
	local child = env.createInstance("Frame", { Parent = frame })
	local other = env.createInstance("Frame", { Parent = frame.Parent })
	expect(ui.styled(child, "BackgroundTransparency")):toBe(0)
	expect(ui.styled(frame, "BackgroundTransparency")):toBe(0)
	frame:AddTag "Lit"
	other:AddTag "Unrelated"
	env.step(0.1)
	near(ui.styled(child, "BackgroundTransparency"), 0.5)
	expect(ui.styled(frame, "BackgroundTransparency")):toBe(0)
	env.step(0.11)
	expect(ui.styled(child, "BackgroundTransparency")):toBe(1)
	child.Parent = other
	env.step(0.1)
	near(ui.styled(child, "BackgroundTransparency"), 0.5)
	env.step(0.11)
	expect(ui.styled(child, "BackgroundTransparency")):toBe(0)
end)

it("a tag retarget preserves an unread token transition", function(own)
	local env, ui, frame, base, _, sheet = fixture(own)
	sheet:SetAttribute("Alpha", 0)
	invoke(base, "SetProperty", "BackgroundTransparency", "$Alpha")
	invoke(base, "SetDefaultPropertyTransition", Datatypes.TweenInfo.new(0.2, Enum.EasingStyle.Linear))
	ui.styled(frame, "BackgroundTransparency")
	sheet:SetAttribute("Alpha", 0.5)
	env.step(0.1)
	frame:AddTag "Hot"
	near(ui.styled(frame, "BackgroundTransparency"), 0.25)
	env.step(0.1)
	near(ui.styled(frame, "BackgroundTransparency"), 0.625)
end)

return nil
