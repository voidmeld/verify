--!strict

local Environment = require "./environment"
local Datatypes = require "./datatypes"
local EnumTypes = require "./datatypes/enum"

type Instance = Environment.Instance
type Vector = { X: number, Y: number, Z: number }
local buttons = {
	Two = "DPadLeft",
	Three = "DPadDown",
	Four = "DPadRight",
	Seven = "ButtonY",
	Eight = "ButtonX",
	Nine = "ButtonA",
	Zero = "ButtonB",
	Q = "ButtonSelect",
	R = "ButtonL1",
	O = "ButtonR1",
	E = "ButtonL2",
	P = "ButtonR2",
	F = "ButtonL3",
	H = "ButtonR3",
}
local sticks = {
	W = "Thumbstick1",
	A = "Thumbstick1",
	S = "Thumbstick1",
	D = "Thumbstick1",
	I = "Thumbstick2",
	J = "Thumbstick2",
	K = "Thumbstick2",
	L = "Thumbstick2",
}
local controls = {
	"ButtonStart",
	"ButtonA",
	"ButtonSelect",
	"ButtonB",
	"ButtonX",
	"ButtonY",
	"ButtonL1",
	"ButtonR1",
	"ButtonL2",
	"ButtonR2",
	"ButtonL3",
	"ButtonUp",
	"ButtonR3",
	"ButtonLeft",
	"DPadUp",
	"DPadDown",
	"DPadLeft",
	"DPadRight",
	"Thumbstick1",
	"Thumbstick2",
	"ButtonCenter",
	"ButtonBack",
	"ButtonDown",
	"ButtonRight",
}

local function create(
	env: Environment.Environment,
	library: Datatypes.Library,
	input: (unknown) -> Instance,
	emit: (string, Instance) -> ()
)
	local states: { [string]: { Instance } } = {}
	local held: { [string]: boolean } = {}
	local function state(kind: unknown): { Instance }
		assert(EnumTypes.isItem(kind) and EnumTypes.enumType(kind) == "UserInputType", "expected Enum.UserInputType")
		local name = tostring(kind):match "([^%.]+)$" or ""
		if not name:match "^Gamepad[1-8]$" or kind ~= library.Enum.UserInputType:FromName(name) then
			return {}
		end
		local entries = states[name]
		if entries == nil then
			entries = {}
			for _, code in controls do
				local object = input(kind)
				env.poke(object, "KeyCode", library.Enum.KeyCode:FromName(code))
				env.poke(object, "UserInputState", library.Enum.UserInputState.End)
				table.insert(entries, object)
			end
			states[name] = entries
		end
		return table.clone(entries)
	end
	local function axis(positive: string, negative: string): number
		return (if held[positive] then 1 else 0) - (if held[negative] then 1 else 0)
	end
	local function key(code: string, down: boolean)
		if code == "One" or code == "Tab" then
			error(
				"VirtualInput::SendKey: key is permanently bound to a CoreGUI core action. VirtualInput cannot process this key.",
				0
			)
		end
		if code == "U" then
			error("unsupported_simulated_input: virtual controller system menu", 0)
		end
		local control = buttons[code] or sticks[code]
		if control == nil or (held[code] == true) == down then
			return
		end
		held[code] = down
		local object: Instance? = nil
		for _, candidate in state(library.Enum.UserInputType.Gamepad1) do
			if env.propertyOf(candidate, "KeyCode") == library.Enum.KeyCode:FromName(control) then
				object = candidate
				break
			end
		end
		local target = assert(object)
		local before = env.propertyOf(target, "Position") :: Vector
		local x, y, z = 0, 0, if down then 1 else 0
		if control == "Thumbstick1" then
			x, y, z = axis("D", "A"), axis("W", "S"), 0
		elseif control == "Thumbstick2" then
			x, y, z = axis("L", "J"), axis("I", "K"), 0
		end
		if before.X == x and before.Y == y and before.Z == z then
			return
		end
		env.poke(target, "Position", library.Vector3.new(x, y, z))
		env.poke(target, "Delta", library.Vector3.new(x - before.X, y - before.Y, z - before.Z))
		local analog = sticks[code] ~= nil
		local trigger = control == "ButtonL2" or control == "ButtonR2"
		if trigger then
			env.poke(target, "UserInputState", library.Enum.UserInputState.Change)
			emit("InputChanged", target)
			env.poke(target, "Delta", library.Vector3.zero)
		end
		local ended = x == 0 and y == 0 and z == 0
		local phase = if ended then "End" elseif analog then "Change" else "Begin"
		env.poke(target, "UserInputState", library.Enum.UserInputState:FromName(phase))
		emit(if ended then "InputEnded" elseif analog then "InputChanged" else "InputBegan", target)
	end
	return { state = state, key = key }
end

return { create = create }
