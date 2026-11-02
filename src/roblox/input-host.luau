--!strict
--!nolint DeprecatedApi

local Core = require "../core"
local Native = require "./experience-host"
local Environment = require "./environment"
local Layout = require "./ui-layout"
local Datatypes = require "./datatypes"
local Values = require "./ui-values"
local EnumTypes = require "./datatypes/enum"
local Gamepad = require "./input-gamepad"
local Touch = require "./input-touch"
local PointerInput = require "./input-pointer"
local VectorTypes = require "./datatypes/vector"
local Names = require "./datatypes/names"
local MODIFIERS = { "PrimaryModifier", "SecondaryModifier" }

export type Key = { code: string, down: boolean }
export type Pointer = { x: number, y: number, button: "left" | "right" | "middle", down: boolean }
export type Backend = { key: (Key) -> (), pointer: (Pointer) -> (), text: (string) -> (), close: () -> () }
export type Simulated = Backend & { connectGamepad: () -> (), disconnectGamepad: () -> () }
export type SimulatedOptions = {
	playerGui: Environment.Instance,
	inputService: Environment.Instance,
	layout: Layout.Controller,
	inset: () -> { X: number, Y: number },
	library: Datatypes.Library,
	activationWindowSeconds: number,
	read: ((Environment.Instance, string) -> unknown)?,
	virtualController: boolean?,
}
local function fields(value: unknown): { [string]: unknown }
	assert(type(value) == "table", "expected input record")
	local result: { [string]: unknown } = {}
	for key, item in value do
		if type(key) == "string" then
			result[key] = item
		end
	end
	return result
end
local function key(value: unknown): Key
	local record = fields(value)
	assert(type(record.code) == "string" and record.code ~= "" and type(record.down) == "boolean", "invalid key")
	return { code = record.code, down = record.down }
end
local function pointer(value: unknown): Pointer
	local record = fields(value)
	assert(type(record.x) == "number" and math.abs(record.x) < math.huge, "invalid pointer x")
	assert(type(record.y) == "number" and math.abs(record.y) < math.huge, "invalid pointer y")
	assert(record.button == "left" or record.button == "right" or record.button == "middle", "invalid pointer button")
	assert(type(record.down) == "boolean", "invalid pointer state")
	return {
		x = record.x,
		y = record.y,
		button = if record.button == "left" then "left" elseif record.button == "right" then "right" else "middle",
		down = record.down,
	}
end
local function text(value: unknown): string
	assert(type(value) == "string", "expected text")
	return value
end
local function empty(value: unknown): nil
	assert(value == nil, "expected no result")
	return nil
end
local keyOperation = Core.operation<<Key, nil>> { kind = "action", name = "input.key", input = key, output = empty }
local pointerOperation =
	Core.operation<<Pointer, nil>> { kind = "action", name = "input.pointer", input = pointer, output = empty }
local textOperation =
	Core.operation<<string, nil>> { kind = "action", name = "input.text", input = text, output = empty }
local function registry(backend: Backend): Native.Registry
	return {
		actions = {
			[keyOperation.name] = Core.bindOperation(keyOperation, function(value)
				backend.key(value)
				return nil
			end),
			[pointerOperation.name] = Core.bindOperation(pointerOperation, function(value)
				backend.pointer(value)
				return nil
			end),
			[textOperation.name] = Core.bindOperation(textOperation, function(value)
				backend.text(value)
				return nil
			end),
		},
		queries = {},
	}
end

type Vector = { X: number, Y: number }
type VirtualInput = {
	SendKey: (VirtualInput, boolean, unknown, boolean) -> (),
	SendMouseButton: (VirtualInput, Vector, unknown, boolean, number) -> (),
	SendMousePosition: (VirtualInput, Vector) -> (),
	SendTextInput: (VirtualInput, string) -> (),
}
type InputService = { CreateVirtualInput: (InputService) -> VirtualInput? }
type Globals = {
	game: { GetService: (unknown, string) -> InputService },
	Enum: { KeyCode: { [string]: unknown }, UserInputType: { [string]: unknown } },
	Vector2: { new: (number, number) -> Vector },
}
export type GuiTarget = { AbsolutePosition: Vector, AbsoluteSize: Vector }
local function screenCenter(target: GuiTarget): { x: number, y: number }
	local globals: { game: { GetService: (unknown, string) -> { GetGuiInset: (unknown) -> (Vector, Vector) } } } =
		getfenv(0)
	local inset = globals.game:GetService("GuiService"):GetGuiInset()
	assert(target.AbsoluteSize.X > 0 and target.AbsoluteSize.Y > 0, "GUI target has no rendered area")
	return {
		x = target.AbsolutePosition.X + target.AbsoluteSize.X / 2 + inset.X,
		y = target.AbsolutePosition.Y + target.AbsoluteSize.Y / 2 + inset.Y,
	}
end

