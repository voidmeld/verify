--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local AgentEval = require "../src/agent-eval"
local Fakes = require "./agent-eval-fakes"
local Lute = require "../src/lute"

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

describe("agent evaluation Codex adapter", function()
	it("builds the Codex command with the instructions as a TOML string", function()
		expect(AgentEval.adapters.codexArguments(request(), nil, Lute.parse)):toEqual {
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

	it("passes the MCP servers of the arm as configuration overrides", function()
		local mcp = Fakes.json {
			mcpServers = {
				docs = { command = "docs-server", args = { "--root", "a b" }, env = { TOKEN = "x" } },
				remote = { url = "http://127.0.0.1:9/mcp" },
			},
		}
		local given = request()
		given.instructions = nil
		given.options = { sandbox = "workspace-write", persistSession = true, config = { "a.b=1" } }
		expect(AgentEval.adapters.codexArguments(given, mcp, Lute.parse)):toEqual {
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

	it("refuses tool lists and unknown options", function()
		local given = request()
		given.allowedTools = { "Read" }
		expect(function()
			AgentEval.adapters.codexArguments(given, nil, Lute.parse)
		end):toThrow "cannot restrict tools"
		local other = request()
		other.options = { maxTurns = 3 }
		expect(function()
			AgentEval.adapters.codexArguments(other, nil, Lute.parse)
		end):toThrow 'unknown field "maxTurns"'
	end)

	it("reads one end-to-end CLI turn while counting its tools separately", function()
		local transcript = AgentEval.transcript.parseCodexStream(stream(), Lute.parse)
		expect(transcript.status):toBe "success"
		expect(transcript.session):toBe "thread-1"
		expect(transcript.startupSeconds):toBe(0.4)
		expect(transcript.toolCalls):toBe(3)
		expect(transcript.toolErrors):toBe(1)
		expect(transcript.toolNames):toEqual { command = 1, file_change = 1, mcp__docs__search = 1 }
		expect(transcript.messages):toBe(2)
		expect(transcript.turns):toBe(1)
		expect(transcript.reportedTurns):toBe(nil)
		expect(transcript.usageSource):toBe "result"
		expect(transcript.usage):toEqual { input = 300, cacheCreation = 100, cacheRead = 600, output = 50 }
		expect(transcript.result):toBe "Done."
		expect(transcript.toolSeconds):toBeCloseTo(1.5)
		expect(#transcript.turnLatencies):toBe(1)
		expect(transcript.turnLatencies[1]):toBeCloseTo(7.7)
		expect(transcript.turnIntervals):toEqual {}
	end)

	it("measures completed CLI turns and their start intervals", function()
		local lines = stream()
		table.insert(lines, { at = 10, text = Fakes.json { type = "turn.started" } })
		table.insert(lines, { at = 15, text = Fakes.json { type = "turn.completed" } })
		local transcript = AgentEval.transcript.parseCodexStream(lines, Lute.parse)
		expect(transcript.turns):toBe(2)
		expect(#transcript.turnLatencies):toBe(2)
		expect(transcript.turnLatencies[1]):toBeCloseTo(7.7)
		expect(transcript.turnLatencies[2]):toBe(5)
		expect(transcript.turnIntervals):toEqual { 9.5 }
		expect(transcript.toolCalls):toBe(3)
		expect(transcript.toolSeconds):toBeCloseTo(1.5)
	end)

	it("does not invent a duration for an interrupted CLI turn", function()
		local lines = stream()
		table.remove(lines)
		local interrupted = AgentEval.transcript.parseCodexStream(lines, Lute.parse)
		expect(interrupted.status):toBe "incomplete"
		expect(interrupted.turns):toBe(0)
		expect(interrupted.turnLatencies):toEqual {}
		local later = stream()
		table.insert(later, { at = 10, text = Fakes.json { type = "turn.started" } })
		local partial = AgentEval.transcript.parseCodexStream(later, Lute.parse)
		expect(partial.status):toBe "incomplete"
		expect(partial.turns):toBe(1)
		expect(#partial.turnLatencies):toBe(1)
		expect(partial.turnLatencies[1]):toBeCloseTo(7.7)
	end)

	it("leaves CLI turn durations unavailable without matched timed boundaries", function()
		local lines = stream()
		table.remove(lines, 2)
		local unmatched = AgentEval.transcript.parseCodexStream(lines, Lute.parse)
		expect(unmatched.turns):toBe(1)
		expect(unmatched.turnLatencies):toEqual {}
		expect(unmatched.turnIntervals):toEqual {}
		lines = stream()
		for _, line in lines do
			line.at = nil
		end
		local untimed = AgentEval.transcript.parseCodexStream(lines, Lute.parse)
		expect(untimed.turnLatencies):toEqual {}
		expect(untimed.turnIntervals):toEqual {}
		expect(untimed.toolSeconds):toBe(nil)
	end)

	it("reports a failed turn, a stream error and a stream with no turn", function()
		local lines = stream()
		lines[#lines] = {
			at = 9,
			text = Fakes.json { type = "turn.failed", error = { message = "usage limit" } },
		}
		local failed = AgentEval.transcript.parseCodexStream(lines, Lute.parse)
		expect(failed.status):toBe "error"
		expect(failed.subtype):toBe "turn.failed"
		expect(failed.result):toBe "usage limit"
		expect(failed.usageSource):toBe "none"
		expect(failed.turnLatencies):toEqual {}
		local broken = AgentEval.transcript.parseCodexStream({
			{ at = 0.1, text = Fakes.json { type = "error", message = "stream disconnected" } },
			{ at = 0.2, text = "not json" },
		}, Lute.parse)
		expect(broken.status):toBe "error"
		expect(broken.result):toBe "stream disconnected"
		expect(broken.malformed):toBe(1)
		local empty = AgentEval.transcript.parseCodexStream({ { at = nil, text = "{}" } }, Lute.parse)
		expect(empty.status):toBe "incomplete"
		expect(empty.turnLatencies):toEqual {}
	end)

	it("accepts completion after transport recovery but rejects later failures", function()
		local lines: { AgentEval.Line } = {
			{ at = 0, text = Fakes.json { type = "turn.started" } },
			{
				at = 3,
				text = Fakes.json {
					type = "error",
					message = "Reconnecting... 2/5 (stream disconnected before completion: websocket closed by server before response.completed)",
				},
			},
			{
				at = 14,
				text = Fakes.json {
					type = "item.completed",
					item = {
						id = "item_0",
						type = "error",
						message = "Falling back from WebSockets to HTTPS transport. stream disconnected before completion: websocket closed by server before response.completed",
					},
				},
			},
			{
				at = 20,
				text = Fakes.json {
					type = "item.completed",
					item = { id = "item_1", type = "agent_message", text = "answer" },
				},
			},
			{ at = 21, text = Fakes.json { type = "turn.completed" } },
		}
		local recovered = AgentEval.transcript.parseCodexStream(lines, Lute.parse)
		expect(recovered.status):toBe "success"
		expect(recovered.result):toBe "answer"
		expect(recovered.turnLatencies):toEqual { 21 }
		expect(recovered.toolCalls):toBe(0)
		table.insert(lines, { at = 22, text = Fakes.json { type = "error", message = "terminal failure" } })
		local terminal = AgentEval.transcript.parseCodexStream(lines, Lute.parse)
		expect(terminal.status):toBe "error"
		expect(terminal.result):toBe "terminal failure"
		table.remove(lines)
		table.insert(lines, { at = 22, text = Fakes.json { type = "turn.started" } })
		table.insert(
			lines,
			{ at = 23, text = Fakes.json { type = "turn.failed", error = { message = "failed final turn" } } }
		)
		expect(AgentEval.transcript.parseCodexStream(lines, Lute.parse).status):toBe "error"
	end)

	it("fails terminal author errors even when the process exits successfully", function()
		local failed = stream()
		table.remove(failed)
		table.insert(
			failed,
			{ at = 9, text = Fakes.json { type = "error", message = "Selected model is at capacity." } }
		)
		table.insert(failed, {
			at = 9.1,
			text = Fakes.json { type = "turn.failed", error = { message = "Selected model is at capacity." } },
		})
		local recovered = stream()
		local completion = table.remove(recovered)
		table.insert(recovered, { at = 8.1, text = Fakes.json { type = "error", message = "retrying request" } })
		assert(completion ~= nil)
		table.insert(recovered, completion)
		local truncated = stream()
		table.remove(truncated)
		local terminal = stream()
		table.insert(terminal, { at = 9, text = Fakes.json { type = "error", message = "stream disconnected" } })
		local cases: { { lines: { AgentEval.Line }, code: number, expected: string, timedOut: boolean?, unsupported: boolean? } } =
			{
				{ lines = failed, code = 0, expected = "failed" },
				{ lines = failed, code = 1, expected = "failed" },
				{ lines = truncated, code = 0, expected = "failed" },
				{ lines = stream(), code = 1, expected = "failed" },
				{ lines = recovered, code = 0, expected = "completed" },
				{ lines = terminal, code = 0, expected = "failed" },
				{ lines = failed, code = 1, timedOut = true, expected = "timed_out" },
				{ lines = failed, code = 1, timedOut = true, unsupported = true, expected = "unsupported" },
			}
		for _, case in cases do
			local memory = Fakes.memory()
			local services = Fakes.services(memory.files)
			services.execute = function(_command: AgentEval.Command): AgentEval.Execution
				return {
					started = true,
					exitcode = case.code,
					timedOut = case.timedOut == true,
					unsupported = case.unsupported == true,
					stdout = "",
					stderr = "",
					lines = case.lines,
					seconds = 10,
				}
			end
			local outcome = AgentEval.adapters.codex(Lute.parse).run(request(), services)
			expect(outcome.status):toBe(case.expected)
			if case.lines == failed and case.expected == "failed" then
				expect(string.find(outcome.detail or "", "at capacity", 1, true) ~= nil):toBe(true)
				expect(outcome.transcript.toolCalls):toBe(3)
			end
			if case.unsupported ~= true then
				local replay = AgentEval.adapters
					.replay({
						decode = Lute.parse,
						parse = AgentEval.transcript.parseCodexStream,
						respond = function(): AgentEval.ReplayResponse
							return {
								lines = case.lines,
								exitcode = case.code,
								timedOut = case.timedOut,
								seconds = 10,
							}
						end,
					})
					.run(request(), services)
				expect(replay.status):toBe(case.expected)
			end
		end
	end)

	it("runs the Codex adapter through an injected executor", function()
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
		expect(adapter.id):toBe "codex"
		expect(outcome.status):toBe "completed"
		expect(outcome.transcript.model):toBe "model-a"
		expect(seen[1].input):toBe "/e/prompt.md"
		expect(seen[1].stamp):toBe(true)
		expect(seen[1].cwd):toBe "/w"
		expect(seen[1].deadlineSeconds):toBe(600)
	end)
end)

return nil
