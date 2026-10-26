--!strict

local source = [==[
local RS = game:GetService('ReplicatedStorage')
local server = game:GetService('RunService'):IsServer()
local name = if server then 'VerifyEngineLogsServer' else 'VerifyEngineLogsClient'
if RS:FindFirstChild(name) then return 'logging' end
local logs = game:GetService('LogService')
local rows = {}
local function receive(message, kind)
    kind = tostring(kind)
    if kind ~= 'Enum.MessageType.MessageError' and kind ~= 'Enum.MessageType.MessageWarning' then return end
    local source, line = string.match(message, '^(.-):(%d+):')
    local logger = string.match(message, '^%[Roblox%]%[([^%]]+)%]')
    if logger then source, line = logger, nil end
    local root = source and string.match(source, '^([^%.:/]+)')
    if root == 'CorePackages' or root == 'CoreGui' or root == 'ScriptContext' or root == 'Script Context' then return end
    table.insert(rows, {message = message, kind = kind, source = source, line = tonumber(line), actor = if server then 'server' else 'client'})
end
for _, entry in logs:GetLogHistory() do receive(entry.message, entry.messageType) end
logs.MessageOut:Connect(receive)
local function drain()
    task.wait()
    local out = rows
    rows = {}
    return out
end
local localDrain = Instance.new('BindableFunction')
localDrain.Name = name
localDrain.Parent = RS
if server then
    local remote = Instance.new('RemoteFunction')
    remote.Name = 'VerifyEngineLogs'
    remote.Parent = RS
    local function collect()
        local out = drain()
        for _, player in game:GetService('Players'):GetPlayers() do
            local values = remote:InvokeClient(player)
            for _, row in values do
                row.actor = 'client-' .. player.UserId
                table.insert(out, row)
            end
        end
        return out
    end
    localDrain.OnInvoke = collect
    remote.OnServerInvoke = function() return collect() end
else
    local remote = RS:WaitForChild('VerifyEngineLogs', 10)
    assert(remote, 'server log collector is unavailable')
    remote.OnClientInvoke = drain
    localDrain.OnInvoke = function() return remote:InvokeServer() end
end
return 'logging'
]==]

local drain =
	"function() local RS = game:GetService('ReplicatedStorage'); local name = if game:GetService('RunService'):IsServer() then 'VerifyEngineLogsServer' else 'VerifyEngineLogsClient'; return RS:WaitForChild(name, 10):Invoke() end"

local install = "for _, spec in {{'Script', game:GetService('ServerScriptService')}, {'LocalScript', game:GetService('StarterPlayer').StarterPlayerScripts}} do local script = Instance.new(spec[1]); script.Name = 'VerifyEngineLogCollector'; script.Source = "
	.. string.format("%q", source)
	.. "; script.Parent = spec[2] end return 'installed'"

return { source = source, drain = drain, install = install }
