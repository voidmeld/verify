--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local Lute = require "../src/lute"
local Gamepad = require "../src/roblox/input-gamepad"
local Vector = require "../src/roblox/datatypes/vector"
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

it("selection publication preserves authored layout changes in selection handlers", function(own)
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
	own(bridge.close)
	local env, engine = bridge.environment, bridge.placeEngine()
	local library = engine.datatypes
	local gui = env.createEngineInstance("PlayerGui", { Parent = engine.game })
	local screen = env.createInstance("ScreenGui", { Parent = gui, IgnoreGuiInset = true })
	own(function()
		gui:Destroy()
	end)
	local first =
		env.createInstance("TextButton", { Parent = screen, Text = "", Size = library.UDim2.fromOffset(30, 30) })
	local second = assert(first:Clone())
	second.Position, second.Parent = library.UDim2.fromOffset(50, 0), screen
	table.insert(roots, gui)
	local service, selection = engine.service "UserInputService", engine.service "GuiService"
	env.poke(service, "GamepadEnabled", false)
	env.poke(service, "PreferredInput", library.Enum.PreferredInput.KeyboardAndMouse)
	local layout = assert(bridge.layout)
	local input = Roblox.inputHost.simulated(env, {
		playerGui = gui,
		inputService = service,
		layout = layout,
		library = library,
		activationWindowSeconds = 0.5,
		virtualController = true,
		inset = function()
			return { X = 0, Y = 0 }
		end,
		read = assert(bridge.ui).styled,
	})
	own(input.close)
	env.method(service, "GetGamepadState")(service, library.Enum.UserInputType.Gamepad1)
	env.poke(selection, "SelectedObject", first)
	layout.step()
	local events, move = 0, false
	local changed = selection:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		events += 1
		if move then
			second.Position = library.UDim2.fromOffset(80, 0)
		end
	end)
	own(function()
		changed:Disconnect()
	end)
	local function press(code: string)
		for _, down in { true, false } do
			input.key { code = code, down = down }
			env.step(1 / 60)
			layout.step()
		end
	end
	local before = env.revision()
	press "Four"
	expect(env.revision()):toBe(before)
	expect(env.propertyOf(selection, "SelectedObject")):toBe(second)
	expect(events):toBe(1)
	move = true
	press "Two"
	expect(env.revision() > before):toBe(true)
	expect(second.AbsolutePosition):toEqual(library.Vector2.new(80, 0))
	expect(events):toBe(2)
	move = false
	local current = env.revision()
	selection.SelectedObject = second
	layout.step()
	expect(env.revision()):toBe(current)
	expect(events):toBe(3)
	local scrolling = env.createInstance("ScrollingFrame", {
		Parent = screen,
		Size = library.UDim2.fromOffset(100, 100),
		CanvasSize = library.UDim2.fromOffset(100, 400),
		ScrollingDirection = library.Enum.ScrollingDirection.Y,
	})
	second.Parent, second.Position = scrolling, library.UDim2.fromOffset(0, 300)
	first.NextSelectionRight = second
	env.poke(selection, "SelectedObject", first)
	move = false
	layout.step()
	press "Four"
	expect(env.propertyOf(selection, "SelectedObject")):toBe(second)
	local observed = Vector.expect2(scrolling.CanvasPosition, 1)
	expect(observed.Y > 0):toBe(true)
	expect(second.AbsolutePosition):toEqual(library.Vector2.new(0, 300 - observed.Y))
end)

