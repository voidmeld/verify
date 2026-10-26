--!strict

local process = require "@std/process"
local Lute = require "../src/lute"

local id, action = process.args[2], process.args[3]
assert(
	id ~= nil and (action == "install" or action == "read"),
	"usage: lute run tools/logservice-spike.luau <studio-id> install|read"
)

local probe = [==[
local logs = game:GetService('LogService')
local http = game:GetService('HttpService')
local root = game:GetService('ReplicatedStorage'):WaitForChild('VerifyLogSpike')
local side = SIDE
local token = root:GetAttribute('token')
local result = {side = side, version = version(), calls = {}, events = {}, samples = {}, roundTrips = {}}
local function safe(value, depth)
    if (depth or 0) > 5 then return tostring(value) end
    if type(value) == 'table' then
        local copy = {}
        for key, child in value do copy[key] = safe(child, (depth or 0) + 1) end
        return copy
    end
    local ok = pcall(http.JSONEncode, http, value)
    return if ok then value else tostring(value)
end
local function attempt(name, body)
    local ok, value = pcall(body)
    result.calls[name] = {ok = ok, value = safe(value)}
    return ok, value
end
local connection
attempt('MessageOut', function()
    connection = logs.MessageOut:Connect(function(message, kind, context)
        if string.find(message, token, 1, true) and not string.find(message, ':retention:', 1, true) then
            table.insert(result.events, {message = message, kind = tostring(kind), context = safe(context)})
        end
    end)
    return 'connected'
end)
local ok, logger = attempt('GetLogger', function() return logs:GetLogger('VerifySpike') end)
if ok then
    for _, method in {'Info', 'Warn', 'Error', 'Output'} do
        attempt(method, function()
            logger[method](logger, token .. ':' .. side .. ':' .. method, {token = token, side = side, sequence = 1, payload = {caseId = 'spike', step = 'nested'}})
            return 'emitted'
        end)
    end
    attempt('Log', function()
        logger:Log(Enum.MessageType.MessageWarning, token .. ':' .. side .. ':Log', {token = token, side = side, sequence = 2})
        return 'emitted'
    end)
end
warn(token .. ':' .. side .. ':plain warning')
task.spawn(function() error(token .. ':' .. side .. ':script error') end)
task.wait(1)
attempt('historyBeforeFlood', function()
    local history = logs:GetLogHistory()
    result.before = #history
    for index, entry in history do
        if string.find(tostring(entry.message), token, 1, true) and not string.find(tostring(entry.message), ':retention:', 1, true) then
            table.insert(result.samples, {index = index, entry = safe(entry)})
        end
    end
    return #history
end)
for _, method in {'Info', 'Warn', 'Error', 'Output', 'Log'} do
    local suffix = ':' .. side .. ':' .. method
    local roundTrip = {messageOut = false, history = false}
    for _, event in result.events do
        local context = event.context
        if string.find(event.message, suffix, 1, true) and type(context) == 'table' then
            roundTrip.messageOut = context.token == token and context.side == side and type(context.sequence) == 'number'
            roundTrip.eventContext = context
        end
    end
    for _, sample in result.samples do
        local context = sample.entry.context
        if string.find(sample.entry.message, suffix, 1, true) and type(context) == 'table' then
            roundTrip.history = context.token == token and context.side == side and type(context.sequence) == 'number'
            roundTrip.historyContext = context
        end
    end
    result.roundTrips[method] = roundTrip
end
if side == 'Server' and ok then
    attempt('flood', function()
        for sequence = 1, 2048 do
            logger:Info(token .. ':retention:' .. sequence, {token = token, sequence = sequence, side = side})
        end
        return 2048
    end)
end
task.wait(2)
attempt('historyAfterFlood', function()
    local history = logs:GetLogHistory()
    result.after = #history
    result.first = safe(history[1])
    result.last = safe(history[#history])
    local retained = {count = 0, ascending = true, descending = true}
    for index, entry in history do
        local sequence = string.match(tostring(entry.message), ':retention:(%d+)$')
                if sequence then
            local n = tonumber(sequence)
            if retained.last then
                retained.ascending = retained.ascending and n > retained.last
                retained.descending = retained.descending and n < retained.last
            end
            retained.first = retained.first or n
            retained.last = n
            retained.count += 1
        end
    end
    result.retained = retained
    return #history
end)
if connection then connection:Disconnect() end
root:SetAttribute(side, http:JSONEncode(result))
return 'recorded ' .. side
]==]

local session, refusal = Lute.studio.attach {
	studioId = id,
	mode = if action == "read" then "play" else "edit",
	authorize = function(request)
		return { ok = request.tool == "list_roblox_studios" or request.tool == "execute_luau" }
	end,
}
assert(session ~= nil, if refusal then refusal.detail else "attach failed")
local opened = session
local function execute(model: string, code: string): string
	local response = opened.execute(model, code)
	assert(response.ok, response.detail)
	return response.text or ""
end
local ran, problem = pcall(function()
	if action == "install" then
		print(
			execute(
				"Edit",
				"local root = Instance.new('Folder'); root.Name = 'VerifyLogSpike'; assert(not game:GetService('ReplicatedStorage'):FindFirstChild(root.Name), 'remove the previous VerifyLogSpike first'); root:SetAttribute('token', game:GetService('HttpService'):GenerateGUID(false)); root.Parent = game:GetService('ReplicatedStorage'); "
					.. "local server = Instance.new('Script'); server.Name = 'VerifyLogSpikeServer'; server.Source = "
					.. string.format("%q", (string.gsub(probe, "SIDE", "'Server'")))
					.. "; server.Parent = game:GetService('ServerScriptService'); "
					.. "local client = Instance.new('LocalScript'); client.Name = 'VerifyLogSpikeClient'; client.Source = "
					.. string.format("%q", (string.gsub(probe, "SIDE", "'Client'")))
					.. "; client.Parent = game:GetService('StarterPlayer').StarterPlayerScripts; return 'installed; start Play, wait five seconds, then read'"
			)
		)
	else
		for _, model in { "Server", "Client" } do
			print(execute(model, (string.gsub(probe, "SIDE", string.format("%q", "Plugin" .. model)))))
			print(
				execute(
					model,
					"local http = game:GetService('HttpService'); local root = game:GetService('ReplicatedStorage').VerifyLogSpike; return http:JSONEncode({script = http:JSONDecode(root:GetAttribute("
						.. string.format("%q", model)
						.. ") or '{}'), plugin = http:JSONDecode(root:GetAttribute("
						.. string.format("%q", "Plugin" .. model)
						.. ") or '{}')})"
				)
			)
		end
	end
end)

opened.close()
assert(ran, tostring(problem))
