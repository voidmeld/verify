--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local Lute = require "../src/lute"
local virtualControllerProbe = require "./fixtures/input-virtual-controller"
local controllerSelectionProbe = require "./fixtures/input-controller-selection"

local textSelectionProbe = [=[
local pad = false
local screen = Instance.new("ScreenGui")
screen.Parent = game.Players.LocalPlayer.PlayerGui
local box = Instance.new("TextBox")
box.Text, box.ClearTextOnFocus, box.TextEditable = "seed", false, false
box.Size, box.Parent = UDim2.fromOffset(200, 40), screen
local input, gui = game.UserInputService, game.GuiService
local virtual = input:CreateVirtualInput()
local focused, released = 0, 0
box.Focused:Connect(function() focused += 1 end)
box.FocusLost:Connect(function(submitted, cause)
	released += 1
	if not pad then assert(submitted and cause.KeyCode == Enum.KeyCode.Return, "submit carries its input") end
end)
local function press()
	local code = if pad then Enum.KeyCode.Nine else Enum.KeyCode.Return
	virtual:SendKey(true, code, false)
	task.wait(0.05)
	virtual:SendKey(false, code, false)
	task.wait(0.05)
end
task.wait(0.05)
gui.SelectedObject = box
press()
assert(not box:IsFocused() and focused == 0, "noneditable selection does not enter editing")
box.TextEditable = true
press()
assert(box:IsFocused() and focused == 1 and released == 0, "accept enters editing once without submitting")
assert(box.Text == "seed", "selection entry retains text when ClearTextOnFocus is false")
if pad then box:ReleaseFocus() else press() end
assert(not box:IsFocused() and released == 1, "the edit releases once")
gui.SelectedObject = nil
screen:Destroy()
return true
]=]
local padTextSelectionProbe = string.gsub(textSelectionProbe, "local pad = false", "local pad = true", 1)

local probe = [==[
local RS = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local GS = game:GetService("GuiService")
local v = UIS:CreateVirtualInput()
local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local g = Instance.new("ScreenGui"); g.Parent = pg
local log = {}
local function button(name, x, y)
	local b = Instance.new("TextButton"); b.Name = name; b.Size = UDim2.fromOffset(100, 50); b.Position = UDim2.fromOffset(x, y); b.Parent = g
	b.Activated:Connect(function(i) table.insert(log, `activated:{name}:{i.KeyCode.Name}`) end)
	return b
end
local b1 = button("B1", 100, 200)
button("B2", 250, 200)
button("B3", 400, 200)
button("Below", 250, 350)
local context = Instance.new("InputContext"); context.Priority = 3000; context.Parent = g
local action = Instance.new("InputAction"); action.Parent = context
for _, code in { Enum.KeyCode.Right, Enum.KeyCode.Return, Enum.KeyCode.E } do
	local binding = Instance.new("InputBinding"); binding.KeyCode = code; binding.Parent = action
end
action.Pressed:Connect(function() table.insert(log, "action") end)
local began = UIS.InputBegan:Connect(function(i, processed) table.insert(log, `began:{i.KeyCode.Name}:{processed}`) end)
RS.RenderStepped:Wait()
GS.SelectedObject = b1
local function press(code)
	v:SendKey(true, code, false); RS.RenderStepped:Wait()
	v:SendKey(false, code, false); RS.RenderStepped:Wait()
	table.insert(log, `|{GS.SelectedObject and GS.SelectedObject.Name or "nil"}`)
end
press(Enum.KeyCode.Right)
press(Enum.KeyCode.Down)
press(Enum.KeyCode.Return)
press(Enum.KeyCode.E)
began:Disconnect()
GS.SelectedObject = nil
g:Destroy()
local got = table.concat(log, " ")
local want = "began:Right:true |B2 began:Down:true |Below began:Return:true activated:Below:Return |Below began:E:false action |Below"
assert(got == want, "got " .. got)
return true
]==]