it("a hot-plugged virtual controller connects, takes primacy on pad input and disconnects", function(own)
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
	own(bridge.close)
	local env, engine = bridge.environment, bridge.placeEngine()
	local library = engine.datatypes
	local gui = env.createEngineInstance("PlayerGui", { Parent = engine.game })
	own(function()
		gui:Destroy()
	end)
	table.insert(roots, gui)
	local service = engine.service "UserInputService"
	local preferred = library.Enum.PreferredInput
	env.poke(service, "GamepadEnabled", false)
	env.poke(service, "PreferredInput", preferred.KeyboardAndMouse)
	local input = Roblox.inputHost.simulated(env, {
		playerGui = gui,
		inputService = service,
		layout = assert(bridge.layout),
		library = library,
		activationWindowSeconds = 0.5,
		inset = function()
			return { X = 0, Y = 0 }
		end,
		read = assert(bridge.ui).styled,
	})
	own(input.close)
	local devices: { string } = {}
	local kinds: { string } = {}
	local changes: { string } = {}
	local context = env.createInstance("InputContext", { Parent = gui, Priority = 10, Sink = true })
	local axis =
		env.createInstance("InputAction", { Parent = context, Type = library.Enum.InputActionType.Direction2D })
	env.createInstance("InputBinding", { Parent = axis, KeyCode = library.Enum.KeyCode.Thumbstick2 })
	local axes: { unknown } = {}
	local connections = {
		env.event(axis, "StateChanged"):Connect(function(value)
			table.insert(axes, value)
		end),
		env.event(service, "LastInputTypeChanged"):Connect(function(kind)
			table.insert(changes, tostring(kind))
		end),
		env.event(service, "GamepadConnected"):Connect(function(gamepad)
			table.insert(devices, "connected " .. tostring(gamepad))
		end),
		env.event(service, "GamepadDisconnected"):Connect(function(gamepad)
			table.insert(devices, "disconnected " .. tostring(gamepad))
		end),
		env.event(service, "InputBegan"):Connect(function(object)
			table.insert(kinds, tostring(env.propertyOf(Roblox.assertInstance(object), "UserInputType")))
		end),
	}
	own(function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)
	local function press(code: string)
		for _, down in { true, false } do
			input.key { code = code, down = down }
			env.step(1 / 60)
		end
	end
	press "Nine"
	expect(kinds):toEqual { "Enum.UserInputType.Keyboard" }
	input.connectGamepad()
	expect(devices):toEqual { "connected Enum.UserInputType.Gamepad1" }
	expect(service.GamepadEnabled):toBe(true)
	expect(env.method(service, "GetConnectedGamepads")(service)):toEqual { library.Enum.UserInputType.Gamepad1 }
	expect(service.PreferredInput):toBe(preferred.KeyboardAndMouse)
	expect(pcall(input.connectGamepad)):toBe(false)
	press "Nine"
	expect(kinds[2]):toBe "Enum.UserInputType.Gamepad1"
	expect(service.PreferredInput):toBe(preferred.Gamepad)
	input.key { code = "I", down = true }
	env.step(1 / 60)
	expect(env.method(axis, "GetState")(axis)):toEqual(library.Vector2.new(0, 1))
	input.key { code = "I", down = false }
	env.step(1 / 60)
	expect(env.method(axis, "GetState")(axis)):toEqual(library.Vector2.zero)
	expect(axes):toEqual { library.Vector2.new(0, 1), library.Vector2.zero }
	input.disconnectGamepad()
	expect(devices[2]):toBe "disconnected Enum.UserInputType.Gamepad1"
	expect(service.GamepadEnabled):toBe(false)
	expect(service.PreferredInput):toBe(preferred.KeyboardAndMouse)
	expect(pcall(input.disconnectGamepad)):toBe(false)
	press "Nine"
	expect(kinds[3]):toBe "Enum.UserInputType.Keyboard"
	expect(changes):toEqual {
		"Enum.UserInputType.Keyboard",
		"Enum.UserInputType.Gamepad1",
		"Enum.UserInputType.Keyboard",
	}
	input.pointer { x = 10, y = 10, button = "left", down = true }
	input.pointer { x = 10, y = 10, button = "left", down = false }
	expect(changes[4]):toBe "Enum.UserInputType.MouseMovement"
	expect(changes[5]):toBe "Enum.UserInputType.MouseButton1"
	expect(env.method(service, "GetLastInputType")(service)):toBe(library.Enum.UserInputType.MouseButton1)
end)

