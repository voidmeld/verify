--!strict

local Core = require "../src/core"
local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

local probe = [==[
local UIS = game:GetService("UserInputService")
local log = {}
local function note(s) table.insert(log, s) end
local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local function context(name, priority, sink)
	local c = Instance.new("InputContext"); c.Name = name; c.Priority = priority; c.Sink = sink
	local a = Instance.new("InputAction"); a.Name = name .. "Action"; a.Parent = c
	local b = Instance.new("InputBinding"); b.KeyCode = Enum.KeyCode.E; b.Parent = a
	a.Pressed:Connect(function() note(name .. " Pressed") end)
	a.Released:Connect(function() note(name .. " Released") end)
	a.StateChanged:Connect(function(v) note(name .. " StateChanged " .. tostring(v)) end)
	c.Parent = pg
	return c
end
local low = context("Low", 1, false)
local high = context("High", 10, true)
local c1 = UIS.InputBegan:Connect(function(i, gp) note("UIS Began " .. i.KeyCode.Name .. " gp=" .. tostring(gp)) end)
local c2 = UIS.InputEnded:Connect(function(i, gp) note("UIS Ended " .. i.KeyCode.Name .. " gp=" .. tostring(gp)) end)
local virtual = UIS:CreateVirtualInput()
virtual:SendKey(true, Enum.KeyCode.E, false)
note("after down (sync)")
task.wait(0.1)
virtual:SendKey(false, Enum.KeyCode.E, false)
task.wait(0.1)
high.Sink = false
virtual:SendKey(true, Enum.KeyCode.E, false)
task.wait(0.1)
virtual:SendKey(false, Enum.KeyCode.E, false)
task.wait(0.1)
low:Destroy(); high:Destroy()
local gui = Instance.new("ScreenGui"); gui.Parent = pg
local box = Instance.new("TextBox"); box.Size = UDim2.fromOffset(200, 40); box.Text = ""; box.ClearTextOnFocus = false; box.Parent = gui
local c = Instance.new("InputContext"); c.Priority = 1
local a = Instance.new("InputAction"); a.Parent = c
local b = Instance.new("InputBinding"); b.KeyCode = Enum.KeyCode.E; b.Parent = a
a.Pressed:Connect(function() note("Action Pressed") end)
c.Parent = pg
box.FocusLost:Connect(function(enter) note("FocusLost enter=" .. tostring(enter) .. " text=" .. box.Text) end)
box:GetPropertyChangedSignal("Text"):Connect(function() note("Text=" .. box.Text) end)
c2:Disconnect()
task.wait(0.1)
box:CaptureFocus()
task.wait(0.1)
virtual:SendKey(true, Enum.KeyCode.E, false); task.wait(0.05); virtual:SendKey(false, Enum.KeyCode.E, false); task.wait(0.05)
virtual:SendTextInput("hi"); task.wait(0.1)
virtual:SendKey(true, Enum.KeyCode.Backspace, false); task.wait(0.05); virtual:SendKey(false, Enum.KeyCode.Backspace, false); task.wait(0.05)
virtual:SendKey(true, Enum.KeyCode.Return, false); task.wait(0.05); virtual:SendKey(false, Enum.KeyCode.Return, false); task.wait(0.1)
note("focused=" .. tostring(box:IsFocused()) .. " final=" .. box.Text)
virtual:SendKey(true, Enum.KeyCode.E, false); task.wait(0.05); virtual:SendKey(false, Enum.KeyCode.E, false); task.wait(0.05)
c1:Disconnect(); gui:Destroy(); c:Destroy()
local function names()
	local t = {}
	for _, k in UIS:GetKeysPressed() do table.insert(t, k.KeyCode.Name) end
	return table.concat(t, ",")
end
virtual:SendKey(true, Enum.KeyCode.Z, false); task.wait(0.3)
virtual:SendKey(true, Enum.KeyCode.C, false); task.wait(0.3)
note("ZC=" .. names() .. " Z=" .. tostring(UIS:IsKeyDown(Enum.KeyCode.Z)) .. " Q=" .. tostring(UIS:IsKeyDown(Enum.KeyCode.Q)))
virtual:SendKey(false, Enum.KeyCode.Z, false); task.wait(0.3)
note("C=" .. names())
virtual:SendKey(false, Enum.KeyCode.C, false); task.wait(0.3)
note("none=" .. names())
return log
]==]

local STUDIO = {
	"after down (sync)",
	"UIS Began E gp=false",
	"High Pressed",
	"High StateChanged true",
	"UIS Ended E gp=false",
	"High Released",
	"High StateChanged false",
	"UIS Began E gp=false",
	"High Pressed",
	"High StateChanged true",
	"Low Pressed",
	"Low StateChanged true",
	"UIS Ended E gp=false",
	"High Released",
	"High StateChanged false",
	"Low Released",
	"Low StateChanged false",
	"UIS Began E gp=true",
	"Text=hi",
	"Text=h",
	"UIS Began Backspace gp=true",
	"FocusLost enter=true text=h",
	"UIS Began Return gp=true",
	"focused=false final=h",
	"UIS Began E gp=false",
	"Action Pressed",
	"ZC=C,Z Z=true Q=false",
	"C=C",
	"none=",
}

return function(harness: Core.Harness)
	harness:case("simulated keyboard input matches the Studio event order", function(check)
		local roots: { Roblox.Instance } = {}
		local snapshot = Lute.fixture.load()
		local bridge = Lute.fixture.bridge(snapshot, {
			handlerErrors = "raise",
			layout = {
				roots = function()
					return roots
				end,
				viewport = function()
					return { X = 800, Y = 600 }
				end,
			},
		})
		check:defer(function()
			bridge.close()
		end)
		local engine = bridge.placeEngine()
		local runtime = Roblox.createPlaceRuntime(engine, { root = engine.game, scripts = {}, sources = {} }, {
			aliases = {},
			cache = Roblox.createPlaceCache(Lute.fixture.host),
			host = Lute.fixture.host,
			client = { name = "Keys", userId = 1, viewport = { x = 800, y = 600 } },
			beforeRender = assert(bridge.layout).step,
		})
		check:defer(function()
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
				return { X = 0, Y = 0 }
			end,
			library = Roblox.reflectionSnapshot.library(snapshot),
			activationWindowSeconds = 0.5,
			read = assert(bridge.ui).styled,
		})
		check:defer(input.close)
		local log: { string }? = nil
		local scheduler = bridge.environment.scheduler
		local thread = scheduler.spawnTagged({ context = "client", source = "input-keyboard" }, function()
			log = Lute.chunk.load(probe, { environment = runtime.globals })() :: { string }
		end)
		check:defer(function()
			scheduler.cancel(thread)
		end)
		for _ = 1, 600 do
			if log or #scheduler.failures > 0 then
				break
			end
			runtime.step(1 / 60)
		end
		check:expect(scheduler.failures):toEqual {}
		check:expect(engine.diagnostics):toEqual {}
		check:expect(table.concat(log or {}, " | ")):toBe(table.concat(STUDIO, " | "))
	end)
end
