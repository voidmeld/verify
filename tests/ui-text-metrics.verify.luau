--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Lute = require "../src/lute"
local Roblox = require "../src/roblox"
local NativeMetrics = require "../src/lute/text-metrics"
local Values = require "../src/roblox/ui-values"

local call = Lute.chunk.load "local service, member = ...; return service[member](service, select(3, ...))"
local xComponent = Lute.chunk.load "local vector = ...; return vector.X"

it("default text measurements use captured native font facts", function(own)
	local bridge = Lute.fixture.bridge()
	own(function()
		bridge.close()
	end)
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
	own(function()
		bridge.close()
	end)
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

it("uniform bold rich text uses the captured bold face across measurement operations", function()
	local measure, truncate, height = NativeMetrics.create(), NativeMetrics.truncator(), NativeMetrics.heights()
	for _, family in { "BuilderSans", "Nunito", "SourceSansPro" } do
		local parameters: Values.TextParameters = {
			Font = Values.font(Roblox.datatypes.Font.new(`rbxasset://fonts/families/{family}.json`)),
			Size = 14,
			Width = 0,
			Text = "",
			RichText = true,
		}
		local expected = table.clone(parameters)
		expected.Font =
			Values.font(Roblox.datatypes.Font.new(parameters.Font.Family, Roblox.datatypes.Enum.FontWeight.Bold))
		expected.Text = "Lap record & SAVE"
		for _, size in { 7, 14, 18, 28 } do
			parameters.Size, expected.Size = size, size
			for _, width in { 0, 40, 120 } do
				parameters.Width, expected.Width = width, width
				for _, text in
					{
						"<b>Lap record &amp; SAVE</b>",
						"<b>Lap <b>record</b> &amp; SAVE</b>",
						"<u><b>Lap record &amp; <uc>save</uc></b></u>",
					}
				do
					parameters.Text = text
					expect(measure(parameters)):toEqual(measure(expected))
					expect(height(parameters, 3, 1.2)):toBe(height(expected, 3, 1.2))
					if width > 0 then
						for _, mode in { "AtEnd", "SplitWord" } do
							expect(truncate(parameters, mode, 1, false)):toBe(truncate(expected, mode, 1, false))
						end
					end
				end
			end
		end
		parameters.Text, parameters.Width = "<b>Lap record</b>", 0
		expected.Text = "Lap record"
		expected.Font = Values.font(Roblox.datatypes.Font.new(parameters.Font.Family))
		expect(measure(parameters) == measure(expected)):toBe(false)
		parameters.Font =
			Values.font(Roblox.datatypes.Font.new(parameters.Font.Family, Roblox.datatypes.Enum.FontWeight.Bold))
		expected.Font = parameters.Font
		parameters.Text, expected.Text = "<b>Lap</b> record", "Lap record"
		expect(measure(parameters)):toEqual(measure(expected))
	end
end)

it("uniform font weights preserve native Heavy selection and nested weight scopes", function()
	local measure, truncate, height = NativeMetrics.create(), NativeMetrics.truncator(), NativeMetrics.heights()
	for _, face in { { "BuilderSans", "Bold" }, { "Fondamento", "Regular" }, { "Michroma", "Regular" } } do
		local family = `rbxasset://fonts/families/{face[1]}.json`
		local parameters: Values.TextParameters = {
			Font = Values.font(Roblox.datatypes.Font.new(family)),
			Size = 14,
			Width = 0,
			Text = "",
			RichText = true,
		}
		local expected = table.clone(parameters)
		expected.Font = Values.font(Roblox.datatypes.Font.new(family, Roblox.datatypes.Enum.FontWeight[face[2]]))
		expected.Text = "Lap record & SAVE"
		for _, size in { 1, 7, 14, 18, 28, 100 } do
			parameters.Size, expected.Size = size, size
			for _, width in { 0, 40, 120 } do
				parameters.Width, expected.Width = width, width
				for _, text in
					{
						'<font weight="heavy">Lap record &amp; SAVE</font>',
						"<font weight='900'>Lap record &amp; SAVE</font>",
						'<font weight="HeAvY"><font color="#ffffff">Lap record</font> &amp; <uc>save</uc></font>',
					}
				do
					parameters.Text = text
					expect(measure(parameters)):toEqual(measure(expected))
					expect(height(parameters, 3, 1.2)):toBe(height(expected, 3, 1.2))
					if width > 0 then
						expect(truncate(parameters, "AtEnd", 1, false)):toBe(truncate(expected, "AtEnd", 1, false))
					end
				end
			end
		end
		parameters.Font = Values.font(Roblox.datatypes.Font.new(family, Roblox.datatypes.Enum.FontWeight.Heavy))
		parameters.Text = expected.Text
		expect(measure(parameters)):toEqual(measure(expected))
	end
	local parameters: Values.TextParameters = {
		Font = Values.font(Roblox.datatypes.Font.new "rbxasset://fonts/families/BuilderSans.json"),
		Size = 14,
		Width = 0,
		Text = "",
		RichText = true,
	}
	for _, text in
		{
			'<font weight="heavy">Lap</font> record',
			'<font weight="invalid">Lap record</font>',
			"<font weight=heavy>Lap record</font>",
			'<font weight="heavy" size="20">Lap record</font>',
		}
	do
		parameters.Text = text
		expect(function()
			measure(parameters)
		end):toThrow "unsupported_text_metrics"
	end
end)

it("the captured missing family fails in the service and uses the native GUI fallback", function()
	local measure, truncate, height = NativeMetrics.create(), NativeMetrics.truncator(), NativeMetrics.heights()
	for _, weight in { "Regular", "Bold", "Heavy" } do
		local parameters: Values.TextParameters = {
			Font = Values.font(
				Roblox.datatypes.Font.new(
					"rbxasset://fonts/families/DoesNotExist.json",
					Roblox.datatypes.Enum.FontWeight[weight]
				)
			),
			Size = 14,
			Width = 0,
			Text = "Unknown family text",
		}
		expect(function()
			measure(parameters)
		end):toThrow "Temp read failed."
		parameters.Gui = true
		local expected = table.clone(parameters)
		expected.Font = Values.font(
			Roblox.datatypes.Font.new(
				"rbxasset://fonts/families/SourceSansPro.json",
				Roblox.datatypes.Enum.FontWeight[if weight == "Heavy" then "Bold" else weight]
			)
		)
		for _, size in { 7, 14, 28 } do
			parameters.Size, expected.Size = size, size
			for _, width in { 0, 40, 120 } do
				parameters.Width, expected.Width = width, width
				for _, rich in { false, true } do
					parameters.RichText, expected.RichText = rich, rich
					expect(measure(parameters)):toEqual(measure(expected))
					expect(height(parameters, 3, 1.2)):toBe(height(expected, 3, 1.2))
					if width > 0 then
						expect(truncate(parameters, "AtEnd", 1, false)):toBe(truncate(expected, "AtEnd", 1, false))
					end
				end
			end
		end
	end
end)

it("text measurements refuse unmodeled shaping and split narrow words", function(own)
	local bridge = Lute.fixture.bridge()
	own(function()
		bridge.close()
	end)
	local library = Roblox.reflectionSnapshot.library(Lute.fixture.load())
	local parameters = bridge.environment.createInstance("GetTextBoundsParams", {
		Font = library.Font.new "rbxasset://fonts/families/BuilderSans.json",
		Size = 14,
		Text = "Hello",
		Width = 100,
	})
	local service = bridge.placeEngine().service "TextService"
	for _, scenario in { "mixed rich text", "unicode", "rich text", "font", "narrow" } do
		parameters.Text, parameters.Width, parameters.RichText = "Hello", 100, false
		parameters.Font = library.Font.new "rbxasset://fonts/families/BuilderSans.json"
		if scenario == "mixed rich text" then
			parameters.Text, parameters.RichText = "<b>Hello</b> world", true
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
				local measured = call(service, "GetTextBoundsAsync", parameters)
				local width = xComponent(measured)
				assert(type(width) == "number")
				widest = math.max(widest, width)
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
	own(function()
		bridge.close()
	end)
	local service = bridge.placeEngine().service "TextService"
	expect(call(service, "GetTextBoundsAsync", {})):toEqual(Roblox.datatypes.Vector2.new(12, 34))
	expect(function()
		call(service, "GetTextSize", "Hello", 14, nil, nil)
	end):toThrow()
	local disabled = Lute.fixture.bridge(nil, { ui = { measureBounds = false } })
	own(function()
		disabled.close()
	end)
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
	own(function()
		bridge.close()
	end)
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
	own(function()
		bridge.close()
	end)
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
