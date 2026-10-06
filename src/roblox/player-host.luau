--!strict
--!nolint DeprecatedApi

local Operations = require "../core/operations"
local Native = require "./experience-host"

export type Vector = { x: number, y: number, z: number }
export type State = { position: Vector, velocity: Vector, health: number, maximumHealth: number, equipped: string? }
export type Backend = { move: (Vector) -> (), jump: () -> (), equip: (string) -> (), state: () -> State }

local function finite(value: unknown): number
	assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "expected finite number")
	return value
end
local function vector(value: unknown): Vector
	assert(type(value) == "table", "expected vector record")
	local fields = value :: { [string]: unknown }
	return { x = finite(fields.x), y = finite(fields.y), z = finite(fields.z) }
end
local function empty(value: unknown): nil
	assert(value == nil, "expected no value")
	return nil
end
local function text(value: unknown): string
	assert(type(value) == "string" and value ~= "", "expected nonempty tool name")
	return value
end
local function state(value: unknown): State
	assert(type(value) == "table", "expected player state")
	local fields = value :: { [string]: unknown }
	assert(fields.equipped == nil or type(fields.equipped) == "string", "invalid equipped tool")
	return {
		position = vector(fields.position),
		velocity = vector(fields.velocity),
		health = finite(fields.health),
		maximumHealth = finite(fields.maximumHealth),
		equipped = fields.equipped :: string?,
	}
end
local move = Operations.operation { kind = "action", name = "player.move", input = vector, output = empty }
local jump = Operations.operation { kind = "action", name = "player.jump", input = empty, output = empty }
local equip = Operations.operation { kind = "action", name = "player.equip", input = text, output = empty }
local inspect = Operations.operation { kind = "query", name = "player.state", input = empty, output = state }

local function registry(backend: Backend): Native.Registry
	return {
		actions = {
			[move.name] = Operations.bind(move, function(value)
				backend.move(value)
				return nil
			end),
			[jump.name] = Operations.bind(jump, function()
				backend.jump()
				return nil
			end),
			[equip.name] = Operations.bind(equip, function(value)
				backend.equip(value)
				return nil
			end),
		},
		queries = { [inspect.name] = Operations.bind(inspect, function()
			return backend.state()
		end) },
	}
end

type EngineVector = { X: number, Y: number, Z: number }
type Node = {
	Name: string,
	Position: EngineVector,
	AssemblyLinearVelocity: EngineVector,
	Health: number,
	MaxHealth: number,
	Jump: boolean,
	ChangeState: (Node, unknown) -> (),
	FindFirstChild: (Node, string) -> Node?,
	FindFirstChildOfClass: (Node, string) -> Node?,
	GetChildren: (Node) -> { Node },
	IsA: (Node, string) -> boolean,
	Move: (Node, EngineVector, boolean) -> (),
	EquipTool: (Node, Node) -> (),
}
type Player = { Character: Node?, FindFirstChild: (Player, string) -> Node? }
type Players = { LocalPlayer: Player? }
type Globals = {
	Enum: { HumanoidStateType: { Jumping: unknown } },
	game: { GetService: (unknown, string) -> Players },
	Vector3: { new: (number, number, number) -> EngineVector },
	task: { wait: (number) -> number },
}

local function native(actor: string): Operations.Host
	local engine = Native.nativeEngine()
	assert(engine.context == "client", "player host requires the live client")
	local globals = (getfenv(0) :: unknown) :: Globals
	local player = globals.game:GetService("Players").LocalPlayer
	assert(player ~= nil, "local player is unavailable")
	local localPlayer = player :: Player
	local function character(): Node
		assert(localPlayer.Character ~= nil, "player character is unavailable")
		return localPlayer.Character :: Node
	end
	local function humanoid(): Node
		local found = character():FindFirstChildOfClass "Humanoid"
		assert(found ~= nil, "player humanoid is unavailable")
		return found :: Node
	end
	local function read(value: EngineVector): Vector
		return { x = value.X, y = value.Y, z = value.Z }
	end
	local backend: Backend = {
		move = function(value)
			assert(
				value.x * value.x + value.y * value.y + value.z * value.z <= 1.000001,
				"movement direction exceeds unit length"
			)
			humanoid():Move(globals.Vector3.new(value.x, value.y, value.z), false)
		end,
		jump = function()
			humanoid():ChangeState(globals.Enum.HumanoidStateType.Jumping)
		end,
		equip = function(name)
			local backpack = localPlayer:FindFirstChild "Backpack"
			assert(backpack ~= nil, "player backpack is unavailable")
			local matches: { Node } = {}
			for _, child in (backpack :: Node):GetChildren() do
				if child.Name == name and child:IsA "Tool" then
					table.insert(matches, child)
				end
			end
			assert(#matches == 1, "tool name must select exactly one backpack tool")
			humanoid():EquipTool(matches[1])
		end,
		state = function()
			local rig = character()
			local root = rig:FindFirstChild "HumanoidRootPart"
			assert(root ~= nil, "player root is unavailable")
			local body = humanoid()
			local tool = rig:FindFirstChildOfClass "Tool"
			return {
				position = read((root :: Node).Position),
				velocity = read((root :: Node).AssemblyLinearVelocity),
				health = body.Health,
				maximumHealth = body.MaxHealth,
				equipped = if tool then tool.Name else nil,
			}
		end,
	}
	local host = Native.create {
		engine = engine,
		actor = actor,
		actors = { [actor] = "client" },
		registry = registry(backend),
		capabilities = { "native-physics" },
		sleep = function(seconds)
			globals.task.wait(seconds)
		end,
	}
	host.close = function()
		if localPlayer.Character ~= nil then
			backend.move { x = 0, y = 0, z = 0 }
		end
	end
	return host
end

return { move = move, jump = jump, equip = equip, inspect = inspect, registry = registry, native = native }
