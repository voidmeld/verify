--!strict

local Eval = require "../src/agent-eval"
local Verify = require "../src/core"
local Files = require "../src/lute/files"
local json = require "@std/json"

return function(harness: Verify.Harness)
	harness:case("restarting one scoped MCP configuration never reuses a previous transport directory", function(t)
		local directory = Files.claimDirectory(Files.temporary "verify-scope-restart")
		t:defer(function()
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
			t:expect(result.exitcode):toBe(0)
			t:expect(string.find(result.stdout, "own", 1, true) ~= nil):toBe(true)
			local claimed = 0
			for _, entry in services.files.list(transport) do
				if entry.kind == "directory" then
					claimed += 1
					for _, name in { "close", "exited", "pid" } do
						services.files.write(transport .. "/" .. entry.name .. "/" .. name, "stale")
					end
				end
			end
			t:expect(claimed):toBe(count)
		end
	end)
	harness:case("scoped MCP handshake serializes capability and ping objects", function(t)
		local directory = Files.claimDirectory(Files.temporary "verify-scope-handshake")
		t:defer(function()
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
		t:expect(result.exitcode):toBe(0)
		local count = 0
		for line in string.gmatch(result.stdout, "[^\r\n]+") do
			local response = json.deserialize(line) :: { id: number, result: json.Value }
			t:expect(json.asObject(response.result) ~= nil):toBe(true)
			if response.id == 1 then
				local initialized = response.result :: { capabilities: { tools: json.Value } }
				t:expect(json.asObject(initialized.capabilities.tools) ~= nil):toBe(true)
			end
			count += 1
		end
		t:expect(count):toBe(2)
	end)

	harness:case("scoped MCP stdio frames several requests from one read", function(t)
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
		t:expect(result.exitcode):toBe(0)
		local count = 0
		for line in string.gmatch(result.stdout, "[^\r\n]+") do
			local response = Eval.lute.decode(line) :: { id: number, result: { content: { { text: string } } } }
			count += 1
			t:expect(response.id):toBe(count)
			local listing = Eval.lute.decode(response.result.content[1].text) :: { studios: { { id: string } } }
			t:expect(listing.studios[1].id):toBe "own"
		end
		t:expect(count):toBe(2)
		services.files.remove(directory)
	end)

	harness:case("MCP and shell tools use the same recorded token accounting", function(t)
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
			t:expect(parsed.toolCalls):toBe(1)
			table.insert(totals, Eval.transcript.total(parsed.usage))
		end
		t:expect(totals):toEqual { 110, 110 }
	end)
	harness:case("scoped MCP lists one Studio without consulting the global server", function(t)
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
		t:expect(#raw.studios):toBe(1)
		t:expect(raw.studios[1].id):toBe "own"
		t:expect(calls):toBe(0)
	end)
	harness:case("scoped MCP rejects alternate ids and tools before forwarding", function(t)
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
			t:expect(ok):toBe(false)
		end
		t:expect((pcall(scope.dispatch, "resources/list", {}))):toBe(false)
		t:expect((pcall(scope.dispatch, "tools/call", { name = "unknown", arguments = {} }))):toBe(false)
		t:expect(calls):toBe(0)
	end)
	harness:case("two MCP scopes cannot steer one another and preserve tool results", function(t)
		local ids: { string } = {}
		local backend = {
			call = function(_name: string, args: { [string]: unknown }): unknown
				table.insert(ids, args.studio_id :: string)
				return { content = { { type = "image", data = "image-bytes", mimeType = "image/png" } } }
			end,
		}
		local a = Eval.scopedMcp.create({ id = "a", name = "A" }, backend, Eval.lute.encode)
		local b = Eval.scopedMcp.create({ id = "b", name = "B" }, backend, Eval.lute.encode)
		local args = {}
		local response =
			a.dispatch("tools/call", { name = "screen_capture", arguments = args }) :: { content: { { data: string } } }
		b.dispatch("tools/call", { name = "screen_capture", arguments = {} })
		t:expect(ids):toEqual { "a", "b" }
		t:expect(response.content[1].data):toBe "image-bytes"
		t:expect((next(args))):toBe(nil)
		a.close()
		t:expect((pcall(a.dispatch, "tools/call", { name = "get_console_output", arguments = {} }))):toBe(false)
		b.dispatch("tools/call", { name = "get_console_output", arguments = {} })
		t:expect(ids[3]):toBe "b"
	end)
	harness:case("scoped MCP validates play and execution and never retries a failed call", function(t)
		local calls = 0
		local scope = Eval.scopedMcp.create({ id = "own", name = "run" }, {
			call = function(): unknown
				calls += 1
				error "lost"
			end,
		}, Eval.lute.encode)
		t:expect((pcall(scope.dispatch, "tools/call", { name = "start_stop_play", arguments = { is_start = "true" } })))
			:toBe(false)
		t:expect(calls):toBe(0)
		t:expect(
			(
				pcall(
					scope.dispatch,
					"tools/call",
					{ name = "execute_luau", arguments = { code = "return 1", datamodel_type = "Client" } }
				)
			)
		):toBe(false)
		t:expect(calls):toBe(1)
	end)
	harness:case("backend failures cannot reveal the global Studio list", function(t)
		local scope = Eval.scopedMcp.create({ id = "own", name = "run" }, {
			call = function(): unknown
				error "missing target; other Studio id secret-other"
			end,
		}, Eval.lute.encode)
		local ok, reason = pcall(scope.dispatch, "tools/call", { name = "screen_capture", arguments = {} })
		t:expect(ok):toBe(false)
		t:expect((string.find(tostring(reason), "secret-other", 1, true))):toBe(nil)
	end)
end
