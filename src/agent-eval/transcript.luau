--!strict

local Schema = require "./schema"
local Services = require "./services"

export type Usage = { input: number, cacheCreation: number, cacheRead: number, output: number }

export type Status = "success" | "error" | "incomplete"

export type Transcript = {
	status: Status,
	subtype: string?,
	model: string?,
	session: string?,
	version: string?,
	tools: { string },
	mcpServers: { { name: string, status: string } },
	turns: number,
	reportedTurns: number?,
	messages: number,
	subagentMessages: number,
	usage: Usage,
	usageSource: "models" | "result" | "messages" | "none",
	modelUsage: { [string]: Usage },
	costUsd: number?,
	durationSeconds: number?,
	apiSeconds: number?,
	startupSeconds: number?,
	toolSeconds: number?,
	turnLatencies: { number },
	turnIntervals: { number },
	toolCalls: number,
	toolErrors: number,
	toolNames: { [string]: number },
	permissionDenials: number,
	result: string?,
	malformed: number,
	events: number,
	lastAt: number?,
}

local RESULT_LIMIT = 4000

local function emptyUsage(): Usage
	return { input = 0, cacheCreation = 0, cacheRead = 0, output = 0 }
end

local function total(usage: Usage): number
	return usage.input + usage.cacheCreation + usage.cacheRead + usage.output
end

local function count(value: unknown): number
	if Schema.finite(value) and (value :: number) >= 0 then
		return value :: number
	end
	return 0
end

local function field(value: unknown, key: string): unknown
	if type(value) ~= "table" then
		return nil
	end
	local item = (value :: { [string]: unknown })[key]
	if type(item) == "userdata" then
		return nil
	end
	return item
end

local function textOf(value: unknown): string?
	if type(value) == "string" then
		return value
	end
	return nil
end

local function apiUsage(value: unknown): Usage?
	if type(value) ~= "table" then
		return nil
	end
	return {
		input = count(field(value, "input_tokens")),
		cacheCreation = count(field(value, "cache_creation_input_tokens")),
		cacheRead = count(field(value, "cache_read_input_tokens")),
		output = count(field(value, "output_tokens")),
	}
end

local function modelUsage(value: unknown): Usage
	return {
		input = count(field(value, "inputTokens")),
		cacheCreation = count(field(value, "cacheCreationInputTokens")),
		cacheRead = count(field(value, "cacheReadInputTokens")),
		output = count(field(value, "outputTokens")),
	}
end

local function add(into: Usage, value: Usage)
	into.input += value.input
	into.cacheCreation += value.cacheCreation
	into.cacheRead += value.cacheRead
	into.output += value.output
end

local function union(intervals: { { number } }): number
	table.sort(intervals, function(left, right)
		return left[1] < right[1]
	end)
	local sum = 0
	local startAt: number? = nil
	local endAt = 0
	for _, interval in intervals do
		if startAt == nil then
			startAt, endAt = interval[1], interval[2]
		elseif interval[1] <= endAt then
			endAt = math.max(endAt, interval[2])
		else
			sum += endAt - (startAt :: number)
			startAt, endAt = interval[1], interval[2]
		end
	end
	if startAt ~= nil then
		sum += endAt - startAt
	end
	return sum
end

local function list(value: unknown): { unknown }
	if type(value) ~= "table" then
		return {}
	end
	local result: { unknown } = {}
	for _, item in ipairs(value :: { unknown }) do
		table.insert(result, item)
	end
	return result
end

