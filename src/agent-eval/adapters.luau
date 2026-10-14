--!strict

local Model = require "./model"
local Paths = require "./paths"
local Schema = require "./schema"
local Services = require "./services"
local Transcript = require "./transcript"

export type Request = {
	run: string,
	task: string,
	arm: string,
	workspace: string,
	directory: string,
	suiteDirectory: string,
	prompt: string,
	promptFile: string,
	instructions: string?,
	mcpConfig: string?,
	allowedTools: { string }?,
	disallowedTools: { string }?,
	env: { [string]: string },
	model: string?,
	seed: number,
	budgets: Model.Budgets,
	options: { [string]: unknown },
}

export type Status = "completed" | "failed" | "timed_out" | "unsupported"

export type Outcome = {
	status: Status,
	exitcode: number?,
	detail: string?,
	transcript: Transcript.Transcript,
	lines: { Services.Line },
	stderr: string,
	seconds: number,
}

export type Adapter = {
	id: string,
	run: (request: Request, services: Services.Services) -> Outcome,
}

export type Parser = (lines: { Services.Line }, decode: (text: string) -> unknown) -> Transcript.Transcript

export type CommandOptions = {
	id: string,
	argv: { string },
	parse: Parser?,
	stamp: boolean?,
	stdin: boolean?,
	decode: (text: string) -> unknown,
}

export type ReplayResponse = {
	files: { [string]: string }?,
	lines: { Services.Line }?,
	exitcode: number?,
	timedOut: boolean?,
	seconds: number?,
}

export type ReplayOptions = {
	id: string?,
	respond: (request: Request) -> ReplayResponse,
	parse: Parser?,
	decode: (text: string) -> unknown,
}

local function optionText(options: { [string]: unknown }, key: string, label: string): string?
	return Schema.optionalText(options[key], label .. "." .. key)
end

local function optionTexts(options: { [string]: unknown }, key: string, label: string): { string }?
	return Schema.optionalTexts(options[key], label .. "." .. key)
end

local function claudeArguments(request: Request): { string }
	local label = "agent options"
	local options = request.options
	Schema.only(options, label, {
		"command",
		"permissionMode",
		"strictMcpConfig",
		"persistSession",
		"settingSources",
		"effort",
		"arguments",
	})
	local argv: { string } = table.clone(optionTexts(options, "command", label) or { "claude" })
	for _, word in { "-p", "--output-format", "stream-json", "--verbose" } do
		table.insert(argv, word)
	end
	if request.model ~= nil then
		table.insert(argv, "--model")
		table.insert(argv, request.model :: string)
	end
	if request.budgets.maxTurns ~= nil then
		table.insert(argv, "--max-turns")
		table.insert(argv, tostring(request.budgets.maxTurns))
	end
	if request.budgets.maxCostUsd ~= nil then
		table.insert(argv, "--max-budget-usd")
		table.insert(argv, tostring(request.budgets.maxCostUsd))
	end
	table.insert(argv, "--permission-mode")
	table.insert(argv, optionText(options, "permissionMode", label) or "bypassPermissions")
	if request.mcpConfig ~= nil then
		table.insert(argv, "--mcp-config")
		table.insert(argv, request.mcpConfig :: string)
	end
	if Schema.flag(options.strictMcpConfig, label .. ".strictMcpConfig", true) then
		table.insert(argv, "--strict-mcp-config")
	end
	if not Schema.flag(options.persistSession, label .. ".persistSession", false) then
		table.insert(argv, "--no-session-persistence")
	end
	local sources = optionText(options, "settingSources", label)
	if sources ~= nil then
		table.insert(argv, "--setting-sources")
		table.insert(argv, sources)
	end
	local effort = optionText(options, "effort", label)
	if effort ~= nil then
		table.insert(argv, "--effort")
		table.insert(argv, effort)
	end
	if request.instructions ~= nil and request.instructions ~= "" then
		table.insert(argv, "--append-system-prompt")
		table.insert(argv, request.instructions :: string)
	end
	if request.allowedTools ~= nil and #(request.allowedTools :: { string }) > 0 then
		table.insert(argv, "--allowedTools")
		table.insert(argv, table.concat(request.allowedTools :: { string }, ","))
	end
	if request.disallowedTools ~= nil and #(request.disallowedTools :: { string }) > 0 then
		table.insert(argv, "--disallowedTools")
		table.insert(argv, table.concat(request.disallowedTools :: { string }, ","))
	end
	local extra: { string } = optionTexts(options, "arguments", label) or {}
	for _, word in extra do
		table.insert(argv, word)
	end
	return argv
end

local function statusOf(execution: Services.Execution): (Status, string?)
	if not execution.started then
		return "failed", execution.detail or "the agent command did not start"
	end
	if execution.timedOut then
		return "timed_out", "the agent exceeded its wall-clock budget"
	end
	return "completed", nil
end

local function executeCommand(
	request: Request,
	services: Services.Services,
	argv: { string },
	stamp: boolean,
	stdin: boolean,
	parse: Parser,
	decode: (text: string) -> unknown
): Outcome
	local execution = services.execute {
		argv = argv,
		cwd = request.workspace,
		env = request.env,
		input = if stdin then request.promptFile else nil,
		deadlineSeconds = request.budgets.wallSeconds,
		stamp = stamp,
		scratch = request.directory,
	}
	local status: Status, detail: string? = statusOf(execution)
	if execution.unsupported == true then
		status = "unsupported"
		detail = execution.detail
	end
	local transcript = parse(execution.lines, decode)
	if status == "completed" and transcript.status == "incomplete" and execution.exitcode ~= 0 then
		status = "failed"
		detail = ("the agent exited with %d and reported no result"):format(execution.exitcode)
	end
	return {
		status = status,
		exitcode = if execution.started then execution.exitcode else nil,
		detail = detail,
		transcript = transcript,
		lines = execution.lines,
		stderr = execution.stderr,
		seconds = execution.seconds,
	}
