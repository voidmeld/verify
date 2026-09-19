--!strict

local Verify = require "../src/core"

local Roblox = require "../src/roblox"

local API: Roblox.ApiDump = {
	Folder = { properties = {} },
	Frame = { properties = { "BackgroundTransparency", "Position", "Size", "Visible" } },
	TextButton = {
		properties = { "AutoButtonColor", "Text", "TextColor3" },
		events = { "Activated" },
	},
	UIPadding = { properties = { "PaddingLeft", "PaddingRight" } },
}

local function layer(): Roblox.InstanceLayer
	return Roblox.instanceLayer { api = API }
end

local function thrown(callback: () -> ...any): string
	local ok, message = pcall(callback)
	assert(not ok, "expected the call to raise")
	return tostring(message)
end

return function(suite: Verify.Harness)
	suite:suite("roblox instance layer", function()
		suite:case("creates declared classes and reports the class name", function(check)
			local fake = layer()
			local frame = fake.new "Frame"
			check:expect(frame.ClassName):toEqual "Frame"
			check:expect(frame.Name):toEqual "Frame"
			check:expect((fake.typeName(frame))):toEqual "Instance"
			check:expect((fake.typeName(12))):toEqual "number"
		end)

		suite:case("refuses a class the supplied api does not declare", function(check)
			local fake = layer()
			assert(string.find(
				thrown(function()
					fake.new "ScrollingFrame"
				end),
				'Unable to create an Instance of type "ScrollingFrame"',
				1,
				true
			) ~= nil)
		end)

		suite:case("refuses an undeclared property write with the engine diagnostic", function(check)
			local fake = layer()
			local padding = fake.new "UIPadding"
			local message = thrown(function()
				padding.PadLeft = 6
			end)
			assert(string.find(message, 'PadLeft is not a valid member of UIPadding "UIPadding"', 1, true) ~= nil)
		end)

		suite:case("refuses an undeclared property read with the engine diagnostic", function(check)
			local fake = layer()
			local padding = fake.new "UIPadding"
			padding.Name = "Inset"
			local message = thrown(function()
				return padding.PadLeft
			end)
			assert(string.find(message, 'PadLeft is not a valid member of UIPadding "Inset"', 1, true) ~= nil)
		end)

		suite:case("accepts declared properties and reports them back", function(check)
			local fake = layer()
			local frame = fake.new "Frame"
			frame.Visible = false
			check:expect((fake.propertyOf(frame, "Visible"))):toEqual(false)
		end)

		suite:case("declares events as connectable signals and refuses undeclared ones", function(check)
			local fake = layer()
			local button = fake.new "TextButton"
			local fired = 0
			local connection = button.Activated:Connect(function()
				fired += 1
			end)
			button.Activated:Fire()
			connection:Disconnect()
			button.Activated:Fire()
			check:expect(fired):toEqual(1)
			assert(string.find(
				thrown(function()
					return button.MouseButton1Click
				end),
				"MouseButton1Click is not a valid member of TextButton",
				1,
				true
			) ~= nil)
		end)

		suite:case("parents and unparents children through the shared tree", function(check)
			local fake = layer()
			local frame = fake.new "Frame"
			frame.Parent = fake.root
			check:expect((#fake.childrenOf(fake.root))):toEqual(1)
			check:expect(fake.childrenOf(fake.root)[1]):toEqual(frame)
			frame.Parent = nil
			check:expect((#fake.childrenOf(fake.root))):toEqual(0)
		end)

		suite:case("destroys a subtree and detaches it from its parent", function(check)
			local fake = layer()
			local frame = fake.new "Frame"
			local child = fake.new "TextButton"
			frame.Parent = fake.root
			child.Parent = frame
			fake.destroy(frame)
			check:expect((#fake.childrenOf(fake.root))):toEqual(0)
			check:expect((#fake.childrenOf(frame))):toEqual(0)
			check:expect(child.Parent):toEqual(nil)
		end)

		suite:case("fires a property changed signal only for declared properties", function(check)
			local fake = layer()
			local frame = fake.new "Frame"
			local changes = 0
			fake.propertyChanged(frame, "Visible"):Connect(function()
				changes += 1
			end)
			frame.Visible = false
			check:expect(changes):toEqual(1)
			assert(string.find(
				thrown(function()
					fake.propertyChanged(frame, "Rotation")
				end),
				"Rotation is not a valid member of Frame",
				1,
				true
			) ~= nil)
		end)

		suite:case("serves universal members without an api entry", function(check)
			local fake = layer()
			local frame = fake.new "Frame"
			frame.Name = "Panel"
			frame.Parent = fake.root
			frame:SetAttribute("zone", "north")
			check:expect(frame:GetAttribute "zone"):toEqual "north"
			check:expect(fake.root:FindFirstChild "Panel"):toEqual(frame)
			check:expect((#fake.root:GetChildren())):toEqual(1)
			assert(frame:IsA "Frame")
			assert(not frame:IsA "Folder")
		end)

		suite:case("refuses an api dump whose members are not names", function(check)
			assert(not pcall(function()
				Roblox.instanceLayer { api = { Frame = { properties = { 12 :: any } } } }
			end))
			assert(not pcall(function()
				Roblox.instanceLayer { api = { Frame = 12 :: any } }
			end))
		end)

		suite:case("refuses a parent that is not part of the layer", function(check)
			local fake = layer()
			local frame = fake.new "Frame"
			assert(not pcall(function()
				frame.Parent = { Name = "not a node" }
			end))
		end)
	end)
end