local function parseClaudeStream(lines: { Services.Line }, decode: (text: string) -> unknown): Transcript
	local transcript: Transcript = {
		status = "incomplete",
		subtype = nil,
		model = nil,
		session = nil,
		version = nil,
		tools = {},
		mcpServers = {},
		turns = 0,
		reportedTurns = nil,
		messages = 0,
		subagentMessages = 0,
		usage = emptyUsage(),
		usageSource = "none",
		modelUsage = {},
		costUsd = nil,
		durationSeconds = nil,
		apiSeconds = nil,
		startupSeconds = nil,
		toolSeconds = nil,
		turnLatencies = {},
		turnIntervals = {},
		toolCalls = 0,
		toolErrors = 0,
		toolNames = {},
		permissionDenials = 0,
		result = nil,
		malformed = 0,
		events = 0,
		lastAt = nil,
	}
	local messageUsage: { [string]: Usage } = {}
	local messageOrder: { string } = {}
	local seenMessage: { [string]: boolean } = {}
	local toolStarted: { [string]: number? } = {}
	local toolSubagent: { [string]: boolean } = {}
	local intervals: { { number } } = {}
	local previousAt: number? = nil
	local lastTurnAt: number? = nil
	local initAt: number? = nil
	local timed = true
	local resultUsage: Usage? = nil
	local resultModels: { [string]: Usage }? = nil

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
		local subagent = textOf(field(event, "parent_tool_use_id")) ~= nil
		local messageId: string? = nil
		if kind == "system" and field(event, "subtype") == "init" then
			transcript.model = textOf(field(event, "model")) or transcript.model
			transcript.session = textOf(field(event, "session_id")) or transcript.session
			transcript.version = textOf(field(event, "claude_code_version")) or transcript.version
			for _, tool in list(field(event, "tools")) do
				if type(tool) == "string" then
					table.insert(transcript.tools, tool)
				end
			end
			for _, server in list(field(event, "mcp_servers")) do
				local name = textOf(field(server, "name"))
				if name ~= nil then
					table.insert(transcript.mcpServers, { name = name, status = textOf(field(server, "status")) or "" })
				end
			end
			if at ~= nil and initAt == nil then
				initAt = at
				transcript.startupSeconds = at
			end
		elseif kind == "assistant" then
			local message = field(event, "message")
			messageId = textOf(field(message, "id")) or ("line-" .. tostring(transcript.events))
			local id = messageId :: string
			if not seenMessage[id] then
				seenMessage[id] = true
				table.insert(messageOrder, id)
				if subagent then
					transcript.subagentMessages += 1
				else
					transcript.messages += 1
					if at ~= nil then
						local base = previousAt or initAt or 0
						table.insert(transcript.turnLatencies, math.max(0, at - base))
						table.insert(transcript.turnIntervals, math.max(0, at - (lastTurnAt or initAt or 0)))
						lastTurnAt = at
					end
				end
			end
			local usage = apiUsage(field(message, "usage"))
			if usage ~= nil then
				local known = messageUsage[id]
				if known == nil then
					messageUsage[id] = usage
				else
					known.input = math.max(known.input, usage.input)
					known.cacheCreation = math.max(known.cacheCreation, usage.cacheCreation)
					known.cacheRead = math.max(known.cacheRead, usage.cacheRead)
					known.output = math.max(known.output, usage.output)
				end
			end
			for _, block in list(field(message, "content")) do
				if field(block, "type") == "tool_use" then
					local toolId = textOf(field(block, "id"))
					local name = textOf(field(block, "name")) or "unknown"
					if toolId ~= nil and toolStarted[toolId] == nil and toolSubagent[toolId] == nil then
						transcript.toolCalls += 1
						transcript.toolNames[name] = (transcript.toolNames[name] or 0) + 1
						toolStarted[toolId] = at
						toolSubagent[toolId] = subagent
					end
				end
			end
		elseif kind == "user" then
			local message = field(event, "message")
			for _, block in list(field(message, "content")) do
				if field(block, "type") == "tool_result" then
					local toolId = textOf(field(block, "tool_use_id"))
					if field(block, "is_error") == true then
						transcript.toolErrors += 1
					end
					if toolId ~= nil then
						local started = toolStarted[toolId]
						if started ~= nil and at ~= nil and not toolSubagent[toolId] then
							table.insert(intervals, { started, math.max(started, at) })
						end
					end
				end
			end
		elseif kind == "result" then
			transcript.subtype = textOf(field(event, "subtype"))
			local isError = field(event, "is_error") == true
			transcript.status = if transcript.subtype == "success" and not isError then "success" else "error"
			local reported = field(event, "num_turns")
			if Schema.finite(reported) then
				transcript.reportedTurns = reported :: number
			end
			local cost = field(event, "total_cost_usd")
			if Schema.finite(cost) then
				transcript.costUsd = cost :: number
			end
			local duration = field(event, "duration_ms")
			if Schema.finite(duration) then
				transcript.durationSeconds = (duration :: number) / 1000
			end
			local api = field(event, "duration_api_ms")
			if Schema.finite(api) then
				transcript.apiSeconds = (api :: number) / 1000
			end
			transcript.session = textOf(field(event, "session_id")) or transcript.session
			transcript.permissionDenials = #list(field(event, "permission_denials"))
			local final = textOf(field(event, "result"))
			if final ~= nil then
				transcript.result = string.sub(final, 1, RESULT_LIMIT)
			end
			resultUsage = apiUsage(field(event, "usage"))
			local models = field(event, "modelUsage")
			if type(models) == "table" then
				local collected: { [string]: Usage } = {}
				local any = false
				for name, entry in models :: { [unknown]: unknown } do
					if type(name) == "string" and type(entry) == "table" then
						collected[name] = modelUsage(entry)
						any = true
					end
				end
				if any then
					resultModels = collected
				end
			end
		end
		if at ~= nil then
			previousAt = at
			transcript.lastAt = at
		end
	end

	if resultModels ~= nil then
		transcript.usageSource = "models"
		transcript.modelUsage = resultModels
		for _, name in Schema.sortedKeys(resultModels) do
			add(transcript.usage, resultModels[name])
		end
	elseif resultUsage ~= nil then
		transcript.usageSource = "result"
		add(transcript.usage, resultUsage)
	elseif #messageOrder > 0 then
		transcript.usageSource = "messages"
		for _, id in messageOrder do
			local usage = messageUsage[id]
			if usage ~= nil then
				add(transcript.usage, usage)
			end
		end
	end
	transcript.turns = transcript.reportedTurns or transcript.messages
	if timed and transcript.events > 0 then
		transcript.toolSeconds = union(intervals)
	else
		transcript.turnLatencies = {}
		transcript.turnIntervals = {}
	end
	return transcript
end

return {
	parseClaudeStream = parseClaudeStream,
	emptyUsage = emptyUsage,
	total = total,
	union = union,
}
