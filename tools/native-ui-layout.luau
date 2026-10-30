--!strict

local Core = require "../src/core"
local Lute = require "../src/lute"
local Files = require "../src/lute/files"
local fixtures = {
	{ name = "native haptic effect requests", source = require "../tests/fixtures/haptic-effect" },
	{ name = "native input action lifecycle", source = require "../tests/fixtures/input-action-probe" },
	{ name = "native bounded automatic parents", source = require "../tests/fixtures/ui-automatic-parent" },
	{ name = "native style selectors and phantom modifiers", source = require "../tests/fixtures/ui-style-selectors" },
	{ name = "native wrapped aspects", source = require "../tests/fixtures/ui-aspect-wrapped" },
	{ name = "native wrapping mutations", source = require "../tests/fixtures/ui-wrap-mutations" },
	{ name = "native aspect flex", source = require "../tests/fixtures/ui-aspect-flex" },
	{ name = "native aspect layout", source = require "../tests/fixtures/ui-aspect-layout" },
	{ name = "native aspect interactions", source = require "../tests/fixtures/ui-aspect-interactions" },
	{ name = "native list wrapping", source = require "../tests/fixtures/ui-list-wrap" },
	{ name = "native wrapping interactions", source = require "../tests/fixtures/ui-wrap-interactions" },
	{ name = "native legacy text layout", source = require "../tests/fixtures/ui-legacy-text" },
	{ name = "native text flex", source = require "../tests/fixtures/ui-text-flex" },
	{ name = "native text clipping", source = require "../tests/fixtures/ui-text-clipping" },
	{ name = "native automatic size constraints", source = require "../tests/fixtures/ui-auto-constraints" },
	{ name = "native text layout", source = require "../tests/fixtures/ui-text-layout" },
	{ name = "native list spacing", source = require "../tests/fixtures/ui-list-spacing" },
	{ name = "native grid layout", source = require "../tests/fixtures/ui-grid-layout" },
	{ name = "native style properties", source = require "../tests/fixtures/ui-style-properties" },
	{ name = "native list flex", source = require "../tests/fixtures/ui-list-flex" },
}

return function()
	local place = Files.temporary "Verify-UI-Layout.rbxlx"
	Lute.place.build { output = place, roots = { "src/core", "src/roblox" }, rootName = "VerifyUILayout" }
	local cases: { string } = {}
	for _, fixture in fixtures do
		table.insert(
			cases,
			string.format(
				"harness:case(%q, function(check) check:expect((function()\n%s\nend)()):toBe(true) end)",
				fixture.name,
				fixture.source
			)
		)
	end
	local result = Lute.studio.run {
		place = place,
		worker = "tools/studio-worker.luau",
		context = "Client",
		deadlineSeconds = 180,
		code = [[
local root = game:GetService("ReplicatedStorage").VerifyUILayout
local Core = require(root.src.core)
local Roblox = require(root.src.roblox)
local harness = Core.createHarness { now = os.clock }
]] .. table.concat(cases, "\n") .. [[
return game:GetService("HttpService"):JSONEncode(Roblox.reportChannel.envelope(runId, harness:run {
    executor = "native-ui-layout",
    environment = { engineVersion = version() },
}))
]],
	}
	assert(result.status == "returned", result.detail)
	local report = Core.decode(result.report)
	print(Core.format(report))
	assert(report.total == #fixtures and report.passed == #fixtures, "native UI layout conformance failed")
end
