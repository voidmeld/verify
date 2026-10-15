--!strict

local Schema = require "./schema"
local Services = require "./services"
local Transcript = require "./transcript"

export type Request = {
	workspace: string,
	instructions: string?,
	allowedTools: { string }?,
	disallowedTools: { string }?,
	model: string?,
	options: { [string]: unknown },
}

local RESULT_LIMIT = 4000

local ESCAPES: { [string]: string } = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\b"] = "\\b",
	["\t"] = "\\t",
	["\n"] = "\\n",
	["\f"] = "\\f",
	["\r"] = "\\r",
}

local TOOL_ITEMS: { [string]: boolean } = {
	command_execution = true,
	file_change = true,
	mcp_tool_call = true,
	web_search = true,
	todo_list = true,
}

local function tomlString(text: string): string
	local escaped = string.gsub(text, '[%c"\\]', function(character: string): string
		return ESCAPES[character] or ("\\u%04X"):format(string.byte(character))
	end)
	return '"' .. escaped .. '"'
end

local function tomlList(values: { string }): string
	local items: { string } = {}
	for _, value in values do
		table.insert(items, tomlString(value))
	end
	return "[" .. table.concat(items, ", ") .. "]"
end

local function tomlTable(values: { [string]: string }): string
	local items: { string } = {}
	for _, key in Schema.sortedKeys(values) do
		table.insert(items, ("%s = %s"):format(tomlString(key), tomlString(values[key])))
	end
	return "{ " .. table.concat(items, ", ") .. " }"
end

local function config(argv: { string }, key: string, value: string)
	table.insert(argv, "-c")
	table.insert(argv, key .. "=" .. value)
end

local function mcpServers(argv: { string }, text: string, decode: (text: string) -> unknown)
	local label = "MCP configuration"
	local document = Schema.record(decode(text), label)
	local servers = Schema.record(document.mcpServers, label .. ".mcpServers")
	for _, name in Schema.sortedKeys(servers) do
		local server = Schema.record(servers[name], ("%s.mcpServers.%s"):format(label, name))
		if string.match(name, "^[%w_%-]+$") == nil then
			Schema.fail(label, ("the server name %q is not a bare configuration key"):format(name))
		end
		local prefix = "mcp_servers." .. name
		local command = Schema.optionalText(server.command, prefix .. ".command")
		local url = Schema.optionalText(server.url, prefix .. ".url")
		if command ~= nil then
			config(argv, prefix .. ".command", tomlString(command))
			local arguments = Schema.optionalTexts(server.args, prefix .. ".args")
			if arguments ~= nil then
				config(argv, prefix .. ".args", tomlList(arguments))
			end
			if server.env ~= nil then
				config(argv, prefix .. ".env", tomlTable(Schema.dictionary(server.env, prefix .. ".env")))
			end
		elseif url ~= nil then
			config(argv, prefix .. ".url", tomlString(url))
		else
			Schema.fail(label, ("the server %s has neither command nor url"):format(name))
		end
	end
end

local function arguments(request: Request, mcp: string?, decode: (text: string) -> unknown): { string }
	local label = "agent options"
	local options = request.options
	Schema.only(options, label, { "command", "effort", "sandbox", "persistSession", "config", "arguments" })
	for _, list in { request.allowedTools, request.disallowedTools } do
		if list ~= nil and #list > 0 then
			Schema.fail(label, "the codex adapter cannot restrict tools; remove allowedTools and disallowedTools")
		end
	end
	local argv: { string } = table.clone(Schema.optionalTexts(options.command, label .. ".command") or { "codex" })
	for _, word in { "exec", "--json", "--skip-git-repo-check", "-C", request.workspace } do
		table.insert(argv, word)
	end
	if request.model ~= nil then
		table.insert(argv, "-m")
		table.insert(argv, request.model :: string)
	end
	local sandbox = Schema.optionalText(options.sandbox, label .. ".sandbox")
	if sandbox ~= nil then
		table.insert(argv, "--sandbox")
		table.insert(argv, sandbox)
	end
	if not Schema.flag(options.persistSession, label .. ".persistSession", false) then
		table.insert(argv, "--ephemeral")
	end
	local effort = Schema.optionalText(options.effort, label .. ".effort")
	if effort ~= nil then
		config(argv, "model_reasoning_effort", tomlString(effort))
	end
	if request.instructions ~= nil and request.instructions ~= "" then
		config(argv, "developer_instructions", tomlString(request.instructions :: string))
	end
	if mcp ~= nil then
		mcpServers(argv, mcp, decode)
	end
	local overrides: { string } = Schema.optionalTexts(options.config, label .. ".config") or {}
	for _, entry in overrides do
		table.insert(argv, "-c")
		table.insert(argv, entry)
	end
	local extra: { string } = Schema.optionalTexts(options.arguments, label .. ".arguments") or {}
	for _, word in extra do
		table.insert(argv, word)
	end
	table.insert(argv, "-")
	return argv
end

local function field(value: unknown, key: string): unknown
	if type(value) ~= "table" then
		return nil
	end
	return (value :: { [string]: unknown })[key]
