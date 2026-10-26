--!strict

local Core = require "../src/core"
local Selector = require "../src/roblox/ui-style-selector"

return function(harness: Core.Harness)
	harness:case("unsupported and malformed selector branches cannot silently match", function(check)
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
			check:expect((pcall(Selector.parse, source))):toBe(false)
		end
	end)
end
