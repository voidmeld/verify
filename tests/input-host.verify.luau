--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect
local Input = require "../src/roblox/input-host"
local Environment = require "../src/roblox/environment"
local Layout = require "../src/roblox/ui-layout"
local Datatypes = require "../src/roblox/datatypes"

local function pointerFixture(raiseErrors: boolean?)
	local library = Datatypes.create {
		enums = {
			UserInputType = { { name = "MouseButton1", value = 0 }, { name = "MouseMovement", value = 4 } },
			UserInputState = {
				{ name = "Begin", value = 0 },
				{ name = "Change", value = 1 },
				{ name = "End", value = 2 },
				{ name = "Cancel", value = 3 },
			},
			KeyCode = {
				{ name = "None", value = 0 },
				{ name = "Tab", value = 9 },
				{ name = "Thumbstick1", value = 1016 },
				{ name = "MouseLeftButton", value = 1026 },
				{ name = "MousePosition", value = 1033 },
				{ name = "MouseDelta", value = 1048 },
			},
			InputActionType = { { name = "Bool", value = 0 }, { name = "Direction2D", value = 2 } },
			InputBindingType = { { name = "Automatic", value = 0 }, { name = "Scriptable", value = 1 } },
			ZIndexBehavior = { { name = "Global", value = 0 }, { name = "Sibling", value = 1 } },
		},
	}
	local guiObject = table.clone(Environment.BASIC_CLASSES.GuiObject)
	local properties = table.clone(assert(guiObject.properties))
	properties.Interactable = true
	guiObject.properties = properties
	guiObject.events = { "InputBegan", "InputChanged", "InputEnded", "MouseEnter", "MouseLeave" }
	local instance = table.clone(Environment.BASIC_CLASSES.Instance)
	instance.super = "Object"
	local options: Environment.Options = {
		handlerErrors = if raiseErrors then "raise" else nil,
		undeclaredWrites = true,
		undeclaredReads = "nil",
		classes = {
			Object = { creatable = false },
			Instance = instance,
			GuiObject = guiObject,
			BasePlayerGui = { super = "Instance", creatable = false },
			PlayerGui = { super = "BasePlayerGui", creatable = false },
			GuiButton = {
				super = "GuiObject",
				creatable = false,
				properties = { Active = true },
				events = { "Activated", "MouseButton1Down", "MouseButton1Up", "MouseButton1Click" },
			},
			TextButton = { super = "GuiButton" },
			UserInputService = {
				super = "Instance",
				creatable = false,
				events = { "InputBegan", "InputChanged", "InputEnded" },
			},
			InputObject = {
				super = "Instance",
				creatable = false,
				properties = {
					Position = library.Vector3.new(0, 0, 0),
					Delta = library.Vector3.new(0, 0, 0),
					KeyCode = library.Enum.KeyCode.None,
					UserInputType = library.Enum.UserInputType.MouseMovement,
					UserInputState = library.Enum.UserInputState.Change,
				},
			},
			VirtualInput = { super = "Object", creatable = false },
			InputContext = { super = "Instance", properties = { Enabled = true, Sink = false, Priority = 0 } },
			InputAction = {
				super = "Instance",
				properties = { Enabled = true, Type = library.Enum.InputActionType.Bool },
				events = { "Pressed", "Released", "StateChanged" },
				methods = { Fire = true },
			},
			InputBinding = {
				super = "Instance",
				properties = {
					Type = library.Enum.InputBindingType.Automatic,
					KeyCode = library.Enum.KeyCode.None,
					UIButton = false,
					Up = library.Enum.KeyCode.None,
					Down = library.Enum.KeyCode.None,
					Left = library.Enum.KeyCode.None,
					Right = library.Enum.KeyCode.None,
					Forward = library.Enum.KeyCode.None,
					Backward = library.Enum.KeyCode.None,
				},
			},
		},
	}
	local env = Environment.create(options)
	local gui = env.createEngineInstance "PlayerGui"
	local service = env.createEngineInstance "UserInputService"
	local screen =
		env.createInstance("ScreenGui", { Parent = gui, ZIndexBehavior = library.Enum.ZIndexBehavior.Global })
	local base = env.createInstance("TextButton", {
		Name = "Base",
		Parent = screen,
		Position = library.UDim2.fromOffset(180, 120),
		Size = library.UDim2.fromOffset(100, 80),
		ZIndex = 3,
	})
	local child = env.createInstance("Frame", {
		Name = "Child",
		Parent = base,
		Position = library.UDim2.fromOffset(10, 10),
		Size = library.UDim2.fromOffset(40, 40),
		ZIndex = 4,
	})
	local overlay = env.createInstance("Frame", {
		Name = "Overlay",
		Parent = screen,
		Position = library.UDim2.fromOffset(180, 120),
		Size = library.UDim2.fromOffset(100, 80),
		ZIndex = 5,
		BackgroundTransparency = 1,
	})
	local layout = Layout.attach(env, {
		roots = function()
			return { gui }
		end,
		viewport = function()
			return { X = 800, Y = 600 }
		end,
		origin = function()
			return { X = 0, Y = -58 }
		end,
	})
	local backend = Input.simulated(env, {
		playerGui = gui,
		inputService = service,
		layout = layout,
		inset = function()
			return { X = 0, Y = 58 }
		end,
		library = library,
		activationWindowSeconds = 0.5,
	})
	local function cleanup()
		backend.close()
		gui:Destroy()
		service:Destroy()
	end
	return {
		env = env,
		library = library,
		gui = gui,
		service = service,
		screen = screen,
		base = base,
		child = child,
		overlay = overlay,
		backend = backend,
		cleanup = cleanup,
	}