for _, case in
	{
		{
			name = "keyboard bindings require both modifiers before the key and release their original actions",
			source = [=[
local screen = Instance.new("ScreenGui")
screen.Parent = game.Players.LocalPlayer.PlayerGui
local counts = {Plain = 0, Chord = 0}
local function action(name, priority, primary, secondary)
	local context = Instance.new("InputContext")
	context.Priority, context.Sink, context.Parent = priority, true, screen
	local target = Instance.new("InputAction")
	target.Parent = context
	local binding = Instance.new("InputBinding")
	binding.KeyCode, binding.Parent = Enum.KeyCode.K, target
	if primary then binding.PrimaryModifier = primary end
	if secondary then binding.SecondaryModifier = secondary end
	target.Pressed:Connect(function() counts[name] += 1 end)
	return target
end
action("Plain", 1)
local chord = action("Chord", 2, Enum.KeyCode.LeftShift, Enum.KeyCode.LeftControl)
local virtual = game.UserInputService:CreateVirtualInput()
local function send(code, down)
	virtual:SendKey(down, code, false)
	task.wait(0.05)
end
local function tap() send(Enum.KeyCode.K, true) send(Enum.KeyCode.K, false) end
tap()
assert(counts.Plain == 1 and counts.Chord == 0, "plain key excludes the chord")
send(Enum.KeyCode.LeftShift, true)
tap()
assert(counts.Plain == 2 and counts.Chord == 0, "one modifier does not satisfy two")
send(Enum.KeyCode.LeftControl, true)
send(Enum.KeyCode.K, true)
assert(counts.Plain == 2 and counts.Chord == 1, "qualified higher priority chord sinks the plain key")
send(Enum.KeyCode.LeftShift, false)
send(Enum.KeyCode.K, false)
assert(not chord:GetState(), "key release resets the chord after its modifier released")
send(Enum.KeyCode.LeftShift, true)
tap()
assert(counts.Chord == 2, "the chord can activate again")
send(Enum.KeyCode.LeftShift, false)
send(Enum.KeyCode.LeftControl, false)
send(Enum.KeyCode.K, true)
send(Enum.KeyCode.LeftShift, true)
send(Enum.KeyCode.LeftControl, true)
assert(counts.Plain == 3 and counts.Chord == 2, "late modifiers do not steal an existing key")
send(Enum.KeyCode.K, false)
send(Enum.KeyCode.LeftShift, false)
send(Enum.KeyCode.LeftControl, false)
screen:Destroy()
return true
]=],
		},
		{ name = "Return accepts a selected TextBox without submitting the entering key", source = textSelectionProbe },
		{ name = "ButtonA accepts a selected editable TextBox", source = padTextSelectionProbe },
		{ name = "controller selection routes activation and DPad repeats", source = controllerSelectionProbe },
		{
			name = "virtual controller events match native button trigger and stick traces",
			source = virtualControllerProbe,
		},
		{ name = "arrow keys move GuiService selection and Return activates it as Studio 0.744 does", source = probe },
		{
			name = "Return inserts a hard break at the multiline TextBox cursor",
			source = [=[
				local screen = Instance.new("ScreenGui")
				screen.Parent = game.Players.LocalPlayer.PlayerGui
				local box = Instance.new("TextBox")
				box.Text, box.ClearTextOnFocus, box.MultiLine = "éx", false, true
				box.Size, box.Parent = UDim2.fromOffset(200, 100), screen
				box:CaptureFocus()
				box.CursorPosition = 2
				local virtual = game.UserInputService:CreateVirtualInput()
				virtual:SendKey(true, Enum.KeyCode.Return, false)
				task.wait(0.05)
				virtual:SendKey(false, Enum.KeyCode.Return, false)
				task.wait(0.05)
				assert(box:IsFocused(), "multiline Return retains editing focus")
				assert(box.Text == "é\nx", "multiline Return inserts at the UTF-8 cursor")
				assert(box.CursorPosition == 3, "multiline Return advances the cursor")
				box:ReleaseFocus()
				screen:Destroy()
				return true
			]=],
		},
		{
			name = "ScreenGui selection groups stop and release navigation",
			source = [=[
				local screen = Instance.new("ScreenGui")
				screen.IgnoreGuiInset, screen.Parent = true, game.Players.LocalPlayer.PlayerGui
				screen.SelectionGroup, screen.SelectionBehaviorRight = true, Enum.SelectionBehavior.Stop
				local outside = screen:Clone()
				outside.Parent = screen.Parent
				local first = Instance.new("TextButton")
				first.Text, first.Size, first.Position = "", UDim2.fromOffset(100, 40), UDim2.fromOffset(100, 100)
				first.Parent = screen
				local second = first:Clone()
				second.Position, second.Parent = UDim2.fromOffset(300, 100), outside
				local virtual = game.UserInputService:CreateVirtualInput()
				local gui = game.GuiService
				local function press()
					virtual:SendKey(true, Enum.KeyCode.Right, false)
					task.wait(0.05)
					virtual:SendKey(false, Enum.KeyCode.Right, false)
					task.wait(0.05)
				end
				task.wait(0.05)
				gui.SelectedObject = first
				press()
				assert(gui.SelectedObject == first, "ScreenGui stops selection at its boundary")
				screen.SelectionBehaviorRight = Enum.SelectionBehavior.Escape
				press()
				assert(gui.SelectedObject == second, "ScreenGui allows selection to escape")
				gui.SelectedObject = nil
				screen:Destroy()
				outside:Destroy()
				return true
			]=],
		},
		{ name = "held selection repeats and stops on release", source = require "./fixtures/input-selection-repeat" },
		{
			name = "navigation reevaluates shared ancestors after visibility interaction and ancestry changes",
			source = [=[
local gui = game.GuiService
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset, screen.Parent = true, game.Players.LocalPlayer.PlayerGui
local disabled = screen:Clone()
disabled.Enabled, disabled.Parent = false, screen.Parent
local function button(x, parent)
	local target = Instance.new("TextButton")
	target.Text, target.Size, target.Position = "", UDim2.fromOffset(30,30), UDim2.fromOffset(x,0)
	target.Parent = parent
	return target
end
local source = button(0, screen)
local outside = button(120, screen)
local parent = Instance.new("Frame")
parent.Size, parent.Visible, parent.Parent = UDim2.fromOffset(100,100), false, screen
local folder = Instance.new("Folder")
folder.Parent = parent
local inside = button(60, folder)
button(90, folder)
local virtual = game.UserInputService:CreateVirtualInput()
local function right(expected)
	task.wait(0.05)
	gui.SelectedObject = source
	virtual:SendKey(true, Enum.KeyCode.Right, false)
	task.wait(0.05)
	virtual:SendKey(false, Enum.KeyCode.Right, false)
	task.wait(0.05)
	assert(gui.SelectedObject == expected, "selection reflects current ancestor eligibility")
end
right(outside)
parent.Visible = true
right(inside)
parent.Interactable = false
right(outside)
parent.Interactable, parent.Parent = true, disabled
right(outside)
disabled.Enabled = true
right(inside)
parent.Parent = screen
inside.Selectable = false
right(folder:GetChildren()[2])
gui.SelectedObject = nil
screen:Destroy()
disabled:Destroy()
return true
]=],
		},
		{ name = "idle gamepad state exposes each control", source = require "./fixtures/input-gamepad-state" },
		{
			name = "GuiService Select chooses eligible descendants by order",
			source = require "./fixtures/input-gui-select",
		},
	}