local function native(): Backend?
	assert(Native.nativeEngine().context == "client", "virtual input requires a live client")
	local globals: Globals = getfenv(0)
	local service = globals.game:GetService "UserInputService"
	local input = service:CreateVirtualInput()
	if input == nil then
		return nil
	end
	local device = input
	local keys: { [string]: boolean } = {}
	local buttons: { [string]: Pointer } = {}
	local closed = false
	local names = { left = "MouseButton1", right = "MouseButton2", middle = "MouseButton3" }
	local function sendKey(value: Key)
		local code = globals.Enum.KeyCode[value.code]
		assert(code ~= nil, "unknown key code: " .. value.code)
		device:SendKey(value.down, code, false)
		if value.down then
			keys[value.code] = true
		else
			keys[value.code] = nil
		end
	end
	local function sendPointer(value: Pointer)
		local position = globals.Vector2.new(value.x, value.y)
		device:SendMousePosition(position)
		device:SendMouseButton(position, globals.Enum.UserInputType[names[value.button]], value.down, 0)
		if value.down then
			buttons[value.button] = value
		else
			buttons[value.button] = nil
		end
	end
	return {
		key = function(value)
			assert(not closed, "input is closed")
			sendKey(value)
		end,
		pointer = function(value)
			assert(not closed, "input is closed")
			sendPointer(value)
		end,
		text = function(value)
			assert(not closed, "input is closed")
			device:SendTextInput(value)
		end,
		close = function()
			if closed then
				return
			end
			closed = true
			local failures: { string } = {}
			for code in table.clone(keys) do
				local ok, err = pcall(function(): unknown
					sendKey { code = code, down = false }
					return nil
				end)
				if not ok then
					table.insert(failures, tostring(err))
				end
			end
			for _, value in table.clone(buttons) do
				value.down = false
				local ok, err = pcall(function(): unknown
					sendPointer(value)
					return nil
				end)
				if not ok then
					table.insert(failures, tostring(err))
				end
			end
			assert(#failures == 0, table.concat(failures, "; "))
		end,
	}
end
local function simulated(env: Environment.Environment, options: SimulatedOptions): Simulated
	type Instance = Environment.Instance
	type Position = { X: number, Y: number }
	local gui, service, layout = options.playerGui, options.inputService, options.layout
	assert(gui:IsA "BasePlayerGui", "simulated pointer requires a BasePlayerGui")
	assert(service:IsA "UserInputService", "simulated pointer requires UserInputService")
	local library = options.library
	local activationWindow = options.activationWindowSeconds
	assert(
		type(activationWindow) == "number" and activationWindow > 0 and activationWindow < math.huge,
		"simulated pointer requires a finite positive activationWindowSeconds"
	)
	local inputTypes, states = library.Enum.UserInputType, library.Enum.UserInputState
	local none = library.Enum.KeyCode.None
	local unknownKey = library.Enum.KeyCode:FromName "Unknown"
	local closed, held = false, false
	local position: Position = { X = 0, Y = 0 }
	local buttonPosition: Position = { X = 0, Y = 0 }
	local hovered: { Instance } = {}
	local pressed: { Instance } = {}
	local pressedButton: Instance? = nil
	type Drag = { detector: Instance, origin: Position }
	local dragging: Drag? = nil
	type Activation = { released: number, count: number }
	local activations: { [Instance]: Activation } = {}
	do
		local weak = activations
		setmetatable(weak, { __mode = "k" })
	end
	local owned: { Environment.Object } = {}
	local registrations: { () -> () } = {}
	local function install<O, A..., R...>(object: O, name: string, handler: (O, A...) -> R...)
		table.insert(registrations, env.fakeOn(object, name, handler))
	end
	local movement: Instance? = nil
	local buttonInput: Instance? = nil
	local lastInput: unknown = inputTypes.MouseMovement
	local function unsupported(reason: string): never
		error("unsupported_simulated_input: " .. reason, 0)
	end
	local function ensureOpen()
		assert(not closed, "input is closed")
	end
	local function read(object: Instance, property: string): unknown
		return if options.read then options.read(object, property) else object[property]
	end
	local function button(object: Instance): boolean
		return object:IsA "GuiButton" or object:IsA "TextButton" or object:IsA "ImageButton"
	end
	local function interactable(object: Instance): boolean
		local current: Instance? = object
		while current and current ~= gui do
			if current:IsA "GuiObject" and read(current, "Interactable") == false then
				return false
			end
			current = current.Parent
		end
		return true
	end
	local stated: { [Instance]: boolean } = {}
	local hasStates, guiStates = pcall(function(): unknown
		return library.Enum.GuiState
	end)
	local function setState(object: Instance, name: string)
		local member = library.Enum.GuiState:FromName(name)
		if env.propertyOf(object, "GuiState") ~= member then
			env.poke(object, "GuiState", member)
		end
	end
	local function refreshStates()
		if not hasStates or guiStates == nil then
			return
		end
		local wanted: { [Instance]: string } = {}
		for _, object in hovered do
			if object:IsA "GuiObject" then
				wanted[object] = "Hover"
			end
		end
		if held then
			for _, object in pressed do
				if wanted[object] then
					wanted[object] = "Press"
				end
			end
		end
		for object in stated do
			if wanted[object] == nil and env.isAlive(object) then
				setState(object, if interactable(object) then "Idle" else "NonInteractable")
			end
		end
		table.clear(stated)
		for object, name in wanted do
			setState(object, name)
			stated[object] = true
		end
	end
	local function validateBindings(source: "movement" | "button"): ()
		local root = gui:FindFirstAncestorWhichIsA "DataModel" or gui
		for _, binding in root:GetDescendants() do
			if not binding:IsA "InputBinding" then
				continue
			end
			local bindingType = tostring(env.propertyOf(binding, "Type")):match "([^%.]+)$"
			if bindingType == "Scriptable" then
				continue
			end
			if bindingType ~= "Automatic" then
				unsupported "InputBinding.Type metadata"
			end
			local action = binding.Parent
			if action == nil or not action:IsA "InputAction" then
				unsupported "InputBinding without a direct InputAction"
				return
			end
			local enabled = env.propertyOf(action, "Enabled")
			if enabled == false then
				continue
			end
			if enabled ~= true then
				unsupported "InputAction.Enabled metadata"
			end
			local context = action:FindFirstAncestorWhichIsA "InputContext"
			if context then
				if context:FindFirstAncestorWhichIsA "InputContext" then
					unsupported "nested InputContext"
				end
				local active = env.propertyOf(context, "Enabled")
				if active == false then
					continue
				end
				if active ~= true then
					unsupported "InputContext.Enabled metadata"
				end
			end
			if source == "button" and env.propertyOf(binding, "UIButton") ~= nil then
				unsupported "InputBinding.UIButton"
			end
			if env.propertyOf(binding, "KeyCode") == nil then
				unsupported "InputBinding.KeyCode metadata"
			end
			for _, property in { "KeyCode", "Up", "Down", "Left", "Right", "Forward", "Backward" } do
				local code = tostring(env.propertyOf(binding, property)):match "([^%.]+)$"
				if source == "button" and code == "MouseLeftButton" then
					unsupported "InputBinding.MouseLeftButton"
				elseif
					source == "movement"
					and (
						code == "MousePosition"
						or code == "MouseDelta"
						or code == "MouseX"
						or code == "MouseY"
						or code == "MouseNoButton"
					)
				then
					unsupported "InputBinding mouse movement"
				end
			end
		end
	end
	local function hits(at: Position, source: "movement" | "button"): { Instance }
		ensureOpen()
		local function validate(object: Instance)
			if object:IsA "StyleLink" and options.read == nil then
				unsupported "StyleLink without effective input properties"
			end
			for _, child in object:GetChildren() do
				validate(child)
			end
		end
		validate(gui)
		validateBindings(source)
		layout.step()
		local inset = options.inset()
		local result: { Instance } = {}
		for _, object in layout.objectsAtPosition(gui, at.X - inset.X, at.Y - inset.Y) do
			if interactable(object) then
				table.insert(result, object)
			end
		end
		return result
	end
	local function recipients(objects: { Instance }): ({ Instance }, Instance?)
		local result: { Instance } = {}
		local barrier: Instance? = nil
		for _, object in objects do
			if barrier and not barrier:IsDescendantOf(object) then
				continue
			end
			table.insert(result, object)
			if button(object) then
				return result, object
			end
			if read(object, "Active") == true then
				barrier = object
			end
		end
		return result, nil
	end
	local function processed(objects: { Instance }, isButton: boolean): boolean
		for _, object in objects do
			if read(object, "Active") == true or isButton and button(object) then
				return true
			end
		end
		return false
	end
	local function input(kind: unknown): Instance
		local object = env.createEngineInstance "InputObject"
		table.insert(owned, object)
		env.poke(object, "UserInputType", kind)
		env.poke(object, "UserInputState", states.Change)
		env.poke(object, "KeyCode", none)
		env.poke(object, "Position", library.Vector3.new(0, 0, 0))
		env.poke(object, "Delta", library.Vector3.new(0, 0, 0))
		return object
	end
	local function update(object: Instance, at: Position, state: unknown)
		local inset = options.inset()
		env.poke(object, "Position", library.Vector3.new(at.X - inset.X, at.Y - inset.Y, 0))
		env.poke(object, "UserInputState", state)
	end
	local function gui2d(at: Position): unknown
		local inset = options.inset()
		return library.Vector2.new(at.X - inset.X, at.Y - inset.Y)
	end
	local function detectorFor(targets: { Instance }): Instance?
		for _, target in targets do
			for _, child in target:GetChildren() do
				if child:IsA "UIDragDetector" and read(child, "Enabled") ~= false then
					if tostring(read(child, "ResponseStyle")) ~= "Enum.UIDragDetectorResponseStyle.CustomOffset" then
						unsupported "UIDragDetector response other than CustomOffset"
					end
					local style = tostring(read(child, "DragStyle"))
					if style == "Enum.UIDragDetectorDragStyle.TranslateLine" then
						local axis = Values.vector(read(child, "DragAxis"))
						if axis.X == 0 and axis.Y == 0 or read(child, "ReferenceUIInstance") ~= nil then
							unsupported "UIDragDetector line axis or reference"
						end
						local ancestor: Instance? = target
						while ancestor and ancestor ~= gui do
							local scale = ancestor:FindFirstChildWhichIsA "UIScale"
							if
								ancestor:IsA "GuiObject" and read(ancestor, "Rotation") ~= 0
								or scale and read(scale, "Scale") ~= 1
							then
								unsupported "UIDragDetector transformed line axis"
							end
							ancestor = ancestor.Parent
						end
					elseif style ~= "Enum.UIDragDetectorDragStyle.TranslatePlane" then
						unsupported "UIDragDetector drag style other than translation"
					end
					for _, limit in { "MinDragTranslation", "MaxDragTranslation" } do
						local value = Values.dimensions(read(child, limit))
						if value.X.Scale ~= 0 or value.X.Offset ~= 0 or value.Y.Scale ~= 0 or value.Y.Offset ~= 0 then
							unsupported "UIDragDetector drag translation limits"
						end
					end
					return child
				end
			end
		end
		return nil
	end
	local function dragOffset(detector: Instance, x: number, y: number): unknown
		if tostring(read(detector, "DragStyle")) == "Enum.UIDragDetectorDragStyle.TranslateLine" then
			local axis = Values.vector(read(detector, "DragAxis"))
			local distance = (x * axis.X + y * axis.Y) / (axis.X * axis.X + axis.Y * axis.Y)
			x, y = axis.X * distance, axis.Y * distance
		end
		return library.UDim2.fromOffset(x, y)
	end
	local function dragTo(at: Position, signal: string)
		local active = dragging
		if active == nil or not env.isAlive(active.detector) then
			return
		end
		env.poke(
			active.detector,
			"DragUDim2",
			dragOffset(active.detector, at.X - active.origin.X, at.Y - active.origin.Y)
		)
		env.fire(active.detector, signal, gui2d(at))
	end
	local function move(at: Position, objects: { Instance })
		local object = movement or input(inputTypes.MouseMovement)
		movement = object
		update(object, at, states.Change)
		for _, previous in hovered do
			if env.isAlive(previous) and not table.find(objects, previous) then
				env.fire(previous, "MouseLeave", at.X, at.Y)
				env.fire(previous, "InputEnded", object)
			end
		end
		for _, target in objects do
			if not table.find(hovered, target) then
				env.fire(target, "MouseEnter", at.X, at.Y)
				env.fire(target, "InputBegan", object)
			else
				env.fire(target, "InputChanged", object)
			end
		end
		position = at
		hovered = objects
		lastInput = inputTypes.MouseMovement
		env.fire(service, "InputChanged", object, processed(objects, false))
		if held and dragging then
			dragTo(at, "DragContinue")
		end
		refreshStates()
	end
	local function focusedBox(): Instance?
		local method = service.GetFocusedTextBox
		if type(method) ~= "function" then
			return nil
		end
		local found = env.method(service, "GetFocusedTextBox")(service)
		if found == nil then
			return nil
		end
		local instance = Environment.assertInstance(found)
		return if env.isAlive(instance) then instance else nil
	end
	local function send(at: Position, down: boolean, movePointer: boolean?)
		local objects = hits(at, "button")
		if movePointer then
			validateBindings "movement"
		end
		local targets, targetButton = recipients(objects)
		assert(down ~= held, "VirtualInput::SendMouseButton: duplicate button state.")
		if movePointer then
			move(at, objects)
		end
		local object = buttonInput or input(inputTypes.MouseButton1)
		buttonInput = object
		update(object, at, if down then states.Begin else states.End)
		env.poke(object, "Delta", library.Vector3.new(at.X - buttonPosition.X, at.Y - buttonPosition.Y, 0))
		buttonPosition = at
		hovered = objects
		lastInput = inputTypes.MouseButton1
		if down then
			held = true
			pressed, pressedButton = targets, targetButton
			local detector = detectorFor(targets)
			if detector then
				dragging = { detector = detector, origin = at }
				env.poke(detector, "DragUDim2", library.UDim2.fromOffset(0, 0))
				env.fire(detector, "DragStart", gui2d(at))
				if targetButton and detector.Parent == targetButton then
					pressedButton, targetButton = nil, nil
				end
			end
			if targetButton then
				env.fire(targetButton, "MouseButton1Down", at.X, at.Y)
			end
			local box = focusedBox()
			local clicked = targets[1]
			if box and box ~= clicked then
				local release = box.ReleaseFocus
				if type(release) == "function" then
					env.method(box, "ReleaseFocus")(box, false, object)
				end
			end
			if clicked and clicked:IsA "TextBox" and read(clicked, "TextEditable") ~= false and box ~= clicked then
				local capture = clicked.CaptureFocus
				if type(capture) == "function" then
					env.method(clicked, "CaptureFocus")(clicked)
				end
				if tostring(clicked.Text) ~= "" then
					unsupported "TextBox click placement inside existing text"
				end
				env.poke(clicked, "CursorPosition", 1)
			end
			for _, target in targets do
				env.fire(target, "InputBegan", object)
			end
			env.fire(service, "InputBegan", object, processed(targets, true))
		else
			held = false
			if dragging then
				dragTo(at, "DragEnd")
				dragging = nil
			end
			local original = pressedButton
			if original and env.isAlive(original) and original == targetButton then
				env.fire(original, "MouseButton1Click")
				env.fire(original, "MouseButton1Up", at.X, at.Y)
				if read(original, "Active") == true then
					local previous = activations[original]
					local released = env.now()
					local count = if previous and released - previous.released < activationWindow
						then previous.count + 1
						else 0
					activations[original] = { released = released, count = count }
					env.fire(original, "Activated", object, count)
				end
			end
			for _, target in pressed do
				if env.isAlive(target) then
					env.fire(target, "InputEnded", object)
				end
			end
			pressed, pressedButton = {}, nil
			env.fire(service, "InputEnded", object, processed(targets, true))
		end
		refreshStates()
	end
	local heldKeys: { [string]: true } = {}
	local heldInputs: { [string]: Instance } = {}
	type BoundAction = { action: Instance, context: Instance, binding: Instance }
	local keyActions: { [string]: { BoundAction } } = {}
	local selectionRepeats: { [string]: {} } = {}
	local function codeName(value: unknown): string
		return (tostring(value):match "([^%.]+)$" or tostring(value))
	end
	local function boundActions(code: string): { BoundAction }
		local root = gui:FindFirstAncestorWhichIsA "DataModel" or gui
		local found: { BoundAction } = {}
		for _, binding in root:GetDescendants() do
			if not binding:IsA "InputBinding" or codeName(env.propertyOf(binding, "KeyCode")) ~= code then
				continue
			end
			local matched = true
			for _, property in MODIFIERS do
				local modifier = env.propertyOf(binding, property)
				if
					modifier ~= nil
					and modifier ~= none
					and modifier ~= unknownKey
					and not heldKeys[codeName(modifier)]
				then
					matched = false
					break
				end
			end
			if not matched then
				continue
			end
			if codeName(env.propertyOf(binding, "Type")) ~= "Automatic" then
				unsupported "keyboard InputBinding.Type metadata"
			end
			local action = binding.Parent
			if action == nil or not action:IsA "InputAction" then
				unsupported "keyboard InputBinding without a direct InputAction"
			end
			local owner = Environment.assertInstance(action):FindFirstAncestorWhichIsA "InputContext"
			if owner == nil then
				unsupported "keyboard InputAction outside an InputContext"
			end
			local context = Environment.assertInstance(owner)
			if codeName(env.propertyOf(Environment.assertInstance(action), "Type")) ~= "Bool" then
				unsupported "keyboard InputAction.Type other than Bool"
			end
			if
				env.propertyOf(Environment.assertInstance(action), "Enabled") == true
				and env.propertyOf(context, "Enabled") == true
			then
				table.insert(
					found,
					{ action = Environment.assertInstance(action), context = context, binding = binding }
				)
			end
		end
		table.sort(found, function(left, right)
			return Values.number(env.propertyOf(left.context, "Priority"))
				> Values.number(env.propertyOf(right.context, "Priority"))
		end)
		return found
	end
	local function deliverActions(code: string, down: boolean)
		if not down then
			for key, actions in keyActions do
				for _, entry in actions do
					if key ~= code and env.isAlive(entry.binding) then
						if
							codeName(env.propertyOf(entry.binding, "PrimaryModifier")) ~= code
							and codeName(env.propertyOf(entry.binding, "SecondaryModifier")) ~= code
						then
							continue
						end
					end
					if env.isAlive(entry.action) then
						env.method(entry.action, "Fire")(entry.action, false)
					end
				end
			end
			keyActions[code] = nil
			return
		end
		local actions: { BoundAction } = {}
		keyActions[code] = actions
		local sunk: number? = nil
		for _, entry in boundActions(code) do
			local priority = Values.number(env.propertyOf(entry.context, "Priority"))
			if sunk and priority < sunk then
				break
			end
			local fire = env.method(entry.action, "Fire")
			fire(entry.action, down)
			table.insert(actions, entry)
			if env.propertyOf(entry.context, "Sink") == true then
				sunk = priority
			end
		end
	end
	local directions: { [string]: { x: number, y: number, name: string } } = {
		Up = { x = 0, y = -1, name = "Up" },
		Down = { x = 0, y = 1, name = "Down" },
		Left = { x = -1, y = 0, name = "Left" },
		Right = { x = 1, y = 0, name = "Right" },
	}
	local function navigable(object: Instance, memo: { [Instance]: boolean }?): boolean
		if object == gui then
			return true
		end
		local known = if memo then memo[object] else nil
		if known ~= nil then
			return known
		end
		local parent = env.parentOf(object)
		local result = parent ~= nil
			and (not object:IsA "GuiObject" or read(object, "Visible") ~= false and read(object, "Interactable") ~= false)
			and (not object:IsA "LayerCollector" or read(object, "Enabled") ~= false)
			and navigable(parent, memo)
		if memo then
			memo[object] = result
		end
		return result
	end
	local function selectable(object: Instance): boolean
		return object:IsA "GuiObject" and read(object, "Selectable") == true and navigable(object, nil)
	end
	local function onScreen(object: Instance): boolean
		local at = Values.vector(read(object, "AbsolutePosition"))
		local size = Values.vector(read(object, "AbsoluteSize"))
		local left, top, right, bottom = at.X, at.Y, at.X + size.X, at.Y + size.Y
		local parent = object.Parent
		while parent and parent ~= gui do
			if parent:IsA "ScreenGui" or parent:IsA "GuiObject" and read(parent, "ClipsDescendants") == true then
				local origin = Values.vector(read(parent, "AbsolutePosition"))
				local extent = Values.vector(read(parent, "AbsoluteSize"))
				left = math.max(left, origin.X)
				top = math.max(top, origin.Y)
				right = math.min(right, origin.X + extent.X)
				bottom = math.min(bottom, origin.Y + extent.Y)
			end
			parent = parent.Parent
		end
		return right > left and bottom > top
	end
	local selectionService = (gui:FindFirstAncestorWhichIsA "DataModel" or gui):FindFirstChildOfClass "GuiService"
	if selectionService then
		install(selectionService, "Select", function(self: Instance, scope: Instance)
			ensureOpen()
			assert(scope == gui or scope:IsDescendantOf(gui), "selection parent must belong to this PlayerGui")
			layout.step()
			local chosen: Instance? = nil
			local order = math.huge
			for _, object in scope:GetDescendants() do
				if selectable(object) and onScreen(object) then
					local candidateOrder = Values.number(read(object, "SelectionOrder"))
					if candidateOrder < order then
						chosen, order = object, candidateOrder
					end
				end
			end
			if chosen then
				env.publish(self, "SelectedObject", chosen)
			end
		end)
	end
	local function groupOf(object: Instance): Instance?
		local current = object.Parent
		while current and current ~= gui do
			if current:IsA "GuiBase2d" and read(current, "SelectionGroup") == true then
				return current
			end
			current = current.Parent
		end
		return nil
	end
	local function nearest(from: Instance, scope: Instance, direction: { x: number, y: number }): Instance?
		local origin = Values.vector(read(from, "AbsolutePosition"))
		local extent = Values.vector(read(from, "AbsoluteSize"))
		local x, y = origin.X + extent.X / 2, origin.Y + extent.Y / 2
		local best: Instance? = nil
		local bestScore = math.huge
		local eligible: { [Instance]: boolean } = {}
		for _, candidate in scope:GetDescendants() do
			if
				candidate ~= from
				and candidate:IsA "GuiObject"
				and read(candidate, "Selectable") == true
				and navigable(candidate, eligible)
			then
				local at = Values.vector(read(candidate, "AbsolutePosition"))
				local size = Values.vector(read(candidate, "AbsoluteSize"))
				local dx, dy = at.X + size.X / 2 - x, at.Y + size.Y / 2 - y
				local along = dx * direction.x + dy * direction.y
				local score = along + 2 * math.abs(dx * direction.y - dy * direction.x)
				if along > 0 and score < bestScore then
					best, bestScore = candidate, score
				end
			end
		end
		return best
	end
	local function navigate(from: Instance, direction: { x: number, y: number, name: string }): Instance?
		local named = read(from, "NextSelection" .. direction.name)
		if Environment.isInstance(named) then
			local target = Environment.assertInstance(named)
			if selectable(target) then
				return target
			end
		end
		local group = groupOf(from)
		while group do
			local found = nearest(from, group, direction)
			if found then
				return found
			end
			if tostring(read(group, "SelectionBehavior" .. direction.name)) == "Enum.SelectionBehavior.Stop" then
				return nil
			end
			group = groupOf(group)
		end
		return nearest(from, gui, direction)
	end
	local function accept(selected: Instance, object: Instance)
		if interactable(selected) then
			if button(selected) then
				env.fire(selected, "Activated", object, 1)
			elseif selected:IsA "TextBox" and read(selected, "TextEditable") ~= false then
				env.method(selected, "CaptureFocus")(selected)
			end
		end
	end
	local function deliverSelection(
		guiService: Instance,
		selected: Instance,
		code: string,
		object: Instance,
		down: boolean
	)
		local direction = directions[code]
		if down and direction then
			local target = navigate(selected, direction)
			if target then
				env.publish(guiService, "SelectedObject", target)
			end
		elseif down and code == "Escape" then
			env.publish(guiService, "SelectedObject", nil)
		end
		if code == "Return" and selected:IsA "TextBox" and read(selected, "TextEditable") ~= false then
			if down then
				accept(selected, object)
			end
			env.fire(service, if down then "InputBegan" else "InputEnded", object, not down and focusedBox() ~= nil)
			return
		end
		env.fire(service, if down then "InputBegan" else "InputEnded", object, true)
		if down and code == "Return" then
			accept(selected, object)
		end
	end
	local navigationKeys: { [string]: boolean } = {
		Return = true,
		Escape = true,
	}
	local function repeatSelection(code: string, token: {})
		if closed or selectionRepeats[code] ~= token then
			return
		end
		local guiService = (gui:FindFirstAncestorWhichIsA "DataModel" or gui):FindFirstChildOfClass "GuiService"
		local selected = if guiService then env.propertyOf(guiService, "SelectedObject") else nil
		if guiService and Environment.isInstance(selected) and not focusedBox() then
			local target = navigate(Environment.assertInstance(selected), directions[code])
			if target then
				env.publish(guiService, "SelectedObject", target)
			end
		end
		env.scheduler.delay(0.12, repeatSelection, code, token)
	end
	local controllerPress: Instance? = nil
	local stickDirection: string? = nil
	local controllerActive = options.virtualController == true
	local gamepad = Gamepad.create(env, library, input, function(event, object)
		local code = codeName(env.propertyOf(object, "KeyCode"))
		local direction = code:match "^DPad(.+)$"
		if event == "InputEnded" and direction then
			selectionRepeats[direction] = nil
		end
		if event == "InputEnded" and code == "Thumbstick1" then
			stickDirection = nil
		end
		if lastInput ~= inputTypes.Gamepad1 then
			lastInput = inputTypes.Gamepad1
			env.fire(service, "LastInputTypeChanged", lastInput)
		end
		if env.propertyOf(service, "PreferredInput") ~= library.Enum.PreferredInput.Gamepad then
			env.poke(service, "PreferredInput", library.Enum.PreferredInput.Gamepad)
		end
		local guiService = (gui:FindFirstAncestorWhichIsA "DataModel" or gui):FindFirstChildOfClass "GuiService"
		local selected = if guiService then env.propertyOf(guiService, "SelectedObject") else nil
		if guiService and Environment.isInstance(selected) then
			local target = Environment.assertInstance(selected)
			if code == "Thumbstick1" then
				local position = VectorTypes.expect3(env.propertyOf(object, "Position"), 1)
				if position.X ~= 0 and position.Y ~= 0 then
					unsupported "virtual controller diagonal thumbstick selection"
				end
				local current = if position.X > 0
					then "Right"
					elseif position.X < 0 then "Left"
					elseif position.Y > 0 then "Up"
					elseif position.Y < 0 then "Down"
					else nil
				if current and current ~= stickDirection then
					local nextTarget = navigate(target, directions[current])
					if nextTarget then
						env.publish(guiService, "SelectedObject", nextTarget)
					end
				end
				stickDirection = current
				env.fire(service, event, object, true)
				return
			end
			if direction and directions[direction] then
				if event == "InputBegan" then
					local nextTarget = navigate(target, directions[direction])
					if nextTarget then
						env.publish(guiService, "SelectedObject", nextTarget)
					end
					local token = {}
					selectionRepeats[direction] = token
					env.scheduler.delay(0.5, repeatSelection, direction, token)
				end
				env.fire(service, event, object, true)
				return
			elseif code == "ButtonA" then
				if event == "InputBegan" then
					controllerPress = target
				elseif event == "InputEnded" then
					if controllerPress == target then
						accept(target, object)
					end
					controllerPress = nil
				end
				env.fire(service, event, object, true)
				return
			end
		end
		if event == "InputEnded" and code == "ButtonA" then
			controllerPress = nil
		end
		env.fire(service, event, object, false)
		if event ~= "InputChanged" then
			deliverActions(code, event == "InputBegan")
		end
	end)
	local function deliverText(value: string)
		local box = focusedBox()
		if box == nil then
			unsupported "text input without a focused TextBox"
		end
		local target = Environment.assertInstance(box)
		local current = tostring(target.Text)
		local length = utf8.len(current) or #current
		local cursor = env.propertyOf(target, "CursorPosition")
		local at = if type(cursor) == "number" and cursor >= 1 and cursor <= length + 1 then cursor else length + 1
		local split = utf8.offset(current, at) or #current + 1
		target.Text = current:sub(1, split - 1) .. value .. current:sub(split)
		env.poke(target, "CursorPosition", at + (utf8.len(value) or #value))
	end
	local function deliverKey(value: Key)
		if controllerActive then
			gamepad.key(value.code, value.down)
			return
		end
		local code = value.code
		local keyboard = inputTypes.Keyboard
		local member = library.Enum.KeyCode:FromName(code)
		if member == nil then
			unsupported("unknown KeyCode " .. code)
		end
		local object = input(keyboard)
		env.poke(object, "KeyCode", member)
		env.poke(object, "UserInputState", if value.down then states.Begin else states.End)
		lastInput = keyboard
		local box = focusedBox()
		if value.down then
			heldKeys[code] = true
			heldInputs[code] = object
		else
			heldKeys[code] = nil
			heldInputs[code] = nil
			selectionRepeats[code] = nil
		end
		if box then
			if value.down and code == "Backspace" then
				local current = tostring(box.Text)
				local length = utf8.len(current) or #current
				local cursor = env.propertyOf(box, "CursorPosition")
				local at = if type(cursor) == "number"
						and cursor >= 1
						and cursor <= length + 1
					then cursor
					else length + 1
				if at > 1 then
					local start = utf8.offset(current, at - 1) or 1
					local finish = utf8.offset(current, at) or #current + 1
					box.Text = current:sub(1, start - 1) .. current:sub(finish)
					env.poke(box, "CursorPosition", at - 1)
				end
			elseif value.down and code == "Return" then
				if (heldKeys.LeftShift or heldKeys.RightShift) and box.MultiLine == true then
					unsupported "Shift+Return in a multiline TextBox"
				end
				if box.MultiLine == true then
					deliverText "\n"
				else
					env.method(box, "ReleaseFocus")(box, true, object)
				end
			end
			env.fire(service, if value.down then "InputBegan" else "InputEnded", object, true)
			return
		end
		local guiService = (gui:FindFirstAncestorWhichIsA "DataModel" or gui):FindFirstChildOfClass "GuiService"
		local selected = if guiService then env.propertyOf(guiService, "SelectedObject") else nil
		if guiService and Environment.isInstance(selected) and (directions[code] or navigationKeys[code]) then
			if value.down and directions[code] and selectionRepeats[code] == nil then
				local token = {}
				selectionRepeats[code] = token
				env.scheduler.delay(0.5, repeatSelection, code, token)
			end
			deliverSelection(guiService, Environment.assertInstance(selected), code, object, value.down)
			return
		end
		env.fire(service, if value.down then "InputBegan" else "InputEnded", object, false)
		deliverActions(code, value.down)
	end
	local function sendKeyLater(value: Key)
		ensureOpen()
		env.scheduler.delay(0, function()
			if not closed then
				deliverKey(value)
			end
		end)
	end
	local function sendTextLater(value: string)
		ensureOpen()
		env.scheduler.delay(0, function()
			if not closed then
				deliverText(value)
			end
		end)
	end
	local prepared, problem = pcall(function()
		movement = input(inputTypes.MouseMovement)
		local preparedButton = input(inputTypes.MouseButton1)
		buttonInput = preparedButton
		env.poke(preparedButton, "UserInputState", states.End)
	end)
	if not prepared then
		for _, object in owned do
			if env.isAlive(object) then
				env.releaseObject(object)
			end
		end
		error(problem, 0)
	end
	local function touchMode(): boolean
		return env.propertyOf(service, "TouchEnabled") == true and env.propertyOf(service, "MouseEnabled") == false
	end
	local function touchPoint(at: Position): Position
		local root = gui:FindFirstAncestorWhichIsA "DataModel"
		local guiService = root and root:FindFirstChildOfClass "GuiService"
		assert(guiService, "touch input requires GuiService")
		local getArea = env.method(guiService, "GetInsetArea")
		local area = getArea(guiService, library.Enum.ScreenInsets.None)
		assert(Datatypes.typeName(area) == "Rect", "GetInsetArea must return a Rect")
		local minimum = Values.vector(Names.fields(area).Min)
		return { X = at.X + minimum.X, Y = at.Y + minimum.Y }
	end
	local pointerInput: PointerInput.Controller? = nil
	local function pointerController(): PointerInput.Controller
		if pointerInput == nil then
			pointerInput = PointerInput.create(env, {
				service = service,
				library = library,
				input = input,
				hits = function(at)
					return hits(at, "movement")
				end,
				inset = options.inset,
				read = read,
				changed = function()
					if lastInput ~= inputTypes.MouseWheel then
						lastInput = inputTypes.MouseWheel
						env.fire(service, "LastInputTypeChanged", lastInput)
					end
				end,
			})
		end
		return assert(pointerInput)
	end
	local touch = Touch.create(env, {
		service = service,
		activationWindowSeconds = activationWindow,
		library = library,
		createInput = input,
		targets = function(at)
			local inset = options.inset()
			local objects = hits({ X = at.X + inset.X, Y = at.Y + inset.Y }, "button")
			local targets, targetButton = recipients(objects)
			return targets, targetButton, objects
		end,
		scroll = function(objects, x, y)
			return pointerController().drag(objects, x, y)
		end,
		processed = processed,
		detector = detectorFor,
		dragOffset = dragOffset,
		read = read,
		changed = function()
			if lastInput ~= inputTypes.Touch then
				lastInput = inputTypes.Touch
				env.fire(service, "LastInputTypeChanged", lastInput)
			end
		end,
	})
	local function createDevice(): Environment.Object
		local device = env.createEngineObject "VirtualInput"
		table.insert(owned, device)
		install(device, "SendPointerAction", function(_self: Environment.Object, at: Position, action: unknown)
			ensureOpen()
			pointerController().send(at, fields(action))
		end)
		install(device, "SendMousePosition", function(_self: Environment.Object, at: Position)
			if touchMode() then
				position = at
				touch.move(touchPoint(at))
			else
				move(at, hits(at, "movement"))
			end
		end)
		install(
			device,
			"SendMouseButton",
			function(_self: Environment.Object, at: Position, kind: unknown, down: boolean, count: number?)
				if kind ~= inputTypes.MouseButton1 then
					unsupported "non-left mouse button"
				end
				if count ~= nil and (type(count) ~= "number" or count < 0 or count % 1 ~= 0) then
					unsupported "non-integer activation count"
				end
				if at.X ~= position.X or at.Y ~= position.Y then
					unsupported "button coordinates without prior pointer movement"
				end
				if touchMode() then
					touch.press(touchPoint(at), down)
				else
					send(at, down)
				end
			end
		)
		install(device, "SendKey", function(_self: Environment.Object, down: boolean, code: unknown, _repeat: boolean)
			sendKeyLater { code = codeName(code), down = down }
		end)
		install(device, "SendTextInput", function(_self: Environment.Object, value: string)
			sendTextLater(value)
		end)
		return device
	end
	install(service, "CreateVirtualInput", function(): Environment.Object
		ensureOpen()
		return createDevice()
	end)
	install(service, "GetMouseLocation", function(): unknown
		ensureOpen()
		return library.Vector2.new(position.X, position.Y)
	end)
	install(service, "GetLastInputType", function(): unknown
		ensureOpen()
		return lastInput
	end)
	install(service, "IsKeyDown", function(_self: Instance, code: unknown): boolean
		ensureOpen()
		return heldKeys[codeName(code)] == true
	end)
	install(service, "GetGamepadState", function(_self: Instance, kind: unknown): { Instance }
		ensureOpen()
		return gamepad.state(kind)
	end)
	local previousGamepad = env.propertyOf(service, "GamepadEnabled")
	local previousPreferred = env.propertyOf(service, "PreferredInput")
	local pluggedGamepad, pluggedPreferred = previousGamepad, previousPreferred
	local connectedQueries: { () -> () } = {}
	local function answerConnected()
		table.insert(
			connectedQueries,
			env.fakeOn(service, "GetConnectedGamepads", function(): { unknown }
				ensureOpen()
				return { inputTypes.Gamepad1 }
			end)
		)
		table.insert(
			connectedQueries,
			env.fakeOn(service, "GetGamepadConnected", function(_self: Instance, kind: unknown): boolean
				ensureOpen()
				return kind == inputTypes.Gamepad1
			end)
		)
	end
	local function forgetConnected()
		for ordinal = #connectedQueries, 1, -1 do
			connectedQueries[ordinal]()
		end
		table.clear(connectedQueries)
	end
	if options.virtualController then
		env.poke(service, "GamepadEnabled", true)
		env.poke(service, "PreferredInput", library.Enum.PreferredInput.Gamepad)
		answerConnected()
	end
	local function connectGamepad()
		ensureOpen()
		if controllerActive then
			unsupported "a second virtual controller"
		end
		controllerActive = true
		pluggedGamepad = env.propertyOf(service, "GamepadEnabled")
		pluggedPreferred = env.propertyOf(service, "PreferredInput")
		answerConnected()
		env.poke(service, "GamepadEnabled", true)
		env.fire(service, "GamepadConnected", inputTypes.Gamepad1)
	end
	local function disconnectGamepad()
		ensureOpen()
		if not controllerActive then
			unsupported "disconnecting an absent virtual controller"
		end
		controllerActive = false
		forgetConnected()
		env.poke(service, "GamepadEnabled", pluggedGamepad)
		env.poke(service, "PreferredInput", pluggedPreferred)
		env.fire(service, "GamepadDisconnected", inputTypes.Gamepad1)
	end
	install(service, "GetKeysPressed", function(): { Instance }
		ensureOpen()
		local pressedKeys: { Instance } = {}
		for _, object in heldInputs do
			table.insert(pressedKeys, object)
		end
		table.sort(pressedKeys, function(left, right)
			return EnumTypes.itemValue(env.propertyOf(left, "KeyCode")).Value
				< EnumTypes.itemValue(env.propertyOf(right, "KeyCode")).Value
		end)
		return pressedKeys
	end)
	install(service, "GetMouseButtonsPressed", function(): { Instance }
		ensureOpen()
		return if held and buttonInput then { buttonInput } else {}
	end)
	install(gui, "GetGuiObjectsAtPosition", function(_self: Instance, x: number, y: number): { Instance }
		ensureOpen()
		layout.step()
		return layout.objectsAtPosition(gui, x, y)
	end)
	local frame = env.heartbeat:Connect(function()
		if pointerInput then
			pointerInput.step()
		end
		if not closed and #hovered > 0 then
			layout.step()
			local inset = options.inset()
			local objects = layout.objectsAtPosition(gui, position.X - inset.X, position.Y - inset.Y, hovered)
			local retained: { Instance } = {}
			for _, object in hovered do
				if table.find(objects, object) and interactable(object) then
					table.insert(retained, object)
				end
			end
			hovered = retained
		end
	end)
	return {
		key = function(value: Key)
			sendKeyLater(key(value))
		end,
		text = sendTextLater,
		connectGamepad = connectGamepad,
		disconnectGamepad = disconnectGamepad,
		pointer = function(value: Pointer)
			local current = pointer(value)
			if current.button ~= "left" then
				unsupported "non-left mouse button"
			end
			local at = { X = current.x, Y = current.y }
			if touchMode() then
				position = at
				local point = touchPoint(at)
				touch.move(point)
				touch.press(point, current.down)
			else
				send(at, current.down, true)
			end
		end,
		close = function()
			if closed then
				return
			end
			frame:Disconnect()
			if pointerInput then
				pointerInput.close()
			end
			touch.close()
			if controllerActive then
				env.poke(service, "GamepadEnabled", previousGamepad)
				env.poke(service, "PreferredInput", previousPreferred)
			end
			controllerActive = false
			forgetConnected()
			closed = true
			for ordinal = #registrations, 1, -1 do
				registrations[ordinal]()
			end
			table.clear(registrations)
			if held and buttonInput then
				env.poke(buttonInput, "UserInputState", states.Cancel)
			end
			held = false
			pressed, hovered, pressedButton = {}, {}, nil
			table.clear(activations)
			table.clear(keyActions)
			for _, object in owned do
				if env.isAlive(object) then
					env.releaseObject(object)
				end
			end
			table.clear(owned)
			movement, buttonInput = nil, nil
		end,
	}
end
return {
	screenCenter = screenCenter,
	key = keyOperation,
	pointer = pointerOperation,
	text = textOperation,
	registry = registry,
	native = native,
	simulated = simulated,
}
