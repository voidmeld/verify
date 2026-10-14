--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local system = require "@std/system"

export type Install = { studio: string, mcp: string }

local MACOS: Install = {
	studio = "/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio",
	mcp = "/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP",
}

local function newest(versions: string): string?
	local listed, entries = pcall(fs.listDirectory, versions)
	if not listed then
		return nil
	end
	local chosen: string? = nil
	local chosenAge = -math.huge
	for _, entry in entries :: { fs.DirectoryEntry } do
		local directory = versions .. "/" .. entry.name
		local executable = directory .. "/RobloxStudioBeta.exe"
		if entry.type == "dir" and fs.exists(executable) then
			local read, metadata = pcall(fs.metadata, executable)
			local modified = if read then (metadata :: fs.FileMetadata).modified:toSeconds() else 0
			if chosen == nil or modified > chosenAge then
				chosen = directory
				chosenAge = modified
			end
		end
	end
	return chosen
end

local function windows(localAppData: string?): (Install?, string?)
	if localAppData == nil or localAppData == "" then
		return nil, "LOCALAPPDATA is not set, so the Roblox Studio installation cannot be found"
	end
	local versions = (string.gsub(localAppData, "\\", "/")) .. "/Roblox/Versions"
	local directory = newest(versions)
	if directory == nil then
		return nil,
			("no RobloxStudioBeta.exe exists under %s; pass studioExecutable and mcpExecutable"):format(versions)
	end
	return { studio = directory .. "/RobloxStudioBeta.exe", mcp = directory .. "/StudioMCP.exe" }, nil
end

local function locate(): (Install?, string?)
	if system.win32 then
		return windows(process.env.LOCALAPPDATA)
	end
	return MACOS, nil
end

return { locate = locate, windows = windows, MACOS = MACOS }
