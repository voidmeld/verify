--!strict

local AgentEval = require "../src/agent-eval"
local Fakes = require "./agent-eval-fakes"
local Lute = require "../src/lute"
local Verify = require "../src/core"

local function request(): AgentEval.AgentRequest
	return {
		run = "r",
		task = "t",
		arm = "a",
		workspace = "/w",
		directory = "/e",
		suiteDirectory = "/s",
		prompt = "brief",
		promptFile = "/e/prompt.md",
		instructions = 'Use "the guide".\nKeep\tit short.',
		env = {},
		model = "model-a",
		seed = 1,
		budgets = { wallSeconds = 600 },
		options = { effort = "medium", arguments = { "--approve-for-me" } },
	}
end

local function stream(): { AgentEval.Line }
	local events: { { at: number, event: { [string]: unknown } } } = {
		{ at = 0.4, event = { type = "thread.started", thread_id = "thread-1" } },
		{ at = 0.5, event = { type = "turn.started" } },
		{
			at = 2,
			event = { type = "item.completed", item = { id = "item_0", type = "agent_message", text = "Looking." } },
		},
		{
			at = 2.1,
			event = {
				type = "item.started",
				item = { id = "item_1", type = "command_execution", command = "ls", status = "in_progress" },
			},
		},
		{
			at = 3.1,
			event = {
				type = "item.completed",
				item = { id = "item_1", type = "command_execution", command = "ls", exit_code = 2, status = "failed" },
			},
		},
		{
			at = 5,
			event = {
				type = "item.completed",
				item = { id = "item_2", type = "file_change", changes = {}, status = "completed" },
			},
		},
		{
			at = 6,
			event = {
				type = "item.started",
				item = {
					id = "item_3",
					type = "mcp_tool_call",
					server = "docs",
					tool = "search",
					status = "in_progress",
				},
			},
		},
		{
			at = 6.5,
			event = {
				type = "item.completed",
				item = { id = "item_3", type = "mcp_tool_call", server = "docs", tool = "search", status = "completed" },
			},
		},
		{
			at = 8,
			event = { type = "item.completed", item = { id = "item_4", type = "agent_message", text = "Done." } },
		},
		{
			at = 8.2,
			event = {
				type = "turn.completed",
				usage = {
					input_tokens = 1000,
					cached_input_tokens = 600,
					cache_write_input_tokens = 100,
					output_tokens = 50,
					reasoning_output_tokens = 20,
				},
			},
		},
	}
	local lines: { AgentEval.Line } = {}
	for _, entry in events do
		table.insert(lines, { at = entry.at, text = Fakes.json(entry.event) })
	end
	return lines
end

