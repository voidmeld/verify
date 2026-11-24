--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

local probe = [==[
local GS = game:GetService("GuiService")
local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
camera.FieldOfView = 70
camera.CFrame = CFrame.lookAt(Vector3.new(0, 5, 20), Vector3.new(0, 5, 0))
local size = camera.ViewportSize
local inset = GS:GetGuiInset()
local failures = {}
local function near(name, got, want)
	if math.abs(got - want) > 0.01 then
		table.insert(failures, `{name}: got {got} want {want}`)
	end
end
local ahead, aheadVisible = camera:WorldToViewportPoint(Vector3.new(0, 5, 10))
near("ahead x", ahead.X, size.X / 2)
near("ahead y", ahead.Y, size.Y / 2)
near("ahead depth", ahead.Z, 10)
if not aheadVisible then table.insert(failures, "ahead not visible") end
local tangent = math.tan(math.rad(35))
local top = camera:WorldToViewportPoint(Vector3.new(0, 5 + 10 * tangent, 10))
near("top y", top.Y, 0)
local side = camera:WorldToViewportPoint(Vector3.new(10 * tangent * size.X / size.Y, 5, 10))
near("side x", side.X, size.X)
local behind, behindVisible = camera:WorldToViewportPoint(Vector3.new(0, 5, 30))
near("behind depth", behind.Z, -10)
if behindVisible then table.insert(failures, "behind visible") end
local screen = camera:WorldToScreenPoint(Vector3.new(0, 5, 10))
near("screen x", screen.X, size.X / 2 - inset.X)
near("screen y", screen.Y, size.Y / 2 - inset.Y)
local ray = camera:ViewportPointToRay(size.X / 2, size.Y / 2)
near("ray look", ray.Direction:Dot(camera.CFrame.LookVector), 1)
near("ray origin", (ray.Origin - camera.CFrame.Position).Magnitude, 0.1)
local screenRay = camera:ScreenPointToRay(size.X / 2 - inset.X, size.Y / 2 - inset.Y)
near("screen ray look", screenRay.Direction:Dot(camera.CFrame.LookVector), 1)
local deep = camera:ViewportPointToRay(size.X / 2, size.Y / 2, 3)
near("depth origin", (deep.Origin - camera.CFrame.Position).Magnitude, 3.1)
assert(#failures == 0, table.concat(failures, "; "))
return true
]==]

it("camera projections and rays match Studio 0.744", function(own)
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
		client = { name = "CameraProjection", userId = 1, viewport = { x = 800, y = 600 } },
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
	local thread = scheduler.spawnTagged({ context = "client", source = "camera-projection" }, function()
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
