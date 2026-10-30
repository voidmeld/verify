--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Lute = require "../src/lute"
local Roblox = require "../src/roblox"

local call = Lute.chunk.load "local service, member = ...; return service[member](service, select(3, ...))"

it("default text measurements use captured native font facts", function(own)
	local bridge = Lute.fixture.bridge()
	own(bridge.close)
	local library = Roblox.reflectionSnapshot.library(Lute.fixture.load())
	local parameters = bridge.environment.createInstance("GetTextBoundsParams", {
		Font = library.Font.new "rbxasset://fonts/families/BuilderSans.json",
		Size = 14,
		Text = "Hello world",
		Width = 100,
	})
	local service = bridge.placeEngine().service "TextService"
	expect(call(service, "GetTextBoundsAsync", parameters)):toEqual(library.Vector2.new(59.333335876464844, 14))
	expect(call(service, "GetTextSize", "Hello world", 14, library.Enum.Font.BuilderSans, library.Vector2.new(100, 0))):toEqual(
		library.Vector2.new(59.333335876464844, 14)
	)
	parameters.Width = 40
	expect(call(service, "GetTextBoundsAsync", parameters)):toEqual(library.Vector2.new(29.33333396911621, 28))
	parameters.Text = "Office staff affiliation"
	parameters.Width = 0
	local previous = call(service, "GetTextBoundsAsync", parameters)
	parameters.Size = 28
	expect(call(service, "GetTextBoundsAsync", parameters) == previous):toBe(false)
end)

it("captured Latin and Japanese text preserves service widths and wrapping", function(own)
	local bridge = Lute.fixture.bridge()
	own(bridge.close)
	local library = Roblox.reflectionSnapshot.library(Lute.fixture.load())
	local parameters = bridge.environment.createInstance("GetTextBoundsParams", {
		Font = library.Font.new "rbxasset://fonts/families/BuilderSans.json",
		Size = 14,
	})
	local service = bridge.placeEngine().service "TextService"
	for _, row in
		{
			{ text = "þṽĥ", width = 0, x = 20, y = 14 },
			{ text = "þṽĥ", width = 40, x = 20, y = 14 },
			{ text = "東京", width = 0, x = 20, y = 14 },
			{ text = "東京", width = 40, x = 20, y = 14 },
			{ text = "速度制限標識と設定画面", width = 0, x = 110, y = 14 },
			{ text = "速度制限標識と設定画面", width = 40, x = 40, y = 42 },
			{ text = "速度制限標識と設定画面", width = 100, x = 100, y = 28 },
		}
	do
		parameters.Text, parameters.Width = row.text, row.width
		expect(call(service, "GetTextBoundsAsync", parameters)):toEqual(library.Vector2.new(row.x, row.y))
	end
end)

it("text measurements refuse unmodeled shaping and split narrow words", function(own)
	local bridge = Lute.fixture.bridge()
	own(bridge.close)
	local library = Roblox.reflectionSnapshot.library(Lute.fixture.load())
	local parameters = bridge.environment.createInstance("GetTextBoundsParams", {
		Font = library.Font.new "rbxasset://fonts/families/BuilderSans.json",
		Size = 14,
		Text = "Hello",
		Width = 100,
	})
	local service = bridge.placeEngine().service "TextService"
	for _, scenario in { "bold rich text", "unicode", "rich text", "font", "narrow" } do
		parameters.Text, parameters.Width, parameters.RichText = "Hello", 100, false
		parameters.Font = library.Font.new "rbxasset://fonts/families/BuilderSans.json"
		if scenario == "bold rich text" then
			parameters.Text, parameters.RichText = "<b>Hello</b>", true
		elseif scenario == "unicode" then
			parameters.Text = "你好"
		elseif scenario == "rich text" then
			parameters.Text, parameters.RichText = '<font size="20">Hello</font>', true
		elseif scenario == "font" then
			parameters.Font = library.Font.new "rbxasset://fonts/families/Unknown.json"
		else
			parameters.Width = 1
		end
		if scenario == "narrow" then
			local actual = call(service, "GetTextBoundsAsync", parameters)
			parameters.Width = 0
			local widest = 0
			for _, codepoint in utf8.codes "Hello" do
				parameters.Text = utf8.char(codepoint)
				local measured = call(service, "GetTextBoundsAsync", parameters) :: { X: number, Y: number }
				widest = math.max(widest, measured.X)
			end
			expect(actual):toEqual(library.Vector2.new(widest, 6 * 14))
			continue
		end
		expect(function()
			call(service, "GetTextBoundsAsync", parameters)
		end):toThrow "unsupported_text_metrics"
	end
end)

