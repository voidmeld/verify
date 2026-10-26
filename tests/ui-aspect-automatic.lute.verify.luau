--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Lute = require "../src/lute"
local Roblox = require "../src/roblox"

for _, axis in { "X", "Y", "XY", "invalid" } do
	it("unmodeled aspect sizing refuses before publication: " .. axis, function(own)
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
		expect(layout.step):toThrow "unsupported_ui_layout"
		expect(root.AbsoluteSize):toEqual(before)
	end)
end

return nil
