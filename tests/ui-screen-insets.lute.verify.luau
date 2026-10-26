--!strict

local Core = require "../src/core"
local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

local probe = [==[
local simulator = game:GetService("StudioDeviceSimulatorService")
local playerGui = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local expected = {
	iphone_14 = { None = { -47, -58, 843, 389 }, CoreUISafeInsets = { 0, 0, 749, 331 }, DeviceSafeInsets = { 0, -58, 749, 389 }, TopbarSafeInsets = { 164, -58, 585, 58 } },
	hd_1080 = { None = { 0, -58, 1919, 1080 }, CoreUISafeInsets = { 0, 0, 1919, 1022 }, DeviceSafeInsets = { 0, -58, 1919, 1080 }, TopbarSafeInsets = { 164, -58, 1755, 58 } },
}
for _, id in { "iphone_14", "hd_1080" } do
	simulator:SetDeviceAsync(id)
	for _ = 1, 10 do task.wait() end
	for mode, area in expected[id] do
		local screen = Instance.new("ScreenGui")
		screen.ScreenInsets = Enum.ScreenInsets[mode]
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.Parent = screen
		screen.Parent = playerGui
		task.wait()
		task.wait()
		assert(frame.AbsolutePosition == Vector2.new(area[1], area[2]), id .. " " .. mode .. " position " .. tostring(frame.AbsolutePosition))
		assert(frame.AbsoluteSize == Vector2.new(area[3], area[4]), id .. " " .. mode .. " size " .. tostring(frame.AbsoluteSize))
		screen:Destroy()
	end
end
local screen = Instance.new("ScreenGui")
assert(screen.ScreenInsets == Enum.ScreenInsets.CoreUISafeInsets, "default insets")
screen.IgnoreGuiInset = true
assert(screen.ScreenInsets == Enum.ScreenInsets.DeviceSafeInsets, "ignoring the inset selects device safe insets")
screen.IgnoreGuiInset = false
assert(screen.ScreenInsets == Enum.ScreenInsets.CoreUISafeInsets, "restoring the inset selects core UI safe insets")
screen:Destroy()
return true
]==]

return function(harness: Core.Harness)
	harness:case("screen insets place each ScreenGui in its captured device area", function(check)
		local roots: { Roblox.Instance } = {}
		local runtime: Roblox.PlaceRuntime? = nil
		local bridge = Lute.fixture.bridge(nil, {
			layout = {
				roots = function()
					return roots
				end,
				viewport = function()
					return { X = 800, Y = 600 }
				end,
				screenArea = function(screen: Roblox.Instance)
					return assert(runtime).screenArea(screen)
				end,
			},
		})
		check:defer(function()
			bridge.close()
		end)
		local engine = bridge.placeEngine()
		local created = Roblox.createPlaceRuntime(engine, { root = engine.game, scripts = {}, sources = {} }, {
			aliases = {},
			cache = Roblox.createPlaceCache(Lute.fixture.host),
			host = Lute.fixture.host,
			client = { name = "Insets", userId = 1, viewport = { x = 800, y = 600 } },
			beforeRender = assert(bridge.layout).step,
		})
		runtime = created
		check:defer(function()
			for index = #created.closeHandlers, 1, -1 do
				created.closeHandlers[index]()
			end
		end)
		table.insert(roots, assert(assert(created.localPlayer):FindFirstChild "PlayerGui"))
		local complete = false
		local scheduler = bridge.environment.scheduler
		local thread = scheduler.spawnTagged({ context = "client", source = "ui-screen-insets" }, function()
			complete = Lute.chunk.load(probe, { environment = created.globals })() == true
		end)
		check:defer(function()
			scheduler.cancel(thread)
		end)
		for _ = 1, 600 do
			if complete or #scheduler.failures > 0 then
				break
			end
			created.step(1 / 60)
		end
		check:expect(created.device().guiInset):toEqual { 0, 58, 0, 0 }
		check:expect(scheduler.failures):toEqual {}
		check:expect(engine.diagnostics):toEqual {}
		check:expect(complete):toBe(true)
	end)
end
