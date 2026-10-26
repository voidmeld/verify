--!strict

local Core = require "../src/core"
local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

local probe = [==[
local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local g = Instance.new("ScreenGui"); g.Parent = pg
local root = Instance.new("Frame"); root.Size = UDim2.fromOffset(1000, 1000); root.Parent = g
local out = {}
local function case(name, base, auto, pad, kid)
	local p = Instance.new("Frame"); p.Size = base; p.AutomaticSize = Enum.AutomaticSize[auto]; p.Parent = root
	local u = Instance.new("UIPadding"); u.PaddingLeft, u.PaddingRight, u.PaddingTop, u.PaddingBottom = pad[1], pad[2], pad[3], pad[4]; u.Parent = p
	local c = Instance.new("Frame"); c.Size = kid; c.Parent = p
	task.wait(); task.wait()
	table.insert(out, `{name}: p={p.AbsoluteSize.X},{p.AbsoluteSize.Y} c={c.AbsoluteSize.X},{c.AbsoluteSize.Y}@{c.AbsolutePosition.X - p.AbsolutePosition.X},{c.AbsolutePosition.Y - p.AbsolutePosition.Y}`)
	p:Destroy()
end
local s10 = UDim.new(0.1, 0)
local z = UDim.new(0, 0)
case("X base100 L10% kid200", UDim2.fromOffset(100, 50), "X", { s10, z, z, z }, UDim2.fromOffset(200, 20))
case("X base100 LR10% kid200", UDim2.fromOffset(100, 50), "X", { s10, s10, z, z }, UDim2.fromOffset(200, 20))
case("X base300 LR10% kid200", UDim2.fromOffset(300, 50), "X", { s10, s10, z, z }, UDim2.fromOffset(200, 20))
case("Y base50 T20% kid80", UDim2.fromOffset(100, 50), "Y", { z, z, UDim.new(0.2, 0), z }, UDim2.fromOffset(20, 80))
case("XY base0 all10% kid100", UDim2.fromOffset(0, 0), "XY", { s10, s10, s10, s10 }, UDim2.fromOffset(100, 100))
case("X base100 L10%+5 kid200", UDim2.fromOffset(100, 50), "X", { UDim.new(0.1, 5), z, z, z }, UDim2.fromOffset(200, 20))
case("Y padding scale X axis only", UDim2.fromOffset(100, 50), "Y", { s10, s10, z, z }, UDim2.fromOffset(20, 80))
g:Destroy()
local want = [[
X base100 L10% kid200: p=200,50 c=200,20@20,0
X base100 LR10% kid200: p=200,50 c=200,20@20,0
X base300 LR10% kid200: p=300,50 c=200,20@30,0
Y base50 T20% kid80: p=100,80 c=20,80@0,16
XY base0 all10% kid100: p=100,100 c=100,100@10,10
X base100 L10%+5 kid200: p=205,50 c=200,20@25.5,0
Y padding scale X axis only: p=100,80 c=20,80@10,0
]]
local got = table.concat(out, "\n") .. "\n"
assert(got == want, got)
return true
]==]

