--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local Lute = require "../src/lute"
local virtualControllerProbe = require "./fixtures/input-virtual-controller"

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
			name = "virtual controller events match native button trigger and stick traces",
			source = virtualControllerProbe,
		},
		{ name = "arrow keys move GuiService selection and Return activates it as Studio 0.744 does", source = probe },
		{ name = "held selection repeats and stops on release", source = require "./fixtures/input-selection-repeat" },
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
		local input = Roblox.inputHost.simulated(bridge.environment, {
			virtualController = case.source == virtualControllerProbe,
			playerGui = playerGui,
			inputService = engine.service "UserInputService",
			layout = assert(bridge.layout),
			inset = function()
				return { X = 0, Y = 0 }
			end,
			library = (engine.datatypes :: unknown) :: Roblox.DatatypeLibrary,
			activationWindowSeconds = 0.5,
			read = assert(bridge.ui).styled,
		})
		own(input.close)
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
	end)
end

return nil
