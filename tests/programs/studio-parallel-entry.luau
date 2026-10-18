--!strict
--!nolint DeprecatedApi

local Core = require "../../src/core"
local Roblox = require "../../src/roblox"

type Storage = {
	GetAttribute: (Storage, string) -> unknown,
	SetAttribute: (Storage, string, unknown) -> (),
}
type Globals = {
	game: { GetService: (unknown, string) -> unknown },
	task: { wait: (number) -> () },
}

local factory: Roblox.CaseEntryFactory = function(host, runId)
	assert(host == "studio" and runId ~= nil, "this fixture requires a Studio run")
	local globals = (getfenv(0) :: unknown) :: Globals
	local storage = globals.game:GetService "ReplicatedStorage" :: Storage
	local case: Core.NamedCase = {
		id = "parallel-lifetime",
		name = "one case survives MCP replacement in its own Studio",
		timeoutSeconds = 45,
		run = function(context: Core.Context)
			local token = storage:GetAttribute "VerifyRun"
			context:expect(type(token) == "string" and #token > 0 and #token <= 50):toBe(true)
			context:expect(storage:GetAttribute "VerifyParallelStarts"):toBe(nil)
			storage:SetAttribute("VerifyParallelStarts", 1)
			context:step("hold for MCP replacement", function()
				globals.task.wait(30)
			end)
			context:expect(storage:GetAttribute "VerifyParallelStarts"):toBe(1)
			context:expect(storage:GetAttribute "VerifyRun"):toBe(token)
		end,
	}
	return { cases = { case }, now = os.clock, options = { executor = "roblox-studio" } }
end

return factory
