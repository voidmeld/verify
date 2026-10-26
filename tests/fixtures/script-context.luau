--!strict

local SOURCE = [=[
--!strict
script:SetAttribute(if game:GetService("RunService"):IsClient() then "ranClient" else "ranServer", true)
]=]

local ASSERTIONS = [==[
for _, service in {"Workspace", "ServerScriptService", "ReplicatedStorage", "ReplicatedFirst", "ServerStorage"} do
    if side == "Client" and (service == "ServerScriptService" or service == "ServerStorage") then
        continue
    end
    for _, name in {"Client", "Server", "DisabledClient", "DisabledServer", "Override"} do
        local object = assert(game:GetService(service):FindFirstChild(name), service .. "." .. name)
        local client = name:sub(-6) == "Client" or name == "Override"
        local modernScript = modern or name == "Override"
        local disabled = name:sub(1, 8) == "Disabled"
        local label = service .. "." .. name
        assert(object.ClassName == (if not modernScript and client then "LocalScript" else "Script"), label .. " class")
        if object:IsA("Script") then
            assert(object.RunContext.Name == (if not modernScript then "Legacy" elseif client then "Client" else "Server"), label .. " context")
        end
        local serverLocation = modernScript or service == "Workspace" or service == "ServerScriptService"
        local clientLocation = service == "ReplicatedFirst" or (modernScript and (service == "Workspace" or service == "ReplicatedStorage"))
        local ranServer = not client and not disabled and serverLocation
        local ranClient = side == "Client" and client and not disabled and clientLocation
        assert((object:GetAttribute("ranServer") == true) == ranServer, label .. " server execution")
        assert((object:GetAttribute("ranClient") == true) == ranClient, label .. " client execution")
    end
end
return true
]==]

local SERVICES = { "Workspace", "ServerScriptService", "ReplicatedStorage", "ReplicatedFirst", "ServerStorage" }
local NAMES = { "Client", "Server", "DisabledClient", "DisabledServer" }
local SOURCES: { [string]: string } = { ["run.client.luau"] = SOURCE, ["run.server.luau"] = SOURCE }
local function project(legacy: boolean?)
	local tree: { [string]: unknown } = { ["$className"] = "DataModel" }
	for _, service in SERVICES do
		local node: { [string]: unknown } = { ["$className"] = service }
		for _, name in NAMES do
			local kind = if name:sub(-6) == "Client" then "client" else "server"
			node[name] = {
				["$path"] = "run." .. kind .. ".luau",
				["$properties"] = if name:sub(1, 8) == "Disabled" then { Disabled = true } else nil,
			}
		end
		node.Override = { ["$path"] = "run.server.luau", ["$properties"] = { RunContext = "Client" } }
		tree[service] = node
	end
	return { name = "VerifyScriptContext", emitLegacyScripts = legacy, tree = tree }
end

return table.freeze {
	project = project,
	assertions = ASSERTIONS,
	sources = SOURCES,
	services = SERVICES,
	names = NAMES,
}
