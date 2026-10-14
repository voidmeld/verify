--!strict

local Files = require "../../src/lute/files"
local Lute = require "../../src/lute"

export type Target = { studioId: string?, studioName: string?, mcp: string? }
export type Connection = { execute: Lute.FixtureExecute, close: () -> () }

local function connect(target: Target, directory: string): Connection
	local studioName = target.studioName
	local session, refusal = Lute.studio.attach {
		authorize = function(request: Lute.StudioRequest): Lute.StudioAuthorization
			local allowed = request.tool == "list_roblox_studios"
				or (request.tool == "execute_luau" and request.fields.datamodel_type == "Edit")
			return { ok = allowed, reason = if allowed then nil else "this tool only reads the edit data model" }
		end,
		studioId = target.studioId,
		match = if studioName ~= nil
			then function(info: Lute.StudioInfo): boolean
				return info.name == studioName
			end
			else nil,
		mcpExecutable = target.mcp,
		directory = Files.claimDirectory(directory),
		callSeconds = 120,
		runSeconds = 1800,
	}
	if session == nil then
		error(
			("cannot attach to Studio (%s): %s"):format(
				if refusal ~= nil then refusal.kind else "unknown",
				if refusal ~= nil then refusal.detail else "no detail"
			),
			0
		)
	end
	local attached = session :: Lute.StudioSession
	return {
		execute = function(code: string): string
			local response = attached.execute("Edit", code)
			if not response.ok or response.text == nil then
				error("Studio refused the request: " .. tostring(response.detail), 0)
			end
			return response.text :: string
		end,
		close = function()
			attached.close()
		end,
	}
end

local function run<T>(target: Target, directory: string, body: (Lute.FixtureExecute) -> T): T
	local connection = connect(target, directory)
	local ok, result = pcall(body, connection.execute)
	connection.close()
	if not ok then
		error(result, 0)
	end
	return result
end

return { connect = connect, run = run }
