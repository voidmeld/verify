--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Core = require "../src/core"
local Roblox = require "../src/roblox"
local Lute = require "../src/lute"
local probe = require "./fixtures/ui-text-layout"

local function mountProbe(caseContext: Core.Context, source: string): (boolean, { string })
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
	caseContext:defer(function()
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
	caseContext:defer(function()
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
	caseContext:defer(function()
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

it("oversized words wrap across glyph boundaries", function(_, caseContext)
	local complete, messages = mountProbe(caseContext, require "./fixtures/ui-word-wrap")
	expect(table.concat(messages, "\n")):toBe ""
	expect(complete):toBe(true)
end)

it("truncation accepts exact and fractional width boundaries", function(_, caseContext)
	local complete, messages = mountProbe(caseContext, require "./fixtures/ui-truncation-boundary")
	expect(table.concat(messages, "\n")):toBe ""
	expect(complete):toBe(true)
end)

it("single-line truncated text reports the Studio ellipsis width", function(_, caseContext)
	local complete, messages = mountProbe(
		caseContext,
		[=[
				local screen = Instance.new("ScreenGui")
				screen.Parent = game.Players.LocalPlayer.PlayerGui
				local expected = {
					{ "AtEnd", 60, 59.333335876464844 },
					{ "AtEnd", 100, 68.666671752929688 },
					{ "AtEnd", 140, 138.66667175292969 },
					{ "SplitWord", 60, 59.333335876464844 },
					{ "SplitWord", 100, 96.666671752929688 },
					{ "SplitWord", 140, 138.66667175292969 },
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
					{ "AtEnd", false, 12, 9.3333339691162109 },
					{ "AtEnd", true, 20, 17.333333969116211 },
					{ "SplitWord", false, 4, 0 },
					{ "SplitWord", true, 12, 9.3333339691162109 },
					{ "SplitWord", false, 20, 17.333333969116211 },
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
	expect(table.concat(messages, "\n")):toBe ""
	expect(complete):toBe(true)
end)

it("wrapped truncated text reports the Studio ellipsis width", function(_, caseContext)
	local complete, messages = mountProbe(
		caseContext,
		[=[
				local screen = Instance.new("ScreenGui")
				screen.Parent = game.Players.LocalPlayer.PlayerGui
				local expected = {
					{ "Automatic transmission mode", "AtEnd", 100, 40, 84, 32, false },
					{ "Automatic transmission mode", "AtEnd", 140, 40, 137.33334350585938, 32, true },
					{ "Automatic transmission mode", "AtEnd", 180, 20, 174.66667175292969, 16, true },
					{ "Automatic transmission mode", "AtEnd", 120, 60, 112, 32, true },
					{ "Automatic transmission mode", "AtEnd", 200, 36, 174.66667175292969, 16, true },
					{ "Automatic transmission mode", "SplitWord", 100, 40, 98.666671752929688, 32, false },
					{ "Automatic transmission mode", "SplitWord", 140, 40, 137.33334350585938, 32, true },
					{ "Automatic transmission mode", "SplitWord", 180, 20, 174.66667175292969, 16, true },
					{ "Automatic transmission mode", "SplitWord", 120, 60, 112, 32, true },
					{ "Automatic transmission mode", "SplitWord", 200, 36, 174.66667175292969, 16, true },
					{ "The quick brown fox jumps over the lazy dog", "AtEnd", 100, 40, 96.666671752929688, 32, false },
					{ "The quick brown fox jumps over the lazy dog", "AtEnd", 140, 40, 124, 32, false },
					{ "The quick brown fox jumps over the lazy dog", "AtEnd", 180, 20, 166.66667175292969, 16, false },
					{ "The quick brown fox jumps over the lazy dog", "AtEnd", 120, 60, 118.66667175292969, 48, true },
					{ "The quick brown fox jumps over the lazy dog", "AtEnd", 200, 36, 187.33334350585938, 32, true },
					{ "The quick brown fox jumps over the lazy dog", "SplitWord", 100, 40, 100, 32, false },
					{ "The quick brown fox jumps over the lazy dog", "SplitWord", 140, 40, 135.33334350585938, 32, false },
					{ "The quick brown fox jumps over the lazy dog", "SplitWord", 120, 60, 118.66667175292969, 48, true },
					{ "The quick brown fox jumps over the lazy dog", "SplitWord", 200, 36, 187.33334350585938, 32, true },
					{ "Confirm the selected driver and race details before continuing.", "AtEnd", 200, 36, 189.33334350585938, 32, true },
					{ "Confirm the selected driver and race details before continuing.", "SplitWord", 100, 40, 91.333335876464844, 32, false },
					{ "Confirm the selected driver and race details before continuing.", "SplitWord", 120, 60, 114.66667175292969, 48, false },
					{ "Confirm the selected driver and race details before continuing.", "SplitWord", 200, 36, 189.33334350585938, 32, true },
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
	expect(table.concat(messages, "\n")):toBe ""
	expect(complete):toBe(true)
end)

it("scaled text reports the Studio size it renders at", function(_, caseContext)
	local complete, messages = mountProbe(
		caseContext,
		[=[
				local screen = Instance.new("ScreenGui")
				screen.Parent = game.Players.LocalPlayer.PlayerGui
				local expected = {
					{ "Score", false, 100, 30, 0, 18, 8, true },
					{ "Score", false, 200, 50, 24, 18, 8, true },
					{ "Score", true, 100, 30, 0, 62, 30, true },
					{ "Score", true, 100, 30, 24, 50, 24, true },
					{ "Score", true, 200, 50, 0, 103.33333587646484, 50, true },
					{ "Score", true, 60, 60, 0, 60, 28.666667938232422, true },
					{ "Score", true, 300, 200, 0, 204.66667175292969, 100, true },
					{ "Score", true, 300, 200, 24, 50, 24, true },
					{ "Automatic transmission mode", false, 100, 30, 0, 93.333335876464844, 8, true },
					{ "Automatic transmission mode", false, 60, 60, 0, 93.333335876464844, 8, false },
					{ "Automatic transmission mode", true, 100, 30, 0, 98.666671752929688, 28, true },
					{ "Automatic transmission mode", true, 200, 50, 0, 172.66667175292969, 49.333335876464844, true },
					{ "Automatic transmission mode", true, 200, 50, 24, 168, 48, true },
					{ "Automatic transmission mode", true, 60, 60, 0, 60, 38, true },
					{ "Automatic transmission mode", true, 300, 200, 0, 296, 194, true },
					{ "Automatic transmission mode", true, 300, 200, 24, 263.33334350585938, 24, true },
					{ "99", false, 100, 30, 0, 8, 8, true },
					{ "99", true, 100, 30, 0, 28, 30, true },
					{ "99", true, 100, 30, 24, 22.666667938232422, 24, true },
					{ "99", true, 200, 50, 0, 46.666667938232422, 50, true },
					{ "99", true, 60, 60, 0, 55.333335876464844, 60, true },
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
	expect(table.concat(messages, "\n")):toBe ""
	expect(complete):toBe(true)
end)

it("fractional rendered text sizes measure at the floored size", function(_, caseContext)
	local complete, messages = mountProbe(
		caseContext,
		[=[
				local screen = Instance.new("ScreenGui")
				screen.Parent = game.Players.LocalPlayer.PlayerGui
				local failures = {}
				for _, row in { { 15.5, 1, 130, 14.666666984558105 }, { 14, 1.25, 148, 16.666667938232422 }, { 16, 1.5, 208, 24 }, { 14.6, 1, 122, 14 } } do
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
	expect(table.concat(messages, "\n")):toBe ""
	expect(complete):toBe(true)
end)

it("rich text without metric tags preserves native text bounds", function(_, caseContext)
	local complete, messages = mountProbe(
		caseContext,
		[=[
				local screen = Instance.new("ScreenGui")
				screen.Parent = game.Players.LocalPlayer.PlayerGui
				local failures = {}
				local rows = {
					{ "<u>Save changes</u>", 1000, 91.333335876464844, 18 },
					{ "<s>Save</s> changes", 1000, 91.333335876464844, 18 },
					{ "<font color=\"#FF0000\">Save</font> changes", 1000, 91.333335876464844, 18 },
					{ "<font transparency=\"0.5\">Save</font> changes", 1000, 91.333335876464844, 18 },
					{ "<stroke color=\"#000000\" thickness=\"2\">Save</stroke> changes", 1000, 91.333335876464844, 18 },
					{ "<mark color=\"#FFFF00\">Save</mark> changes", 1000, 91.333335876464844, 18 },
					{ "<!--note-->Save changes", 1000, 91.333335876464844, 18 },
					{ "Tom &amp; Jerry &lt;3 &gt; &quot;x&quot; &apos;y&apos;", 1000, 152, 18 },
					{ "line one<br />line two", 1000, 52.666667938232422, 36 },
					{ "<uc>Save</uc> changes", 1000, 94.666664123535156, 18 },
					{ "<u>Save all of these changes now</u>", 90, 88.666664123535156, 54 },
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
	expect(table.concat(messages, "\n")):toBe ""
	expect(complete):toBe(true)
end)

it("a hyphen beside punctuation preserves native text bounds", function(_, caseContext)
	local complete, messages = mountProbe(
		caseContext,
		[=[
				local screen = Instance.new("ScreenGui")
				screen.Parent = game.Players.LocalPlayer.PlayerGui
				local failures = {}
				local faces = {
					{ "BuilderSans", 16, { 8.6666669845581055, 13.333333969116211, 6, 6, 6, 12.666666984558105, 9.3333339691162109 } },
					{ "Nunito", 20, { 13.333333969116211, 20, 9.3333339691162109, 9.3333339691162109, 9.3333339691162109, 16, 16 } },
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
	expect(table.concat(messages, "\n")):toBe ""
	expect(complete):toBe(true)
end)

it("rich text with tags that change metrics is refused", function(_, caseContext)
	for _, row in { { "<b>Save</b> changes", "<b>" }, { '<font size="24">Save</font> changes', "<font size>" } } do
		local complete, messages = mountProbe(
			caseContext,
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
		expect(complete):toBe(false)
		expect(table.concat(messages, "\n")):toContain("unsupported_text_metrics: RichText " .. row[2])
	end
end)

it("wrapped truncation preserves preceding lines and accepts a width boundary", function(_, caseContext)
	local rows = {
		{ mode = "AtEnd", width = 100, height = 40, bounds = 97.33333587646484 },
		{ mode = "SplitWord", width = 140, height = 40, bounds = 136 },
	}
	for _, row in rows do
		local complete, messages = mountProbe(
			caseContext,
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
						assert(label.TextBounds == Vector2.new(%.17g, 32), tostring(label.TextBounds))
						assert(label.TextFits == false)
						return true
					]],
				row.width,
				row.height,
				row.mode,
				row.bounds
			)
		)
		expect(complete):toBe(true)
		expect(table.concat(messages, "\n")):toBe ""
	end
end)

it("text layout matches the same native conformance assertions", function(own)
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
		client = { name = "Text", userId = 1, viewport = { x = 800, y = 600 } },
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
	local thread = scheduler.spawnTagged({ context = "client", source = "ui-text-layout" }, function()
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