it("gamepad state publication keeps authored geometry revisions for callback writes", function(own)
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
	own(bridge.close)
	local env, library = bridge.environment, bridge.placeEngine().datatypes
	local screen = env.createInstance "ScreenGui"
	table.insert(roots, screen)
	own(function()
		screen:Destroy()
	end)
	local target = env.createInstance("Frame", { Parent = screen, Size = library.UDim2.fromOffset(100, 40) })
	local events, move = 0, false
	local gamepad = Gamepad.create(env, library, function(kind: unknown): Roblox.Instance
		local object = env.createEngineInstance "InputObject"
		env.poke(object, "UserInputType", kind)
		env.poke(object, "Position", library.Vector3.zero)
		own(function()
			env.releaseObject(object)
		end)
		return object
	end, function()
		events += 1
		if move then
			target.Position = library.UDim2.fromOffset(40, 30)
		end
	end)
	gamepad.state(library.Enum.UserInputType.Gamepad1)
	local layout = assert(bridge.layout)
	layout.step()
	local before, published = env.revision()
	gamepad.key("Eight", true)
	gamepad.key("Eight", false)
	local after, updated = env.revision()
	expect(after):toBe(before)
	expect(updated > published):toBe(true)
	expect(events):toBe(2)
	move = true
	gamepad.key("Eight", true)
	expect(env.revision() > after):toBe(true)
	layout.step()
	expect(target.AbsolutePosition):toEqual(library.Vector2.new(40, 30))
end)

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
assert(not chord:GetState(), "releasing either required modifier releases the held action")
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
		{
			name = "Return TextBox focus and processed events match Studio 0.745",
			source = [=[
local screen = Instance.new("ScreenGui")
screen.Parent = game.Players.LocalPlayer.PlayerGui
local box = Instance.new("TextBox")
box.Text, box.ClearTextOnFocus = "seed", false
box.Size, box.Parent = UDim2.fromOffset(200, 40), screen
local input, gui = game.UserInputService, game.GuiService
local virtual = input:CreateVirtualInput()
local events = {}
local function record(event)
	table.insert(events, event .. "/" .. tostring(input:GetFocusedTextBox() == box) .. "/" .. box.CursorPosition)
end
local connections = {
	box.Focused:Connect(function() record("focused") end),
	box.FocusLost:Connect(function(submitted, cause)
		assert(submitted and cause.KeyCode == Enum.KeyCode.Return)
		record("lost")
	end),
	input.InputBegan:Connect(function(object, processed)
		if object.KeyCode == Enum.KeyCode.Return then record("began/" .. tostring(processed)) end
	end),
	input.InputEnded:Connect(function(object, processed)
		if object.KeyCode == Enum.KeyCode.Return then record("ended/" .. tostring(processed)) end
	end),
}
task.wait(0.05)
gui.SelectedObject = box
for _ = 1, 2 do
	virtual:SendKey(true, Enum.KeyCode.Return, false)
	task.wait(0.05)
	virtual:SendKey(false, Enum.KeyCode.Return, false)
	task.wait(0.05)
end
assert(table.concat(events, "|") == "focused/true/5|began/false/true/5|ended/true/true/5|lost/false/-1|began/true/false/-1|ended/false/false/-1", table.concat(events, "|"))
assert(box.Text == "seed" and gui.SelectedObject == box)
for _, connection in connections do connection:Disconnect() end
gui.SelectedObject = nil
screen:Destroy()
return true
]=],
		},
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
				box.CursorPosition = 3
				local virtual = game.UserInputService:CreateVirtualInput()
				virtual:SendKey(true, Enum.KeyCode.Return, false)
				task.wait(0.05)
				virtual:SendKey(false, Enum.KeyCode.Return, false)
				task.wait(0.05)
				assert(box:IsFocused(), "multiline Return retains editing focus")
				assert(box.Text == "é\nx", "multiline Return inserts at the UTF-8 cursor")
				assert(box.CursorPosition == 4, "multiline Return advances the byte cursor")
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
			name = "action teardown retains its last preferred binding",
			source = require "./fixtures/input-action-teardown",
		},
		{ name = "pointer focus respects native GUI barriers", source = require "./fixtures/input-pointer-focus" },
		{ name = "text selections edit complete byte ranges", source = require "./fixtures/input-text-editing" },
		{
			name = "directional selection prioritizes overlapping rectangles",
			source = require "./fixtures/input-selection-geometry",
		},
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
		for _ = 1, 600 do
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

it("selection transfers emit gained and lost once with the current selection", function(own)
	local bridge = Lute.fixture.bridge(nil, { ui = { selection = "native" } })
	own(bridge.close)
	local env, engine = bridge.environment, bridge.placeEngine()
	local playerGui = env.createEngineInstance("PlayerGui", { Parent = engine.game })
	local screen = env.createInstance("ScreenGui", { Parent = playerGui })
	local first = env.createInstance("TextButton", { Name = "first", Parent = screen })
	local second = env.createInstance("TextButton", { Name = "second", Parent = screen })
	local service = engine.service "GuiService"
	local events: { string } = {}
	for _, target in { first, second } do
		for _, event in { "SelectionGained", "SelectionLost" } do
			env.event(target, event):Connect(function()
				local selected = service.SelectedObject
				table.insert(
					events,
					env.nameOf(target)
						.. ":"
						.. event
						.. ":"
						.. (if Roblox.isInstance(selected) then env.nameOf(Roblox.assertInstance(selected)) else "nil")
				)
			end)
		end
	end
	service.SelectedObject = first
	service.SelectedObject = first
	env.publish(service, "SelectedObject", second)
	service.SelectedObject = nil
	expect(events):toEqual {
		"first:SelectionGained:first",
		"first:SelectionLost:second",
		"second:SelectionGained:second",
		"second:SelectionLost:nil",
	}
	first.Selectable = false
	service.SelectedObject = first
	service.SelectedObject = nil
	expect(#events):toBe(4)
end)

return nil