return function(suite: Verify.Harness)
	suite:suite("agent evaluation Codex adapter", function()
		suite:case("builds the Codex command with the instructions as a TOML string", function(context)
			context:expect(AgentEval.adapters.codexArguments(request(), nil, Lute.parse)):toEqual {
				"codex",
				"exec",
				"--json",
				"--skip-git-repo-check",
				"-C",
				"/w",
				"-m",
				"model-a",
				"--ephemeral",
				"-c",
				'model_reasoning_effort="medium"',
				"-c",
				'developer_instructions="Use \\"the guide\\".\\nKeep\\tit short."',
				"--approve-for-me",
				"-",
			}
		end)

		suite:case("passes the MCP servers of the arm as configuration overrides", function(context)
			local mcp = Fakes.json {
				mcpServers = {
					docs = { command = "docs-server", args = { "--root", "a b" }, env = { TOKEN = "x" } },
					remote = { url = "http://127.0.0.1:9/mcp" },
				},
			}
			local given = request()
			given.instructions = nil
			given.options = { sandbox = "workspace-write", persistSession = true, config = { "a.b=1" } }
			context:expect(AgentEval.adapters.codexArguments(given, mcp, Lute.parse)):toEqual {
				"codex",
				"exec",
				"--json",
				"--skip-git-repo-check",
				"-C",
				"/w",
				"-m",
				"model-a",
				"--sandbox",
				"workspace-write",
				"-c",
				'mcp_servers.docs.command="docs-server"',
				"-c",
				'mcp_servers.docs.args=["--root", "a b"]',
				"-c",
				'mcp_servers.docs.env={ "TOKEN" = "x" }',
				"-c",
				'mcp_servers.remote.url="http://127.0.0.1:9/mcp"',
				"-c",
				"a.b=1",
				"-",
			}
		end)

		suite:case("refuses tool lists and unknown options", function(context)
			local given = request()
			given.allowedTools = { "Read" }
			context
				:expect(function()
					AgentEval.adapters.codexArguments(given, nil, Lute.parse)
				end)
				:toThrow "cannot restrict tools"
			local other = request()
			other.options = { maxTurns = 3 }
			context
				:expect(function()
					AgentEval.adapters.codexArguments(other, nil, Lute.parse)
				end)
				:toThrow 'unknown field "maxTurns"'
		end)

		suite:case("reads tokens, model steps, tools and timing from the JSON events", function(context)
			local transcript = AgentEval.transcript.parseCodexStream(stream(), Lute.parse)
			context:expect(transcript.status):toBe "success"
			context:expect(transcript.session):toBe "thread-1"
			context:expect(transcript.startupSeconds):toBe(0.4)
			context:expect(transcript.toolCalls):toBe(3)
			context:expect(transcript.toolErrors):toBe(1)
			context:expect(transcript.toolNames):toEqual { command = 1, file_change = 1, mcp__docs__search = 1 }
			context:expect(transcript.messages):toBe(4)
			context:expect(transcript.turns):toBe(4)
			context:expect(transcript.reportedTurns):toBe(nil)
			context:expect(transcript.usageSource):toBe "result"
			context:expect(transcript.usage):toEqual { input = 300, cacheCreation = 100, cacheRead = 600, output = 50 }
			context:expect(transcript.result):toBe "Done."
			context:expect(transcript.toolSeconds):toBeCloseTo(1.5)
			context:expect(#transcript.turnIntervals):toBe(4)
			context:expect(transcript.turnIntervals[1]):toBeCloseTo(1.7)
		end)

		suite:case("reports a failed turn, a stream error and a stream with no turn", function(context)
			local lines = stream()
			lines[#lines] = {
				at = 9,
				text = Fakes.json { type = "turn.failed", error = { message = "usage limit" } },
			}
			local failed = AgentEval.transcript.parseCodexStream(lines, Lute.parse)
			context:expect(failed.status):toBe "error"
			context:expect(failed.subtype):toBe "turn.failed"
			context:expect(failed.result):toBe "usage limit"
			context:expect(failed.usageSource):toBe "none"
			local broken = AgentEval.transcript.parseCodexStream({
				{ at = 0.1, text = Fakes.json { type = "error", message = "stream disconnected" } },
				{ at = 0.2, text = "not json" },
			}, Lute.parse)
			context:expect(broken.status):toBe "error"
			context:expect(broken.result):toBe "stream disconnected"
			context:expect(broken.malformed):toBe(1)
			local empty = AgentEval.transcript.parseCodexStream({ { at = nil, text = "{}" } }, Lute.parse)
			context:expect(empty.status):toBe "incomplete"
			context:expect(empty.turnLatencies):toEqual {}
		end)

		suite:case("runs the Codex adapter through an injected executor", function(context)
			local memory = Fakes.memory()
			local services = Fakes.services(memory.files)
			local seen: { AgentEval.Command } = {}
			services.execute = function(command: AgentEval.Command): AgentEval.Execution
				table.insert(seen, command)
				return {
					started = true,
					exitcode = 0,
					timedOut = false,
					unsupported = false,
					stdout = "",
					stderr = "",
					lines = stream(),
					seconds = 9,
				}
			end
			local adapter = AgentEval.adapters.codex(Lute.parse)
			local outcome = adapter.run(request(), services)
			context:expect(adapter.id):toBe "codex"
			context:expect(outcome.status):toBe "completed"
			context:expect(outcome.transcript.model):toBe "model-a"
			context:expect(seen[1].input):toBe "/e/prompt.md"
			context:expect(seen[1].stamp):toBe(true)
			context:expect(seen[1].cwd):toBe "/w"
			context:expect(seen[1].deadlineSeconds):toBe(600)
		end)
	end)
end