do
	it(case.name, function(own)
		local roots: { Roblox.Instance } = {}
		local bridge = Lute.fixture.bridge(nil, {
			layout = {
				roots = function()
					return roots
				end,
				viewport = function()
					return { X = 800, Y = 600 }
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
			client = { name = "SelectionNavigation", userId = 1, viewport = { x = 800, y = 600 } },
			beforeRender = assert(bridge.layout).step,
		})
		own(function()
			for index = #runtime.closeHandlers, 1, -1 do
				runtime.closeHandlers[index]()
			end
		end)
		local playerGui = assert(assert(runtime.localPlayer):FindFirstChild "PlayerGui")
		table.insert(roots, playerGui)
		local inputService = engine.service "UserInputService"
		local priorGamepad, priorPreferred = inputService.GamepadEnabled, inputService.PreferredInput
		local priorKeyboard, priorMouse = inputService.KeyboardEnabled, inputService.MouseEnabled
		local input = Roblox.inputHost.simulated(bridge.environment, {
			virtualController = case.source == virtualControllerProbe
				or case.source == controllerSelectionProbe
				or case.source == padTextSelectionProbe,
			playerGui = playerGui,
			inputService = engine.service "UserInputService",
			layout = assert(bridge.layout),
			inset = function()
				return { X = 0, Y = 0 }
			end,
			library = engine.datatypes,
			activationWindowSeconds = 0.5,
			read = assert(bridge.ui).styled,
		})
		own(input.close)
		expect(inputService.KeyboardEnabled):toBe(priorKeyboard)
		expect(inputService.MouseEnabled):toBe(priorMouse)
		local complete = false
		local scheduler = bridge.environment.scheduler
		local thread = scheduler.spawnTagged({ context = "client", source = "input-selection-navigation" }, function()
			complete = Lute.chunk.load(case.source, { environment = runtime.globals })() == true
		end)
		own(function()
			scheduler.cancel(thread)
		end)
		for _ = 1, 360 do
			if complete or #scheduler.failures > 0 then
				break
			end
			runtime.step(1 / 60)
		end
		expect(scheduler.failures):toEqual {}
		expect(engine.diagnostics):toEqual {}
		expect(complete):toBe(true)
		local restored: unknown = nil
		local restoreConnection = inputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
			restored = bridge.environment.method(inputService, "GetLastInputType")(inputService)
		end)
		input.close()
		restoreConnection:Disconnect()
		if
			case.source == virtualControllerProbe
			or case.source == controllerSelectionProbe
			or case.source == padTextSelectionProbe
		then
			expect(restored ~= nil):toBe(true)
		end
		expect(inputService.GamepadEnabled):toBe(priorGamepad)
		expect(inputService.PreferredInput):toBe(priorPreferred)
	end)
end

return nil
