--!strict

local Core = require "../src/core"
local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

local probe = [==[
local RS = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local v = UIS:CreateVirtualInput()
local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local g = Instance.new("ScreenGui"); g.Parent = pg
local inset = game:GetService("GuiService"):GetGuiInset()
local log = {}
local box = Instance.new("TextBox"); box.Size = UDim2.fromOffset(200, 40); box.Position = UDim2.fromOffset(100, 200); box.Text = "Racer"; box.ClearTextOnFocus = true; box.TextSize = 16; box.Parent = g
local other = Instance.new("Frame"); other.Size = UDim2.fromOffset(100, 40); other.Position = UDim2.fromOffset(400, 200); other.Active = true; other.Parent = g
box.Focused:Connect(function() table.insert(log, "focused") end)
box.FocusLost:Connect(function(enter, input) table.insert(log, `lost:{enter}:{input and input.UserInputType.Name or "nil"}`) end)
box.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then table.insert(log, "began") end end)
RS.RenderStepped:Wait()
local p = Vector2.new(150, 220) + inset
v:SendMousePosition(p); RS.RenderStepped:Wait()
v:SendMouseButton(p, Enum.UserInputType.MouseButton1, true); RS.RenderStepped:Wait(); table.insert(log, `|down focused={box:IsFocused()} text={box.Text}`)
v:SendMouseButton(p, Enum.UserInputType.MouseButton1, false); RS.RenderStepped:Wait(); RS.RenderStepped:Wait(); table.insert(log, `|up focused={box:IsFocused()} text={box.Text} cursor={box.CursorPosition}`)
v:SendTextInput("X"); RS.RenderStepped:Wait(); RS.RenderStepped:Wait(); table.insert(log, `|typed text={box.Text} cursor={box.CursorPosition}`)
local q = Vector2.new(450, 220) + inset
v:SendMousePosition(q); RS.RenderStepped:Wait()
v:SendMouseButton(q, Enum.UserInputType.MouseButton1, true); RS.RenderStepped:Wait(); table.insert(log, `|otherdown focused={box:IsFocused()}`)
v:SendMouseButton(q, Enum.UserInputType.MouseButton1, false); RS.RenderStepped:Wait(); RS.RenderStepped:Wait(); table.insert(log, `|otherup focused={box:IsFocused()}`)
local got = table.concat(log, " ")
local want = "focused began |down focused=true text= |up focused=true text= cursor=1 |typed text=X cursor=2 lost:false:MouseButton1 |otherdown focused=false |otherup focused=false"
g:Destroy()
assert(got == want, `got "{got}"`)
return true
]==]

return function(harness: Core.Harness)
	harness:case(
		"a click focuses an empty TextBox and a click elsewhere releases it as Studio 0.744 does",
		function(check)
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
			check:defer(function()
				bridge.close()
			end)
			local engine = bridge.placeEngine()
			local runtime = Roblox.createPlaceRuntime(engine, { root = engine.game, scripts = {}, sources = {} }, {
				aliases = {},
				cache = Roblox.createPlaceCache(Lute.fixture.host),
				host = Lute.fixture.host,
				client = { name = "TextBoxFocus", userId = 1, viewport = { x = 800, y = 600 } },
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
				library = Roblox.reflectionSnapshot.library(Lute.fixture.load()),
				activationWindowSeconds = 0.5,
				read = assert(bridge.ui).styled,
			})
			check:defer(input.close)
			local complete = false
			local scheduler = bridge.environment.scheduler
			local thread = scheduler.spawnTagged({ context = "client", source = "input-textbox-focus" }, function()
				complete = Lute.chunk.load(probe, { environment = runtime.globals })() == true
			end)
			check:defer(function()
				scheduler.cancel(thread)
			end)
			for _ = 1, 240 do
				if complete or #scheduler.failures > 0 then
					break
				end
				runtime.step(1 / 60)
			end
			check:expect(scheduler.failures):toEqual {}
			check:expect(engine.diagnostics):toEqual {}
			check:expect(complete):toBe(true)
		end
	)
end
