--!strict

local Core = require "../../src/core"
local Roblox = require "../../src/roblox"
local Input = Roblox.inputHost
local function empty(value: unknown): nil
	assert(value == nil)
	return nil
end
local counter = Core.operation {
	kind = "query",
	name = "counter",
	input = empty,
	output = function(value: unknown): number
		assert(type(value) == "number")
		return value
	end,
}
local button = Core.operation {
	kind = "query",
	name = "button",
	input = empty,
	output = function(value: unknown): { x: number, y: number }
		assert(type(value) == "table")
		local fields = value :: { [string]: unknown }
		assert(type(fields.x) == "number" and type(fields.y) == "number")
		return { x = fields.x, y = fields.y }
	end,
}
return function(sleep: (number) -> (), limitations: { string }): Core.NamedCase
	return {
		id = "multiplayer-ui",
		name = "UI reaches server and second client",
		timeoutSeconds = 30,
		limitations = limitations,
		run = function(context: Core.Context)
			local position = context:perform("client-1", button, nil)
			context:perform("client-1", Input.pointer, { x = position.x, y = position.y, button = "left", down = true })
			sleep(0.1)
			context:perform(
				"client-1",
				Input.pointer,
				{ x = position.x, y = position.y, button = "left", down = false }
			)
			context:await("server", counter, nil, function(value)
				return value == 1
			end, 0.05)
			context:await("client-2", counter, nil, function(value)
				return value == 1
			end, 0.05)
			context:checkpoint("client-1", "shared-state-1")
			context:checkpoint("client-2", "shared-state-2")
		end,
	}
end
