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
local failures = {}
local function expect(name, got, want) if got ~= want then table.insert(failures, `{name}: got "{got}" want "{want}"`) end end
for _, class in { "Frame", "TextButton" } do
	local target = Instance.new(class); target.Size = UDim2.fromOffset(100, 40); target.Position = UDim2.fromOffset(100, 200); target.Parent = g
	local d = Instance.new("UIDragDetector"); d.ResponseStyle = Enum.UIDragDetectorResponseStyle.CustomOffset; d.Parent = target
	local log = {}
	local function rec(name) return function(p) table.insert(log, `{name}@{string.format("%.0f,%.0f", p.X, p.Y)}`) end end
	d.DragStart:Connect(rec("start")); d.DragContinue:Connect(rec("cont")); d.DragEnd:Connect(rec("end"))
	if target:IsA("GuiButton") then target.Activated:Connect(function() table.insert(log, "activated") end) end
	target.InputBegan:Connect(function(i) table.insert(log, "began:" .. i.UserInputType.Name) end)
	RS.RenderStepped:Wait()
	local p = Vector2.new(150, 220) + inset
	v:SendMousePosition(p); RS.RenderStepped:Wait()
	v:SendMouseButton(p, Enum.UserInputType.MouseButton1, true); RS.RenderStepped:Wait(); table.insert(log, "|pressed")
	local q = p + Vector2.new(10, 0); v:SendMousePosition(q); RS.RenderStepped:Wait(); table.insert(log, "|moved1")
	local r = p + Vector2.new(30, 5); v:SendMousePosition(r); RS.RenderStepped:Wait(); table.insert(log, "|moved2")
	v:SendMouseButton(r, Enum.UserInputType.MouseButton1, false); RS.RenderStepped:Wait(); RS.RenderStepped:Wait(); table.insert(log, "|released")
	expect(class .. " drag", table.concat(log, " "), "began:MouseMovement start@150,220 began:MouseButton1 |pressed cont@160,220 |moved1 cont@180,225 |moved2 end@180,225 |released")
	expect(class .. " position", tostring(target.Position), "{0, 100}, {0, 200}")
	expect(class .. " offset", tostring(d.DragUDim2), "{0, 30}, {0, 5}")
	table.clear(log)
	v:SendMousePosition(p)
	RS.RenderStepped:Wait()
	v:SendMouseButton(p, Enum.UserInputType.MouseButton1, true); RS.RenderStepped:Wait(); v:SendMouseButton(p, Enum.UserInputType.MouseButton1, false); RS.RenderStepped:Wait(); RS.RenderStepped:Wait()
	expect(class .. " tap", table.concat(log, " "), "start@150,220 began:MouseButton1 end@150,220")
	target:Destroy()
end
for _, case in { {"Frame", "Frame", false, "start end"}, {"Frame", "TextButton", false, "down click up"}, {"Frame", "Frame", true, "start end"}, {"TextButton", nil, false, "start end"} } do
	local target = Instance.new(case[1]); target.Size = UDim2.fromOffset(100, 40); target.Position = UDim2.fromOffset(100, 300); target.Parent = g
	local d = Instance.new("UIDragDetector"); d.ResponseStyle = Enum.UIDragDetectorResponseStyle.CustomOffset; d.Parent = target
	local child
	if case[2] then child = Instance.new(case[2]); child.Size = UDim2.fromScale(1, 1); child.Active = case[3]; child.Parent = target end
	local log = {}
	d.DragStart:Connect(function() table.insert(log, "start") end); d.DragEnd:Connect(function() table.insert(log, "end") end)
	local b = if target:IsA("GuiButton") then target elseif child and child:IsA("GuiButton") then child else nil
	if b then
		b.Activated:Connect(function() table.insert(log, "activated") end)
		b.MouseButton1Click:Connect(function() table.insert(log, "click") end)
		b.MouseButton1Down:Connect(function() table.insert(log, "down") end)
		b.MouseButton1Up:Connect(function() table.insert(log, "up") end)
	end
	RS.RenderStepped:Wait()
	local p = Vector2.new(150, 320) + inset
	v:SendMousePosition(p); RS.RenderStepped:Wait()
	v:SendMouseButton(p, Enum.UserInputType.MouseButton1, true); RS.RenderStepped:Wait(); v:SendMouseButton(p, Enum.UserInputType.MouseButton1, false); RS.RenderStepped:Wait(); RS.RenderStepped:Wait()
	expect(`{case[1]} over {case[2]} active {case[3]}`, table.concat(log, " "), case[4])
	target:Destroy()
end
g:Destroy()
assert(#failures == 0, table.concat(failures, "\n"))
return true
]==]

return function(harness: Core.Harness)
	harness:case("UIDragDetector reports drags and holds back button input as Studio 0.744 does", function(check)
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
			client = { name = "DragDetector", userId = 1, viewport = { x = 800, y = 600 } },
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
		local thread = scheduler.spawnTagged({ context = "client", source = "input-drag-detector" }, function()
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
	end)
end