it("text measurement providers remain explicit overrides and can be disabled", function(own)
	local bridge = Lute.fixture.bridge(nil, {
		ui = {
			measureBounds = function(): unknown
				return Roblox.datatypes.Vector2.new(12, 34)
			end,
			measureText = false,
		},
	})
	own(bridge.close)
	local service = bridge.placeEngine().service "TextService"
	expect(call(service, "GetTextBoundsAsync", {})):toEqual(Roblox.datatypes.Vector2.new(12, 34))
	expect(function()
		call(service, "GetTextSize", "Hello", 14, nil, nil)
	end):toThrow()
	local disabled = Lute.fixture.bridge(nil, { ui = { measureBounds = false } })
	own(disabled.close)
	expect(function()
		local service = disabled.placeEngine().service "TextService"
		call(service, "GetTextBoundsAsync", {})
	end):toThrow()
end)
it("automatic text shrinks after edits and rejects unmodeled text before publishing geometry", function(own)
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
	own(bridge.close)
	local library = Roblox.reflectionSnapshot.library(Lute.fixture.load())
	local env, layout = bridge.environment, assert(bridge.layout)
	local frame = env.createInstance("Frame", { Size = library.UDim2.fromOffset(100, 100) })
	table.insert(roots, frame)
	local label = env.createInstance("TextLabel", {
		Parent = frame,
		Size = library.UDim2.fromOffset(100, 0),
		FontFace = library.Font.new "rbxasset://fonts/families/BuilderSans.json",
		TextSize = 14,
		Text = string.rep("Wrapped text ", 6),
		TextWrapped = true,
		AutomaticSize = library.Enum.AutomaticSize.Y,
	})
	layout.step()
	expect(label.AbsoluteSize):toEqual(library.Vector2.new(100, 84))
	label.Text = "Hello"
	layout.step()
	expect(label.AbsoluteSize):toEqual(library.Vector2.new(100, 14))
	expect(label.TextBounds):toEqual(library.Vector2.new(26.666667938232422, 14))
	label.AutomaticSize = library.Enum.AutomaticSize.None
	label.Size = library.UDim2.fromOffset(100, 14)
	label.Text = string.rep("Wrapped text ", 6)
	layout.step()
	expect(label.TextBounds):toEqual(library.Vector2.new(73.33333587646484, 14))
	expect(label.TextFits):toBe(false)
	label.TextWrapped = false
	label.Text = "Hello\nworld"
	expect(layout.step):toThrow "unwrapped multiline text exceeds available height"
	label.TextWrapped = true
	label.AutomaticSize = library.Enum.AutomaticSize.Y
	label.Text = "Hello"
	local beforeFrame, beforeLabel = frame.AbsoluteSize, label.TextBounds
	frame.Size = library.UDim2.fromOffset(200, 200)
	label.Text = "你好"
	expect(layout.step):toThrow "unsupported_text_metrics"
	expect(frame.AbsoluteSize):toEqual(beforeFrame)
	expect(label.TextBounds):toEqual(beforeLabel)
end)

it("native boundary corrections and Legacy Arial line metrics", function(own)
	local bridge = Lute.fixture.bridge()
	own(bridge.close)
	local library = Roblox.reflectionSnapshot.library(Lute.fixture.load())
	local parameters = bridge.environment.createInstance("GetTextBoundsParams", {
		Font = library.Font.new "rbxasset://fonts/families/LegacyArial.json",
		Size = 14,
		Width = 0,
	})
	local service = bridge.placeEngine().service "TextService"
	for _, entry in
		{
			{ text = "A", width = 12.666666984558105 },
			{ text = " A", width = 18 },
			{ text = "H A", width = 30.666667938232422 },
			{ text = "K2A", width = 36 },
		}
	do
		parameters.Text = entry.text
		expect(call(service, "GetTextBoundsAsync", parameters)):toEqual(
			library.Vector2.new(entry.width, 20.666667938232422)
		)
	end
	expect(
		call(
			service,
			"GetTextSize",
			string.rep("Wrapped text ", 6),
			14,
			library.Enum.Font.Legacy,
			library.Vector2.new(100, 50)
		)
	):toEqual(library.Vector2.new(78, 41.333335876464844))
end)

return nil
