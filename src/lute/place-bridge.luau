--!strict

local task = require "@std/task"

export type Reply = { ok: boolean, text: string?, detail: string? }
export type Execute = (datamodel: string, source: string) -> Reply
export type Options = { execute: Execute, context: string, text: string, deadlineSeconds: number? }
export type Outcome = { ok: boolean, text: string?, detail: string? }

local PREFIX = "VerifyBridge"
local SEGMENT_BYTES = 100000
local MARK = "verify-bridge:"
local INLINE_WAIT_SECONDS = 5
local counter = 0

local function scriptSource(module: string): string
	return "local MODULE = function() return require("
		.. module
		.. ") end\nlocal PREFIX = "
		.. string.format("%q", PREFIX)
		.. "\nlocal SIZE = "
		.. tostring(SEGMENT_BYTES)
		.. [==[

local RS = game:GetService('ReplicatedStorage')
local context = if game:GetService('RunService'):IsServer() then 'Server' else 'Client'
local F = Instance.new('Folder')
F.Name = PREFIX .. context
local handler = nil
local function handle(id, text)
	local ok, result = pcall(function()
		handler = handler or MODULE()
		return handler.call(text)
	end)
	local out = tostring(result)
	local R = Instance.new('Folder')
	R.Name = id
	local count = 0
	for index = 1, math.max(#out, 1), SIZE do
		count += 1
		local value = Instance.new('StringValue')
		value.Name = 'p' .. count
		value.Value = string.sub(out, index, index + SIZE - 1)
		value.Parent = R
	end
	R:SetAttribute('ok', ok)
	R:SetAttribute('count', count)
	R.Parent = F
	R:SetAttribute('state', 'done')
end
F:GetAttributeChangedSignal('request'):Connect(function()
	local raw = F:GetAttribute('request')
	if type(raw) ~= 'string' then
		return
	end
	local id, text = string.match(raw, '^(%w+)\n(.*)$')
	if id ~= nil and F:FindFirstChild(id) == nil then
		task.spawn(handle, id, text)
	end
end)
F:GetAttributeChangedSignal('ack'):Connect(function()
	local id = F:GetAttribute('ack')
	local R = if type(id) == 'string' then F:FindFirstChild(id) else nil
	if R ~= nil then
		R:Destroy()
	end
end)
F.Parent = RS
]==]
end

local function folder(context: string): string
	return "local F = game:GetService('ReplicatedStorage'):WaitForChild("
		.. string.format("%q", PREFIX .. context)
		.. ", 10)\nif F == nil then return '"
		.. MARK
		.. "missing' end\n"
end

local function marked(reply: Reply, what: string): (string?, string?)
	if not reply.ok then
		return nil, ("the bridge %s call failed: %s"):format(what, tostring(reply.detail))
	end
	local text = reply.text or ""
	local start = string.find(text, MARK, 1, true)
	if start == nil then
		return nil, ("the bridge %s call returned no bridge reply: %s"):format(what, string.sub(text, 1, 300))
	end
	return string.sub(text, start + #MARK), nil
end

local function call(options: Options): Outcome
	counter += 1
	local id = ("r%d%d"):format(counter, math.random(100000, 999999))
	local deadline = os.clock() + (options.deadlineSeconds or 120)
	local function run(source: string, what: string): (string?, string?)
		return marked(options.execute(options.context, folder(options.context) .. source), what)
	end
	local wait = math.max(0, math.min(INLINE_WAIT_SECONDS, deadline - os.clock()))
	local sent, problem = run(
		"F:SetAttribute('request', "
			.. string.format("%q", id .. "\n" .. options.text)
			.. ")\nlocal ID = "
			.. string.format("%q", id)
			.. "\nlocal started = os.clock()\nlocal R = F:FindFirstChild(ID)\nwhile (R == nil or R:GetAttribute('state') ~= 'done') and os.clock() - started < "
			.. tostring(wait)
			.. " do\n\ttask.wait()\n\tR = F:FindFirstChild(ID)\nend\nif R == nil or R:GetAttribute('state') ~= 'done' then return '"
			.. MARK
			.. "sent' end\nlocal head = '"
			.. MARK
			.. "' .. (if R:GetAttribute('ok') then 'ok ' else 'error ') .. tostring(R:GetAttribute('count'))\nif R:GetAttribute('count') ~= 1 then return head end\nlocal text = R:FindFirstChild('p1').Value\nF:SetAttribute('ack', ID)\nreturn head .. '\\n' .. text",
		"request"
	)
	if sent == nil or sent == "missing" then
		return {
			ok = false,
			detail = problem or "the place has no " .. PREFIX .. options.context .. " bridge",
		}
	end
	local inlineStatus, inlineText = string.match(sent, "^(%a+) 1\n(.*)$")
	if inlineStatus ~= nil and inlineText ~= nil then
		if inlineStatus ~= "ok" then
			return { ok = false, text = inlineText, detail = "the bridge module raised: " .. inlineText }
		end
		return { ok = true, text = inlineText }
	end
	local state: string? = if sent ~= "sent" then sent else nil
	while state == nil do
		state, problem = run(
			"local R = F:FindFirstChild("
				.. string.format("%q", id)
				.. ")\nif R == nil or R:GetAttribute('state') ~= 'done' then return '"
				.. MARK
				.. "waiting' end\nreturn '"
				.. MARK
				.. "' .. (if R:GetAttribute('ok') then 'ok ' else 'error ') .. tostring(R:GetAttribute('count'))",
			"poll"
		)
		if state == nil then
			return { ok = false, detail = problem }
		end
		if state ~= "waiting" then
			break
		end
		state = nil
		if os.clock() >= deadline then
			return { ok = false, detail = "the bridge did not answer before its deadline" }
		end
		task.wait(0.05)
	end
	local status, count = string.match(assert(state), "^(%a+) (%d+)$")
	if status == nil then
		return { ok = false, detail = "the bridge returned an invalid state: " .. tostring(state) }
	end
	local parts: { string } = {}
	for index = 1, assert(tonumber(count)) do
		local part, failed = run(
			"local R = F:FindFirstChild("
				.. string.format("%q", id)
				.. ")\nreturn '"
				.. MARK
				.. "' .. R:FindFirstChild('p"
				.. tostring(index)
				.. "').Value",
			"read"
		)
		if part == nil then
			return { ok = false, detail = failed }
		end
		table.insert(parts, part)
	end
	run("F:SetAttribute('ack', " .. string.format("%q", id) .. ")\nreturn '" .. MARK .. "acknowledged'", "acknowledge")
	local text = table.concat(parts)
	if status ~= "ok" then
		return { ok = false, text = text, detail = "the bridge module raised: " .. text }
	end
	return { ok = true, text = text }
end

return { call = call, scriptSource = scriptSource, PREFIX = PREFIX, SEGMENT_BYTES = SEGMENT_BYTES }
