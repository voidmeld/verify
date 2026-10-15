--!strict

local Eval = require "../src/agent-eval"
local Verify = require "../src/core"

return function(harness: Verify.Harness)
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
		local scope = Eval.scopedMcp.create({ id = "own", name = "run" }, {
			call = function(): unknown
				calls += 1
				return {}
			end,
		}, Eval.lute.encode)
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
end
