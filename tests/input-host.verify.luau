--!strict
local Core = require "../src/core"
local Input = require "../src/roblox/input-host"
local Environment = require "../src/roblox/environment"
local Layout = require "../src/roblox/ui-layout"
local Datatypes = require "../src/roblox/datatypes"

local function pointerFixture()
	local library = Datatypes.create {
		enums = {
			UserInputType = { { name = "MouseButton1", value = 0 }, { name = "MouseMovement", value = 4 } },
			UserInputState = {
				{ name = "Begin", value = 0 },
				{ name = "Change", value = 1 },
				{ name = "End", value = 2 },
				{ name = "Cancel", value = 3 },
			},
			KeyCode = { { name = "None", value = 0 } },
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
		undeclaredWrites = true,
		undeclaredReads = "nil",
		classes = ({
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
		} :: unknown) :: { [string]: Environment.ClassSpec },
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

return function(suite: Core.Harness)
	suite:suite("semantic input adapter", function()
		suite:case(
			"captured release timing counts repeated activation per target and resets after a long hold",
			function(check)
				local f = pointerFixture()
				check:defer(f.cleanup)
				local other = assert(f.base:Clone())
				other.Name = "Other"
				other.Position = f.library.UDim2.fromOffset(450, 120)
				other.Parent = f.screen
				local counts: { string } = {}
				for _, target in { f.base, other } do
					local activated = target.Activated :: Environment.Signal<Environment.Instance, number>
					activated:Connect(function(_input, count)
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
				check:expect(counts):toEqual { "Base:0", "Base:1", "Other:0", "Base:2", "Base:0", "Base:0", "Base:1" }
			end
		)
		suite:case("virtual input and typed pointer operations share the same press state", function(check)
			local f = pointerFixture()
			check:defer(f.cleanup)
			local create = f.service.CreateVirtualInput :: Environment.Method
			local virtual = create(f.service) :: Environment.Instance
			check:expect(virtual:IsA "VirtualInput"):toEqual(true)
			check:expect(virtual:IsA "Instance"):toEqual(false)
			local another = create(f.service) :: Environment.Instance
			check:expect(another == virtual):toEqual(false)
			check:expect(Environment.isInstance(virtual)):toEqual(false)
			check:expect(virtual.Destroy):toEqual(nil)
			check:expect(virtual.Parent):toEqual(nil)
			local move = virtual.SendMousePosition :: Environment.Method
			local send = virtual.SendMouseButton :: Environment.Method
			move(virtual, f.library.Vector2.new(200, 140))
			send(virtual, f.library.Vector2.new(200, 140), f.library.Enum.UserInputType.MouseButton1, true, 0)
			local anotherSend = another.SendMouseButton :: Environment.Method
			check
				:expect(pcall(function()
					anotherSend(
						another,
						f.library.Vector2.new(200, 140),
						f.library.Enum.UserInputType.MouseButton1,
						true,
						0
					)
				end))
				:toEqual(false)
			check
				:expect(pcall(function()
					f.backend.pointer { x = 200, y = 140, button = "left", down = true }
				end))
				:toEqual(false)
			f.backend.pointer { x = 200, y = 140, button = "left", down = false }
			check
				:expect(pcall(function()
					send(virtual, f.library.Vector2.new(200, 140), f.library.Enum.UserInputType.MouseButton1, false, 0)
				end))
				:toEqual(false)
		end)
		suite:case("stationary scene changes invalidate hover silently until explicit movement", function(check)
			local f = pointerFixture()
			check:defer(f.cleanup)
			local create = f.service.CreateVirtualInput :: Environment.Method
			local virtual = create(f.service) :: Environment.Instance
			local move = virtual.SendMousePosition :: Environment.Method
			move(virtual, f.library.Vector2.new(200, 140))
			local leaves, enters, inputChanged = 0, 0, 0
			local leave = f.base.MouseLeave :: Environment.Signal
			leave:Connect(function()
				leaves += 1
			end)
			local enter = f.base.MouseEnter :: Environment.Signal
			enter:Connect(function()
				enters += 1
			end)
			local changed = f.service.InputChanged :: Environment.Signal
			changed:Connect(function()
				inputChanged += 1
			end)
			f.base.Visible = false
			f.env.step(1 / 60)
			f.base.Visible = true
			f.env.step(1 / 60)
			check:expect(leaves):toEqual(0)
			check:expect(enters):toEqual(0)
			check:expect(inputChanged):toEqual(0)
			move(virtual, f.library.Vector2.new(200, 140))
			check:expect(enters):toEqual(1)
			check:expect(inputChanged):toEqual(1)
			move(virtual, f.library.Vector2.new(200, 140))
			check:expect(enters):toEqual(1)
			check:expect(inputChanged):toEqual(2)
		end)
		suite:case(
			"button input displacement follows button events while virtual movement Delta stays zero",
			function(check)
				local f = pointerFixture()
				check:defer(f.cleanup)
				local create = f.service.CreateVirtualInput :: Environment.Method
				local device = create(f.service) :: Environment.Instance
				local move = device.SendMousePosition :: Environment.Method
				local send = device.SendMouseButton :: Environment.Method
				local deltas: { unknown } = {}
				local began: Environment.Instance? = nil
				for _, name in { "InputBegan", "InputChanged", "InputEnded" } do
					local signal = f.service[name] :: Environment.Signal<Environment.Instance>
					signal:Connect(function(object)
						table.insert(deltas, object.Delta)
						if name == "InputBegan" then
							began = object
						end
					end)
				end
				move(device, f.library.Vector2.new(200, 140))
				send(device, f.library.Vector2.new(200, 140), f.library.Enum.UserInputType.MouseButton1, true, 0)
				move(device, f.library.Vector2.new(210, 150))
				check:expect(assert(began).Position):toEqual(f.library.Vector3.new(200, 82, 0))
				send(device, f.library.Vector2.new(210, 150), f.library.Enum.UserInputType.MouseButton1, false, 0)
				move(device, f.library.Vector2.new(230, 170))
				send(device, f.library.Vector2.new(230, 170), f.library.Enum.UserInputType.MouseButton1, true, 0)
				send(device, f.library.Vector2.new(230, 170), f.library.Enum.UserInputType.MouseButton1, false, 0)
				check:expect(deltas):toEqual {
					f.library.Vector3.zero,
					f.library.Vector3.new(200, 140, 0),
					f.library.Vector3.zero,
					f.library.Vector3.new(10, 10, 0),
					f.library.Vector3.zero,
					f.library.Vector3.new(20, 20, 0),
					f.library.Vector3.zero,
				}
			end
		)
		suite:case("matches native pointer press and release delivery through coordinate hit testing", function(check)
			local f = pointerFixture()
			check:defer(f.cleanup)
			local log: { string } = {}
			local began: unknown = nil
			local ended: unknown = nil
			for _, object in { f.overlay, f.child, f.base } do
				local inputBegan = object.InputBegan :: Environment.Signal<Environment.Instance>
				inputBegan:Connect(function(input)
					if input.UserInputType == f.library.Enum.UserInputType.MouseButton1 then
						table.insert(log, tostring(object.Name) .. ".InputBegan")
						began = input
					end
				end)
				local inputEnded = object.InputEnded :: Environment.Signal<Environment.Instance>
				inputEnded:Connect(function(input)
					if input.UserInputType == f.library.Enum.UserInputType.MouseButton1 then
						table.insert(log, tostring(object.Name) .. ".InputEnded")
						ended = input
					end
				end)
			end
			for _, event in { "MouseButton1Down", "MouseButton1Click", "MouseButton1Up", "Activated" } do
				local signal = f.base[event] :: Environment.Signal
				signal:Connect(function()
					table.insert(log, "Base." .. event)
				end)
			end
			f.backend.pointer { x = 200, y = 140, button = "left", down = true }
			f.backend.pointer { x = 200, y = 140, button = "left", down = false }
			check:expect(log):toEqual {
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
			check:expect(began == ended):toEqual(true)
			local input = began :: Environment.Instance
			check:expect(input:IsA "InputObject"):toEqual(true)
			check:expect(input.Position):toEqual(f.library.Vector3.new(200, 82, 0))
			check:expect(input.UserInputState):toEqual(f.library.Enum.UserInputState.End)
		end)
		suite:case("inactive buttons still receive click events without Activated", function(check)
			local f = pointerFixture()
			check:defer(f.cleanup)
			f.base.Active = false
			local clicked, activated = 0, 0
			local click = f.base.MouseButton1Click :: Environment.Signal
			local activate = f.base.Activated :: Environment.Signal
			click:Connect(function()
				clicked += 1
			end)
			activate:Connect(function()
				activated += 1
			end)
			f.backend.pointer { x = 200, y = 140, button = "left", down = true }
			f.backend.pointer { x = 200, y = 140, button = "left", down = false }
			check:expect(clicked):toEqual(1)
			check:expect(activated):toEqual(0)
		end)
		suite:case("release outside ends the original input without activating the button", function(check)
			local f = pointerFixture()
			check:defer(f.cleanup)
			local activated, ended = 0, 0
			local activate = f.base.Activated :: Environment.Signal
			local finish = f.base.InputEnded :: Environment.Signal<Environment.Instance>
			activate:Connect(function()
				activated += 1
			end)
			finish:Connect(function(input)
				if input.UserInputType == f.library.Enum.UserInputType.MouseButton1 then
					ended += 1
				end
			end)
			f.backend.pointer { x = 200, y = 140, button = "left", down = true }
			f.backend.pointer { x = 400, y = 300, button = "left", down = false }
			check:expect(activated):toEqual(0)
			check:expect(ended):toEqual(1)
		end)
		suite:case(
			"noninteractable button ancestry is excluded from event routing but remains in the hit query",
			function(check)
				local f = pointerFixture()
				check:defer(f.cleanup)
				f.base.Interactable = false
				local began = 0
				local baseBegin = f.base.InputBegan :: Environment.Signal
				local childBegin = f.child.InputBegan :: Environment.Signal
				baseBegin:Connect(function()
					began += 1
				end)
				childBegin:Connect(function()
					began += 1
				end)
				f.backend.pointer { x = 200, y = 140, button = "left", down = true }
				f.backend.pointer { x = 200, y = 140, button = "left", down = false }
				local query = f.gui.GetGuiObjectsAtPosition :: Environment.Method
				check:expect(query(f.gui, 200, 82)):toEqual { f.overlay, f.child, f.base }
				check:expect(began):toEqual(0)
			end
		)
		suite:case("close cancels retained input and releases owned objects without activation", function(check)
			local f = pointerFixture()
			local create = f.service.CreateVirtualInput :: Environment.Method
			create(f.service)
			create(f.service)
			local baseline = f.env.liveObjects()
			local activated = 0
			(f.base.Activated :: Environment.Signal):Connect(function()
				activated += 1
			end)
			f.backend.pointer { x = 200, y = 140, button = "left", down = true }
			f.backend.close()
			f.backend.close()
			check:expect(f.service.CreateVirtualInput):toEqual(nil)
			check:expect(f.gui.GetGuiObjectsAtPosition):toEqual(nil)
			check:expect(activated):toEqual(0)
			check:expect(f.env.liveObjects()):toEqual(baseline - 4)
			check
				:expect(pcall(function()
					f.backend.pointer { x = 200, y = 140, button = "left", down = false }
				end))
				:toEqual(false)
			f.cleanup()
			check:expect(f.env.liveObjects()):toEqual(0)
			check:expect(f.env.liveConnections()):toEqual(0)
		end)
		suite:case("closing input preserves a later override without retaining its removed predecessor", function(check)
			local f = pointerFixture()
			check:defer(f.cleanup)
			local restore = f.env.fakeOn(f.service, "GetLastInputType", function(): string
				return "later-owner"
			end)
			f.backend.close()
			check:expect((f.service.GetLastInputType :: Environment.Method)(f.service)):toEqual "later-owner"
			restore()
			check:expect(f.service.GetLastInputType):toEqual(nil)
		end)
		suite:case("unsupported geometry fails before the next press", function(check)
			local f = pointerFixture()
			check:defer(f.cleanup)
			local presses = 0
			(f.base.MouseButton1Down :: Environment.Signal):Connect(function()
				presses += 1
			end)
			f.backend.pointer { x = 200, y = 140, button = "left", down = true }
			f.backend.pointer { x = 200, y = 140, button = "left", down = false }
			f.base.Rotation = 10
			check
				:expect(pcall(function()
					f.backend.pointer { x = 200, y = 140, button = "left", down = true }
				end))
				:toEqual(false)
			check:expect(presses):toEqual(1)
		end)
		suite:case("rejects malformed keys, pointers and text", function(check)
			local badKeys: { unknown } = { {}, { code = "", down = true }, { code = "A", down = 1 } }
			for _, value in badKeys do
				check:expect((pcall(Input.key.input, value))):toEqual(false)
			end
			local badPointers: { unknown } = {
				{ x = math.huge, y = 1, button = "left", down = true },
				{ x = math.huge - math.huge, y = 1, button = "left", down = true },
				{ x = 1, y = 2, button = "extra", down = true },
				{ x = 1, y = 2, button = "left", down = "yes" },
			}
			for _, value in badPointers do
				check:expect((pcall(Input.pointer.input, value))):toEqual(false)
			end
			check:expect((pcall(Input.text.input, 1))):toEqual(false)
			check:expect(Input.pointer.input({ x = 0, y = -1, button = "middle", down = false }).y):toEqual(-1)
		end)
		suite:case("registry forwards typed input and preserves backend failures", function(check)
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
			check:expect(table.concat(received, ",")):toEqual "A,right,hello"
			check:expect((pcall(run, "input.text", "fail"))):toEqual(false)
			check:expect((pcall(run, "input.pointer", { x = math.huge }))):toEqual(false)
			check:expect(#received):toEqual(3)
		end)
	end)
end
