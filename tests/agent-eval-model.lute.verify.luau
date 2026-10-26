--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local AgentEval = require "../src/agent-eval"
local Fakes = require "./agent-eval-fakes"
local Lute = require "../src/lute"

type Object = { [string]: unknown }

local function object(value: Object): Object
	return value
end

local function put(memory: Fakes.Memory, path: string, text: string)
	memory.files.makeDirectory(assert(string.match(path, "^(.*)/[^/]+$")))
	memory.files.write(path, text)
end

local function base(): Object
	return {
		schemaVersion = 1,
		id = "suite",
		tasks = { "tasks/a" },
		arms = { { id = "left" }, { id = "right" } },
		agents = { { id = "agent", adapter = "claude-code", model = "m" } },
		seeds = { 1, 2 },
	}
end

local function task<T>(extra: { [string]: T }?, remove: { string }?): Object
	local value: Object = {
		schemaVersion = 1,
		id = "a",
		title = "A",
		brief = "brief.md",
		starter = "starter",
		checks = { { id = "c", kind = "command", argv = { "true" } } },
	}
	local additions: { [string]: T } = extra or {}
	for key, item in additions do
		value[key] = item
	end
	local removed: { string } = remove or {}
	for _, key in removed do
		value[key] = nil
	end
	return value
end

local function load(suiteValue: Object, tasks: { [string]: Object }): (AgentEval.Suite?, string?)
	local memory = Fakes.memory()
	put(memory, "/s/eval.json", Fakes.json(suiteValue))
	for name, value in tasks do
		put(memory, ("/s/tasks/%s/task.json"):format(name), Fakes.json(value))
		put(memory, ("/s/tasks/%s/brief.md"):format(name), "brief " .. name)
		put(memory, ("/s/tasks/%s/starter/file.txt"):format(name), "x")
	end
	local ok, result = pcall(function(): AgentEval.Suite
		return AgentEval.decodeSuite(
			Lute.parse(memory.files.read "/s/eval.json"),
			"/s/eval.json",
			Fakes.loader(memory.files)
		)
	end)
	if ok then
		return result, nil
	end
	return nil, tostring(result)
end

local function refusal(suiteValue: Object, tasks: { [string]: Object }): string
	local suite, problem = load(suiteValue, tasks)
	assert(suite == nil, "the definition was accepted")
	return assert(problem)
end

