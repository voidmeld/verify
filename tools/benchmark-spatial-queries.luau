--!strict

local Lute = require "../src/lute"
local Queries = require "../src/roblox/spatial-query-fakes"

local engine = Lute.fixture.bridge().placeEngine()
local world = engine.service "Workspace"
local V, CF = engine.datatypes.Vector3, engine.datatypes.CFrame
for i = 0, 4999 do
	local part = engine.newInstance "Part"
	part.Size = V.new(4, 2, 4)
	part.CFrame = CF.new((i % 100) * 16, 0, math.floor(i / 100) * 16)
	part.Parent = world
end
local ray = engine.environment.method(world, "Raycast")
local started = os.clock()
local hits, distance = 0, 0
for i = 0, 9999 do
	local index = (i * 7919) % 5000
	local result = ray(world, V.new((index % 100) * 16, 20, math.floor(index / 100) * 16), V.new(0, -40, 0))
	if result ~= nil then
		hits += 1
		distance += Queries.expectResult(result).Distance
	end
end
print(
	string.format(
		"parts=5000 rays=10000 hits=%d distance=%.0f query_seconds=%.6f",
		hits,
		distance,
		os.clock() - started
	)
)