end

local function textOf(value: unknown): string?
	return if type(value) == "string" then value else nil
end

local function count(value: unknown): number
	if Schema.finite(value) and (value :: number) >= 0 then
		return value :: number
	end
	return 0
end

local function toolName(item: unknown): string
	local kind = textOf(field(item, "type")) or "unknown"
	if kind == "command_execution" then
		return "command"
	elseif kind == "mcp_tool_call" then
		return ("mcp__%s__%s"):format(textOf(field(item, "server")) or "?", textOf(field(item, "tool")) or "?")
	end
	return kind
end

local function failed(item: unknown): boolean
	local status = textOf(field(item, "status"))
	if status == "failed" or status == "declined" then
		return true
	end
	local code = field(item, "exit_code")
	return Schema.finite(code) and code ~= 0
end

local function parse(lines: { Services.Line }, decode: (text: string) -> unknown): Transcript.Transcript
	local transcript = Transcript.parseClaudeStream({}, function(): unknown
		return nil
	end)
	local started: { [string]: number? } = {}
	local counted: { [string]: boolean } = {}
	local intervals: { { number } } = {}
	local previousAt: number? = nil
	local lastStepAt: number? = nil
	local timed = true
	local completedTurns = 0
	local failedTurn = false
	local streamError: string? = nil
	local usageSeen = false

	local function step(at: number?)
		transcript.messages += 1
		if at ~= nil then
			local base = previousAt or transcript.startupSeconds or 0
			table.insert(transcript.turnLatencies, math.max(0, at - base))
			table.insert(transcript.turnIntervals, math.max(0, at - (lastStepAt or transcript.startupSeconds or 0)))
			lastStepAt = at
		end
	end

	for _, line in lines do
		if string.match(line.text, "^%s*$") ~= nil then
			continue
		end
		local parsed, event: unknown = pcall(decode, line.text)
		if not parsed or type(event) ~= "table" then
			transcript.malformed += 1
			continue
		end
		transcript.events += 1
		if line.at == nil then
			timed = false
		end
		local at = line.at
		local kind = textOf(field(event, "type"))
		if kind == "thread.started" then
			transcript.session = textOf(field(event, "thread_id")) or transcript.session
			if at ~= nil and transcript.startupSeconds == nil then
				transcript.startupSeconds = at
			end
		elseif kind == "item.started" or kind == "item.updated" or kind == "item.completed" then
			local item = field(event, "item")
			local id = textOf(field(item, "id")) or ("line-" .. tostring(transcript.events))
			local itemKind = textOf(field(item, "type"))
			if itemKind ~= nil and TOOL_ITEMS[itemKind] then
				if not counted[id] then
					counted[id] = true
					local name = toolName(item)
					transcript.toolCalls += 1
					transcript.toolNames[name] = (transcript.toolNames[name] or 0) + 1
					started[id] = at
					step(at)
				end
				if kind == "item.completed" then
					if failed(item) then
						transcript.toolErrors += 1
					end
					local from = started[id]
					if from ~= nil and at ~= nil then
						table.insert(intervals, { from, math.max(from, at) })
					end
				end
			elseif itemKind == "agent_message" and kind == "item.completed" then
				local text = textOf(field(item, "text"))
				if text ~= nil then
					transcript.result = string.sub(text, 1, RESULT_LIMIT)
				end
			end
		elseif kind == "turn.completed" then
			completedTurns += 1
			step(at)
			local usage = field(event, "usage")
			if type(usage) == "table" then
				usageSeen = true
				local cached = count(field(usage, "cached_input_tokens"))
				local written = count(field(usage, "cache_write_input_tokens"))
				transcript.usage.input += math.max(0, count(field(usage, "input_tokens")) - cached - written)
				transcript.usage.cacheRead += cached
				transcript.usage.cacheCreation += written
				transcript.usage.output += count(field(usage, "output_tokens"))
			end
		elseif kind == "turn.failed" then
			failedTurn = true
			local message = textOf(field(field(event, "error"), "message"))
			if message ~= nil then
				transcript.result = string.sub(message, 1, RESULT_LIMIT)
			end
		elseif kind == "error" then
			streamError = textOf(field(event, "message")) or streamError
		end
		if at ~= nil then
			previousAt = at
			transcript.lastAt = at
		end
	end

	if failedTurn then
		transcript.status = "error"
		transcript.subtype = "turn.failed"
	elseif completedTurns > 0 then
		transcript.status = "success"
		transcript.subtype = "success"
	elseif streamError ~= nil then
		transcript.status = "error"
		transcript.subtype = "error"
		transcript.result = string.sub(streamError :: string, 1, RESULT_LIMIT)
	end
	transcript.usageSource = if usageSeen then "result" else "none"
	transcript.turns = transcript.messages
	if timed and transcript.events > 0 then
		transcript.toolSeconds = Transcript.union(intervals)
	else
		transcript.turnLatencies = {}
		transcript.turnIntervals = {}
	end
	return transcript
end

return {
	arguments = arguments,
	parse = parse,
	tomlString = tomlString,
}
