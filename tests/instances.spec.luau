--!strict

local test = require "@std/test"

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

test.suite("roblox instance layer", function(suite)
	suite:case("creates declared classes and reports the class name", function(assert)
		local fake = layer()
		local frame = fake.new "Frame"
		assert.eq(frame.ClassName, "Frame")
		assert.eq(frame.Name, "Frame")
		assert.eq(fake.typeName(frame), "Instance")
		assert.eq(fake.typeName(12), "number")
	end)

	suite:case("refuses a class the supplied api does not declare", function(assert)
		local fake = layer()
		assert.that(string.find(
			thrown(function()
				fake.new "ScrollingFrame"
			end),
			'Unable to create an Instance of type "ScrollingFrame"',
			1,
			true
		) ~= nil)
	end)

	suite:case("refuses an undeclared property write with the engine diagnostic", function(assert)
		local fake = layer()
		local padding = fake.new "UIPadding"
		local message = thrown(function()
			padding.PadLeft = 6
		end)
		assert.that(string.find(message, 'PadLeft is not a valid member of UIPadding "UIPadding"', 1, true) ~= nil)
	end)

	suite:case("refuses an undeclared property read with the engine diagnostic", function(assert)
		local fake = layer()
		local padding = fake.new "UIPadding"
		padding.Name = "Inset"
		local message = thrown(function()
			return padding.PadLeft
		end)
		assert.that(string.find(message, 'PadLeft is not a valid member of UIPadding "Inset"', 1, true) ~= nil)
	end)

	suite:case("accepts declared properties and reports them back", function(assert)
		local fake = layer()
		local frame = fake.new "Frame"
		frame.Visible = false
		assert.eq(fake.propertyOf(frame, "Visible"), false)
	end)

	suite:case("declares events as connectable signals and refuses undeclared ones", function(assert)
		local fake = layer()
		local button = fake.new "TextButton"
		local fired = 0
		local connection = button.Activated:Connect(function()
			fired += 1
		end)
		button.Activated:Fire()
		connection:Disconnect()
		button.Activated:Fire()
		assert.eq(fired, 1)
		assert.that(string.find(
			thrown(function()
				return button.MouseButton1Click
			end),
			"MouseButton1Click is not a valid member of TextButton",
			1,
			true
		) ~= nil)
	end)

	suite:case("parents and unparents children through the shared tree", function(assert)
		local fake = layer()
		local frame = fake.new "Frame"
		frame.Parent = fake.root
		assert.eq(#fake.childrenOf(fake.root), 1)
		assert.eq(fake.childrenOf(fake.root)[1], frame)
		frame.Parent = nil
		assert.eq(#fake.childrenOf(fake.root), 0)
	end)

	suite:case("destroys a subtree and detaches it from its parent", function(assert)
		local fake = layer()
		local frame = fake.new "Frame"
		local child = fake.new "TextButton"
		frame.Parent = fake.root
		child.Parent = frame
		fake.destroy(frame)
		assert.eq(#fake.childrenOf(fake.root), 0)
		assert.eq(#fake.childrenOf(frame), 0)
		assert.eq(child.Parent, nil)
	end)

	suite:case("fires a property changed signal only for declared properties", function(assert)
		local fake = layer()
		local frame = fake.new "Frame"
		local changes = 0
		fake.propertyChanged(frame, "Visible"):Connect(function()
			changes += 1
		end)
		frame.Visible = false
		assert.eq(changes, 1)
		assert.that(string.find(
			thrown(function()
				fake.propertyChanged(frame, "Rotation")
			end),
			"Rotation is not a valid member of Frame",
			1,
			true
		) ~= nil)
	end)

	suite:case("serves universal members without an api entry", function(assert)
		local fake = layer()
		local frame = fake.new "Frame"
		frame.Name = "Panel"
		frame.Parent = fake.root
		frame:SetAttribute("zone", "north")
		assert.eq(frame:GetAttribute "zone", "north")
		assert.eq(fake.root:FindFirstChild "Panel", frame)
		assert.eq(#fake.root:GetChildren(), 1)
		assert.that(frame:IsA "Frame")
		assert.that(not frame:IsA "Folder")
	end)

	suite:case("refuses an api dump whose members are not names", function(assert)
		assert.that(not pcall(function()
			Roblox.instanceLayer { api = { Frame = { properties = { 12 :: any } } } }
		end))
		assert.that(not pcall(function()
			Roblox.instanceLayer { api = { Frame = 12 :: any } }
		end))
	end)

	suite:case("refuses a parent that is not part of the layer", function(assert)
		local fake = layer()
		local frame = fake.new "Frame"
		assert.that(not pcall(function()
			frame.Parent = { Name = "not a node" }
		end))
	end)
end)
