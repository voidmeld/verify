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
