--!strict

local Types = require "./place-types"
local Frames = require "./datatypes/cframe"
local Datatypes = require "./datatypes"
local Enums = require "./datatypes/enum"
type Instance = Types.Instance

local function load(engine: Types.Engine, player: Instance): Instance
	assert(
		player:IsA "Player" and player.Parent == engine.service "Players",
		"character loading requires a connected player"
	)
	local environment = engine.environment
	local previous = player.Character
	if previous ~= nil then
		local old = environment.assertInstance(previous)
		environment.fire(player, "CharacterRemoving", old)
		old:Destroy()
	end
	local template = engine.service("StarterPlayer"):FindFirstChild "StarterCharacter"
	local character: Instance
	if template ~= nil then
		assert(template:IsA "Model", "StarterCharacter must be a Model")
		character = assert(template:Clone(), "StarterCharacter must be archivable")
	else
		character = engine.newInstance "Model"
		for _, name in { "HumanoidRootPart", "Head" } do
			local part = engine.newInstance "Part"
			part.Name, part.Parent = name, character
		end
		local humanoid = engine.newInstance "Humanoid"
		humanoid.Parent = character
		local animator = engine.newInstance "Animator"
		animator.Parent = humanoid
	end
	character.Name = player.Name
	local root = assert(character:FindFirstChild "HumanoidRootPart", "character requires HumanoidRootPart")
	assert(root:IsA "BasePart", "character root must be a BasePart")
	character.PrimaryPart = root
	environment.poke(player, "Character", character)
	environment.fire(player, "CharacterAdded", character)
	environment.fire(player, "CharacterAppearanceLoaded", character)
	character.Parent = engine.service "Workspace"
	local spawn = player.RespawnLocation
	if spawn ~= nil then
		local location = environment.assertInstance(spawn)
		assert(location:IsA "SpawnLocation", "RespawnLocation must be a SpawnLocation")
		environment.method(character, "PivotTo")(
			character,
			Frames.expect(location.CFrame, 2) * engine.datatypes.CFrame.new(0, 3, 0)
		)
	end
	return character
end

local function replace(engine: Types.Engine, humanoid: Instance, bodyPart: unknown, replacement: Instance): boolean
	assert(Datatypes.enumType(bodyPart) == "BodyPartR15", "body part must be a BodyPartR15")
	assert(replacement:IsA "BasePart", "replacement must be a BasePart")
	local name = Enums.itemValue(bodyPart).Name
	if name == "Unknown" then
		return false
	end
	local character = humanoid.Parent
	if character == nil or not character:IsA "Model" then
		return false
	end
	local previous = character:FindFirstChild(name)
	if previous == nil or not previous:IsA "BasePart" then
		return false
	end
	assert(replacement.Name == name, "replacement name must match the body part")
	local environment = engine.environment
	environment.poke(replacement, "CFrame", previous.CFrame)
	for _, node in character:GetDescendants() do
		if node:IsA "JointInstance" or node:IsA "WeldConstraint" then
			for _, key in { "Part0", "Part1" } do
				if environment.propertyOf(node, key) == previous then
					environment.poke(node, key, replacement)
				end
			end
		end
	end
	if character.PrimaryPart == previous then
		character.PrimaryPart = replacement
	end
	replacement.Parent = character
	previous:Destroy()
	return true
end

return { load = load, replace = replace }
