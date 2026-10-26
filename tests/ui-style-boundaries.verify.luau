--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Selector = require "../src/roblox/ui-style-selector"

it("unsupported and malformed selector branches cannot silently match", function()
	for _, source in
		{
			"",
			"Frame,",
			",Frame",
			"Frame,,TextLabel",
			"Frame >",
			"Frame > > .Card",
			"Frame >>> .Card",
			".Container .Card",
			"#",
			".Card:Hovering",
			".Card:Hover:Press",
			"@PreferredInputTouch",
			".Card::UIStroke#Outer",
			".Card::UIStroke::UIGradient",
			"Frame, .Card:Pressed",
		}
	do
		expect((pcall(Selector.parse, source))):toBe(false)
	end
end)

return nil
