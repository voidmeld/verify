--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

local probe = [==[
local RS = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local v = UIS:CreateVirtualInput()
local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local g = Instance.new("ScreenGui"); g.Parent = pg
local inset = game:GetService("GuiService"):GetGuiInset()
local items = {}
local function make(name, class, props, parent)
	local o = Instance.new(class); o.Name = name; for k, val in props do o[k] = val end; o.Parent = parent or g; items[name] = o; return o
end
make("FrameInactive", "Frame", { Size = UDim2.fromOffset(100, 40), Position = UDim2.fromOffset(0, 200), Active = false })
make("FrameActive", "Frame", { Size = UDim2.fromOffset(100, 40), Position = UDim2.fromOffset(120, 200), Active = true })
local btn = make("Button", "TextButton", { Size = UDim2.fromOffset(100, 40), Position = UDim2.fromOffset(240, 200) })
make("ButtonChild", "Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundTransparency = 0.5 }, btn)
make("ButtonOff", "TextButton", { Size = UDim2.fromOffset(100, 40), Position = UDim2.fromOffset(360, 200), Interactable = false })
local holder = make("Holder", "Frame", { Size = UDim2.fromOffset(100, 40), Position = UDim2.fromOffset(480, 200), Interactable = false })
make("NestedButton", "TextButton", { Size = UDim2.fromScale(1, 1) }, holder)
RS.RenderStepped:Wait()
local function snapshot(label)
	local parts = {}
	for _, n in { "FrameInactive", "FrameActive", "Button", "ButtonChild", "ButtonOff", "Holder", "NestedButton" } do table.insert(parts, n .. "=" .. items[n].GuiState.Name) end
	return label .. ": " .. table.concat(parts, " ")
end
local out = { snapshot("idle") }
for _, target in { {50, 220, "overFrameInactive"}, {170, 220, "overFrameActive"}, {290, 220, "overButton"}, {250, 220, "overButtonChild"} } do
	local p = Vector2.new(target[1], target[2]) + inset
	v:SendMousePosition(p); RS.RenderStepped:Wait(); RS.RenderStepped:Wait()
	table.insert(out, snapshot(target[3]))
end
local p = Vector2.new(290, 220) + inset
v:SendMousePosition(p); RS.RenderStepped:Wait()
v:SendMouseButton(p, Enum.UserInputType.MouseButton1, true); RS.RenderStepped:Wait(); RS.RenderStepped:Wait()
table.insert(out, snapshot("pressButton"))
local q = Vector2.new(170, 220) + inset
v:SendMousePosition(q); RS.RenderStepped:Wait(); RS.RenderStepped:Wait()
table.insert(out, snapshot("draggedOffButton"))
v:SendMouseButton(q, Enum.UserInputType.MouseButton1, false); RS.RenderStepped:Wait(); RS.RenderStepped:Wait()
table.insert(out, snapshot("released"))
local want = {
	"idle: FrameInactive=Idle FrameActive=Idle Button=Idle ButtonChild=Idle ButtonOff=NonInteractable Holder=NonInteractable NestedButton=NonInteractable",
	"overFrameInactive: FrameInactive=Hover FrameActive=Idle Button=Idle ButtonChild=Idle ButtonOff=NonInteractable Holder=NonInteractable NestedButton=NonInteractable",
	"overFrameActive: FrameInactive=Idle FrameActive=Hover Button=Idle ButtonChild=Idle ButtonOff=NonInteractable Holder=NonInteractable NestedButton=NonInteractable",
	"overButton: FrameInactive=Idle FrameActive=Idle Button=Hover ButtonChild=Hover ButtonOff=NonInteractable Holder=NonInteractable NestedButton=NonInteractable",
	"overButtonChild: FrameInactive=Idle FrameActive=Idle Button=Hover ButtonChild=Hover ButtonOff=NonInteractable Holder=NonInteractable NestedButton=NonInteractable",
	"pressButton: FrameInactive=Idle FrameActive=Idle Button=Press ButtonChild=Press ButtonOff=NonInteractable Holder=NonInteractable NestedButton=NonInteractable",
	"draggedOffButton: FrameInactive=Idle FrameActive=Hover Button=Idle ButtonChild=Idle ButtonOff=NonInteractable Holder=NonInteractable NestedButton=NonInteractable",
	"released: FrameInactive=Idle FrameActive=Hover Button=Idle ButtonChild=Idle ButtonOff=NonInteractable Holder=NonInteractable NestedButton=NonInteractable",
}
local failures = {}
for index, line in want do
	if out[index] ~= line then table.insert(failures, `got "{out[index]}" want "{line}"`) end
end
local sheet = Instance.new("StyleSheet"); sheet.Parent = g
local rule = Instance.new("StyleRule"); rule.Selector = ".swatch:Hover"; rule:SetProperty("BackgroundTransparency", 0.25); rule.Parent = sheet
local link = Instance.new("StyleLink"); link.StyleSheet = sheet; link.Parent = g
local swatch = make("Swatch", "Frame", { Size = UDim2.fromOffset(100, 40), Position = UDim2.fromOffset(0, 300), BackgroundTransparency = 0 })
swatch:AddTag("swatch")
RS.RenderStepped:Wait()
local resting = swatch:GetStyled("BackgroundTransparency")
v:SendMousePosition(Vector2.new(50, 320) + inset); RS.RenderStepped:Wait(); RS.RenderStepped:Wait()
local hovering = swatch:GetStyled("BackgroundTransparency")
if resting ~= 0 or hovering ~= 0.25 then table.insert(failures, `swatch {resting} {hovering}`) end
local log = {}
local frame = make("Target", "Frame", { Size = UDim2.fromOffset(100, 40), Position = UDim2.fromOffset(120, 400), Active = true })
local button = make("Pressed", "TextButton", { Size = UDim2.fromOffset(100, 40), Position = UDim2.fromOffset(240, 400) })
for _, o in { frame, button } do
	o.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then table.insert(log, o.Name .. ":began") end end)
	o.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then table.insert(log, o.Name .. ":ended") end end)
end
button.MouseButton1Click:Connect(function() table.insert(log, "click") end)
button.MouseButton1Up:Connect(function() table.insert(log, "up") end)
button.Activated:Connect(function() table.insert(log, "activated") end)
frame.MouseEnter:Connect(function() table.insert(log, "frame:enter") end)
RS.RenderStepped:Wait()
local start = Vector2.new(290, 420) + inset
v:SendMousePosition(start); RS.RenderStepped:Wait()
v:SendMouseButton(start, Enum.UserInputType.MouseButton1, true); RS.RenderStepped:Wait()
local finish = Vector2.new(170, 420) + inset
v:SendMousePosition(finish); RS.RenderStepped:Wait()
v:SendMouseButton(finish, Enum.UserInputType.MouseButton1, false); RS.RenderStepped:Wait(); RS.RenderStepped:Wait()
if table.concat(log, " ") ~= "Pressed:began frame:enter Pressed:ended" then table.insert(failures, "release elsewhere: " .. table.concat(log, " ")) end
g:Destroy()
assert(#failures == 0, table.concat(failures, "\n"))
return true
]==]

it("GuiState follows hover, press and interactability as Studio 0.744 reports it", function(own)
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
		client = { name = "GuiStates", userId = 1, viewport = { x = 800, y = 600 } },
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
	own(input.close)
	local complete = false
	local scheduler = bridge.environment.scheduler
	local thread = scheduler.spawnTagged({ context = "client", source = "input-gui-state" }, function()
		complete = Lute.chunk.load(probe, { environment = runtime.globals })() == true
	end)
	own(function()
		scheduler.cancel(thread)
	end)
	for _ = 1, 240 do
		if complete or #scheduler.failures > 0 then
			break
		end
		runtime.step(1 / 60)
	end
	expect(scheduler.failures):toEqual {}
	expect(engine.diagnostics):toEqual {}
	expect(complete):toBe(true)
end)

return nil