local function contains(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

describe("agent evaluation task model", function()
	it("decodes a suite with defaults and resolved paths", function()
		local value = base()
		value.budgets = { maxTurns = 30, wallSeconds = 900 }
		value.devices = { { id = "phone", width = 844, height = 390, scale = 3, input = { "touch" } } }
		local decoded = assert(load(value, { a = task { budgets = { maxTurns = 5 } } }))
		expect(decoded.id):toBe "suite"
		expect(decoded.directory):toBe "/s"
		expect(#decoded.tasks):toBe(1)
		local first = decoded.tasks[1]
		expect(first.brief):toBe "/s/tasks/a/brief.md"
		expect(first.briefText):toBe "brief a"
		expect(first.starter):toBe "/s/tasks/a/starter"
		expect(first.tier):toBe "default"
		expect(first.budgets.maxTurns):toBe(5)
		expect(first.budgets.wallSeconds):toBe(900)
		expect(first.devices[1].scale):toBe(3)
		expect(first.checks[1].required):toBe(true)
		expect(decoded.parallelism):toBe(1)
	end)

	it("refuses malformed tasks with a named field", function()
		expect(contains(refusal(base(), { a = task { from = "a" } }), "exactly one of starter or from")):toBe(true)
		expect(contains(refusal(base(), { a = task { arms = { middle = {} } } }), "undeclared arm")):toBe(true)
		expect(contains(refusal(base(), { a = task { extra = true } }), 'unknown field "extra"')):toBe(true)
		expect(
			contains(
				refusal(base(), { a = task { checks = { { id = "v", kind = "verify", argv = { "x" } } } } }),
				"must pass {report}"
			)
		):toBe(true)
		expect(
			contains(
				refusal(base(), { a = task { checks = { { id = "u", kind = "audit" } } } }),
				"is required for an audit check"
			)
		):toBe(true)
		expect(contains(
			refusal(base(), {
				a = task {
					checks = {
						object { id = "one", kind = "command", argv = { "x" }, after = { "two" } },
						{ id = "two", kind = "command", argv = { "x" } },
					},
				},
			}),
			"not an earlier check"
		)):toBe(true)
		expect(contains(
			refusal(base(), {
				a = task {
					checks = { { id = "d", kind = "command", argv = { "x" }, perDevice = true } },
				},
			}),
			"no devices"
		)):toBe(true)
		expect(contains(refusal(base(), { a = task { id = "bad id" } }), "identifier")):toBe(true)
	end)

	it("orders follow-ups after their source and refuses cycles", function()
		local value = base()
		value.tasks = { "tasks/b", "tasks/a" }
		local decoded = assert(load(value, { a = task(), b = task({ id = "b", from = "a" }, { "starter" }) }))
		expect(decoded.tasks[1].id):toBe "a"
		expect(decoded.tasks[2].id):toBe "b"
		local cyclic = base()
		cyclic.tasks = { "tasks/a", "tasks/b" }
		local problem = refusal(cyclic, {
			a = task({ from = "b" }, { "starter" }),
			b = task({ id = "b", from = "a" }, { "starter" }),
		})
		expect(contains(problem, "follow-up cycle")):toBe(true)
		local unknown = base()
		expect(contains(refusal(unknown, { a = task({ from = "z" }, { "starter" }) }), "unknown task")):toBe(true)
	end)

	it("plans deterministic runs that rotate the arm order by seed", function()
		local value = base()
		value.tasks = { "tasks/a", "tasks/b" }
		local memory = Fakes.memory()
		put(memory, "/s/eval.json", Fakes.json(value))
		for _, name in { "a", "b" } do
			local definition = if name == "a" then task() else task({ id = "b", from = "a" }, { "starter" })
			put(memory, ("/s/tasks/%s/task.json"):format(name), Fakes.json(definition))
			put(memory, ("/s/tasks/%s/brief.md"):format(name), "brief")
			put(memory, ("/s/tasks/%s/starter/file.txt"):format(name), "x")
		end
		local loader = Fakes.loader(memory.files)
		local decoded = AgentEval.decodeSuite(Lute.parse(memory.files.read "/s/eval.json"), "/s/eval.json", loader)
		local specs = AgentEval.plan(decoded, loader)
		local ids: { string } = {}
		for _, spec in specs do
			table.insert(ids, spec.id)
		end
		expect(ids):toEqual {
			"a/left/agent/1",
			"a/right/agent/1",
			"b/left/agent/1",
			"b/right/agent/1",
			"a/right/agent/2",
			"a/left/agent/2",
			"b/right/agent/2",
			"b/left/agent/2",
		}
		expect(specs[3].parent):toBe "a/left/agent/1"
		expect(specs[1].path):toBe "runs/a/left/agent/seed-1"
		local again = AgentEval.plan(decoded, loader)
		expect(again[5].digest):toBe(specs[5].digest)
		expect(specs[1].digest == specs[2].digest):toBe(false)
		local narrowed = AgentEval.plan(decoded, loader, { tasks = { "b" }, seeds = { 2 } })
		expect(#narrowed):toBe(2)
		expect(narrowed[1].parent):toBe "a/right/agent/2"
		memory.files.write("/s/tasks/a/starter/file.txt", "y")
		local changed = AgentEval.decodeSuite(Lute.parse(memory.files.read "/s/eval.json"), "/s/eval.json", loader)
		local rerun = AgentEval.plan(changed, loader)
		expect(rerun[1].digest == specs[1].digest):toBe(false)
		expect(rerun[3].digest == specs[3].digest):toBe(false)
	end)
end)

describe("agent evaluation transcripts", function()
	it("parses a Claude Code stream with repeated message blocks, tools and a result", function()
		local lines = Fakes.stream { session = "s", turns = 3, output = 50, cost = 0.25 }
		local transcript = AgentEval.transcript.parseClaudeStream(lines, Lute.parse)
		expect(transcript.status):toBe "success"
		expect(transcript.subtype):toBe "success"
		expect(transcript.turns):toBe(3)
		expect(transcript.messages):toBe(3)
		expect(transcript.usageSource):toBe "result"
		expect(transcript.usage):toEqual { input = 30, cacheCreation = 300, cacheRead = 3000, output = 150 }
		expect(transcript.costUsd):toBe(0.25)
		expect(transcript.toolCalls):toBe(3)
		expect(transcript.toolNames):toEqual { Write = 3 }
		expect(transcript.turnLatencies):toEqual { 2, 2, 2 }
		expect(transcript.turnIntervals):toEqual { 2, 3, 3 }
		expect(transcript.toolSeconds):toBeCloseTo(2.7)
		expect(transcript.startupSeconds):toBe(0.5)
		expect(transcript.model):toBe "claude-opus-5-5"
		expect(transcript.version):toBe "9.9.9"
		expect(transcript.mcpServers):toEqual { { name = "docs", status = "connected" } }
		expect(transcript.apiSeconds):toBe(4.5)
		expect(transcript.result):toBe "done"
	end)

	it("sums message usage without a result, counts subagents apart and keeps malformed lines", function()
		local lines = Fakes.stream { session = "s", turns = 2, output = 40, result = false }
		table.insert(lines, { at = 9, text = "not json" })
		table.insert(lines, {
			at = 9.5,
			text = Fakes.json {
				type = "assistant",
				parent_tool_use_id = "outer",
				message = {
					id = "sub-1",
					content = { { type = "tool_use", id = "inner", name = "Read", input = {} } },
					usage = { input_tokens = 1, output_tokens = 7 },
				},
			},
		})
		local transcript = AgentEval.transcript.parseClaudeStream(lines, Lute.parse)
		expect(transcript.status):toBe "incomplete"
		expect(transcript.usageSource):toBe "messages"
		expect(transcript.usage):toEqual { input = 21, cacheCreation = 200, cacheRead = 2000, output = 87 }
		expect(transcript.messages):toBe(2)
		expect(transcript.subagentMessages):toBe(1)
		expect(transcript.turns):toBe(2)
		expect(transcript.malformed):toBe(1)
		expect(transcript.toolCalls):toBe(3)
	end)

	it("prefers per-model usage and drops latencies when a line has no time", function()
		local lines = Fakes.stream { session = "s", turns = 1, output = 10 }
		local result = Lute.parse(lines[#lines].text) :: Object
		result.modelUsage = {
			["claude-opus-5-5"] = {
				inputTokens = 5,
				outputTokens = 6,
				cacheReadInputTokens = 7,
				cacheCreationInputTokens = 8,
			},
			["claude-haiku-5-5"] = {
				inputTokens = 1,
				outputTokens = 2,
				cacheReadInputTokens = 0,
				cacheCreationInputTokens = 0,
			},
		}
		lines[#lines] = { at = nil, text = Fakes.json(result) }
		local transcript = AgentEval.transcript.parseClaudeStream(lines, Lute.parse)
		expect(transcript.usageSource):toBe "models"
		expect(transcript.usage):toEqual { input = 6, cacheCreation = 8, cacheRead = 7, output = 8 }
		expect(transcript.modelUsage["claude-haiku-5-5"].output):toBe(2)
		expect(transcript.turnLatencies):toEqual {}
		expect(transcript.toolSeconds):toBe(nil)
	end)

	it("reads stamped lines and builds the Claude Code command", function()
		local lines = AgentEval.adapters.parseStamped '1.250000\t{"a":1}\r\nplain line\n2.5\t{}\n'
		local expected: { AgentEval.Line } = {
			{ at = 1.25, text = '{"a":1}' },
			{ at = nil, text = "plain line" },
			{ at = 2.5, text = "{}" },
		}
		expect(lines):toEqual(expected)
		local request: AgentEval.AgentRequest = {
			run = "r",
			task = "t",
			arm = "a",
			workspace = "/w",
			directory = "/e",
			suiteDirectory = "/s",
			prompt = "brief",
			promptFile = "/e/prompt.md",
			instructions = "Use the guide.",
			mcpConfig = "/e/mcp.json",
			allowedTools = { "Read", "Edit" },
			disallowedTools = { "WebFetch" },
			env = {},
			model = "claude-opus-5-5",
			seed = 1,
			budgets = { maxTurns = 40, maxCostUsd = 5, wallSeconds = 600 },
			options = { effort = "high", arguments = { "--fallback-model", "x" } },
		}
		expect(AgentEval.adapters.claudeArguments(request)):toEqual {
			"claude",
			"-p",
			"--output-format",
			"stream-json",
			"--verbose",
			"--model",
			"claude-opus-5-5",
			"--max-turns",
			"40",
			"--max-budget-usd",
			"5",
			"--permission-mode",
			"bypassPermissions",
			"--mcp-config",
			"/e/mcp.json",
			"--strict-mcp-config",
			"--no-session-persistence",
			"--effort",
			"high",
			"--append-system-prompt",
			"Use the guide.",
			"--allowedTools",
			"Read,Edit",
			"--disallowedTools",
			"WebFetch",
			"--fallback-model",
			"x",
		}
		request.options = { unknown = true }
		expect(function()
			AgentEval.adapters.claudeArguments(request)
		end):toThrow 'unknown field "unknown"'
	end)

	it("runs the Claude Code adapter through an injected executor", function()
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
				lines = Fakes.stream { session = "s", turns = 1, output = 9 },
				seconds = 4,
			}
		end
		local adapter = AgentEval.adapters.claudeCode(Lute.parse)
		local request: AgentEval.AgentRequest = {
			run = "r",
			task = "t",
			arm = "a",
			workspace = "/w",
			directory = "/e",
			suiteDirectory = "/s",
			prompt = "brief",
			promptFile = "/e/prompt.md",
			env = { KEY = "value" },
			seed = 1,
			budgets = { wallSeconds = 30 },
			options = {},
		}
		local outcome = adapter.run(request, services)
		expect(outcome.status):toBe "completed"
		expect(outcome.transcript.usage.output):toBe(9)
		expect(seen[1].cwd):toBe "/w"
		expect(seen[1].input):toBe "/e/prompt.md"
		expect(seen[1].deadlineSeconds):toBe(30)
		expect(seen[1].stamp):toBe(true)
		expect(seen[1].env):toEqual { KEY = "value" }
		services.execute = function(_command: AgentEval.Command): AgentEval.Execution
			return {
				started = true,
				exitcode = 1,
				timedOut = false,
				unsupported = false,
				stdout = "",
				stderr = "boom",
				lines = {},
				seconds = 1,
			}
		end
		local failed = adapter.run(request, services)
		expect(failed.status):toBe "failed"
		expect(failed.detail):toBe "the agent exited with 1 and reported no result"
		services.execute = function(_command: AgentEval.Command): AgentEval.Execution
			return {
				started = false,
				exitcode = -1,
				timedOut = false,
				unsupported = true,
				stdout = "",
				stderr = "",
				lines = {},
				seconds = 0,
				detail = "no process group",
			}
		end
		expect(adapter.run(request, services).status):toBe "unsupported"
	end)

	it("completes only the configured Claude turn limit exception", function()
		local services = Fakes.services(Fakes.memory().files)
		local scenarios: { { subtype: string, turns: number, limit: number?, exitcode: number, status: string } } = {
			{ subtype = "error_max_turns", turns = 2, limit = 2, exitcode = 1, status = "completed" },
			{ subtype = "error_max_turns", turns = 1, limit = 2, exitcode = 0, status = "failed" },
			{ subtype = "error_max_turns", turns = 2, exitcode = 0, status = "failed" },
			{ subtype = "error_during_execution", turns = 2, limit = 2, exitcode = 0, status = "failed" },
			{ subtype = "success", turns = 1, limit = 2, exitcode = 1, status = "failed" },
		}
		for _, scenario in scenarios do
			local lines = Fakes.stream { session = "s", subtype = scenario.subtype, turns = scenario.turns, output = 9 }
			local request: AgentEval.AgentRequest = {
				run = "r",
				task = "t",
				arm = "a",
				workspace = "/w",
				directory = "/e",
				suiteDirectory = "/s",
				prompt = "brief",
				promptFile = "/e/prompt.md",
				env = {},
				seed = 1,
				budgets = { maxTurns = scenario.limit, wallSeconds = 30 },
				options = {},
			}
			services.execute = function(_command: AgentEval.Command): AgentEval.Execution
				return {
					started = true,
					exitcode = scenario.exitcode,
					timedOut = false,
					unsupported = false,
					stdout = "",
					stderr = "",
					lines = lines,
					seconds = 1,
				}
			end
			expect(AgentEval.adapters.claudeCode(Lute.parse).run(request, services).status):toBe(scenario.status)
			local replay = AgentEval.adapters.replay {
				decode = Lute.parse,
				respond = function(_request: AgentEval.AgentRequest): AgentEval.ReplayResponse
					return { lines = lines, exitcode = scenario.exitcode }
				end,
			}
			expect(replay.run(request, services).status):toBe(scenario.status)
		end
	end)

	it("expands command adapter placeholders without naming the arm", function()
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
				lines = { { at = 1, text = "final answer" } },
				seconds = 1,
			}
		end
		local adapter = AgentEval.adapters.command {
			id = "other",
			argv = { "agent", "--model", "{model}", "--prompt", "{prompt_file}", "{arm}" },
			decode = Lute.parse,
		}
		local request: AgentEval.AgentRequest = {
			run = "r",
			task = "t",
			arm = "secret",
			workspace = "/w",
			directory = "/e",
			suiteDirectory = "/s",
			prompt = "brief",
			promptFile = "/e/prompt.md",
			env = {},
			model = "m",
			seed = 1,
			budgets = { wallSeconds = 30 },
			options = {},
		}
		local outcome = adapter.run(request, services)
		expect(seen[1].argv):toEqual { "agent", "--model", "m", "--prompt", "/e/prompt.md", "{arm}" }
		expect(outcome.status):toBe "completed"
		expect(outcome.transcript.result):toBe "final answer"
		services.execute = function(_command: AgentEval.Command): AgentEval.Execution
			return {
				started = true,
				exitcode = 1,
				timedOut = false,
				unsupported = false,
				stdout = "",
				stderr = "",
				lines = { { at = 1, text = "partial answer" } },
				seconds = 1,
			}
		end
		expect(adapter.run(request, services).status):toBe "failed"
	end)
end)

return nil
