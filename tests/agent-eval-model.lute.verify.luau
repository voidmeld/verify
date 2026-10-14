--!strict

local AgentEval = require "../src/agent-eval"
local Fakes = require "./agent-eval-fakes"
local Lute = require "../src/lute"
local Verify = require "../src/core"

type Object = { [string]: unknown }

local function put(memory: Fakes.Memory, path: string, text: string)
	memory.files.makeDirectory(string.match(path, "^(.*)/[^/]+$") :: string)
	memory.files.write(path, text)
end

local function base(): Object
	return {
		schemaVersion = 1,
		id = "suite",
		tasks = { "tasks/a" },
		arms = { { id = "left" } :: Object, { id = "right" } :: Object },
		agents = { { id = "agent", adapter = "claude-code", model = "m" } },
		seeds = { 1, 2 },
	}
end

local function task(extra: unknown, remove: { string }?): Object
	local value: Object = {
		schemaVersion = 1,
		id = "a",
		title = "A",
		brief = "brief.md",
		starter = "starter",
		checks = { { id = "c", kind = "command", argv = { "true" } } },
	}
	local additions: Object = if extra ~= nil then extra :: Object else {}
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
	return problem :: string
end

local function contains(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

return function(suite: Verify.Harness)
	suite:suite("agent evaluation task model", function()
		suite:case("decodes a suite with defaults and resolved paths", function(context)
			local value = base()
			value.budgets = { maxTurns = 30, wallSeconds = 900 }
			value.devices = { { id = "phone", width = 844, height = 390, scale = 3, input = { "touch" } } }
			local decoded = load(value, { a = task { budgets = { maxTurns = 5 } } }) :: AgentEval.Suite
			context:expect(decoded.id):toBe "suite"
			context:expect(decoded.directory):toBe "/s"
			context:expect(#decoded.tasks):toBe(1)
			local first = decoded.tasks[1]
			context:expect(first.brief):toBe "/s/tasks/a/brief.md"
			context:expect(first.briefText):toBe "brief a"
			context:expect(first.starter):toBe "/s/tasks/a/starter"
			context:expect(first.tier):toBe "default"
			context:expect(first.budgets.maxTurns):toBe(5)
			context:expect(first.budgets.wallSeconds):toBe(900)
			context:expect(first.devices[1].scale):toBe(3)
			context:expect(first.checks[1].required):toBe(true)
			context:expect(decoded.parallelism):toBe(1)
		end)

		suite:case("refuses malformed tasks with a named field", function(context)
			context
				:expect(contains(refusal(base(), { a = task { from = "a" } }), "exactly one of starter or from"))
				:toBe(true)
			context
				:expect(contains(refusal(base(), { a = task { arms = { middle = {} } } }), "undeclared arm"))
				:toBe(true)
			context:expect(contains(refusal(base(), { a = task { extra = true } }), 'unknown field "extra"')):toBe(true)
			context
				:expect(
					contains(
						refusal(base(), { a = task { checks = { { id = "v", kind = "verify", argv = { "x" } } } } }),
						"must pass {report}"
					)
				)
				:toBe(true)
			context
				:expect(
					contains(
						refusal(base(), { a = task { checks = { { id = "u", kind = "audit" } } } }),
						"is required for an audit check"
					)
				)
				:toBe(true)
			context
				:expect(contains(
					refusal(base(), {
						a = task {
							checks = {
								{ id = "one", kind = "command", argv = { "x" }, after = { "two" } } :: Object,
								{ id = "two", kind = "command", argv = { "x" } } :: Object,
							},
						},
					}),
					"not an earlier check"
				))
				:toBe(true)
			context
				:expect(contains(
					refusal(base(), {
						a = task {
							checks = { { id = "d", kind = "command", argv = { "x" }, perDevice = true } },
						},
					}),
					"no devices"
				))
				:toBe(true)
			context:expect(contains(refusal(base(), { a = task { id = "bad id" } }), "identifier")):toBe(true)
		end)

		suite:case("orders follow-ups after their source and refuses cycles", function(context)
			local value = base()
			value.tasks = { "tasks/b", "tasks/a" }
			local decoded =
				load(value, { a = task(), b = task({ id = "b", from = "a" }, { "starter" }) }) :: AgentEval.Suite
			context:expect(decoded.tasks[1].id):toBe "a"
			context:expect(decoded.tasks[2].id):toBe "b"
			local cyclic = base()
			cyclic.tasks = { "tasks/a", "tasks/b" }
			local problem = refusal(cyclic, {
				a = task({ from = "b" }, { "starter" }),
				b = task({ id = "b", from = "a" }, { "starter" }),
			})
			context:expect(contains(problem, "follow-up cycle")):toBe(true)
			local unknown = base()
			context
				:expect(contains(refusal(unknown, { a = task({ from = "z" }, { "starter" }) }), "unknown task"))
				:toBe(true)
		end)

		suite:case("plans deterministic runs that rotate the arm order by seed", function(context)
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
			context:expect(ids):toEqual {
				"a/left/agent/1",
				"a/right/agent/1",
				"b/left/agent/1",
				"b/right/agent/1",
				"a/right/agent/2",
				"a/left/agent/2",
				"b/right/agent/2",
				"b/left/agent/2",
			}
			context:expect(specs[3].parent):toBe "a/left/agent/1"
			context:expect(specs[1].path):toBe "runs/a/left/agent/seed-1"
			local again = AgentEval.plan(decoded, loader)
			context:expect(again[5].digest):toBe(specs[5].digest)
			context:expect(specs[1].digest == specs[2].digest):toBe(false)
			local narrowed = AgentEval.plan(decoded, loader, { tasks = { "b" }, seeds = { 2 } })
			context:expect(#narrowed):toBe(2)
			context:expect(narrowed[1].parent):toBe "a/right/agent/2"
			memory.files.write("/s/tasks/a/starter/file.txt", "y")
			local changed = AgentEval.decodeSuite(Lute.parse(memory.files.read "/s/eval.json"), "/s/eval.json", loader)
			local rerun = AgentEval.plan(changed, loader)
			context:expect(rerun[1].digest == specs[1].digest):toBe(false)
			context:expect(rerun[3].digest == specs[3].digest):toBe(false)
		end)
	end)

	suite:suite("agent evaluation transcripts", function()
		suite:case("parses a Claude Code stream with repeated message blocks, tools and a result", function(context)
			local lines = Fakes.stream { session = "s", turns = 3, output = 50, cost = 0.25 }
			local transcript = AgentEval.transcript.parseClaudeStream(lines, Lute.parse)
			context:expect(transcript.status):toBe "success"
			context:expect(transcript.subtype):toBe "success"
			context:expect(transcript.turns):toBe(3)
			context:expect(transcript.messages):toBe(3)
			context:expect(transcript.usageSource):toBe "result"
			context:expect(transcript.usage):toEqual { input = 30, cacheCreation = 300, cacheRead = 3000, output = 150 }
			context:expect(transcript.costUsd):toBe(0.25)
			context:expect(transcript.toolCalls):toBe(3)
			context:expect(transcript.toolNames):toEqual { Write = 3 }
			context:expect(transcript.turnLatencies):toEqual { 2, 2, 2 }
			context:expect(transcript.turnIntervals):toEqual { 2, 3, 3 }
			context:expect(transcript.toolSeconds):toBeCloseTo(2.7)
			context:expect(transcript.startupSeconds):toBe(0.5)
			context:expect(transcript.model):toBe "claude-opus-5-5"
			context:expect(transcript.version):toBe "9.9.9"
			context:expect(transcript.mcpServers):toEqual { { name = "docs", status = "connected" } }
			context:expect(transcript.apiSeconds):toBe(4.5)
			context:expect(transcript.result):toBe "done"
		end)

		suite:case(
			"sums message usage without a result, counts subagents apart and keeps malformed lines",
			function(context)
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
				context:expect(transcript.status):toBe "incomplete"
				context:expect(transcript.usageSource):toBe "messages"
				context
					:expect(transcript.usage)
					:toEqual { input = 21, cacheCreation = 200, cacheRead = 2000, output = 87 }
				context:expect(transcript.messages):toBe(2)
				context:expect(transcript.subagentMessages):toBe(1)
				context:expect(transcript.turns):toBe(2)
				context:expect(transcript.malformed):toBe(1)
				context:expect(transcript.toolCalls):toBe(3)
			end
		)

		suite:case("prefers per-model usage and drops latencies when a line has no time", function(context)
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
			context:expect(transcript.usageSource):toBe "models"
			context:expect(transcript.usage):toEqual { input = 6, cacheCreation = 8, cacheRead = 7, output = 8 }
			context:expect(transcript.modelUsage["claude-haiku-5-5"].output):toBe(2)
			context:expect(transcript.turnLatencies):toEqual {}
			context:expect(transcript.toolSeconds):toBe(nil)
		end)

		suite:case("reads stamped lines and builds the Claude Code command", function(context)
			local lines = AgentEval.adapters.parseStamped '1.250000\t{"a":1}\r\nplain line\n2.5\t{}\n'
			context:expect(lines):toEqual {
				{ at = 1.25, text = '{"a":1}' } :: AgentEval.Line,
				{ at = nil, text = "plain line" } :: AgentEval.Line,
				{ at = 2.5, text = "{}" },
			}
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
			context:expect(AgentEval.adapters.claudeArguments(request)):toEqual {
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
			context
				:expect(function()
					AgentEval.adapters.claudeArguments(request)
				end)
				:toThrow 'unknown field "unknown"'
		end)

		suite:case("runs the Claude Code adapter through an injected executor", function(context)
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
					detail = nil,
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
				instructions = nil,
				mcpConfig = nil,
				allowedTools = nil,
				disallowedTools = nil,
				env = { KEY = "value" },
				model = nil,
				seed = 1,
				budgets = { wallSeconds = 30 },
				options = {},
			}
			local outcome = adapter.run(request, services)
			context:expect(outcome.status):toBe "completed"
			context:expect(outcome.transcript.usage.output):toBe(9)
			context:expect(seen[1].cwd):toBe "/w"
			context:expect(seen[1].input):toBe "/e/prompt.md"
			context:expect(seen[1].deadlineSeconds):toBe(30)
			context:expect(seen[1].stamp):toBe(true)
			context:expect(seen[1].env):toEqual { KEY = "value" }
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
					detail = nil,
				}
			end
			local failed = adapter.run(request, services)
			context:expect(failed.status):toBe "failed"
			context:expect(failed.detail):toBe "the agent exited with 1 and reported no result"
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
			context:expect(adapter.run(request, services).status):toBe "unsupported"
		end)

		suite:case("expands command adapter placeholders without naming the arm", function(context)
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
					detail = nil,
				}
			end
			local adapter = AgentEval.adapters.command {
				id = "other",
				argv = { "agent", "--model", "{model}", "--prompt", "{prompt_file}", "{arm}" },
				decode = Lute.parse,
			}
			local outcome = adapter.run({
				run = "r",
				task = "t",
				arm = "secret",
				workspace = "/w",
				directory = "/e",
				suiteDirectory = "/s",
				prompt = "brief",
				promptFile = "/e/prompt.md",
				instructions = nil,
				mcpConfig = nil,
				allowedTools = nil,
				disallowedTools = nil,
				env = {},
				model = "m",
				seed = 1,
				budgets = { wallSeconds = 30 },
				options = {},
			}, services)
			context:expect(seen[1].argv):toEqual { "agent", "--model", "m", "--prompt", "/e/prompt.md", "{arm}" }
			context:expect(outcome.status):toBe "completed"
			context:expect(outcome.transcript.result):toBe "final answer"
		end)
	end)
end
