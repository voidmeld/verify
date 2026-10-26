--!strict

local Core = require "../src/core"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"

local call = Lute.chunk.load "local service, member = ...; return service[member](service, select(3, ...))"

return function(harness: Core.Harness)
	harness:case("default text measurements use captured native font facts", function(check)
		local bridge = Lute.fixture.bridge()
		check:defer(bridge.close)
		local library = Roblox.reflectionSnapshot.library(Lute.fixture.load())
		local parameters = bridge.environment.createInstance("GetTextBoundsParams", {
			Font = library.Font.new "rbxasset://fonts/families/BuilderSans.json",
			Size = 14,
			Text = "Hello world",
			Width = 100,
		})
		local service = bridge.placeEngine().service "TextService"
		check:expect(call(service, "GetTextBoundsAsync", parameters)):toEqual(library.Vector2.new(61, 14))
		check
			:expect(
				call(
					service,
					"GetTextSize",
					"Hello world",
					14,
					library.Enum.Font.BuilderSans,
					library.Vector2.new(100, 0)
				)
			)
			:toEqual(library.Vector2.new(61, 14))
		parameters.Width = 40
		check:expect(call(service, "GetTextBoundsAsync", parameters)):toEqual(library.Vector2.new(30, 28))
		parameters.Text = "Office staff affiliation"
		parameters.Width = 0
		local previous = call(service, "GetTextBoundsAsync", parameters)
		parameters.Size = 28
		check:expect(call(service, "GetTextBoundsAsync", parameters) == previous):toBe(false)
	end)

	harness:case("text measurements refuse unmodeled shaping and narrow word splitting", function(check)
		local bridge = Lute.fixture.bridge()
		check:defer(bridge.close)
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
			check
				:expect(function()
					call(service, "GetTextBoundsAsync", parameters)
				end)
				:toThrow "unsupported_text_metrics"
		end
	end)

	harness:case("text measurement providers remain explicit overrides and can be disabled", function(check)
		local bridge = Lute.fixture.bridge(nil, {
			ui = {
				measureBounds = function(): unknown
					return Roblox.datatypes.Vector2.new(12, 34)
				end,
				measureText = false,
			},
		})
		check:defer(bridge.close)
		local service = bridge.placeEngine().service "TextService"
		check:expect(call(service, "GetTextBoundsAsync", {})):toEqual(Roblox.datatypes.Vector2.new(12, 34))
		check
			:expect(function()
				call(service, "GetTextSize", "Hello", 14, nil, nil)
			end)
			:toThrow()
		local disabled = Lute.fixture.bridge(nil, { ui = { measureBounds = false } })
		check:defer(disabled.close)
		check
			:expect(function()
				local service = disabled.placeEngine().service "TextService"
				call(service, "GetTextBoundsAsync", {})
			end)
			:toThrow()
	end)
	harness:case(
		"automatic text shrinks after edits and rejects unmodeled text before publishing geometry",
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
			check:defer(bridge.close)
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
			check:expect(label.AbsoluteSize):toEqual(library.Vector2.new(100, 84))
			label.Text = "Hello"
			layout.step()
			check:expect(label.AbsoluteSize):toEqual(library.Vector2.new(100, 14))
			check:expect(label.TextBounds):toEqual(library.Vector2.new(28, 14))
			label.AutomaticSize = library.Enum.AutomaticSize.None
			label.Size = library.UDim2.fromOffset(100, 14)
			label.Text = string.rep("Wrapped text ", 6)
			layout.step()
			check:expect(label.TextBounds):toEqual(library.Vector2.new(75, 14))
			check:expect(label.TextFits):toBe(false)
			label.TextWrapped = false
			label.Text = "Hello\nworld"
			check:expect(layout.step):toThrow "unwrapped multiline text exceeds available height"
			label.TextWrapped = true
			label.AutomaticSize = library.Enum.AutomaticSize.Y
			label.Text = "Hello"
			local beforeFrame, beforeLabel = frame.AbsoluteSize, label.TextBounds
			frame.Size = library.UDim2.fromOffset(200, 200)
			label.Text = "你好"
			check:expect(layout.step):toThrow "unsupported_text_metrics"
			check:expect(frame.AbsoluteSize):toEqual(beforeFrame)
			check:expect(label.TextBounds):toEqual(beforeLabel)
		end
	)

	harness:case("native boundary corrections and Legacy Arial line metrics", function(check)
		local bridge = Lute.fixture.bridge()
		check:defer(bridge.close)
		local library = Roblox.reflectionSnapshot.library(Lute.fixture.load())
		local parameters = bridge.environment.createInstance("GetTextBoundsParams", {
			Font = library.Font.new "rbxasset://fonts/families/LegacyArial.json",
			Size = 14,
			Width = 0,
		})
		local service = bridge.placeEngine().service "TextService"
		for _, entry in
			{
				{ text = "A", width = 13 },
				{ text = " A", width = 18 },
				{ text = "H A", width = 31 },
				{ text = "K2A", width = 37 },
			}
		do
			parameters.Text = entry.text
			check:expect(call(service, "GetTextBoundsAsync", parameters)):toEqual(library.Vector2.new(entry.width, 21))
		end
		check
			:expect(
				call(
					service,
					"GetTextSize",
					string.rep("Wrapped text ", 6),
					14,
					library.Enum.Font.Legacy,
					library.Vector2.new(100, 50)
				)
			)
			:toEqual(library.Vector2.new(80, 42))
	end)
end
