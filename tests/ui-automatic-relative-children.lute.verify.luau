--!strict

local Core = require "../src/core"
local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

local probe = [==[
local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local g = Instance.new("ScreenGui"); g.Parent = pg
local failures = {}
local function frame(props, parent) local f = Instance.new("Frame"); for k, v in props do f[k] = v end; f.Parent = parent; return f end
local function case(name, mode, base, layout, pad, kids, want)
	local root = frame({ Size = UDim2.fromOffset(400, 300) }, g)
	local p = frame({ Name = (name:gsub(" ", "_")), Size = base, AutomaticSize = Enum.AutomaticSize[mode] }, root)
	if pad then local u = Instance.new("UIPadding"); u.PaddingLeft, u.PaddingRight, u.PaddingTop, u.PaddingBottom = UDim.new(0, pad), UDim.new(0, pad), UDim.new(0, pad), UDim.new(0, pad); u.Parent = p end
	if layout then local l = Instance.new("UIListLayout"); l.FillDirection = Enum.FillDirection[layout[1]]; l.Padding = UDim.new(0, layout[2]); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = p end
	local made = {}
	for i, k in kids do made[i] = frame({ Size = k[1], Position = k[2] or UDim2.new(), AnchorPoint = k[3] or Vector2.zero, LayoutOrder = i }, p) end
	task.wait(); task.wait()
	local got = { `{p.AbsoluteSize.X},{p.AbsoluteSize.Y}` }
	for _, c in made do
		local at = c.AbsolutePosition - p.AbsolutePosition
		table.insert(got, `{c.AbsoluteSize.X},{c.AbsoluteSize.Y}@{at.X},{at.Y}`)
	end
	local text = table.concat(got, " ")
	if text ~= want then table.insert(failures, `{name}: got "{text}" want "{want}"`) end
	root:Destroy()
end
local off = { UDim2.fromOffset(200, 20) }
case("scale 1 beside offset", "X", UDim2.fromOffset(100, 50), nil, nil, { off, { UDim2.new(1, 0, 0, 10) } }, "200,50 200,20@0,0 200,10@0,0")
case("scale 0.5 beside offset", "X", UDim2.fromOffset(100, 50), nil, nil, { off, { UDim2.new(0.5, 0, 0, 10) } }, "200,50 200,20@0,0 100,10@0,0")
case("scale 1 plus offset", "X", UDim2.fromOffset(100, 50), nil, nil, { off, { UDim2.new(1, 10, 0, 10) } }, "210,50 200,20@0,0 210,10@0,0")
case("scale 1.5 alone", "X", UDim2.fromOffset(100, 50), nil, nil, { { UDim2.new(1.5, 0, 0, 10) } }, "225,50 225,10@0,0")
case("scale 1.5 and centred", "X", UDim2.fromOffset(100, 50), nil, nil, { { UDim2.new(1.5, 0, 0, 10) }, { UDim2.fromOffset(40, 10), UDim2.fromScale(0.5, 0) } }, "225,50 225,10@0,0 40,10@75,0")
case("zero base", "X", UDim2.fromOffset(0, 50), nil, nil, { { UDim2.new(1.5, 0, 0, 10) }, { UDim2.fromOffset(120, 10) } }, "180,50 180,10@0,0 120,10@0,0")
case("trailing anchored", "X", UDim2.fromOffset(100, 50), nil, nil, { off, { UDim2.fromOffset(40, 10), UDim2.fromScale(1, 0), Vector2.new(1, 0) } }, "200,50 200,20@0,0 40,10@160,0")
case("trailing unanchored", "X", UDim2.fromOffset(100, 50), nil, nil, { off, { UDim2.fromOffset(40, 10), UDim2.fromScale(1, 0) } }, "240,50 200,20@0,0 40,10@200,0")
case("padded scale 1", "X", UDim2.fromOffset(100, 50), nil, 10, { off, { UDim2.new(1, 0, 0, 10) } }, "220,50 200,20@10,10 200,10@10,10")
case("padded centred", "X", UDim2.fromOffset(100, 50), nil, 10, { off, { UDim2.fromOffset(40, 10), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0) } }, "220,50 200,20@10,10 40,10@90,10")
case("scale 0.9 beside wider", "X", UDim2.fromOffset(100, 50), nil, nil, { { UDim2.new(0.9, 0, 0, 10) }, { UDim2.fromOffset(150, 10) } }, "150,50 135,10@0,0 150,10@0,0")
case("height scale 1.5", "Y", UDim2.fromOffset(50, 100), nil, nil, { { UDim2.new(0, 10, 1.5, 0) } }, "50,225 10,225@0,0")
case("vertical list scale 1", "X", UDim2.fromOffset(100, 50), { "Vertical", 0 }, nil, { off, { UDim2.new(1, 0, 0, 10) } }, "400,50 200,20@0,0 400,10@0,20")
case("vertical list scale 1.5", "X", UDim2.fromOffset(100, 50), { "Vertical", 0 }, nil, { off, { UDim2.new(1.5, 0, 0, 10) } }, "900,50 200,20@0,0 900,10@0,20")
case("horizontal list gap", "X", UDim2.fromOffset(100, 50), { "Horizontal", 8 }, nil, { off, { UDim2.new(0.25, 0, 0, 10) } }, "308,50 200,20@0,0 77,10@208,0")
local function limited(name, base, minimum, maximum, layout, kids, want)
	local root = frame({ Size = UDim2.fromOffset(400, 300) }, g)
	local p = frame({ Name = (name:gsub(" ", "_")), Size = base, AutomaticSize = Enum.AutomaticSize.X }, root)
	local c = Instance.new("UISizeConstraint"); c.MinSize, c.MaxSize = minimum, maximum; c.Parent = p
	if layout then local l = Instance.new("UIListLayout"); l.FillDirection = Enum.FillDirection[layout]; l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = p end
	local made = {}
	for i, k in kids do made[i] = frame({ Size = k[1], LayoutOrder = i }, p) end
	task.wait(); task.wait()
	local got = { `{p.AbsoluteSize.X}` }
	for _, m in made do table.insert(got, `{m.AbsoluteSize.X}@{m.AbsolutePosition.X - p.AbsolutePosition.X}`) end
	local text = table.concat(got, " ")
	if text ~= want then table.insert(failures, `{name}: got "{text}" want "{want}"`) end
	root:Destroy()
end
local function automatic(name, layout, sibling, childSize, inner, want)
	local root = frame({ Size = UDim2.fromOffset(400, 300) }, g)
	local p = frame({ Name = (name:gsub(" ", "_")), Size = UDim2.fromOffset(100, 50), AutomaticSize = Enum.AutomaticSize.X }, root)
	if layout then local l = Instance.new("UIListLayout"); l.FillDirection = Enum.FillDirection[layout]; l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = p end
	if sibling then frame({ Size = UDim2.fromOffset(sibling, 20), LayoutOrder = 1 }, p) end
	local c = frame({ Size = childSize, AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 }, p)
	frame({ Size = UDim2.fromOffset(inner, 10) }, c)
	task.wait(); task.wait()
	local text = `{p.AbsoluteSize.X} {c.AbsoluteSize.X}@{c.AbsolutePosition.X - p.AbsolutePosition.X}`
	if text ~= want then table.insert(failures, `{name}: got "{text}" want "{want}"`) end
	root:Destroy()
end
automatic("automatic scale 1 small", nil, 200, UDim2.new(1, 0, 0, 10), 50, "200 200@0")
automatic("automatic scale 1 wide", nil, 200, UDim2.new(1, 0, 0, 10), 300, "300 300@0")
automatic("automatic scale 0.5 small", nil, 200, UDim2.new(0.5, 0, 0, 10), 50, "200 100@0")
automatic("automatic scale 0.5 wide", nil, 200, UDim2.new(0.5, 0, 0, 10), 150, "200 150@0")
automatic("automatic scale 1 alone", nil, nil, UDim2.new(1, 0, 0, 10), 150, "150 150@0")
automatic("automatic scale 1.5 alone", nil, nil, UDim2.new(1.5, 0, 0, 10), 50, "150 150@0")
automatic("automatic vertical list scale 1", "Vertical", 200, UDim2.new(1, 0, 0, 10), 50, "200 200@0")
automatic("automatic vertical list wide", "Vertical", 200, UDim2.new(0.5, 0, 0, 10), 300, "300 300@0")
automatic("automatic vertical list narrow", "Vertical", 50, UDim2.new(0.5, 0, 0, 10), 50, "100 50@0")
automatic("automatic horizontal list", "Horizontal", 200, UDim2.new(0.25, 0, 0, 10), 50, "300 75@200")
automatic("automatic horizontal list wide", "Horizontal", 200, UDim2.new(0.25, 0, 0, 10), 150, "350 150@200")
local open = Vector2.new(math.huge, math.huge)
local function most(x) return Vector2.new(x, math.huge) end
limited("max 250 scale 1", UDim2.fromOffset(100, 50), Vector2.zero, most(250), nil, { off, { UDim2.new(1, 0, 0, 10) } }, "200 200@0 200@0")
limited("max 150 scale 1", UDim2.fromOffset(100, 50), Vector2.zero, most(150), nil, { off, { UDim2.new(1, 0, 0, 10) } }, "200 200@0 150@0")
limited("max 150 scale 0.5", UDim2.fromOffset(100, 50), Vector2.zero, most(150), nil, { off, { UDim2.new(0.5, 0, 0, 10) } }, "200 200@0 75@0")
limited("min 300 scale 0.5", UDim2.fromOffset(100, 50), Vector2.new(300, 0), open, nil, { off, { UDim2.new(0.5, 0, 0, 10) } }, "300 200@0 150@0")
limited("max 300 scale 1.5", UDim2.fromOffset(100, 50), Vector2.zero, most(300), nil, { { UDim2.new(1.5, 0, 0, 10) } }, "225 225@0")
limited("max 200 scale 1.5", UDim2.fromOffset(100, 50), Vector2.zero, most(200), nil, { { UDim2.new(1.5, 0, 0, 10) } }, "225 225@0")
limited("min 50 scale 0.5", UDim2.fromOffset(100, 50), Vector2.new(50, 0), open, nil, { { UDim2.new(0.5, 0, 0, 10) } }, "100 50@0")
limited("max 250 vertical list", UDim2.fromOffset(100, 50), Vector2.zero, most(250), "Vertical", { off, { UDim2.new(1, 0, 0, 10) } }, "250 200@0 250@0")
limited("max 150 vertical list", UDim2.fromOffset(100, 50), Vector2.zero, most(150), "Vertical", { off, { UDim2.new(1, 0, 0, 10) } }, "200 200@0 150@0")
limited("max 250 horizontal list", UDim2.fromOffset(100, 50), Vector2.zero, most(250), "Horizontal", { off, { UDim2.new(0.25, 0, 0, 10) } }, "262.5 200@0 62.5@200")
limited("min 500 vertical list", UDim2.fromOffset(100, 50), Vector2.new(500, 0), open, "Vertical", { off, { UDim2.new(0.5, 0, 0, 10) } }, "500 200@0 250@0")
limited("max 250 over base", UDim2.fromOffset(300, 50), Vector2.zero, most(250), nil, { { UDim2.new(1, 0, 0, 10) } }, "250 250@0")
limited("max 150 offset only", UDim2.fromOffset(100, 50), Vector2.zero, most(150), nil, { off }, "200 200@0")
g:Destroy()
assert(#failures == 0, table.concat(failures, "\n"))
return true
]==]

return function(harness: Core.Harness)
	harness:case(
		"relative children resolve against a growing automatic parent in two passes as Studio 0.744 does",
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
				client = { name = "AutomaticRelative", userId = 1, viewport = { x = 800, y = 600 } },
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
				{ context = "client", source = "ui-automatic-relative-children" },
				function()
					complete = Lute.chunk.load(probe, { environment = runtime.globals })() == true
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
	)
end