local layoutProbe = [==[
local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local g = Instance.new("ScreenGui"); g.Parent = pg
local out = {}
local function frame(props, parent) local f = Instance.new("Frame"); for k, v in props do f[k] = v end; f.Parent = parent; return f end
local function case(name, mode, base, dir, pad, kids)
	local root = frame({ Size = UDim2.fromOffset(400, 300) }, g)
	local p = frame({ Size = base, AutomaticSize = Enum.AutomaticSize[mode] }, root)
	local u = Instance.new("UIPadding"); u.PaddingLeft, u.PaddingRight, u.PaddingTop, u.PaddingBottom = pad[1], pad[2], pad[3], pad[4]; u.Parent = p
	if dir then local l = Instance.new("UIListLayout"); l.FillDirection = Enum.FillDirection[dir]; l.Padding = UDim.new(0, 4); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = p end
	local made = {}
	for i, k in kids do made[i] = frame({ Size = k, LayoutOrder = i }, p) end
	task.wait(); task.wait()
	local got = { `{p.AbsoluteSize.X},{p.AbsoluteSize.Y}` }
	for _, c in made do
		local at = c.AbsolutePosition - p.AbsolutePosition
		table.insert(got, string.format("%d,%d@%.2f,%.2f", c.AbsoluteSize.X, c.AbsoluteSize.Y, at.X, at.Y))
	end
	table.insert(out, name .. ": " .. table.concat(got, " "))
	root:Destroy()
end
local s10, o8, z = UDim.new(0.1, 0), UDim.new(0, 8), UDim.new(0, 0)
local s10o4 = UDim.new(0.1, 4)
case("V list XY s10 all", "XY", UDim2.fromOffset(0, 0), "Vertical", {s10, s10, s10, s10}, {UDim2.fromOffset(100, 20), UDim2.fromOffset(60, 20)})
case("V list Y s10 all base200", "Y", UDim2.fromOffset(200, 0), "Vertical", {s10, s10, s10, s10}, {UDim2.fromOffset(100, 20), UDim2.fromOffset(60, 20)})
case("V list Y s10o4", "Y", UDim2.fromOffset(200, 0), "Vertical", {s10o4, s10o4, s10o4, s10o4}, {UDim2.fromOffset(100, 20), UDim2.fromOffset(60, 20)})
case("H list X s10 lr", "X", UDim2.fromOffset(0, 50), "Horizontal", {s10, s10, z, z}, {UDim2.fromOffset(100, 20), UDim2.fromOffset(60, 20)})
case("H list XY mixed", "XY", UDim2.fromOffset(0, 0), "Horizontal", {s10, o8, s10o4, o8}, {UDim2.fromOffset(100, 20), UDim2.fromOffset(60, 30)})
case("V list Y base100 grows", "Y", UDim2.fromOffset(200, 100), "Vertical", {s10, s10, s10, s10}, {UDim2.fromOffset(100, 80), UDim2.fromOffset(60, 80)})
case("V list Y base300 nogrow", "Y", UDim2.fromOffset(200, 300), "Vertical", {s10, s10, s10, s10}, {UDim2.fromOffset(100, 80), UDim2.fromOffset(60, 80)})
case("rel child Y s10", "Y", UDim2.fromOffset(200, 50), nil, {s10, s10, s10, s10}, {UDim2.new(0.5, 0, 0, 120), UDim2.new(1, 0, 0.5, 0)})
case("V list scale kid", "Y", UDim2.fromOffset(200, 0), "Vertical", {s10, s10, s10, s10}, {UDim2.new(1, 0, 0, 20), UDim2.new(0.5, 0, 0, 20)})
g:Destroy()
local want = [[
V list XY s10 all: 100,44 100,20@10.00,4.40 60,20@10.00,28.40
V list Y s10 all base200: 200,44 100,20@20.00,4.40 60,20@20.00,28.40
V list Y s10o4: 200,52 100,20@24.00,9.20 60,20@24.00,33.20
H list X s10 lr: 164,50 100,20@16.40,0.00 60,20@120.40,0.00
H list XY mixed: 172,42 100,20@17.20,8.20 60,30@121.20,8.20
V list Y base100 grows: 200,164 100,80@20.00,16.40 60,80@20.00,100.40
V list Y base300 nogrow: 200,300 100,80@20.00,30.00 60,80@20.00,114.00
rel child Y s10: 200,120 80,120@20.00,12.00 160,48@20.00,12.00
V list scale kid: 200,44 160,20@20.00,4.40 80,20@20.00,28.40
]]
local got = table.concat(out, "\n") .. "\n"
assert(got == want, got)
return true
]==]

return function(harness: Core.Harness)
	local function run(source: string): (check: Core.Context) -> ()
		return function(check: Core.Context)
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
				client = { name = "ScaledPadding", userId = 1, viewport = { x = 800, y = 600 } },
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
			local thread = scheduler.spawnTagged(
				{ context = "client", source = "ui-automatic-scaled-padding" },
				function()
					complete = Lute.chunk.load(source, { environment = runtime.globals })() == true
				end
			)
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
	end
	harness:case("scaled padding resolves against the grown size without growing it as Studio 0.744 does", run(probe))
	harness:case(
		"scaled padding around a list or relative children resolves against the grown size as Studio 0.744 does",
		run(layoutProbe)
	)
end
