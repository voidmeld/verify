--!strict

local Core = require "../src/core"
local Roblox = require "../src/roblox"

local LOG = "line one\nline two\n"

local function case(id: string, run: (context: Core.Context) -> ()): Core.NamedCase
	return { name = id, id = id, run = run }
end

return function(host: Roblox.CaseHostName): Roblox.CaseEntry
	return {
		cases = {
			case("attach-ok", function(context)
				context:attach("logs/run.txt", "text/plain", LOG)
				context:attach("summary.json", "application/json", '{"lines":2}')
			end),
			case("attach-large", function(context)
				context:attach("large.txt", "text/plain", string.rep("0123456789abcdef", 19200))
			end),
			case("attach-too-large", function(context)
				context:attach("huge.txt", "text/plain", string.rep("x", 1048577))
			end),
			case("attach-duplicate", function(context)
				context:attach("same.txt", "text/plain", "a")
				context:attach("same.txt", "text/plain", "b")
			end),
			case("attach-unsafe", function(context)
				context:attach("../escape.txt", "text/plain", "a")
			end),
			case("attach-binary", function(context)
				context:attach("blob.txt", "text/plain", "ok\255\254")
			end),
		},
		now = os.clock,
		options = {
			executor = host,
			capabilities = {},
			environment = { runtime = host :: string },
			bind = function(_context: Core.Context): Core.CaseHost
				return Roblox.instanceHost.simulated("server").host
			end,
		},
	}
end
