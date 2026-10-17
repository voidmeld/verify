--!strict
local Mcp = require "./studio-mcp"
export type Identity = { placeId: number, universeId: number }
local Identity = {}
function Identity.read(value: unknown): Identity
	assert(type(value) == "table", "Studio identity requires placeId and universeId")
	local fields = Mcp.record(value)
	local placeId, universeId: unknown = nil, nil
	for key, field in fields do
		assert(key == "placeId" or key == "universeId", "Unknown Studio identity field")
		if key == "placeId" then
			placeId = field
		else
			universeId = field
		end
	end
	local function id(field: unknown): number
		assert(
			type(field) == "number" and field >= 1 and field <= 9007199254740991 and field % 1 == 0,
			"Studio identity IDs must be positive safe integers"
		)
		return field
	end
	return { placeId = id(placeId), universeId = id(universeId) }
end
function Identity.source(value: Identity): string
	local identity = Identity.read(value)
	local place, universe = string.format("%.0f", identity.placeId), string.format("%.0f", identity.universeId)
	return "assert(game:GetService('RunService'):IsStudio(), 'Studio identity requires Studio'); game:SetPlaceId("
		.. place
		.. "); game:SetUniverseId("
		.. universe
		.. "); assert(game.PlaceId == "
		.. place
		.. " and game.GameId == "
		.. universe
		.. ", 'Studio identity readback failed'); return 'verify-studio-identity-ok'"
end
return Identity
