--!strict

local Core = require "../src/core"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"

return function(harness: Core.Harness)
	for _, axis in { "X", "Y", "XY", "invalid" } do
		harness:case("unmodeled aspect sizing refuses before publication: " .. axis, function(check)
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
			local root = env.createInstance("Frame", { Size = library.UDim2.fromOffset(100, 50) })
			local aspect = env.createInstance("UIAspectRatioConstraint", { Parent = root, AspectRatio = 2 })
			table.insert(roots, root)
			layout.step()
			local before = root.AbsoluteSize
			if axis == "invalid" then
				env.poke(aspect, "AspectRatio", 0)
			else
				root.AutomaticSize = library.Enum.AutomaticSize[axis]
			end
			root.Size = library.UDim2.fromOffset(200, 100)
			check:expect(layout.step):toThrow "unsupported_ui_layout"
			check:expect(root.AbsoluteSize):toEqual(before)
		end)
	end
end
