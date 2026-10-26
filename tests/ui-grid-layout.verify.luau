--!strict

local Core = require "../src/core"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"

local function fixture(check: Core.Context)
	local snapshot = Lute.fixture.load()
	local library = Roblox.reflectionSnapshot.library(snapshot)
	local roots: { Roblox.Instance } = {}
	local bridge = Lute.fixture.bridge(snapshot, {
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
	local env = bridge.environment
	local root = env.createInstance(
		"Frame",
		{ Size = library.UDim2.fromOffset(200, 0), AutomaticSize = library.Enum.AutomaticSize.Y }
	)
	table.insert(roots, root)
	local grid = env.createInstance("UIGridLayout", {
		Parent = root,
		CellSize = library.UDim2.fromOffset(50, 20),
		CellPadding = library.UDim2.fromOffset(5, 10),
		SortOrder = library.Enum.SortOrder.LayoutOrder,
	})
	return bridge, root, grid, library
end

return function(harness: Core.Harness)
	harness:case("grid reflows visible cells after removal, ordering and cell-size changes", function(check)
		local bridge, root, grid, library = fixture(check)
		local env, layout = bridge.environment, assert(bridge.layout)
		local cells: { Roblox.Instance } = {}
		for index = 1, 5 do
			cells[index] = env.createInstance("Frame", { Parent = root, LayoutOrder = index })
		end
		layout.step()
		check:expect(root.AbsoluteSize):toEqual(library.Vector2.new(200, 50))
		cells[1].Visible = false
		cells[2]:Destroy()
		layout.step()
		check:expect(root.AbsoluteSize):toEqual(library.Vector2.new(200, 20))
		check:expect(cells[3].AbsolutePosition):toEqual(library.Vector2.zero)
		cells[5].LayoutOrder = -1
		layout.step()
		check:expect(cells[5].AbsolutePosition):toEqual(library.Vector2.zero)
		grid.FillDirectionMaxCells = 2
		grid.CellSize = library.UDim2.fromOffset(30, 10)
		layout.step()
		check:expect(root.AbsoluteSize):toEqual(library.Vector2.new(200, 30))
		check:expect(grid.AbsoluteCellCount):toEqual(library.Vector2.new(2, 2))
	end)

	harness:case("unmodeled grid constraints fail before geometry changes", function(check)
		for _, scenario in { "scaled automatic axis", "cell constraint", "cell scale", "zero cell" } do
			local bridge, root, grid, library = fixture(check)
			local env = bridge.environment
			local child = env.createInstance("Frame", { Parent = root })
			if scenario == "scaled automatic axis" then
				grid.CellSize = library.UDim2.new(0, 50, 1, 20)
			elseif scenario == "cell constraint" then
				env.createInstance("UISizeConstraint", { Parent = child })
			elseif scenario == "cell scale" then
				env.createInstance("UIScale", { Parent = child })
			else
				grid.CellSize = library.UDim2.fromOffset(0, 20)
			end
			local before = root.AbsoluteSize
			check
				:expect(function()
					assert(bridge.layout).step()
				end)
				:toThrow "unsupported_ui_layout"
			check:expect(root.AbsoluteSize):toEqual(before)
		end
	end)
end
