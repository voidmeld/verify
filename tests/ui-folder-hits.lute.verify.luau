--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

local probe = [==[
local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local out = {}
for _, mode in { Enum.ZIndexBehavior.Sibling, Enum.ZIndexBehavior.Global } do
	for _, cfg in { {1, 1, "frame-first"}, {1, 1, "folder-first"}, {2, 1, "frame-first"}, {1, 2, "frame-first"} } do
		local g = Instance.new("ScreenGui"); g.ZIndexBehavior = mode; g.Parent = pg
		local host = Instance.new("Frame"); host.Name = "Host"; host.Size = UDim2.fromOffset(400, 400); host.Position = UDim2.fromOffset(200, 200)
		local a = Instance.new("Frame"); a.Name = "A"; a.Size = UDim2.fromOffset(100, 100); a.ZIndex = cfg[1]
		local folder = Instance.new("Folder"); folder.Name = "Folder"
		local b = Instance.new("Frame"); b.Name = "B"; b.Size = UDim2.fromOffset(100, 100); b.Position = UDim2.fromOffset(50, 50); b.ZIndex = cfg[2]; b.Parent = folder
		host.Parent = g
		if cfg[3] == "frame-first" then a.Parent = host; folder.Parent = host else folder.Parent = host; a.Parent = host end
		task.wait(); task.wait()
		local names = {}
		for _, o in pg:GetGuiObjectsAtPosition(275, 275) do if o:IsDescendantOf(g) then table.insert(names, o.Name) end end
		table.insert(out, `{mode.Name} A.z={cfg[1]} B.z={cfg[2]} {cfg[3]}: B.abs={b.AbsolutePosition} hits={table.concat(names, ",")}`)
		g:Destroy()
	end
end
local want = [[
Sibling A.z=1 B.z=1 frame-first: B.abs=250, 250 hits=B,A,Host
Sibling A.z=1 B.z=1 folder-first: B.abs=250, 250 hits=A,B,Host
Sibling A.z=2 B.z=1 frame-first: B.abs=250, 250 hits=A,B,Host
Sibling A.z=1 B.z=2 frame-first: B.abs=250, 250 hits=B,A,Host
Global A.z=1 B.z=1 frame-first: B.abs=250, 250 hits=B,A,Host
Global A.z=1 B.z=1 folder-first: B.abs=250, 250 hits=A,B,Host
Global A.z=2 B.z=1 frame-first: B.abs=250, 250 hits=A,B,Host
Global A.z=1 B.z=2 frame-first: B.abs=250, 250 hits=B,A,Host
]]
local got = table.concat(out, "\n") .. "\n"
assert(got == want, got)
return true
]==]

it("Folder children hit-test in their GuiObject ancestor at the Folder position as Studio 0.744 does", function(own)
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
		client = { name = "Folders", userId = 1, viewport = { x = 800, y = 600 } },
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
	local thread = scheduler.spawnTagged({ context = "client", source = "ui-folder-hits" }, function()
		complete = Lute.chunk.load(probe, { environment = runtime.globals })() == true
			and Lute.chunk.load(require "./fixtures/ui-screen-order", { environment = runtime.globals })() == true
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
