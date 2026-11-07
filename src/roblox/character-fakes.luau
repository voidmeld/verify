--!strict

local Types = require "./place-types"
type Instance = Types.Instance

local function load(engine: Types.Engine, player: Instance): Instance
	assert(
		player:IsA "Player" and player.Parent == engine.service "Players",
		"character loading requires a connected player"
	)
	local environment = engine.environment
	local previous = player.Character
	if previous ~= nil then
		assert(engine.isInstance(previous), "player character must be an instance")
		environment.fire(player, "CharacterRemoving", previous)
		previous:Destroy()
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
	local spawn = player.RespawnLocation
	if spawn ~= nil then
		assert(engine.isInstance(spawn) and spawn:IsA "SpawnLocation", "RespawnLocation must be a SpawnLocation")
		character:PivotTo(spawn.CFrame * engine.datatypes.CFrame.new(0, 3, 0))
	end
	character.Parent = engine.service "Workspace"
	environment.poke(player, "Character", character)
	environment.fire(player, "CharacterAdded", character)
	return character
end

return { load = load }
