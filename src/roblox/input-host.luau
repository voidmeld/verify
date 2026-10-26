--!strict
--!nolint DeprecatedApi

local Core = require "../core"
local Native = require "./experience-host"
local Environment = require "./environment"
local Layout = require "./ui-layout"
local Datatypes = require "./datatypes"
local Values = require "./ui-values"
local EnumTypes = require "./datatypes/enum"

export type Key = { code: string, down: boolean }
export type Pointer = { x: number, y: number, button: "left" | "right" | "middle", down: boolean }
export type Backend = { key: (Key) -> (), pointer: (Pointer) -> (), text: (string) -> (), close: () -> () }
export type SimulatedOptions = {
	playerGui: Environment.Instance,
	inputService: Environment.Instance,
	layout: Layout.Controller,
	inset: () -> { X: number, Y: number },
	library: Datatypes.Library,
	activationWindowSeconds: number,
	read: ((Environment.Instance, string) -> unknown)?,
}
local function fields(value: unknown): { [string]: unknown }
	assert(type(value) == "table", "expected input record")
	return value :: { [string]: unknown }
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
local keyOperation = Core.operation { kind = "action", name = "input.key", input = key, output = empty }
local pointerOperation = Core.operation { kind = "action", name = "input.pointer", input = pointer, output = empty }
local textOperation = Core.operation { kind = "action", name = "input.text", input = text, output = empty }
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
local function simulated(env: Environment.Environment, options: SimulatedOptions): Backend
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
				return unsupported "InputBinding without a direct InputAction"
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
		for _, object in objects do
			table.insert(result, object)
			if button(object) then
				return result, object
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
					if tostring(read(child, "DragStyle")) ~= "Enum.UIDragDetectorDragStyle.TranslatePlane" then
						unsupported "UIDragDetector drag style other than TranslatePlane"
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
	local function dragTo(at: Position, signal: string)
		local active = dragging
		if active == nil or not env.isAlive(active.detector) then
			return
		end
		env.poke(active.detector, "DragUDim2", library.UDim2.fromOffset(at.X - active.origin.X, at.Y - active.origin.Y))
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
		local found = (method :: (Instance) -> Instance?)(service)
		return if found and env.isAlive(found) then found else nil
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
					(release :: (Instance, boolean, Instance) -> ())(box, false, object)
				end
			end
			if clicked and clicked:IsA "TextBox" and read(clicked, "TextEditable") ~= false and box ~= clicked then
				local capture = clicked.CaptureFocus
				if type(capture) == "function" then
					(capture :: (Instance) -> ())(clicked)
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
	local actionStates: { [Instance]: boolean } = {}
	setmetatable(actionStates, { __mode = "k" })
	local function codeName(value: unknown): string
		return (tostring(value):match "([^%.]+)$" or tostring(value))
	end
	local function boundActions(code: string): { { action: Instance, context: Instance } }
		local root = gui:FindFirstAncestorWhichIsA "DataModel" or gui
		local found: { { action: Instance, context: Instance } } = {}
		for _, binding in root:GetDescendants() do
			if not binding:IsA "InputBinding" or codeName(env.propertyOf(binding, "KeyCode")) ~= code then
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
				table.insert(found, { action = Environment.assertInstance(action), context = context })
			end
		end
		table.sort(found, function(left, right)
			return Values.number(env.propertyOf(left.context, "Priority"))
				> Values.number(env.propertyOf(right.context, "Priority"))
		end)
		return found
	end
	local function deliverKey(value: Key)
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
				local release = box.ReleaseFocus
				if type(release) == "function" then
					(release :: (Instance, boolean) -> ())(box, true)
				end
			end
			env.fire(service, if value.down then "InputBegan" else "InputEnded", object, true)
			return
		end
		local guiService = (gui:FindFirstAncestorWhichIsA "DataModel" or gui):FindFirstChildOfClass "GuiService"
		if guiService and env.propertyOf(guiService, "SelectedObject") ~= nil then
			unsupported "keyboard input while a GuiObject is selected"
		end
		env.fire(service, if value.down then "InputBegan" else "InputEnded", object, false)
		local sunk: number? = nil
		for _, entry in boundActions(code) do
			local priority = Values.number(env.propertyOf(entry.context, "Priority"))
			if sunk and priority < sunk then
				break
			end
			if actionStates[entry.action] ~= value.down then
				actionStates[entry.action] = value.down
				env.fire(entry.action, if value.down then "Pressed" else "Released")
				env.fire(entry.action, "StateChanged", value.down)
			end
			if env.propertyOf(entry.context, "Sink") == true then
				sunk = priority
			end
		end
	end
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
	local function createDevice(): Environment.Object
		local device = env.createEngineObject "VirtualInput"
		table.insert(owned, device)
		install(device, "SendMousePosition", function(_self: Environment.Object, at: Position)
			move(at, hits(at, "movement"))
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
				send(at, down)
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
		if not closed then
			local objects = hits(position, "movement")
			local retained: { Instance } = {}
			for _, object in hovered do
				if table.find(objects, object) then
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
		pointer = function(value: Pointer)
			local current = pointer(value)
			if current.button ~= "left" then
				unsupported "non-left mouse button"
			end
			send({ X = current.x, Y = current.y }, current.down, true)
		end,
		close = function()
			if closed then
				return
			end
			closed = true
			frame:Disconnect()
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
