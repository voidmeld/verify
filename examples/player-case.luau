--!strict

local Core = require "../src/core"
local Player = require "../src/roblox/player-host"

local case: Core.NamedCase = {
	id = "player-motion",
	name = "a live player jumps and returns to the floor",
	requires = { "native-physics", "action:player.jump", "query:player.state" },
	timeoutSeconds = 12,
	run = function(context: Core.Context)
		local start = context:perform("client", Player.inspect, nil)
		context:expect(start.health > 0):toBe(true)
		context:perform("client", Player.jump, nil)
		context:await("client", Player.inspect, nil, function(state)
			return state.position.y > start.position.y + 1
		end, 0.05)
		context:await("client", Player.inspect, nil, function(state)
			return math.abs(state.position.y - start.position.y) < 0.5 and math.abs(state.velocity.y) < 1
		end, 0.05)
	end,
}
return case
