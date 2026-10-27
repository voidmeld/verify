--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local Lute = require "../src/lute"
local probe = require "./fixtures/ui-style-selectors"

it("pseudo-instance selectors with hyphenated tags keep physical components independent", function(own)
	local bridge = Lute.fixture.bridge(nil, { ui = { measureBounds = false, measureText = false } })
	own(bridge.close)
	local globals: { [string]: unknown } = {
		env = bridge.environment,
		ui = assert(bridge.ui),
		UDim = Roblox.datatypes.UDim,
		TweenInfo = Roblox.datatypes.TweenInfo,
	}
	local complete = Lute.chunk.load(
		[==[
local root = env.createInstance "ScreenGui"
local sheet = env.createInstance "StyleSheet"
local link = env.createInstance("StyleLink", { StyleSheet = sheet, Parent = root })
local frame = env.createInstance("Frame", { Parent = root })
frame:AddTag "rounded-track"
local rule = env.createInstance("StyleRule", { Selector = ".rounded-track::UICorner", Parent = sheet })
local radius = UDim.new(0, 12)
rule:SetProperty("CornerRadius", radius)
local function pseudo()
	return frame:GetStyled("CornerRadius", "::UICorner")
end
assert(pseudo() == radius)
rule:SetPropertyTransition("CornerRadius", TweenInfo.new(0.2))
assert(pseudo() == radius)
rule:SetPropertyTransition("CornerRadius", TweenInfo.new(0))
assert(pseudo() == radius)
rule:SetPropertyTransition("CornerRadius", nil)
assert(ui.component(frame, "UICorner", "CornerRadius") == radius)
assert(#frame:GetChildren() == 0)
local physical = env.createInstance("UICorner", { Parent = frame })
local fallback = env.defaultPropertyOf(physical, "CornerRadius")
assert(pseudo() == radius)
assert(ui.styled(physical, "CornerRadius") == fallback)
assert(ui.component(frame, "UICorner", "CornerRadius") == fallback)
frame:RemoveTag "rounded-track"
assert(pcall(pseudo) == false)
assert(physical.Parent == frame)
assert(ui.styled(physical, "CornerRadius") == fallback)
physical:Destroy()
assert(ui.component(frame, "UICorner", "CornerRadius") == nil)
frame:AddTag "rounded-track"
assert(pseudo() == radius)
rule.Selector = ".other-track::UICorner"
assert(pcall(pseudo) == false)
rule.Selector = ".rounded-track::UICorner"
assert(pseudo() == radius)
link.StyleSheet = nil
assert(pcall(pseudo) == false)
link.StyleSheet = sheet
assert(pseudo() == radius)
rule:Destroy()
assert(pcall(pseudo) == false)
assert(#frame:GetChildren() == 0)
return true
]==],
		{ environment = globals }
	)()
	expect(complete):toBe(true)
end)

it("style hierarchy and phantom resolution matches the same native conformance assertions", function(own)
	local roots: { Roblox.Instance } = {}
	local bridge = Lute.fixture.bridge(nil, {
		ui = { measureBounds = false, measureText = false },
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
		client = { name = "Grid", userId = 1, viewport = { x = 800, y = 600 } },
		beforeRender = assert(bridge.layout).step,
	})
	own(function()
		for index = #runtime.closeHandlers, 1, -1 do
			runtime.closeHandlers[index]()
		end
	end)
	table.insert(roots, assert(assert(runtime.localPlayer):FindFirstChild "PlayerGui"))
	local complete = false
	local scheduler = bridge.environment.scheduler
	local thread = scheduler.spawnTagged({ context = "client", source = "ui-style-selectors" }, function()
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
	expect(engine.diagnostics):toEqual {}
	expect(complete):toBe(true)
end)

return nil
