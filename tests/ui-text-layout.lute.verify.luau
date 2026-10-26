--!strict

local Core = require "../src/core"
local Roblox = require "../src/roblox"
local Lute = require "../src/lute"
local probe = require "./fixtures/ui-text-layout"

return function(harness: Core.Harness)
	local function mountProbe(check: Core.Context, source: string): (boolean, { string })
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
			client = { name = "Text", userId = 1, viewport = { x = 800, y = 600 } },
			beforeRender = assert(bridge.layout).step,
		})
		check:defer(function()
			for index = #runtime.closeHandlers, 1, -1 do
				runtime.closeHandlers[index]()
			end
		end)
		table.insert(roots, assert(assert(runtime.localPlayer):FindFirstChild "PlayerGui"))
		local complete = false
		local scheduler = bridge.environment.scheduler
		local thread = scheduler.spawnTagged({ context = "client", source = "ui-text-layout" }, function()
			complete = Lute.chunk.load(source, { environment = runtime.globals })() == true
		end)
		check:defer(function()
			scheduler.cancel(thread)
		end)
		for _ = 1, 240 do
			if complete or #scheduler.failures > 0 then
				break
			end
			local stepped = table.pack(pcall(runtime.step, 1 / 60))
			if not stepped[1] then
				return false, { tostring(stepped[2]) }
			end
		end
		local messages: { string } = {}
		for _, failure in scheduler.failures do
			table.insert(messages, tostring(failure))
		end
		return complete, messages
	end

	harness:case("single-line truncated text reports the Studio ellipsis width", function(check)
		local complete, messages = mountProbe(
			check,
			[=[
				local screen = Instance.new("ScreenGui")
				screen.Parent = game.Players.LocalPlayer.PlayerGui
				local expected = {
					{ "AtEnd", 60, 57 },
					{ "AtEnd", 100, 72 },
					{ "AtEnd", 140, 72 },
					{ "SplitWord", 60, 57 },
					{ "SplitWord", 100, 93 },
					{ "SplitWord", 140, 137 },
				}
				local labels = {}
				for index, row in expected do
					local label = Instance.new("TextLabel")
					label.FontFace, label.TextSize = Font.new("rbxasset://fonts/families/BuilderSans.json"), 16
					label.Text = "Automatic transmission mode"
					label.Size, label.TextTruncate = UDim2.fromOffset(row[2], 20), Enum.TextTruncate[row[1]]
					label.Parent = screen
					labels[index] = label
				end
				task.wait(0.05)
				for index, row in expected do
					local label = labels[index]
					assert(label.TextBounds == Vector2.new(row[3], 16), `{row[1]} {row[2]}: {label.TextBounds}`)
					assert(label.TextFits == false, `{row[1]} {row[2]} fits`)
				end
				local narrow = {
					{ "AtEnd", false, 4, 0 },
					{ "AtEnd", false, 12, 9 },
					{ "AtEnd", true, 20, 17 },
					{ "SplitWord", false, 4, 0 },
					{ "SplitWord", true, 12, 9 },
					{ "SplitWord", false, 20, 17 },
				}
				for _, row in narrow do
					local label = Instance.new("TextLabel")
					label.FontFace, label.TextSize = Font.new("rbxasset://fonts/families/BuilderSans.json"), 16
					label.Text, label.TextWrapped = "Automatic", row[2]
					label.Size, label.TextTruncate = UDim2.fromOffset(row[3], 20), Enum.TextTruncate[row[1]]
					label.Parent = screen
					task.wait(0.05)
					assert(label.TextBounds == Vector2.new(row[4], 16), `narrow {row[1]} {row[3]}: {label.TextBounds}`)
					label:Destroy()
				end
				return true
			]=]
		)
		check:expect(table.concat(messages, "\n")):toBe ""
		check:expect(complete):toBe(true)
	end)

	harness:case("wrapped truncated text reports the Studio ellipsis width", function(check)
		local complete, messages = mountProbe(
			check,
			[=[
				local screen = Instance.new("ScreenGui")
				screen.Parent = game.Players.LocalPlayer.PlayerGui
				local expected = {
					{ "Automatic transmission mode", "AtEnd", 100, 40, 86, 32, false },
					{ "Automatic transmission mode", "AtEnd", 140, 40, 117, 32, true },
					{ "Automatic transmission mode", "AtEnd", 180, 20, 153, 16, false },
					{ "Automatic transmission mode", "AtEnd", 120, 60, 117, 32, true },
					{ "Automatic transmission mode", "AtEnd", 200, 36, 184, 16, true },
					{ "Automatic transmission mode", "SplitWord", 100, 40, 90, 32, false },
					{ "Automatic transmission mode", "SplitWord", 140, 40, 117, 32, true },
					{ "Automatic transmission mode", "SplitWord", 180, 20, 177, 16, false },
					{ "Automatic transmission mode", "SplitWord", 120, 60, 117, 32, true },
					{ "Automatic transmission mode", "SplitWord", 200, 36, 184, 16, true },
					{ "The quick brown fox jumps over the lazy dog", "AtEnd", 100, 40, 71, 32, false },
					{ "The quick brown fox jumps over the lazy dog", "AtEnd", 140, 40, 130, 32, false },
					{ "The quick brown fox jumps over the lazy dog", "AtEnd", 180, 20, 176, 16, false },
					{ "The quick brown fox jumps over the lazy dog", "AtEnd", 120, 60, 117, 48, true },
					{ "The quick brown fox jumps over the lazy dog", "AtEnd", 200, 36, 199, 32, true },
					{ "The quick brown fox jumps over the lazy dog", "SplitWord", 100, 40, 98, 32, false },
					{ "The quick brown fox jumps over the lazy dog", "SplitWord", 140, 40, 134, 32, false },
					{ "The quick brown fox jumps over the lazy dog", "SplitWord", 120, 60, 117, 48, true },
					{ "The quick brown fox jumps over the lazy dog", "SplitWord", 200, 36, 199, 32, true },
					{ "Confirm the selected driver and race details before continuing.", "AtEnd", 200, 36, 198, 32, true },
					{ "Confirm the selected driver and race details before continuing.", "SplitWord", 100, 40, 96, 32, false },
					{ "Confirm the selected driver and race details before continuing.", "SplitWord", 120, 60, 119, 48, false },
					{ "Confirm the selected driver and race details before continuing.", "SplitWord", 200, 36, 198, 32, true },
				}
				local labels = {}
				for index, row in expected do
					local label = Instance.new("TextLabel")
					label.FontFace, label.TextSize = Font.new("rbxasset://fonts/families/BuilderSans.json"), 16
					label.Text, label.TextWrapped = row[1], true
					label.Size, label.TextTruncate = UDim2.fromOffset(row[3], row[4]), Enum.TextTruncate[row[2]]
					label.Parent = screen
					labels[index] = label
				end
				task.wait(0.05)
				local failures = {}
				for index, row in expected do
					local label = labels[index]
					if label.TextBounds ~= Vector2.new(row[5], row[6]) or label.TextFits ~= row[7] then
						table.insert(failures, `{row[2]} {row[3]}x{row[4]} "{row[1]}": {label.TextBounds} {label.TextFits}`)
					end
				end
				assert(#failures == 0, table.concat(failures, "\n"))
				return true
			]=]
		)
		check:expect(table.concat(messages, "\n")):toBe ""
		check:expect(complete):toBe(true)
	end)

	harness:case("scaled text reports the Studio size it renders at", function(check)
		local complete, messages = mountProbe(
			check,
			[=[
				local screen = Instance.new("ScreenGui")
				screen.Parent = game.Players.LocalPlayer.PlayerGui
				local expected = {
					{ "Score", false, 100, 30, 0, 19, 8, true },
					{ "Score", false, 200, 50, 24, 19, 8, true },
					{ "Score", true, 100, 30, 0, 64, 30, true },
					{ "Score", true, 100, 30, 24, 50, 24, true },
					{ "Score", true, 200, 50, 0, 104, 50, true },
					{ "Score", true, 60, 60, 0, 59, 28, true },
					{ "Score", true, 300, 200, 0, 206, 100, true },
					{ "Score", true, 300, 200, 24, 50, 24, true },
					{ "Automatic transmission mode", false, 100, 30, 0, 96, 8, true },
					{ "Automatic transmission mode", false, 60, 60, 0, 96, 8, false },
					{ "Automatic transmission mode", true, 100, 30, 0, 94, 26, true },
					{ "Automatic transmission mode", true, 200, 50, 0, 180, 50, true },
					{ "Automatic transmission mode", true, 200, 50, 24, 168, 48, true },
					{ "Automatic transmission mode", true, 60, 60, 0, 60, 36, true },
					{ "Automatic transmission mode", true, 300, 200, 0, 299, 195, true },
					{ "Automatic transmission mode", true, 300, 200, 24, 262, 24, true },
					{ "99", false, 100, 30, 0, 8, 8, true },
					{ "99", true, 100, 30, 0, 28, 30, true },
					{ "99", true, 100, 30, 24, 22, 24, true },
					{ "99", true, 200, 50, 0, 46, 50, true },
					{ "99", true, 60, 60, 0, 56, 60, true },
					{ "99", true, 300, 200, 0, 92, 100, true },
				}
				local labels = {}
				for index, row in expected do
					local label = Instance.new("TextLabel")
					label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json")
					label.Text, label.TextScaled, label.TextWrapped = row[1], true, row[2]
					label.Size = UDim2.fromOffset(row[3], row[4])
					if row[5] > 0 then
						local limit = Instance.new("UITextSizeConstraint")
						limit.MaxTextSize, limit.Parent = row[5], label
					end
					label.Parent = screen
					labels[index] = label
				end
				task.wait(0.05)
				local failures = {}
				for index, row in expected do
					local label = labels[index]
					if label.TextBounds ~= Vector2.new(row[6], row[7]) or label.TextFits ~= row[8] then
						table.insert(failures, `{row[1]} {row[2]} {row[3]}x{row[4]} max {row[5]}: {label.TextBounds} {label.TextFits}`)
					end
				end
				assert(#failures == 0, table.concat(failures, "\n"))
				return true
			]=]
		)
		check:expect(table.concat(messages, "\n")):toBe ""
		check:expect(complete):toBe(true)
	end)

	harness:case("fractional rendered text sizes measure at the floored size as Studio 0.744 does", function(check)
		local complete, messages = mountProbe(
			check,
			[=[
				local screen = Instance.new("ScreenGui")
				screen.Parent = game.Players.LocalPlayer.PlayerGui
				local failures = {}
				for _, row in { { 15.5, 1, 135, 15 }, { 14, 1.25, 149, 17 }, { 16, 1.5, 206, 24 }, { 14.6, 1, 126, 14 } } do
					local frame = Instance.new("Frame")
					frame.Size, frame.Parent = UDim2.fromOffset(600, 100), screen
					local scale = Instance.new("UIScale")
					scale.Scale, scale.Parent = row[2], frame
					local label = Instance.new("TextLabel")
					label.Text, label.FontFace = "Automatic transmission", Font.new("rbxasset://fonts/families/BuilderSans.json")
					label.TextSize, label.Size, label.Parent = row[1], UDim2.fromOffset(400, 40), frame
					task.wait(0.05)
					if label.TextBounds ~= Vector2.new(row[3], row[4]) then
						table.insert(failures, `{row[1]} x {row[2]}: {label.TextBounds}`)
					end
					frame:Destroy()
				end
				assert(#failures == 0, table.concat(failures, "\n"))
				return true
			]=]
		)
		check:expect(table.concat(messages, "\n")):toBe ""
		check:expect(complete):toBe(true)
	end)

	harness:case("rich text without metric tags measures as its plain text as Studio 0.744 does", function(check)
		local complete, messages = mountProbe(
			check,
			[=[
				local screen = Instance.new("ScreenGui")
				screen.Parent = game.Players.LocalPlayer.PlayerGui
				local failures = {}
				local rows = {
					{ "<u>Save changes</u>", 1000, 94, 18 },
					{ "<s>Save</s> changes", 1000, 94, 18 },
					{ '<font color="#FF0000">Save</font> changes', 1000, 94, 18 },
					{ '<font transparency="0.5">Save</font> changes', 1000, 94, 18 },
					{ '<stroke color="#000000" thickness="2">Save</stroke> changes', 1000, 94, 18 },
					{ '<mark color="#FFFF00">Save</mark> changes', 1000, 94, 18 },
					{ "<!--note-->Save changes", 1000, 94, 18 },
					{ "Tom &amp; Jerry &lt;3 &gt; &quot;x&quot; &apos;y&apos;", 1000, 154, 18 },
					{ "line one<br />line two", 1000, 53, 36 },
					{ "<uc>Save</uc> changes", 1000, 96, 18 },
					{ "<u>Save all of these changes now</u>", 90, 69, 72 },
				}
				for _, row in rows do
					local label = Instance.new("TextLabel")
					label.FontFace, label.TextSize = Font.new("rbxasset://fonts/families/BuilderSans.json"), 18
					label.RichText, label.TextWrapped, label.Text = true, row[2] < 1000, row[1]
					label.Size, label.Parent = UDim2.fromOffset(row[2], 200), screen
					task.wait(0.05)
					if label.TextBounds ~= Vector2.new(row[3], row[4]) then
						table.insert(failures, `{row[1]}: {label.TextBounds}`)
					end
					label:Destroy()
				end
				assert(#failures == 0, table.concat(failures, "\n"))
				return true
			]=]
		)
		check:expect(table.concat(messages, "\n")):toBe ""
		check:expect(complete):toBe(true)
	end)

	harness:case("a hyphen beside punctuation measures as Studio 0.744 does", function(check)
		local complete, messages = mountProbe(
			check,
			[=[
				local screen = Instance.new("ScreenGui")
				screen.Parent = game.Players.LocalPlayer.PlayerGui
				local failures = {}
				local faces = {
					{ "BuilderSans", 16, { 9, 14, 7, 6, 7, 12, 10 } },
					{ "Nunito", 20, { 14, 21, 10, 10, 10, 17, 16 } },
				}
				for _, face in faces do
					for index, text in { "--", "---", "-.", ".-", "-,", "(-)", "->" } do
						local label = Instance.new("TextLabel")
						label.FontFace = Font.new(`rbxasset://fonts/families/{face[1]}.json`)
						label.TextSize, label.Text = face[2], text
						label.Size, label.Parent = UDim2.fromOffset(400, 40), screen
						task.wait(0.05)
						if label.TextBounds.X ~= face[3][index] then
							table.insert(failures, `{face[1]} {text}: {label.TextBounds.X}`)
						end
						label:Destroy()
					end
				end
				assert(#failures == 0, table.concat(failures, "\n"))
				return true
			]=]
		)
		check:expect(table.concat(messages, "\n")):toBe ""
		check:expect(complete):toBe(true)
	end)

	harness:case("rich text with tags that change metrics is refused", function(check)
		for _, row in { { "<b>Save</b> changes", "<b>" }, { '<font size="24">Save</font> changes', "<font size>" } } do
			local complete, messages = mountProbe(
				check,
				string.format(
					[[
						local screen = Instance.new("ScreenGui")
						screen.Parent = game.Players.LocalPlayer.PlayerGui
						local label = Instance.new("TextLabel")
						label.FontFace, label.TextSize = Font.new("rbxasset://fonts/families/BuilderSans.json"), 18
						label.RichText, label.Text = true, %q
						label.Size, label.Parent = UDim2.fromOffset(400, 40), screen
						task.wait(0.05)
						return true
					]],
					row[1]
				)
			)
			check:expect(complete):toBe(false)
			check:expect(table.concat(messages, "\n")):toContain("unsupported_text_metrics: RichText " .. row[2])
		end
	end)

	harness:case("truncation the text model cannot place exactly is refused", function(check)
		local rows: { { mode: string, width: number, height: number, message: string } } = {
			{ mode = "AtEnd", width = 100, height = 40, message = "wrapped truncation shorter than its line" },
			{ mode = "SplitWord", width = 140, height = 40, message = "truncation within a pixel of the limit" },
		}
		for _, row in rows do
			local complete, messages = mountProbe(
				check,
				string.format(
					[[
						local screen = Instance.new("ScreenGui")
						screen.Parent = game.Players.LocalPlayer.PlayerGui
						local label = Instance.new("TextLabel")
						label.FontFace, label.TextSize = Font.new("rbxasset://fonts/families/BuilderSans.json"), 16
						label.Text, label.TextWrapped = "Confirm the selected driver and race details before continuing.", true
						label.Size, label.TextTruncate = UDim2.fromOffset(%d, %d), Enum.TextTruncate.%s
						label.Parent = screen
						task.wait(0.05)
						return true
					]],
					row.width,
					row.height,
					row.mode
				)
			)
			check:expect(complete):toBe(false)
			check:expect(table.concat(messages, "\n")):toContain(row.message)
		end
	end)

	harness:case("text layout matches the same native conformance assertions", function(check)
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
			client = { name = "Text", userId = 1, viewport = { x = 800, y = 600 } },
			beforeRender = assert(bridge.layout).step,
		})
		check:defer(function()
			for index = #runtime.closeHandlers, 1, -1 do
				runtime.closeHandlers[index]()
			end
		end)
		table.insert(roots, assert(assert(runtime.localPlayer):FindFirstChild "PlayerGui"))
		local complete = false
		local scheduler = bridge.environment.scheduler
		local thread = scheduler.spawnTagged({ context = "client", source = "ui-text-layout" }, function()
			complete = Lute.chunk.load(probe, { environment = runtime.globals })() == true
		end)
		check:defer(function()
			scheduler.cancel(thread)
		end)
		for _ = 1, 240 do
			if complete or #scheduler.failures > 0 then
				break
			end
			runtime.step(1 / 60)
		end
		check:expect(engine.diagnostics):toEqual {}
		check:expect(complete):toBe(true)
	end)
end
