--!strict
--!nolint DeprecatedApi

local Core = require "../core"
local Native = require "./experience-host"
local Environment = require "./environment"
local Layout = require "./ui-layout"
local Datatypes = require "./datatypes"

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
	return { x = record.x, y = record.y, button = record.button :: "left" | "right" | "middle", down = record.down }
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
	local globals = (
		getfenv(0) :: unknown
	) :: { game: { GetService: (unknown, string) -> { GetGuiInset: (unknown) -> (Vector, Vector) } } }
	local inset = globals.game:GetService("GuiService"):GetGuiInset()
	assert(target.AbsoluteSize.X > 0 and target.AbsoluteSize.Y > 0, "GUI target has no rendered area")
	return {
		x = target.AbsolutePosition.X + target.AbsoluteSize.X / 2 + inset.X,
		y = target.AbsolutePosition.Y + target.AbsoluteSize.Y / 2 + inset.Y,
	}
end

local function native(): Backend?
	assert(Native.nativeEngine().context == "client", "virtual input requires a live client")
	local globals = (getfenv(0) :: unknown) :: Globals
	local service = globals.game:GetService "UserInputService"
	local input = service:CreateVirtualInput()
	if input == nil then
		return nil
	end
	local device = input :: VirtualInput
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
	type Activation = { released: number, count: number }
	local activations = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: Activation }
	local owned: { Environment.Object } = {}
	local registrations: { () -> () } = {}
	local function install<O, A..., R...>(object: O, name: string, handler: (O, A...) -> R...)
		table.insert(registrations, env.fakeOn(object, name, handler))
	end
	local movement: Instance? = nil
	local buttonInput: Instance? = nil
	local lastInput: unknown = inputTypes.MouseMovement
	local function unsupported(reason: string)
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
	local function hits(at: Position): { Instance }
		ensureOpen()
		local function validate(object: Instance)
			if object:IsA "StyleLink" and options.read == nil then
				unsupported "StyleLink without effective input properties"
			end
			if object:IsA "UIDragDetector" or object:IsA "InputContext" then
				unsupported(object.ClassName)
			end
			for _, child in object:GetChildren() do
				validate(child)
			end
		end
		validate(gui)
		layout.step()
		local inset = options.inset()
		local result: { Instance } = {}
		for _, object in layout.objectsAtPosition(gui, at.X - inset.X, at.Y - inset.Y) do
			if object:IsA "TextBox" then
				unsupported "TextBox focus and editing"
			end
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
	end
	local function send(at: Position, down: boolean, movePointer: boolean?)
		local objects = hits(at)
		local targets, targetButton = recipients(objects)
		assert(down ~= held, "VirtualInput::SendMouseButton: duplicate button state.")
		if not down and #targets > 0 then
			if #targets ~= #pressed then
				unsupported "release onto different input recipients"
			end
			for ordinal, object in targets do
				if object ~= pressed[ordinal] then
					unsupported "release onto different input recipients"
				end
			end
		end
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
			if targetButton then
				env.fire(targetButton, "MouseButton1Down", at.X, at.Y)
			end
			for _, target in targets do
				env.fire(target, "InputBegan", object)
			end
			env.fire(service, "InputBegan", object, processed(targets, true))
		else
			held = false
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
	end
	local function noKey(_value: Key)
		unsupported "keyboard input"
	end
	local function noText(_value: string)
		unsupported "text input"
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
			move(at, hits(at))
		end)
		install(
			device,
			"SendMouseButton",
			function(_self: Environment.Object, at: Position, kind: unknown, down: boolean, count: number)
				if kind ~= inputTypes.MouseButton1 then
					unsupported "non-left mouse button"
				end
				if count ~= 0 then
					unsupported "explicit activation count"
				end
				if at.X ~= position.X or at.Y ~= position.Y then
					unsupported "button coordinates without prior pointer movement"
				end
				send(at, down)
			end
		)
		install(device, "SendKey", function()
			unsupported "keyboard input"
		end)
		install(device, "SendTextInput", function()
			unsupported "text input"
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
	install(gui, "GetGuiObjectsAtPosition", function(_self: Instance, x: number, y: number): { Instance }
		ensureOpen()
		layout.step()
		return layout.objectsAtPosition(gui, x, y)
	end)
	local frame = env.heartbeat:Connect(function()
		if not closed then
			local objects = hits(position)
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
		key = noKey,
		text = noText,
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
