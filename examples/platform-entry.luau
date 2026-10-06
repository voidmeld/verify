--!strict

local Core = require "../src/core"
local Roblox = require "../src/roblox"
local case = require "./instance-case"

return function(host: Roblox.CaseHostName): Roblox.CaseEntry
	local environment: { [string]: string } = { runtime = host :: string }
	if host ~= "simulator" then
		local engine = Roblox.experienceHost.nativeEngine()
		environment.context = engine.context
		environment.placeId = tostring(engine.placeId)
		environment.gameId = tostring(engine.gameId)
		environment.version = engine.version
		environment.studio = tostring(engine.studio)
	end
	return {
		cases = { case },
		now = os.clock,
		options = {
			executor = host,
			capabilities = case.requires,
			environment = environment,
			bind = function(_context: Core.Context): Core.CaseHost
				return if host == "simulator"
					then Roblox.instanceHost.simulated("server").host
					else Roblox.instanceHost.native("server").host
			end,
		},
	}
end