end

describe("semantic input adapter", function()
	it("idle frames need no pointer geometry before movement", function(own)
		local f = pointerFixture()
		own(f.cleanup)
		local queried = 0
		local backend = Input.simulated(f.env, {
			playerGui = f.gui,
			inputService = f.service,
			layout = {
				step = function() end,
				flush = function() end,
				objectsAtPosition = function()
					queried += 1
					return {}
				end,
				close = function() end,
			},
			inset = function()
				return { X = 0, Y = 0 }
			end,
			library = f.library,
			activationWindowSeconds = 0.5,
		})
		own(backend.close)
		f.env.step(1 / 60)
		expect(queried):toEqual(0)
	end)
	it("native nonmatching Tab and Thumbstick contexts preserve pointer routing", function(own)
		local f = pointerFixture(true)
		own(f.cleanup)
		local tab = f.env.createInstance("InputContext", { Parent = f.gui, Priority = 1500 })
		local thumb = f.env.createInstance("InputContext", { Parent = f.gui, Priority = 30 })
		local changes, clicks = 0, 0
		for _, entry in
			{
				{ context = tab, key = "Tab", kind = "Bool" },
				{ context = thumb, key = "Thumbstick1", kind = "Direction2D" },
			}
		do
			local action = f.env.createInstance("InputAction", {
				Parent = entry.context,
				Type = f.library.Enum.InputActionType[entry.kind],
			})
			f.env.createInstance("InputBinding", { Parent = action, KeyCode = f.library.Enum.KeyCode[entry.key] })
			for _, name in { "Pressed", "Released", "StateChanged" } do
				(f.env.event(action, name)):Connect(function()
					changes += 1
				end)
			end
		end
		(f.env.event(f.base, "Activated")):Connect(function()
			clicks += 1
		end)
		for _, tabEnabled in { false, true } do
			for _, thumbEnabled in { false, true } do
				for _, sink in { false, true } do
					tab.Enabled, thumb.Enabled, tab.Sink, thumb.Sink = tabEnabled, thumbEnabled, sink, sink
					f.env.step(0.01)
					f.backend.pointer { x = 200, y = 140, button = "left", down = true }
					f.backend.pointer { x = 200, y = 140, button = "left", down = false }
				end
			end
		end
		expect(changes):toBe(0)
		expect(clicks):toBe(8)
		expect(f.env.errors):toEqual {}
	end)
	it("relevant automatic mouse bindings still refuse input before dispatch", function(own)
		for _, bindingKind in { "MouseLeftButton", "MousePosition" } do
			local f = pointerFixture(true)
			own(f.cleanup)
			local context = f.env.createInstance("InputContext", { Parent = f.gui })
			local action = f.env.createInstance("InputAction", { Parent = context })
			local binding = f.env.createInstance("InputBinding", { Parent = action })
			binding.KeyCode = f.library.Enum.KeyCode[bindingKind]
			local events = 0
			(f.env.event(f.service, "InputBegan")):Connect(function()
				events += 1
			end)
			expect(function()
				f.backend.pointer { x = 200, y = 140, button = "left", down = true }
			end):toThrow()
			expect(events):toBe(0)
		end
	end)
	it("a pointer press on a UIButton binding drives its Bool action", function(own)
		local f = pointerFixture(true)
		own(f.cleanup)
		local context = f.env.createInstance("InputContext", { Parent = f.gui })
		local action = f.env.createInstance("InputAction", { Parent = context })
		f.env.createInstance("InputBinding", { Parent = action, UIButton = f.base })
		local fired: { boolean } = {}
		f.env.fake("InputAction.Fire", function(_target: unknown, value: boolean)
			table.insert(fired, value)
		end)
		f.backend.pointer { x = 200, y = 140, button = "left", down = true }
		f.env.step(0.01)
		f.backend.pointer { x = 200, y = 140, button = "left", down = false }
		f.env.step(0.01)
		expect(fired):toEqual { true, false }
		action.Enabled = false
		f.backend.pointer { x = 200, y = 140, button = "left", down = true }
		f.backend.pointer { x = 200, y = 140, button = "left", down = false }
		expect(#fired):toBe(2)
	end)
	it("mouse binding validation follows source and enabled hardware participation", function(own)
		local f = pointerFixture(true)
		own(f.cleanup)
		local context = f.env.createInstance("InputContext", { Parent = f.gui })
		local action = f.env.createInstance("InputAction", { Parent = context })
		local binding = f.env.createInstance("InputBinding", {
			Parent = action,
			KeyCode = f.library.Enum.KeyCode.MouseLeftButton,
		})
		local virtual = Environment.assertObject(f.env.method(f.service, "CreateVirtualInput")(f.service))
		local move = f.env.method(virtual, "SendMousePosition")
		move(virtual, f.library.Vector2.new(200, 140))
		f.env.step(0.01)
		expect(function()
			f.backend.pointer { x = 200, y = 140, button = "left", down = true }
		end):toThrow()
		for _, inactive in { "context", "action", "scriptable" } do
			context.Enabled = inactive ~= "context"
			action.Enabled = inactive ~= "action"
			binding.Type = if inactive == "scriptable"
				then f.library.Enum.InputBindingType.Scriptable
				else f.library.Enum.InputBindingType.Automatic
			f.backend.pointer { x = 200, y = 140, button = "left", down = true }
			f.backend.pointer { x = 200, y = 140, button = "left", down = false }
		end
		expect(f.env.errors):toEqual {}
	end)
	it("VirtualInput clicks the specified coordinates without a preceding mouse move", function(own)
		local f = pointerFixture()
		own(f.cleanup)
		local activations = 0
		f.env.event(f.base, "Activated"):Connect(function()
			activations += 1
		end)
		local virtual = Environment.assertObject(f.env.method(f.service, "CreateVirtualInput")(f.service))
		local send = f.env.method(virtual, "SendMouseButton")
		local at = f.library.Vector2.new(200, 140)
		local button = f.library.Enum.UserInputType.MouseButton1
		send(virtual, at, button, true, 0)
		send(virtual, at, button, false, 0)
		expect(activations):toBe(1)
		expect(f.env.errors):toEqual {}
	end)
	it("VirtualInput accepts omitted and explicit click counts and keeps window counting", function(own)
		local f = pointerFixture()
		own(f.cleanup)
		local counts: { number } = {}
		local activated = f.env.event(f.base, "Activated")
		activated:Connect(function(_input, count)
			assert(type(count) == "number")
			table.insert(counts, count)
		end)
		local create = f.env.method(f.service, "CreateVirtualInput")
		local virtual = Environment.assertObject(create(f.service))
		local move = f.env.method(virtual, "SendMousePosition")
		local send = f.env.method(virtual, "SendMouseButton")
		local at = f.library.Vector2.new(200, 140)
		local button = f.library.Enum.UserInputType.MouseButton1
		move(virtual, at)
		send(virtual, at, button, true)
		send(virtual, at, button, false)
		f.env.step(0.6)
		for count = 0, 1 do
			send(virtual, at, button, true, count)
			send(virtual, at, button, false, count)
			f.env.step(0.02)
		end
		f.env.step(0.6)
		send(virtual, at, button, true, 1)
		send(virtual, at, button, false, 1)
		expect(counts):toEqual { 0, 0, 1, 0 }
	end)
	it("captured release timing counts repeated activation per target and resets after a long hold", function(own)
		local f = pointerFixture()
		own(f.cleanup)
		local other = assert(f.base:Clone())
		other.Name = "Other"
		other.Position = f.library.UDim2.fromOffset(450, 120)
		other.Parent = f.screen
		local counts: { string } = {}
		for _, target in { f.base, other } do
			local activated = f.env.event(target, "Activated")
			activated:Connect(function(_input, count)
				assert(type(count) == "number")
				table.insert(counts, tostring(target.Name) .. ":" .. count)
			end)
		end
		local function click(x: number, hold: number?)
			f.backend.pointer { x = x, y = 140, button = "left", down = true }
			if hold then
				f.env.step(hold)
			end
			f.backend.pointer { x = x, y = 140, button = "left", down = false }
		end
		click(200)
		f.env.step(0.1)
		click(200)
		f.env.step(0.1)
		click(470)
		f.env.step(0.1)
		click(200)
		f.env.step(0.6)
		click(200)
		click(200, 0.8)
		click(200)
		expect(counts):toEqual { "Base:0", "Base:1", "Other:0", "Base:2", "Base:0", "Base:0", "Base:1" }
	end)
	it("virtual input and typed pointer operations share the same press state", function(own)
		local f = pointerFixture()
		own(f.cleanup)
		local create = f.env.method(f.service, "CreateVirtualInput")
		local virtual = Environment.assertObject(create(f.service))
		expect(virtual:IsA "VirtualInput"):toEqual(true)
		expect(virtual:IsA "Instance"):toEqual(false)
		local another = Environment.assertObject(create(f.service))
		expect(another == virtual):toEqual(false)
		expect(Environment.isInstance(virtual)):toEqual(false)
		expect(f.env.propertyOf(virtual, "Destroy")):toEqual(nil)
		expect(f.env.propertyOf(virtual, "Parent")):toEqual(nil)
		local move = f.env.method(virtual, "SendMousePosition")
		local send = f.env.method(virtual, "SendMouseButton")
		move(virtual, f.library.Vector2.new(200, 140))
		local pressedButtons = f.env.method(f.service, "GetMouseButtonsPressed")
		local pressed = pressedButtons(f.service)
		assert(type(pressed) == "table")
		expect(#pressed):toEqual(0)
		send(virtual, f.library.Vector2.new(200, 140), f.library.Enum.UserInputType.MouseButton1, true, 0)
		local heldValue = pressedButtons(f.service)
		assert(type(heldValue) == "table")
		local held: { Environment.Instance } = {}
		for _, value in heldValue do
			table.insert(held, Environment.assertInstance(value))
		end
		expect(#held):toEqual(1)
		expect(held[1].UserInputType):toEqual(f.library.Enum.UserInputType.MouseButton1)
		local anotherSend = f.env.method(another, "SendMouseButton")
		expect(pcall(function()
			anotherSend(another, f.library.Vector2.new(200, 140), f.library.Enum.UserInputType.MouseButton1, true, 0)
		end)):toEqual(false)
		expect(pcall(function()
			f.backend.pointer { x = 200, y = 140, button = "left", down = true }
		end)):toEqual(false)
		f.backend.pointer { x = 200, y = 140, button = "left", down = false }
		local released = pressedButtons(f.service)
		assert(type(released) == "table")
		expect(#released):toEqual(0)
		expect(pcall(function()
			send(virtual, f.library.Vector2.new(200, 140), f.library.Enum.UserInputType.MouseButton1, false, 0)
		end)):toEqual(false)
	end)
	it("stationary scene changes invalidate hover silently until explicit movement", function(own)
		local f = pointerFixture()
		own(f.cleanup)
		local create = f.env.method(f.service, "CreateVirtualInput")
		local virtual = Environment.assertObject(create(f.service))
		local move = f.env.method(virtual, "SendMousePosition")
		move(virtual, f.library.Vector2.new(200, 140))
		local leaves, enters, inputChanged = 0, 0, 0
		local leave = f.env.event(f.base, "MouseLeave")
		leave:Connect(function()
			leaves += 1
		end)
		local enter = f.env.event(f.base, "MouseEnter")
		enter:Connect(function()
			enters += 1
		end)
		local changed = f.env.event(f.service, "InputChanged")
		changed:Connect(function()
			inputChanged += 1
		end)
		f.base.Visible = false
		f.env.step(1 / 60)
		f.base.Visible = true
		f.env.step(1 / 60)
		expect(leaves):toEqual(0)
		expect(enters):toEqual(0)
		expect(inputChanged):toEqual(0)
		move(virtual, f.library.Vector2.new(200, 140))
		expect(enters):toEqual(1)
		expect(inputChanged):toEqual(1)
		move(virtual, f.library.Vector2.new(200, 140))
		expect(enters):toEqual(1)
		expect(inputChanged):toEqual(2)
	end)
	it("button input displacement follows button events while virtual movement Delta stays zero", function(own)
		local f = pointerFixture()
		own(f.cleanup)
		local create = f.env.method(f.service, "CreateVirtualInput")
		local device = Environment.assertObject(create(f.service))
		local move = f.env.method(device, "SendMousePosition")
		local send = f.env.method(device, "SendMouseButton")
		local deltas: { unknown } = {}
		local began: Environment.Instance? = nil
		for _, name in { "InputBegan", "InputChanged", "InputEnded" } do
			local signal = f.env.event(f.service, name)
			signal:Connect(function(value)
				local object = Environment.assertInstance(value)
				table.insert(deltas, object.Delta)
				if name == "InputBegan" then
					began = object
				end
			end)
		end
		move(device, f.library.Vector2.new(200, 140))
		send(device, f.library.Vector2.new(200, 140), f.library.Enum.UserInputType.MouseButton1, true, 0)
		move(device, f.library.Vector2.new(210, 150))
		expect(assert(began).Position):toEqual(f.library.Vector3.new(200, 82, 0))
		send(device, f.library.Vector2.new(210, 150), f.library.Enum.UserInputType.MouseButton1, false, 0)
		move(device, f.library.Vector2.new(230, 170))
		send(device, f.library.Vector2.new(230, 170), f.library.Enum.UserInputType.MouseButton1, true, 0)
		send(device, f.library.Vector2.new(230, 170), f.library.Enum.UserInputType.MouseButton1, false, 0)
		expect(deltas):toEqual {
			f.library.Vector3.zero,
			f.library.Vector3.new(200, 140, 0),
			f.library.Vector3.zero,
			f.library.Vector3.new(10, 10, 0),
			f.library.Vector3.zero,
			f.library.Vector3.new(20, 20, 0),
			f.library.Vector3.zero,
		}
	end)
	it("matches native pointer press and release delivery through coordinate hit testing", function(own)
		local f = pointerFixture()
		own(f.cleanup)
		local log: { string } = {}
		local began: unknown = nil
		local ended: unknown = nil
		for _, object in { f.overlay, f.child, f.base } do
			local inputBegan = f.env.event(object, "InputBegan")
			inputBegan:Connect(function(value)
				local input = Environment.assertInstance(value)
				if input.UserInputType == f.library.Enum.UserInputType.MouseButton1 then
					table.insert(log, tostring(object.Name) .. ".InputBegan")
					began = input
				end
			end)
			local inputEnded = f.env.event(object, "InputEnded")
			inputEnded:Connect(function(value)
				local input = Environment.assertInstance(value)
				if input.UserInputType == f.library.Enum.UserInputType.MouseButton1 then
					table.insert(log, tostring(object.Name) .. ".InputEnded")
					ended = input
				end
			end)
		end
		for _, event in { "MouseButton1Down", "MouseButton1Click", "MouseButton1Up", "Activated" } do
			local signal = f.env.event(f.base, event)
			signal:Connect(function()
				table.insert(log, "Base." .. event)
			end)
		end
		f.backend.pointer { x = 200, y = 140, button = "left", down = true }
		f.backend.pointer { x = 200, y = 140, button = "left", down = false }
		expect(log):toEqual {
			"Base.MouseButton1Down",
			"Overlay.InputBegan",
			"Child.InputBegan",
			"Base.InputBegan",
			"Base.MouseButton1Click",
			"Base.MouseButton1Up",
			"Base.Activated",
			"Overlay.InputEnded",
			"Child.InputEnded",
			"Base.InputEnded",
		}
		expect(began == ended):toEqual(true)
		local input = Environment.assertInstance(began)
		expect(input:IsA "InputObject"):toEqual(true)
		expect(input.Position):toEqual(f.library.Vector3.new(200, 82, 0))
		expect(input.UserInputState):toEqual(f.library.Enum.UserInputState.End)
	end)
	it("inactive buttons still receive click events without Activated", function(own)
		local f = pointerFixture()
		own(f.cleanup)
		f.base.Active = false
		local clicked, activated = 0, 0
		local click = f.env.event(f.base, "MouseButton1Click")
		local activate = f.env.event(f.base, "Activated")
		click:Connect(function()
			clicked += 1
		end)
		activate:Connect(function()
			activated += 1
		end)
		f.backend.pointer { x = 200, y = 140, button = "left", down = true }
		f.backend.pointer { x = 200, y = 140, button = "left", down = false }
		expect(clicked):toEqual(1)
		expect(activated):toEqual(0)
	end)
	it("release outside ends the original input without activating the button", function(own)
		local f = pointerFixture()
		own(f.cleanup)
		local activated, ended = 0, 0
		local activate = f.env.event(f.base, "Activated")
		local finish = f.env.event(f.base, "InputEnded")
		activate:Connect(function()
			activated += 1
		end)
		finish:Connect(function(value)
			local input = Environment.assertInstance(value)
			if input.UserInputType == f.library.Enum.UserInputType.MouseButton1 then
				ended += 1
			end
		end)
		f.backend.pointer { x = 200, y = 140, button = "left", down = true }
		f.backend.pointer { x = 400, y = 300, button = "left", down = false }
		expect(activated):toEqual(0)
		expect(ended):toEqual(1)
	end)
	it("noninteractable button ancestry is excluded from event routing but remains in the hit query", function(own)
		local f = pointerFixture()
		own(f.cleanup)
		f.base.Interactable = false
		local began = 0
		local baseBegin = f.env.event(f.base, "InputBegan")
		local childBegin = f.env.event(f.child, "InputBegan")
		baseBegin:Connect(function()
			began += 1
		end)
		childBegin:Connect(function()
			began += 1
		end)
		f.backend.pointer { x = 200, y = 140, button = "left", down = true }
		f.backend.pointer { x = 200, y = 140, button = "left", down = false }
		local query = f.env.method(f.gui, "GetGuiObjectsAtPosition")
		expect(query(f.gui, 200, 82)):toEqual { f.overlay, f.child, f.base }
		expect(began):toEqual(0)
	end)
	it("close cancels retained input and releases owned objects without activation", function()
		local f = pointerFixture()
		local create = f.env.method(f.service, "CreateVirtualInput")
		create(f.service)
		create(f.service)
		local baseline = f.env.liveObjects()
		local activated = 0
		(f.env.event(f.base, "Activated")):Connect(function()
			activated += 1
		end)
		f.backend.pointer { x = 200, y = 140, button = "left", down = true }
		f.backend.close()
		f.backend.close()
		expect(f.service.CreateVirtualInput):toEqual(nil)
		expect(f.gui.GetGuiObjectsAtPosition):toEqual(nil)
		expect(activated):toEqual(0)
		expect(f.env.liveObjects()):toEqual(baseline - 4)
		expect(pcall(function()
			f.backend.pointer { x = 200, y = 140, button = "left", down = false }
		end)):toEqual(false)
		f.cleanup()
		expect(f.env.liveObjects()):toEqual(0)
		expect(f.env.liveConnections()):toEqual(0)
	end)
	it("closing input preserves a later override without retaining its removed predecessor", function(own)
		local f = pointerFixture()
		own(f.cleanup)
		local restore = f.env.fakeOn(f.service, "GetLastInputType", function(): string
			return "later-owner"
		end)
		f.backend.close()
		expect((f.env.method(f.service, "GetLastInputType"))(f.service)):toEqual "later-owner"
		restore()
		expect(f.service.GetLastInputType):toEqual(nil)
	end)
	it("unsupported geometry fails before the next press", function(own)
		local f = pointerFixture()
		own(f.cleanup)
		local presses = 0
		(f.env.event(f.base, "MouseButton1Down")):Connect(function()
			presses += 1
		end)
		f.backend.pointer { x = 200, y = 140, button = "left", down = true }
		f.backend.pointer { x = 200, y = 140, button = "left", down = false }
		f.base.Rotation = 10
		f.base.ClipsDescendants = true
		f.backend.pointer { x = 200, y = 140, button = "left", down = true }
		f.backend.pointer { x = 200, y = 140, button = "left", down = false }
		expect(presses):toEqual(2)
		f.base.SizeConstraint = "RelativeXX"
		f.backend.pointer { x = 200, y = 140, button = "left", down = true }
		f.backend.pointer { x = 200, y = 140, button = "left", down = false }
		expect(presses):toEqual(3)
		f.env.defineClass("UITableLayout", { super = "Instance" })
		f.env.createInstance("UITableLayout", { Parent = f.base })
		expect(pcall(function()
			f.backend.pointer { x = 200, y = 140, button = "left", down = true }
		end)):toEqual(false)
		expect(presses):toEqual(3)
	end)
	it("rejects malformed keys, pointers and text", function()
		local badKeys: { unknown } = { {}, { code = "", down = true }, { code = "A", down = 1 } }
		for _, value in badKeys do
			expect((pcall(Input.key.input, value))):toEqual(false)
		end
		local badPointers: { unknown } = {
			{ x = math.huge, y = 1, button = "left", down = true },
			{ x = math.huge - math.huge, y = 1, button = "left", down = true },
			{ x = 1, y = 2, button = "extra", down = true },
			{ x = 1, y = 2, button = "left", down = "yes" },
		}
		for _, value in badPointers do
			expect((pcall(Input.pointer.input, value))):toEqual(false)
		end
		expect((pcall(Input.text.input, 1))):toEqual(false)
		expect(Input.pointer.input({ x = 0, y = -1, button = "middle", down = false }).y):toEqual(-1)
	end)
	it("registry forwards typed input and preserves backend failures", function()
		local received: { string } = {}
		local registry = Input.registry {
			key = function(value)
				table.insert(received, value.code)
			end,
			pointer = function(value)
				table.insert(received, value.button)
			end,
			text = function(value)
				if value == "fail" then
					error "backend failure"
				end
				table.insert(received, value)
			end,
			close = function() end,
		}
		local function run(name: string, payload: unknown): unknown
			return registry.actions[name].run(
				payload,
				{ kind = "action", actor = "client", name = name, payload = payload, deadline = 10 }
			)
		end
		run("input.key", { code = "A", down = true })
		run("input.pointer", { x = 10, y = 20, button = "right", down = false })
		run("input.text", "hello")
		expect(table.concat(received, ",")):toEqual "A,right,hello"
		expect((pcall(run, "input.text", "fail"))):toEqual(false)
		expect((pcall(run, "input.pointer", { x = math.huge }))):toEqual(false)
		expect(#received):toEqual(3)
	end)
end)

return nil
