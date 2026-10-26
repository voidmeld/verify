--!strict

local Core = require "../src/core"
local Environment = require "../src/roblox/environment"
local Layout = require "../src/roblox/ui-layout"
local Types = require "../src/roblox/datatypes"

local function fixture(): Environment.Environment
	local options: Environment.Options = {
		undeclaredWrites = true,
		classes = ({
			UIScale = { super = "Instance", properties = { Scale = 1 } },
			UISizeConstraint = {
				super = "Instance",
				properties = { MinSize = Types.Vector2.new(0, 0), MaxSize = Types.Vector2.new(math.huge, math.huge) },
			},
		} :: unknown) :: { [string]: Environment.ClassSpec },
	}
	return Environment.create(options)
end

local function controller(env: Environment.Environment, root: Environment.Instance): Layout.Controller
	return Layout.attach(env, {
		roots = function()
			return { root }
		end,
		viewport = function()
			return { X = 800, Y = 600 }
		end,
	})
end

return function(suite: Core.Harness)
	suite:suite("simulated GUI layout", function()
		suite:case(
			"wrapped and aligned spacing is modeled and overflowing spacing fails before publishing geometry",
			function(check)
				for _, scenario in { "overflow", "non-leading", "wrap" } do
					local env = fixture()
					local root = env.createInstance("Frame", { Size = Types.UDim2.fromOffset(100, 100) })
					local list = env.createInstance("UIListLayout", {
						Parent = root,
						FillDirection = "Horizontal",
						HorizontalFlex = "SpaceEvenly",
						HorizontalAlignment = if scenario == "non-leading" then "Center" else "Left",
						Wraps = scenario == "wrap",
					})
					local child = env.createInstance("Frame", {
						Parent = root,
						Size = Types.UDim2.fromOffset(if scenario == "overflow" then 101 else 20, 20),
					})
					if scenario == "wrap" or scenario == "non-leading" then
						controller(env, root).step()
						check:expect(env.propertyOf(root, "AbsoluteSize")):toEqual(Types.Vector2.new(100, 100))
						check:expect(env.propertyOf(child, "AbsolutePosition")):toEqual(Types.Vector2.new(40, 0))
						check:expect(env.propertyOf(list, "AbsoluteContentSize")):toEqual(Types.Vector2.new(20, 20))
						continue
					end
					check
						:expect(function()
							controller(env, root).step()
						end)
						:toThrow "unsupported_ui_layout"
					check:expect(env.propertyOf(root, "AbsoluteSize")):toBe(nil)
					check:expect(env.propertyOf(list, "AbsoluteContentSize")):toBe(nil)
				end
			end
		)

		suite:case("rounds fractional hit coordinates to the nearest pixel as Studio 0.744 does", function(check)
			local env = fixture()
			local root = env.createInstance("ScreenGui", {})
			local box = env.createInstance("Frame", {
				Parent = root,
				Position = Types.UDim2.fromOffset(100, 100),
				Size = Types.UDim2.fromOffset(10, 10),
			})
			local layout = controller(env, root)
			layout.step()
			local observed: { boolean } = {}
			for _, dx in { -0.6, -0.5, -0.4, 0, 9.4, 9.5, 9.6, 10, 10.4, 10.5, 10.6 } do
				table.insert(observed, table.find(layout.objectsAtPosition(root, 100 + dx, 105), box) ~= nil)
			end
			check:expect(observed):toEqual { false, true, true, true, true, true, true, true, true, false, false }
		end)

		suite:case("matches Studio 0.744 Global and Sibling rectangular hit order", function(check)
			local env = fixture()
			local root = env.createInstance("ScreenGui", { ZIndexBehavior = Types.Enum.ZIndexBehavior.Global })
			local base = env.createInstance("TextButton", {
				Parent = root,
				Position = Types.UDim2.fromOffset(180, 120),
				Size = Types.UDim2.fromOffset(100, 80),
				ZIndex = 10,
			})
			local child = env.createInstance("Frame", {
				Parent = base,
				Position = Types.UDim2.fromOffset(10, 10),
				Size = Types.UDim2.fromOffset(40, 40),
				ZIndex = 1,
			})
			local overlay = env.createInstance("Frame", {
				Parent = root,
				Position = Types.UDim2.fromOffset(180, 120),
				Size = Types.UDim2.fromOffset(100, 80),
				ZIndex = 5,
				BackgroundTransparency = 1,
			})
			local layout = controller(env, root)
			layout.step()
			check:expect(layout.objectsAtPosition(root, 200, 140)):toEqual { base, overlay, child }
			root.ZIndexBehavior = Types.Enum.ZIndexBehavior.Sibling
			check:expect(layout.objectsAtPosition(root, 200, 140)):toEqual { child, base, overlay }
			overlay.ZIndex = 10
			check:expect(layout.objectsAtPosition(root, 200, 140)):toEqual { overlay, child, base }
			root.ZIndexBehavior = Types.Enum.ZIndexBehavior.Global
			check:expect(layout.objectsAtPosition(root, 200, 140)):toEqual { overlay, base, child }
			base.Interactable = false
			check:expect(layout.objectsAtPosition(root, 200, 140)):toEqual { overlay, base, child }
		end)
		suite:case("matches native inclusive edges, clipping and hidden hit exclusion", function(check)
			local env = fixture()
			local root = env.createInstance "ScreenGui"
			local base = env.createInstance(
				"Frame",
				{ Parent = root, Position = Types.UDim2.fromOffset(180, 120), Size = Types.UDim2.fromOffset(100, 80) }
			)
			local child = env.createInstance(
				"Frame",
				{ Parent = base, Position = Types.UDim2.fromOffset(80, 10), Size = Types.UDim2.fromOffset(60, 40) }
			)
			local layout = controller(env, root)
			layout.step()
			check:expect(layout.objectsAtPosition(root, 280, 180)):toEqual { base }
			check:expect(layout.objectsAtPosition(root, 200, 200)):toEqual { base }
			check:expect(layout.objectsAtPosition(root, 281, 180)):toEqual {}
			check:expect(layout.objectsAtPosition(root, 300, 140)):toEqual { child }
			base.ClipsDescendants = true
			check:expect(layout.objectsAtPosition(root, 300, 140)):toEqual {}
			base.Visible = false
			check:expect(layout.objectsAtPosition(root, 200, 140)):toEqual {}
			base.Visible = true
			root.Enabled = false
			check:expect(layout.objectsAtPosition(root, 200, 140)):toEqual {}
		end)
		suite:case("matches native scale and padding observations at a nonzero screen origin", function(check)
			local env = fixture()
			local root = env.createInstance "ScreenGui"
			local parent = env.createInstance("Frame", {
				Parent = root,
				Position = Types.UDim2.fromOffset(10, 20),
				Size = Types.UDim2.fromOffset(200, 100),
			})
			local child = env.createInstance("Frame", {
				Parent = parent,
				Position = Types.UDim2.new(0.5, 3, 0.25, 4),
				Size = Types.UDim2.new(0.5, 7, 0.5, 9),
				AnchorPoint = Types.Vector2.new(0.5, 0.5),
			})
			local layout = Layout.attach(env, {
				roots = function()
					return { root }
				end,
				viewport = function()
					return { X = 800, Y = 600 }
				end,
				origin = function()
					return { X = 0, Y = -58 }
				end,
			})
			layout.step()
			check:expect(parent.AbsolutePosition):toEqual(Types.Vector2.new(10, -38))
			check:expect(child.AbsolutePosition):toEqual(Types.Vector2.new(59.5, -38.5))
			check:expect(child.AbsoluteSize):toEqual(Types.Vector2.new(107, 59))
			env.createInstance("UIScale", { Parent = parent, Scale = 0.5 })
			layout.step()
			check:expect(parent.AbsolutePosition):toEqual(Types.Vector2.new(10, -38))
			check:expect(parent.AbsoluteSize):toEqual(Types.Vector2.new(100, 50))
			check:expect(child.AbsolutePosition):toEqual(Types.Vector2.new(34.75, -38.25))
			check:expect(child.AbsoluteSize):toEqual(Types.Vector2.new(53.5, 29.5))
			env.createInstance("UIPadding", {
				Parent = parent,
				PaddingLeft = Types.UDim.new(0, 10),
				PaddingTop = Types.UDim.new(0, 6),
			})
			layout.step()
			check:expect(child.AbsolutePosition):toEqual(Types.Vector2.new(38.5, -35.25))
			check:expect(child.AbsoluteSize):toEqual(Types.Vector2.new(51, 28))
		end)

		suite:case("resolves nested scale, offsets and anchor points on each frame", function(check)
			local env = fixture()
			local root = env.createInstance "ScreenGui"
			local parent = env.createInstance("Frame", {
				Parent = root,
				Position = Types.UDim2.fromOffset(10, 20),
				Size = Types.UDim2.fromOffset(200, 100),
			})
			local child = env.createInstance("Frame", {
				Parent = parent,
				Position = Types.UDim2.new(0.5, 3, 0.25, 4),
				Size = Types.UDim2.new(0.5, 7, 0.5, 9),
				AnchorPoint = Types.Vector2.new(0.5, 0.5),
			})
			local layout = controller(env, root)
			layout.step()
			check:expect(child.AbsoluteSize):toEqual(Types.Vector2.new(107, 59))
			check:expect(child.AbsolutePosition):toEqual(Types.Vector2.new(59.5, 19.5))
			parent.Size = Types.UDim2.fromOffset(300, 200)
			layout.step()
			check:expect(child.AbsoluteSize):toEqual(Types.Vector2.new(157, 109))
			check:expect(child.AbsolutePosition):toEqual(Types.Vector2.new(84.5, 19.5))
		end)

		suite:case("lays out visible siblings in stable order with padding and alignment", function(check)
			local env = fixture()
			local root = env.createInstance("Frame", { Size = Types.UDim2.fromOffset(200, 100) })
			env.createInstance("UIPadding", {
				Parent = root,
				PaddingLeft = Types.UDim.new(0, 10),
				PaddingRight = Types.UDim.new(0, 10),
				PaddingTop = Types.UDim.new(0, 6),
				PaddingBottom = Types.UDim.new(0, 4),
			})
			local list = env.createInstance("UIListLayout", {
				Parent = root,
				FillDirection = "Horizontal",
				SortOrder = "LayoutOrder",
				Padding = Types.UDim.new(0, 8),
				HorizontalAlignment = "Center",
				VerticalAlignment = "Bottom",
			})
			local first = env.createInstance("Frame", { Parent = root, Size = Types.UDim2.fromOffset(40, 20) })
			local second = env.createInstance("Frame", { Parent = root, Size = Types.UDim2.fromOffset(20, 30) })
			env.createInstance("Frame", { Parent = root, Visible = false, Size = Types.UDim2.fromOffset(100, 100) })
			controller(env, root).step()
			check:expect(first.AbsolutePosition):toEqual(Types.Vector2.new(66, 76))
			check:expect(second.AbsolutePosition):toEqual(Types.Vector2.new(114, 66))
			check:expect(list.AbsoluteContentSize):toEqual(Types.Vector2.new(68, 30))
		end)

		suite:case("scales descendants and applies minimum and maximum size constraints", function(check)
			local env = fixture()
			local root = env.createInstance("Frame", { Size = Types.UDim2.fromOffset(200, 100) })
			env.createInstance("UIScale", { Parent = root, Scale = 0.5 })
			local child = env.createInstance("Frame", { Parent = root, Size = Types.UDim2.new(0.5, 10, 1, 20) })
			env.createInstance("UISizeConstraint", {
				Parent = child,
				MinSize = Types.Vector2.new(120, 0),
				MaxSize = Types.Vector2.new(200, 80),
			})
			controller(env, root).step()
			check:expect(root.AbsoluteSize):toEqual(Types.Vector2.new(100, 50))
			check:expect(child.AbsoluteSize):toEqual(Types.Vector2.new(60, 40))
		end)

		suite:case("matches Studio Client 2026-10-22 intrinsic column growth shrink and authored floor", function(check)
			local env = fixture()
			local root = env.createInstance("Frame", { Size = Types.UDim2.fromOffset(10, 12), AutomaticSize = "XY" })
			local list = env.createInstance("UIListLayout", { Parent = root, Padding = Types.UDim.new(0, 5) })
			local first = env.createInstance("Frame", { Parent = root, Size = Types.UDim2.fromOffset(40, 20) })
			local second = env.createInstance("Frame", { Parent = root, Size = Types.UDim2.fromOffset(60, 30) })
			local layout = controller(env, root)
			layout.step()
			check:expect(root.AbsoluteSize):toEqual(Types.Vector2.new(60, 55))
			check:expect(list.AbsoluteContentSize):toEqual(Types.Vector2.new(60, 55))
			second.Visible = false
			layout.step()
			check:expect(root.AbsoluteSize):toEqual(Types.Vector2.new(40, 20))
			check:expect(list.AbsoluteContentSize):toEqual(Types.Vector2.new(40, 20))
			first.Size = Types.UDim2.fromOffset(80, 25)
			layout.step()
			check:expect(root.AbsoluteSize):toEqual(Types.Vector2.new(80, 25))
			check:expect(list.AbsoluteContentSize):toEqual(Types.Vector2.new(80, 25))
			first:Destroy()
			layout.step()
			check:expect(root.AbsoluteSize):toEqual(Types.Vector2.new(10, 12))
			check:expect(list.AbsoluteContentSize):toEqual(Types.Vector2.new(0, 0))
		end)

		suite:case("matches Studio Client 2026-10-22 positioned child and intrinsic padding", function(check)
			local env = fixture()
			local root = env.createInstance("Frame", { Size = Types.UDim2.fromOffset(10, 12), AutomaticSize = "XY" })
			env.createInstance("Frame", {
				Parent = root,
				Position = Types.UDim2.fromOffset(7, 9),
				Size = Types.UDim2.fromOffset(40, 20),
			})
			local layout = controller(env, root)
			layout.step()
			check:expect(root.AbsoluteSize):toEqual(Types.Vector2.new(47, 29))
			env.createInstance("UIPadding", {
				Parent = root,
				PaddingLeft = Types.UDim.new(0, 3),
				PaddingRight = Types.UDim.new(0, 4),
				PaddingTop = Types.UDim.new(0, 2),
				PaddingBottom = Types.UDim.new(0, 6),
			})
			layout.step()
			check:expect(root.AbsoluteSize):toEqual(Types.Vector2.new(54, 37))
		end)

		suite:case("intrinsic axes preserve fixed axes and size nested columns bottom up", function(check)
			local env = fixture()
			local root = env.createInstance("Frame", { Size = Types.UDim2.fromOffset(120, 12), AutomaticSize = "Y" })
			env.createInstance("UIListLayout", { Parent = root })
			local inner = env.createInstance(
				"Frame",
				{ Parent = root, Size = Types.UDim2.fromOffset(0, 0), AutomaticSize = "XY" }
			)
			env.createInstance(
				"UIListLayout",
				{ Parent = inner, FillDirection = "Horizontal", Padding = Types.UDim.new(0, 4) }
			)
			env.createInstance("Frame", { Parent = inner, Size = Types.UDim2.fromOffset(20, 30) })
			env.createInstance("Frame", { Parent = inner, Size = Types.UDim2.fromOffset(40, 10) })
			controller(env, root).step()
			check:expect(inner.AbsoluteSize):toEqual(Types.Vector2.new(64, 30))
			check:expect(root.AbsoluteSize):toEqual(Types.Vector2.new(120, 30))
		end)

		suite:case("unsupported mechanisms fail before publishing geometry", function(check)
			local env = fixture()
			local root = env.createInstance("Frame", { Size = Types.UDim2.fromOffset(200, 100) })
			env.createInstance("TextLabel", { Parent = root, AutomaticSize = "XY" })
			local ok, message = pcall(function(): unknown
				controller(env, root).step()
				return nil
			end)
			check:expect(ok):toBe(false)
			check:expect(tostring(message)):toContain "unsupported_ui_layout"
			check:expect(tostring(message)):toContain "AutomaticSize"
			check:expect(env.propertyOf(root, "AbsoluteSize")):toBe(nil)
		end)
		suite:case("supplied optional-property reader failures stop geometry publication", function(check)
			local env = fixture()
			local root = env.createInstance("Frame", { Size = Types.UDim2.fromOffset(200, 100) })
			local layout = Layout.attach(env, {
				roots = function()
					return { root }
				end,
				viewport = function()
					return { X = 800, Y = 600 }
				end,
				read = function(object, property)
					if property == "Rotation" then
						error("supplied reader failed", 0)
					end
					return env.propertyOf(object, property)
				end,
			})
			local ok, message = pcall(function(): unknown
				layout.step()
				return nil
			end)
			check:expect(ok):toBe(false)
			check:expect(tostring(message)):toContain "supplied reader failed"
			check:expect(env.propertyOf(root, "AbsoluteSize")):toBe(nil)
		end)
		suite:case("rejects world-space LayerCollectors before publishing any root geometry", function(check)
			for _, className in { "BillboardGui", "SurfaceGui" } do
				local env = fixture()
				env.defineClass("LayerCollector", { super = "Instance", creatable = false })
				env.defineClass("SurfaceGuiBase", { super = "LayerCollector", creatable = false })
				env.defineClass(className, {
					super = if className == "SurfaceGui" then "SurfaceGuiBase" else "LayerCollector",
				})
				local screen = env.createInstance("Frame", { Size = Types.UDim2.fromOffset(200, 100) })
				local world = env.createInstance(className)
				local child = env.createInstance("Frame", { Parent = world, Size = Types.UDim2.fromScale(1, 1) })
				local layout = Layout.attach(env, {
					roots = function()
						return { screen, world }
					end,
					viewport = function()
						return { X = 800, Y = 600 }
					end,
				})
				local ok, message = pcall(function(): unknown
					layout.step()
					return nil
				end)
				check:expect(ok):toBe(false)
				check:expect(tostring(message)):toContain "unsupported_ui_layout"
				check:expect(tostring(message)):toContain(className)
				check:expect(env.propertyOf(screen, "AbsoluteSize")):toBe(nil)
				check:expect(env.propertyOf(child, "AbsoluteSize")):toBe(nil)
			end
		end)

		suite:case("sizes an automatic list parent from its ancestor as Studio 0.744 does", function(check)
			local env = fixture()
			local root = env.createInstance("Frame", { Size = Types.UDim2.fromOffset(400, 300) })
			local automatic = env.createInstance("Frame", {
				Parent = root,
				Size = Types.UDim2.fromOffset(200, 120),
				AutomaticSize = "XY",
			})
			env.createInstance("UIListLayout", { Parent = automatic, FillDirection = "Horizontal" })
			local child = env.createInstance("Frame", { Parent = automatic, Size = Types.UDim2.new(1, -4, 0, 40) })
			controller(env, root).step()
			check:expect(env.propertyOf(automatic, "AbsoluteSize")):toEqual(Types.Vector2.new(396, 120))
			check:expect(env.propertyOf(child, "AbsoluteSize")):toEqual(Types.Vector2.new(392, 40))
		end)

		suite:case("centres a child in a padded automatic parent as Studio 0.744 does", function(check)
			local env = fixture()
			local root = env.createInstance("Frame", { Size = Types.UDim2.fromOffset(400, 300) })
			local automatic = env.createInstance("Frame", {
				Parent = root,
				Size = Types.UDim2.fromOffset(200, 120),
				AutomaticSize = "XY",
			})
			env.createInstance("UIPadding", { Parent = automatic, PaddingLeft = Types.UDim.new(0, 6) })
			local child = env.createInstance("Frame", {
				Parent = automatic,
				Size = Types.UDim2.fromOffset(20, 10),
				Position = Types.UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Types.Vector2.new(0.5, 0.5),
			})
			controller(env, root).step()
			check:expect(env.propertyOf(automatic, "AbsoluteSize")):toEqual(Types.Vector2.new(200, 120))
			check:expect(env.propertyOf(child, "AbsoluteSize")):toEqual(Types.Vector2.new(20, 10))
			check:expect(env.propertyOf(child, "AbsolutePosition")):toEqual(Types.Vector2.new(93, 55))
		end)

		suite:case("sizes a self-relative automatic child as Studio 0.744 does", function(check)
			local env = fixture()
			local root = env.createInstance("Frame", { Size = Types.UDim2.fromOffset(200, 100) })
			local automatic = env.createInstance("Frame", { Parent = root, AutomaticSize = "XY" })
			local child = env.createInstance("Frame", { Parent = automatic, Size = Types.UDim2.new(1, 1, 1, 1) })
			controller(env, root).step()
			check:expect(env.propertyOf(automatic, "AbsoluteSize")):toEqual(Types.Vector2.new(2, 2))
			check:expect(env.propertyOf(child, "AbsoluteSize")):toEqual(Types.Vector2.new(2, 2))
		end)
	end)
end
