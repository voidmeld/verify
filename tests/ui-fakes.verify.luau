--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect
local Environment = require "../src/roblox/environment"
local UI = require "../src/roblox/ui-fakes"
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
		expect((pcall(ui.styled, frame, "BackgroundTransparency"))):toEqual(false)
		invoke(rule, "SetPropertyTransition", "BackgroundTransparency", { Time = 0 })
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

return nil
