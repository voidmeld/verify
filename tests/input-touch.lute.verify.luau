--!strict
local Test = require "./harness"
local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

local cases: { { name: string, source: string, limitations: { string }? } } = {
	{
		name = "touch contact events and button activation match native input",
		source = require "./fixtures/input-touch-button",
	},
	{ name = "touch drag capture matches native input", source = require "./fixtures/input-touch-drag" },
	{
		name = "touch taps transfer text focus and preserve the accepted edit",
		source = [=[
local simulator = game:GetService("StudioDeviceSimulatorService")
simulator:SetDeviceAsync("iphone_14")
local input, gui = game:GetService("UserInputService"), game:GetService("GuiService")
local virtual = input:CreateVirtualInput()
local screen = Instance.new("ScreenGui")
screen.Parent = game.Players.LocalPlayer.PlayerGui
local first = Instance.new("TextBox")
first.Text, first.ClearTextOnFocus = "seed", false
first.Size, first.Parent = UDim2.fromOffset(150, 50), screen
local second = Instance.new("TextBox")
second.Text, second.ClearTextOnFocus = "other", false
second.Size, second.Position, second.Parent = UDim2.fromOffset(150, 50), UDim2.fromOffset(0, 80), screen
local gained, lost = 0, 0
first.Focused:Connect(function() gained += 1 end)
first.FocusLost:Connect(function(submitted) assert(not submitted); lost += 1 end)
task.wait(.05)
local function tap(box)
 local at = box.AbsolutePosition + box.AbsoluteSize / 2 - gui:GetInsetArea(Enum.ScreenInsets.None).Min
 virtual:SendMousePosition(at)
 virtual:SendMouseButton(at, Enum.UserInputType.MouseButton1, true)
 virtual:SendMouseButton(at, Enum.UserInputType.MouseButton1, false)
 task.wait(.05)
end
tap(first)
assert(first:IsFocused() and input:GetFocusedTextBox() == first and gained == 1)
virtual:SendTextInput("hi")
task.wait(.05)
assert(first.Text == "seedhi")
tap(first)
assert(first:IsFocused() and gained == 1 and lost == 0)
second.TextEditable = false
tap(second)
assert(not first:IsFocused() and not second:IsFocused() and lost == 1)
second.TextEditable = true
tap(second)
assert(second:IsFocused() and first.Text == "seedhi")
screen:Destroy()
simulator:StopSimulationAsync()
return true
]=],
	},
	{
		name = "pointer actions route nested scrolling and preserve native events",
		source = require "./fixtures/input-pointer-actions",
	},
	{
		name = "sibling shields route clicks, wheel and touch scrolling as Studio 0.745 reports",
		source = require "./fixtures/input-scroll-shield",
		limitations = {
			"One full-screen sibling shield in one ScreenGui; other overlay classes and DisplayOrder combinations are not measured.",
			"Touch without InputSink.All on a plain Frame, and touch with Active false, are not measured.",
			"Drags that start before a shield opens, cross its bounds, use multiple contacts, overscroll or produce inertia are not measured.",
			"The scrolling shield uses Active true, CanvasSize zero and ScrollBarThickness zero; other shield settings are not measured.",
			"Shielding of Pan and Pinch actions, mixed wheel and touch motion, and processed-event flags are not measured.",
		},
	},
}
for _, case in cases do
	Test.it(case.name, {
		limitations = case.limitations,
		run = function(own)
			local roots: { Roblox.Instance } = {}
			local placed: Roblox.PlaceRuntime? = nil
			local bridge = Lute.fixture.bridge(nil, {
				layout = {
					roots = function()
						return roots
					end,
					viewport = function()
						local viewport = assert(placed).device().viewport
						return { X = viewport[1], Y = viewport[2] }
					end,
					screenArea = function(screen)
						return assert(placed).screenArea(screen)
					end,
				},
			})
			own(function()
				bridge.close()
			end)
			local engine = bridge.placeEngine()
			local runtime = Roblox.createPlaceRuntime(engine, { root = engine.game, scripts = {}, sources = {} }, {
				aliases = {},
				cache = Roblox.createPlaceCache(Lute.fixture.host),
				host = Lute.fixture.host,
				client = { name = "Touch", userId = 1, viewport = { x = 800, y = 600 } },
				beforeRender = assert(bridge.layout).step,
			})
			placed = runtime
			own(function()
				for index = #runtime.closeHandlers, 1, -1 do
					runtime.closeHandlers[index]()
				end
			end)
			local playerGui = assert(assert(runtime.localPlayer):FindFirstChild "PlayerGui")
			table.insert(roots, playerGui)
			local input = Roblox.inputHost.simulated(bridge.environment, {
				playerGui = playerGui,
				inputService = engine.service "UserInputService",
				layout = assert(bridge.layout),
				inset = function()
					local inset = runtime.device().guiInset
					return { X = inset[1], Y = inset[2] }
				end,
				library = engine.datatypes,
				activationWindowSeconds = 0.5,
				read = assert(bridge.ui).styled,
			})
			own(input.close)
			local complete = false
			local scheduler = bridge.environment.scheduler
			local thread = scheduler.spawnTagged({ context = "client", source = "input-touch" }, function()
				complete = Lute.chunk.load(case.source, { environment = runtime.globals })() == true
			end)
			own(function()
				scheduler.cancel(thread)
			end)
			for _ = 1, 1200 do
				if complete or #scheduler.failures > 0 then
					break
				end
				runtime.step(1 / 60)
			end
			Test.expect(scheduler.failures):toEqual {}
			Test.expect(engine.diagnostics):toEqual {}
			Test.expect(complete):toBe(true)
		end,
	})
end

return nil
