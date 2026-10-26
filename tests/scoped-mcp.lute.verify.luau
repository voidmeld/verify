--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local function asString(value: unknown): string
	assert(type(value) == "string")
	return value
end

local Eval = require "../src/agent-eval"
local Files = require "../src/lute/files"
local json = require "@std/json"
local Lute = require "../src/lute"

for _, mode in { "unanswered", "unsent", "raised", "normal-error", "run-deadline", "override" } do
	it("scoped MCP bounds and drains queued requests after " .. mode, function()
		local now, opened, closed, claimed = 0, 0, 0, 0
		local calls: { { connection: number, name: string, limit: number, arguments: string } } = {}
		local responses: { string } = {}
		local pending = table.concat({
			'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"screen_capture","arguments":{}}}',
			'{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"execute_luau","arguments":{"datamodel_type":"Edit","code":"return true"}}}',
			'{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_roblox_studios","arguments":{}}}',
		}, "\n") .. "\n"
		local config = Eval.lute.encode {
			studio = { id = "own", name = "run" },
			executable = "unused",
			directory = "transport",
			seconds = if mode == "run-deadline" then 10 else 120,
			callSeconds = if mode == "override" then 5 else nil,
		}
		local imports: { [string]: unknown } = {
			["@std/fs"] = {
				readFileToString = function()
					return config
				end,
			},
			["@std/process"] = { args = { "proxy", "scope.json" } },
			["@std/json"] = json,
			["@lute/io"] = {
				read = function(): string
					local value = pending
					pending = ""
					return value
				end,
				write = function(value: string)
					table.insert(responses, value)
				end,
			},
			["../src/agent-eval"] = Eval,
			["../src/lute/wire"] = { encode = Lute.encode },
			["../src/lute/files"] = {
				claimDirectory = function(): string
					claimed += 1
					return "transport/" .. claimed
				end,
			},
			["../src/lute/studio-mcp"] = {
				connect = function()
					opened += 1
					local connection = opened
					return {
						close = function()
							closed += 1
						end,
						callRaw = function(name: string, arguments: string, limit: number): unknown
							table.insert(
								calls,
								{ connection = connection, name = name, limit = limit, arguments = arguments }
							)
							if #calls == 1 then
								if mode == "raised" then
									error("secret-other-backend", 0)
								end
								if mode == "normal-error" then
									return { status = "answered", detail = "secret-other-backend" }
								end
								if mode == "unsent" then
									return { status = "unsent" }
								end
								now = limit
								return { status = "unanswered" }
							end
							return {
								status = "answered",
								result = {
									content = {
										{
											type = "text",
											text = if connection == 1 and mode ~= "normal-error"
												then "late-old-response"
												else "new-response",
										},
									},
								},
							}
						end,
					}
				end,
			},
		}
		local environment: { [string]: unknown } = {
			require = function(path: string): unknown
				return assert(imports[path], path)
			end,
			os = {
				clock = function(): number
					return now
				end,
			},
			assert = assert,
			error = error,
			pcall = pcall,
			type = type,
			tostring = tostring,
			math = math,
			string = string,
			table = table,
		}
		Lute.chunk.load(Eval.lute.services().files.read "tools/scoped-studio-mcp.luau", {
			environment = environment,
			name = "scoped-deadline-" .. mode,
		})()
		expect(#responses):toBe(3)
		local first = Eval.lute.decode(responses[1]) :: { error: { message: string } }
		expect((string.find(first.error.message, "secret-other", 1, true))):toBe(nil)
		local uncertain = mode ~= "unsent" and mode ~= "normal-error"
		expect(string.find(first.error.message, "may have been applied", 1, true) ~= nil):toBe(uncertain)
		expect(calls[1].limit):toBe(if mode == "override" then 5 else if mode == "run-deadline" then 10 else 60)
		expect(calls[1].name):toBe "screen_capture"
		local second = Eval.lute.decode(responses[2]) :: { error: unknown?, result: { content: { { text: string } } }? }
		if mode == "run-deadline" then
			expect(second.error ~= nil):toBe(true)
			expect(#calls):toBe(1)
			expect(opened):toBe(1)
		else
			expect(second.error):toBe(nil)
			expect(assert(second.result).content[1].text):toBe "new-response"
			expect(#calls):toBe(2)
			expect(calls[2].name):toBe "execute_luau"
			expect(string.find(calls[2].arguments, '"studio_id":"own"', 1, true) ~= nil):toBe(true)
			expect(opened):toBe(if mode == "normal-error" then 1 else 2)
		end
		expect(closed):toBe(opened)
		expect(claimed):toBe(opened)
	end)
end
it("restarting one scoped MCP configuration never reuses a previous transport directory", function(own)
	local directory = Files.claimDirectory(Files.temporary "verify-scope-restart")
	own(function()
		Files.removeIfPresent(directory)
	end)
	local services = Eval.lute.services()
	local transport = directory .. "/mcp"
	services.files.makeDirectory(transport)
	for _, name in { "close", "exited", "pid" } do
		services.files.write(transport .. "/" .. name, "stale")
	end
	local scope, input = directory .. "/scope.json", directory .. "/input.jsonl"
	services.files.write(
		scope,
		Eval.lute.encode {
			studio = { id = "own", name = "run" },
			executable = "unused",
			directory = transport,
			seconds = 10,
		}
	)
	services.files.write(
		input,
		'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_roblox_studios","arguments":{}}}\n'
	)
	for count = 1, 4 do
		local result = services.execute {
			argv = { "lute", "run", "tools/scoped-studio-mcp.luau", scope },
			input = input,
			deadlineSeconds = 10,
		}
		expect(result.exitcode):toBe(0)
		expect(string.find(result.stdout, "own", 1, true) ~= nil):toBe(true)
		local claimed = 0
		for _, entry in services.files.list(transport) do
			if entry.kind == "directory" then
				claimed += 1
				for _, name in { "close", "exited", "pid" } do
					services.files.write(transport .. "/" .. entry.name .. "/" .. name, "stale")
				end
			end
		end
		expect(claimed):toBe(count)
	end
end)
it("scoped MCP handshake serializes capability and ping objects", function(own)
	local directory = Files.claimDirectory(Files.temporary "verify-scope-handshake")
	own(function()
		Files.removeIfPresent(directory)
	end)
	local services = Eval.lute.services()
	local scope = directory .. "/scope.json"
	local input = directory .. "/input.jsonl"
	services.files.write(
		scope,
		Eval.lute.encode {
			studio = { id = "own", name = "run" },
			executable = "unused",
			directory = directory .. "/mcp",
			seconds = 10,
		}
	)
	services.files.write(
		input,
		'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":2,"method":"ping"}\n'
	)
	local result = services.execute {
		argv = { "lute", "run", "tools/scoped-studio-mcp.luau", scope },
		input = input,
		deadlineSeconds = 10,
	}
	expect(result.exitcode):toBe(0)
	local count = 0
	for line in string.gmatch(result.stdout, "[^\r\n]+") do
		local response = assert(json.asObject(json.deserialize(line)))
		expect(json.asObject(response.result) ~= nil):toBe(true)
		if response.id == 1 then
			local initialized = assert(json.asObject(response.result))
			local capabilities = assert(json.asObject(initialized.capabilities))
			expect(json.asObject(capabilities.tools) ~= nil):toBe(true)
		end
		count += 1
	end
	expect(count):toBe(2)
end)

it("scoped MCP stdio frames several requests from one read", function()
	local directory = Files.claimDirectory(Files.temporary "verify-scope-stdio")
	local services = Eval.lute.services()
	local scope = directory .. "/scope.json"
	local input = directory .. "/input.jsonl"
	services.files.write(
		scope,
		Eval.lute.encode {
			studio = { id = "own", name = "run" },
			executable = "unused",
			directory = directory .. "/mcp",
			seconds = 10,
		}
	)
	local requests: { string } = {}
	for id = 1, 2 do
		table.insert(
			requests,
			json.serialize {
				jsonrpc = "2.0",
				id = id,
				method = "tools/call",
				params = { name = "list_roblox_studios", arguments = {} },
			}
		)
	end
	services.files.write(input, table.concat(requests, "\n") .. "\n")
	local result = services.execute {
		argv = { "lute", "run", "tools/scoped-studio-mcp.luau", scope },
		input = input,
		deadlineSeconds = 10,
	}
	expect(result.exitcode):toBe(0)
	local count = 0
	for line in string.gmatch(result.stdout, "[^\r\n]+") do
		local response = Eval.lute.decode(line) :: { id: number, result: { content: { { text: string } } } }
		count += 1
		expect(response.id):toBe(count)
		local listing = Eval.lute.decode(response.result.content[1].text) :: { studios: { { id: string } } }
		expect(listing.studios[1].id):toBe "own"
	end
	expect(count):toBe(2)
	services.files.remove(directory)
end)

it("MCP and shell tools use the same recorded token accounting", function()
	local totals: { number } = {}
	for _, kind in { "command_execution", "mcp_tool_call" } do
		local lines: { Eval.Line } = {
			{
				at = 0,
				text = Eval.lute.encode {
					type = "item.started",
					item = { id = "tool", type = kind, server = "studio", tool = "execute_luau" },
				},
			},
			{
				at = 1,
				text = Eval.lute.encode {
					type = "item.completed",
					item = { id = "tool", type = kind, server = "studio", tool = "execute_luau" },
				},
			},
			{
				at = 2,
				text = Eval.lute.encode {
					type = "turn.completed",
					usage = { input_tokens = 100, cached_input_tokens = 20, output_tokens = 10 },
				},
			},
		}
		local parsed = Eval.transcript.parseCodexStream(lines, Eval.lute.decode)
		expect(parsed.toolCalls):toBe(1)
		table.insert(totals, Eval.transcript.total(parsed.usage))
	end
	expect(totals):toEqual { 110, 110 }
end)
it("scoped MCP lists one Studio without consulting the global server", function()
	local calls = 0
	local studio = { id = "own", name = "run" }
	local scope = Eval.scopedMcp.create(studio, {
		call = function(): unknown
			calls += 1
			return {}
		end,
	}, Eval.lute.encode)
	studio.id = "changed"
	local listing =
		scope.dispatch("tools/call", { name = "list_roblox_studios", arguments = {} }) :: { content: { { text: string } } }
	local raw = Eval.lute.decode(listing.content[1].text) :: { studios: { { id: string } } }
	expect(#raw.studios):toBe(1)
	expect(raw.studios[1].id):toBe "own"
	expect(calls):toBe(0)
end)
it("scoped MCP advertises only each operation's accepted arguments", function()
	local calls = 0
	local scope = Eval.scopedMcp.create({ id = "own", name = "run" }, {
		call = function(): unknown
			calls += 1
			return {}
		end,
	}, Eval.lute.encode)
	local listing =
		scope.dispatch("tools/list", {}) :: { tools: { { name: string, inputSchema: { [string]: unknown } } } }
	local examples: { [string]: { [string]: unknown } } = {
		list_roblox_studios = {},
		start_stop_play = { is_start = true },
		screen_capture = { capture_id = "capture" },
		execute_luau = { code = "return 1", datamodel_type = "Edit" },
		get_console_output = {},
		input = { code = "return 1" },
	}
	expect(#listing.tools):toBe(6)
	for _, tool in listing.tools do
		local example = assert(examples[tool.name])
		local schema = tool.inputSchema
		local properties = schema.properties :: { [string]: unknown }
		expect(schema.additionalProperties):toBe(false)
		for key in properties do
			expect(key == "studio_id" or example[key] ~= nil):toBe(true)
		end
		for key in example do
			expect(properties[key] ~= nil):toBe(true)
		end
		expect((pcall(scope.dispatch, "tools/call", { name = tool.name, arguments = example }))):toBe(true)
		for _, key in (schema.required or {}) :: { string } do
			local missing = table.clone(example)
			missing[key] = nil
			expect((pcall(scope.dispatch, "tools/call", { name = tool.name, arguments = missing }))):toBe(false)
		end
		local extra = table.clone(example)
		extra.unknown = true
		expect((pcall(scope.dispatch, "tools/call", { name = tool.name, arguments = extra }))):toBe(false)
	end
	expect(calls):toBe(5)
end)
it("scoped MCP rejects alternate ids and tools before forwarding", function()
	local calls = 0
	local scope = Eval.scopedMcp.create({ id = "own", name = "run" }, {
		call = function(): unknown
			calls += 1
			return {}
		end,
	}, Eval.lute.encode)
	for _, name in
		{
			"list_roblox_studios",
			"start_stop_play",
			"screen_capture",
			"execute_luau",
			"get_console_output",
			"unknown",
		}
	do
		local ok = pcall(scope.dispatch, "tools/call", {
			name = name,
			arguments = { studio_id = "other", code = "return 1", datamodel_type = "Edit", is_start = true },
		})
		expect(ok):toBe(false)
	end
	expect((pcall(scope.dispatch, "resources/list", {}))):toBe(false)
	expect((pcall(scope.dispatch, "tools/call", { name = "unknown", arguments = {} }))):toBe(false)
	expect(calls):toBe(0)
end)
it("two MCP scopes cannot steer one another and preserve tool results", function()
	local ids: { string } = {}
	local backend = {
		call = function(_name: string, args: { [string]: unknown }): unknown
			table.insert(ids, asString(args.studio_id))
			return { content = { { type = "image", data = "image-bytes", mimeType = "image/png" } } }
		end,
	}
	local a = Eval.scopedMcp.create({ id = "a", name = "A" }, backend, Eval.lute.encode)
	local b = Eval.scopedMcp.create({ id = "b", name = "B" }, backend, Eval.lute.encode)
	local args = {}
	local response =
		a.dispatch("tools/call", { name = "screen_capture", arguments = args }) :: { content: { { data: string } } }
	b.dispatch("tools/call", { name = "screen_capture", arguments = {} })
	expect(ids):toEqual { "a", "b" }
	expect(response.content[1].data):toBe "image-bytes"
	expect((next(args))):toBe(nil)
	a.close()
	expect((pcall(a.dispatch, "tools/call", { name = "get_console_output", arguments = {} }))):toBe(false)
	b.dispatch("tools/call", { name = "get_console_output", arguments = {} })
	expect(ids[3]):toBe "b"
end)
it("scoped MCP validates play and execution and never retries a failed call", function()
	local calls = 0
	local scope = Eval.scopedMcp.create({ id = "own", name = "run" }, {
		call = function(): unknown
			calls += 1
			error "lost"
		end,
	}, Eval.lute.encode)
	expect((pcall(scope.dispatch, "tools/call", { name = "start_stop_play", arguments = { is_start = "true" } }))):toBe(
		false
	)
	expect(calls):toBe(0)
	expect(
		(
			pcall(
				scope.dispatch,
				"tools/call",
				{ name = "execute_luau", arguments = { code = "return 1", datamodel_type = "Client" } }
			)
		)
	):toBe(false)
	expect(calls):toBe(1)
end)
it("backend failures cannot reveal the global Studio list", function()
	local scope = Eval.scopedMcp.create({ id = "own", name = "run" }, {
		call = function(): unknown
			error "missing target; other Studio id secret-other"
		end,
	}, Eval.lute.encode)
	local ok, reason = pcall(scope.dispatch, "tools/call", { name = "screen_capture", arguments = {} })
	expect(ok):toBe(false)
	expect((string.find(tostring(reason), "secret-other", 1, true))):toBe(nil)
end)

return nil
