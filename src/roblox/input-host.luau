--!strict
--!nolint DeprecatedApi

local Core = require "../core"
local Native = require "./experience-host"

export type Key = { code: string, down: boolean }
export type Pointer = { x: number, y: number, button: "left" | "right" | "middle", down: boolean }
export type Backend = { key: (Key) -> (), pointer: (Pointer) -> (), text: (string) -> (), close: () -> () }
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
return {
	screenCenter = screenCenter,
	key = keyOperation,
	pointer = pointerOperation,
	text = textOperation,
	registry = registry,
	native = native,
}
