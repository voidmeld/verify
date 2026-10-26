--!strict
local Core = require "../src/core"
local Environment = require "../src/roblox/environment"
local UI = require "../src/roblox/ui-fakes"
local function invoke(object: Environment.Instance, name: string, ...: unknown): unknown
	return (object[name] :: Environment.Method)(object, ...)
end
local function create(): Environment.Environment
	return Environment.create { classes = UI.classes, validateProperty = UI.validateProperty }
end
return function(suite: Core.Harness)
	suite:suite("explicit UI fakes", function()
		suite:case("GUI insets require an explicit provider and retain both current values", function(check)
			local env = create()
			UI.attach(env)
			local service = env.createInstance "GuiService"
			check
				:expect(pcall(function()
					invoke(service, "GetGuiInset")
				end))
				:toEqual(false)
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
			check:expect(first == topLeft):toEqual(true)
			check:expect(second == bottomRight):toEqual(true)
			topLeft, bottomRight = { X = 19, Y = 23 }, { X = 29, Y = 31 }
			first, second = method(service)
			check:expect(first == topLeft):toEqual(true)
			check:expect(second == bottomRight):toEqual(true)
		end)
		suite:case(
			"scroll velocity resets without moving the canvas because the double has no momentum",
			function(check)
				local classes = table.clone(UI.classes)
				local properties: { [string]: unknown } = { CanvasPosition = { X = 0, Y = 0 } }
				local methods: { [string]: unknown } = { ResetScrollVelocity = true }
				classes.ScrollingFrame = { super = "Instance", properties = properties, methods = methods }
				local env = Environment.create { classes = classes, validateProperty = UI.validateProperty }
				UI.attach(env)
				local frame = env.createInstance "ScrollingFrame"
				local position = { X = 0, Y = 40 }
				frame.CanvasPosition = position
				check:expect((pcall(invoke, frame, "ResetScrollVelocity"))):toEqual(true)
				check:expect(frame.CanvasPosition == position):toEqual(true)
			end
		)
		suite:case("focus transfers and destruction cleans connections", function(check)
			local env = create()
			local controller = UI.attach(env)
			local first = env.createInstance("TextBox", { Text = "before" })
			local second = env.createInstance "TextBox"
			invoke(first, "CaptureFocus")
			check:expect(first.Text):toEqual ""
			check:expect(invoke(first, "IsFocused")):toEqual(true)
			invoke(second, "CaptureFocus")
			check:expect(invoke(first, "IsFocused")):toEqual(false)
			check:expect(controller.focused() == second):toEqual(true)
			second:Destroy()
			check:expect(controller.focused()):toEqual(nil)
			controller.close()
			check:expect(env.liveConnections()):toEqual(0)
		end)
		suite:case("hidden ancestor rejects focus and selection before mutation", function(check)
			local env = create()
			UI.attach(env)
			local panel = env.createInstance("Frame", { Visible = false })
			local textbox = env.createInstance("TextBox", { Parent = panel })
			local service = env.createInstance "GuiService"
			check
				:expect(pcall(function()
					invoke(textbox, "CaptureFocus")
				end))
				:toEqual(false)
			check
				:expect(pcall(function()
					service.SelectedObject = textbox
				end))
				:toEqual(false)
			check:expect(service.SelectedObject):toEqual(nil)
			panel.Visible = true
			service.SelectedObject = textbox
			check:expect(service.SelectedObject == textbox):toEqual(true)
		end)
		suite:case("measurement requires an explicit provider", function(check)
			local env = create()
			UI.attach(env)
			local service = env.createInstance "TextService"
			check
				:expect(pcall(function()
					invoke(service, "GetTextSize", "x", 12)
				end))
				:toEqual(false)
			UI.attach(env, {
				measureText = function(text: string, size: number): unknown
					return #text * size
				end,
			})
			check:expect(invoke(service, "GetTextSize", "abc", 12)):toEqual(36)
		end)
		suite:case("style property and transition maps are copied", function(check)
			local env = create()
			UI.attach(env)
			local rule = env.createInstance "StyleRule"
			local values: { [string]: unknown } = { TextSize = 16 }
			invoke(rule, "SetProperties", values)
			values.TextSize = 30
			check:expect(invoke(rule, "GetProperty", "TextSize")):toEqual(16)
			local read = invoke(rule, "GetProperties") :: { [string]: unknown }
			read.TextSize = 90
			check:expect(invoke(rule, "GetProperty", "TextSize")):toEqual(16)
			invoke(rule, "SetProperty", "TextSize", nil)
			check:expect(invoke(rule, "GetProperty", "TextSize")):toEqual(nil)
			invoke(rule, "SetPropertyTransition", "TextSize", "injected")
			check:expect((invoke(rule, "GetPropertyTransitions") :: { [string]: unknown }).TextSize):toEqual "injected"
		end)
		suite:case("native flat style cascade retains raw overrides and effective notifications", function(check)
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
			check:expect(fired):toEqual(0)
			local link = env.createInstance("StyleLink", { StyleSheet = sheet, Parent = root })
			ui.step()
			check:expect(fired):toEqual(1)
			check:expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.3)
			frame:ResetPropertyToDefault "BackgroundTransparency"
			check:expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.6)
			ui.step()
			check:expect(fired):toEqual(1)
			frame.BackgroundTransparency = 0.7
			sheet:SetAttribute("Alpha", 0.2)
			ui.step()
			check:expect(fired):toEqual(2)
			check:expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.7)
			frame.BackgroundTransparency = 0
			check:expect(frame:IsPropertyModified "BackgroundTransparency"):toEqual(false)
			check:expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.2)
			local hot = env.createInstance("StyleRule", { Selector = ".Hot", Priority = 20, Parent = sheet })
			invoke(hot, "SetProperty", "BackgroundTransparency", 0.8)
			frame:AddTag "Hot"
			check:expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.8)
			local nested = env.createInstance "StyleSheet"
			local nestedLink = env.createInstance("StyleLink", { Parent = frame })
			check:expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.8)
			nestedLink.StyleSheet = nested
			check:expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0)
			link:Destroy()
			ui.close()
			check:expect(env.liveConnections()):toEqual(0)
		end)
		suite:case("native selector lists match independently and validate every branch", function(check)
			local env = create()
			local ui = UI.attach(env)
			local root = env.createInstance "Folder"
			local frame = env.createInstance("Frame", { Parent = root })
			frame:AddTag "Hot"
			local other = env.createInstance("TextLabel", { Parent = root })
			local sheet = env.createInstance "StyleSheet"
			env.createInstance("StyleLink", { StyleSheet = sheet, Parent = root })
			local rule =
				env.createInstance("StyleRule", { Selector = "Frame, TextLabel", Priority = 10, Parent = sheet })
			invoke(rule, "SetProperty", "BackgroundTransparency", 0.6)
			local higher = env.createInstance("StyleRule", { Selector = ".Hot", Priority = 20, Parent = sheet })
			invoke(higher, "SetProperty", "BackgroundTransparency", 0.8)
			check:expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.8)
			check:expect(ui.styled(other, "BackgroundTransparency")):toEqual(0.6)
			rule.Selector = "  .Missing , .Hot  "
			check:expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.8)
			check:expect(ui.styled(other, "BackgroundTransparency")):toEqual(0)
			higher:Destroy()
			rule.Selector = "Frame, .Hot, Frame"
			check:expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.6)
			rule.Selector = ".Missing, TextLabel"
			check:expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0)
			check:expect(ui.styled(other, "BackgroundTransparency")):toEqual(0.6)
			for _, selector in { "Frame,", ",Frame", "Frame,,TextLabel", "Frame, .Hot > > Frame", "Frame, .Hot:Hover" } do
				rule.Selector = selector
				check:expect((pcall(ui.styled, frame, "BackgroundTransparency"))):toEqual(false)
			end
		end)
		suite:case("unsupported selectors only block properties that their rules can affect", function(check)
			local env = create()
			local ui = UI.attach(env)
			local root = env.createInstance "Folder"
			local frame = env.createInstance("Frame", { Parent = root })
			local sheet = env.createInstance "StyleSheet"
			env.createInstance("StyleLink", { StyleSheet = sheet, Parent = root })
			local rule = env.createInstance("StyleRule", { Selector = ".Card::UICorner", Parent = sheet })
			invoke(rule, "SetProperty", "CornerRadius", "unmodeled")
			check:expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0)
			local signal =
				invoke(frame, "GetStyledPropertyChangedSignal", "BackgroundTransparency") :: Environment.Signal<()>
			local fired = 0
			signal:Connect(function()
				fired += 1
			end)
			ui.step()
			check:expect(fired):toEqual(0)
			invoke(rule, "SetProperty", "BackgroundTransparency", 0.5)
			check:expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0)
			invoke(rule, "SetProperty", "BackgroundTransparency", nil)
			local child = env.createInstance("StyleRule", { Selector = "Frame", Parent = rule })
			invoke(child, "SetProperty", "BackgroundTransparency", 0.5)
			check:expect((pcall(ui.styled, frame, "BackgroundTransparency"))):toEqual(false)
			invoke(child, "SetProperty", "BackgroundTransparency", nil)
			check:expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0)
			ui.close()
			check:expect(env.liveConnections()):toEqual(0)
		end)
		suite:case("unsupported styling fails before exposing raw fallback", function(check)
			local env = create()
			local ui = UI.attach(env)
			local root = env.createInstance "Folder"
			local frame = env.createInstance("Frame", { Parent = root })
			local sheet = env.createInstance "StyleSheet"
			env.createInstance("StyleLink", { StyleSheet = sheet, Parent = root })
			local rule = env.createInstance("StyleRule", { Selector = "Frame:hover", Parent = sheet })
			invoke(rule, "SetProperty", "BackgroundTransparency", 0.5)
			check:expect((pcall(ui.styled, frame, "BackgroundTransparency"))):toEqual(false)
			rule.Selector = "Frame"
			invoke(rule, "SetPropertyTransition", "BackgroundTransparency", { Time = 1 })
			check:expect((pcall(ui.styled, frame, "BackgroundTransparency"))):toEqual(false)
			invoke(rule, "SetPropertyTransition", "BackgroundTransparency", { Time = 0 })
			check:expect(ui.styled(frame, "BackgroundTransparency")):toEqual(0.5)
			invoke(sheet, "SetDerives", { env.createInstance "StyleSheet" })
			check:expect((pcall(ui.styled, frame, "BackgroundTransparency"))):toEqual(false)
		end)
		suite:case("release emits submission state and media records explicit playback state", function(check)
			local env = create()
			local controller = UI.attach(env)
			local textbox = env.createInstance "TextBox"
			local submitted = false
			local connection = (textbox.FocusLost :: Environment.Signal<boolean, unknown>):Connect(
				function(value: boolean)
					submitted = value
				end
			)
			invoke(textbox, "CaptureFocus")
			invoke(textbox, "ReleaseFocus", true)
			check:expect(submitted):toEqual(true)
			check:expect(controller.focused()):toEqual(nil)
			connection:Disconnect()
			local video = env.createInstance "VideoFrame"
			invoke(video, "Play")
			check:expect(video.Playing):toEqual(true)
			invoke(video, "Pause")
			check:expect(video.Playing):toEqual(false)
			check:expect(env.liveConnections()):toEqual(0)
		end)
		suite:case("style derivations copy lists and reject unrelated objects", function(check)
			local env = create()
			UI.attach(env)
			local sheet = env.createInstance "StyleSheet"
			local base = env.createInstance "StyleSheet"
			local values = { base }
			invoke(sheet, "SetDerives", values)
			table.clear(values)
			local read = invoke(sheet, "GetDerives") :: { Environment.Instance }
			check:expect(read[1] == base):toEqual(true)
			table.clear(read)
			check:expect(#(invoke(sheet, "GetDerives") :: { Environment.Instance })):toEqual(1)
			check
				:expect(pcall(function()
					invoke(sheet, "SetDerives", { env.createInstance "Folder" })
				end))
				:toEqual(false)
		end)
		suite:case("path storage copies arrays and instant page jumps emit state changes", function(check)
			local env = create()
			UI.attach(env)
			local path = env.createInstance "Path2D"
			local values: { unknown } = { "explicit-point" }
			invoke(path, "SetControlPoints", values)
			table.clear(values)
			check:expect((invoke(path, "GetControlPoints") :: { unknown })[1]):toEqual "explicit-point"
			local container = env.createInstance "Frame"
			local layout = env.createInstance("UIPageLayout", { Parent = container })
			local page = env.createInstance("Frame", { Parent = container })
			local entered = false
			local connection = (layout.PageEnter :: Environment.Signal<Environment.Instance>):Connect(function(value)
				entered = value == page
			end)
			invoke(layout, "JumpTo", page)
			check:expect(layout.CurrentPage == page and entered):toEqual(true)
			page.Visible = false
			check
				:expect(pcall(function()
					invoke(layout, "JumpTo", page)
				end))
				:toEqual(false)
			connection:Disconnect()
		end)
		suite:case("path and page refuse behavior until explicitly injected", function(check)
			local env = create()
			UI.attach(env)
			local path = env.createInstance "Path2D"
			local page = env.createInstance "UIPageLayout"
			check
				:expect(pcall(function()
					invoke(path, "GetLength")
				end))
				:toEqual(false)
			check
				:expect(pcall(function()
					invoke(page, "Next")
				end))
				:toEqual(false)
			env.fake("Path2D.GetLength", function(_object: Environment.Instance): number
				return 42
			end)
			check:expect(invoke(path, "GetLength")):toEqual(42)
		end)
	end)
end