end

local function claudeCode(decode: (text: string) -> unknown): Adapter
	return {
		id = "claude-code",
		run = function(request: Request, services: Services.Services): Outcome
			return executeCommand(
				request,
				services,
				claudeArguments(request),
				true,
				true,
				Transcript.parseClaudeStream,
				decode
			)
		end,
	}
end

local function expand(word: string, request: Request): string
	local values: { [string]: string } = {
		prompt_file = request.promptFile,
		workspace = request.workspace,
		model = request.model or "",
		max_turns = if request.budgets.maxTurns ~= nil then tostring(request.budgets.maxTurns) else "",
		mcp_config = request.mcpConfig or "",
		seed = tostring(request.seed),
		evidence = request.directory,
	}
	return (
		string.gsub(word, "{([%w_]+)}", function(name: string): string
			return values[name] or ("{" .. name .. "}")
		end)
	)
end

local function plainTranscript(lines: { Services.Line }, _decode: (text: string) -> unknown): Transcript.Transcript
	local transcript = Transcript.parseClaudeStream({}, function(): unknown
		return nil
	end)
	transcript.status = "success"
	transcript.events = #lines
	if #lines > 0 then
		transcript.result = string.sub(lines[#lines].text, 1, 4000)
		transcript.lastAt = lines[#lines].at
	end
	return transcript
end

local function command(options: CommandOptions): Adapter
	Schema.identifier(options.id, "command adapter id")
	assert(#options.argv > 0, "a command adapter needs argv")
	local parse: Parser = options.parse or plainTranscript
	return {
		id = options.id,
		run = function(request: Request, services: Services.Services): Outcome
			local argv: { string } = {}
			for _, word in options.argv do
				table.insert(argv, expand(word, request))
			end
			return executeCommand(
				request,
				services,
				argv,
				options.stamp ~= false,
				options.stdin ~= false,
				parse,
				options.decode
			)
		end,
	}
end

local function replay(options: ReplayOptions): Adapter
	local parse: Parser = options.parse or Transcript.parseClaudeStream
	return {
		id = options.id or "replay",
		run = function(request: Request, services: Services.Services): Outcome
			local response = options.respond(request)
			for _, name in Schema.sortedKeys(response.files or {}) do
				if not Paths.contained(name) then
					error(("replay file %s leaves the workspace"):format(name), 0)
				end
				local target = Paths.join(request.workspace, name)
				services.files.makeDirectory(Paths.parent(target))
				services.files.write(target, (response.files :: { [string]: string })[name])
			end
			local lines = response.lines or {}
			local seconds = response.seconds or (if #lines > 0 then lines[#lines].at else nil) or 0
			local transcript = parse(lines, options.decode)
			local status: Status = "completed"
			local detail: string? = nil
			if response.timedOut == true then
				status = "timed_out"
				detail = "the agent exceeded its wall-clock budget"
			elseif (response.exitcode or 0) ~= 0 and transcript.status == "incomplete" then
				status = "failed"
				detail = ("the agent exited with %d and reported no result"):format(response.exitcode or 0)
			end
			return {
				status = status,
				exitcode = response.exitcode or 0,
				detail = detail,
				transcript = transcript,
				lines = lines,
				stderr = "",
				seconds = seconds,
			}
		end,
	}
end

local function parseStamped(text: string): { Services.Line }
	local result: { Services.Line } = {}
	for line in string.gmatch(text, "[^\n]+") do
		local stamp, rest = string.match(line, "^(%d+%.?%d*)\t(.*)$")
		if stamp ~= nil then
			table.insert(result, { at = tonumber(stamp), text = (string.gsub(rest :: string, "\r$", "")) })
		else
			table.insert(result, { at = nil, text = (string.gsub(line, "\r$", "")) })
		end
	end
	return result
end

local function fixture(decode: (text: string) -> unknown): Adapter
	return {
		id = "fixture",
		run = function(request: Request, services: Services.Services): Outcome
			local label = "agent options"
			Schema.only(request.options, label, { "stream", "files", "exitcode", "timedOut" })
			local values = { arm = request.arm, task = request.task, seed = tostring(request.seed) }
			local function resolve(path: string): string
				return Paths.join(
					request.suiteDirectory,
					(
						string.gsub(path, "{([%w_]+)}", function(name: string): string
							return values[name] or ("{" .. name .. "}")
						end)
					)
				)
			end
			local stream = resolve(Schema.text(request.options.stream, label .. ".stream"))
			local copies = Schema.dictionary(request.options.files, label .. ".files")
			local files: { [string]: string } = {}
			for _, target in Schema.sortedKeys(copies) do
				local source = resolve(copies[target])
				if services.files.exists(source) then
					files[target] = services.files.read(source)
				end
			end
			local exitcode = Schema.optionalNumber(request.options.exitcode, label .. ".exitcode", nil, true)
			local timedOut = Schema.flag(request.options.timedOut, label .. ".timedOut", false)
			return replay({
				id = "fixture",
				decode = decode,
				respond = function(): ReplayResponse
					return {
						files = files,
						lines = parseStamped(services.files.read(stream)),
						exitcode = exitcode,
						timedOut = timedOut,
					}
				end,
			}).run(request, services)
		end,
	}
end

return {
	claudeCode = claudeCode,
	claudeArguments = claudeArguments,
	command = command,
	replay = replay,
	fixture = fixture,
	parseStamped = parseStamped,
	expand = expand,
}
