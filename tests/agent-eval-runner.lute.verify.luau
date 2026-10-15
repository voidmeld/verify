--!strict

local AgentEval = require "../src/agent-eval"
local Fakes = require "./agent-eval-fakes"
local Lute = require "../src/lute"
local Verify = require "../src/core"

type Object = { [string]: unknown }

local PNG = "\137PNG\r\n\26\n" .. string.rep("x", 32)

local function dump(width: number): string
	return Fakes.json {
		schemaVersion = 1,
		screen = { width = 800, height = 400, scale = 1, input = { "touch" } },
		roots = {
			{
				index = 1,
				class = "ScreenGui",
				path = "Gui",
				enabled = true,
				world = false,
				rect = { x = 0, y = 0, width = 800, height = 400 },
			},
		},
		elements = {
			{
				index = 1,
				root = 1,
				class = "TextButton",
				path = "Gui.Button",
				rect = { x = 10, y = 10, width = width, height = 48 },
				visible = true,
				interactive = true,
				selectable = true,
				background = { color = { r = 0, g = 0, b = 0 }, transparency = 0 },
				text = {
					content = "Go",
					size = 18,
					bounds = { width = 20, height = 18 },
					fits = true,
					color = { r = 1, g = 1, b = 1 },
				},
			},
		},
		instances = 2,
	}
end

local function corpus(memory: Fakes.Memory, brief: string?)
	local files = memory.files
	local function put(path: string, text: string)
		files.makeDirectory(string.match(path, "^(.*)/[^/]+$") :: string)
		files.write(path, text)
	end
	put(
		"/suite/eval.json",
		Fakes.json {
			schemaVersion = 1,
			id = "suite",
			tasks = { "tasks/one", "tasks/two" },
			arms = {
				{
					id = "treatment",
					overlay = { "arms/treatment" },
					instructions = "arms/treatment.md",
					mcp = "arms/mcp.json",
					allowedTools = { "Read", "Write" },
				} :: Object,
				{ id = "baseline" } :: Object,
			},
			agents = { { id = "agent", adapter = "replay", model = "model-x" } },
			seeds = { 1 },
			budgets = { maxTurns = 10, maxOutputTokens = 500, wallSeconds = 60 },
			devices = {
				{ id = "phone", width = 800, height = 400, input = { "touch" } },
				{ id = "console", width = 1920, height = 1080, input = { "gamepad" } },
			},
		}
	)
	put("/suite/arms/treatment/GUIDE.md", "guide")
	put("/suite/arms/treatment.md", "Read GUIDE.md.")
	put("/suite/arms/mcp.json", '{"mcpServers":{"docs":{"command":"docs","args":["{workspace}"]}}}')
	put(
		"/suite/tasks/one/task.json",
		Fakes.json {
			schemaVersion = 1,
			id = "one",
			title = "First task",
			tier = "core",
			brief = "brief.md",
			starter = "starter",
			checks = {
				{ id = "module", kind = "command", argv = { "need", "{workspace}/main.luau" } } :: Object,
				{
					id = "cases",
					kind = "verify",
					argv = { "cases", "{workspace}/main.luau", "{report}" },
					after = { "module" },
				},
				{
					id = "dump",
					kind = "command",
					perDevice = true,
					argv = { "write", "{outputs}/dump-{device}.json", "{workspace}" },
				},
				{
					id = "capture",
					kind = "command",
					perDevice = true,
					argv = { "write", "{captures}/{device}/main.png", "PNG" },
				},
				{ id = "score", kind = "command", scores = true, argv = { "write", "{scores}", '{"lines": 3}' } },
				{ id = "devices", kind = "command", argv = { "write", "{outputs}/devices.txt", "{devices}" } },
				{ id = "optional", kind = "command", required = false, argv = { "fail" } },
				{
					id = "interface",
					kind = "audit",
					perDevice = true,
					dump = "{outputs}/dump-{device}.json",
					after = { "dump" },
				} :: Object,
			},
		}
	)
	put("/suite/tasks/one/brief.md", brief or "Build the first thing.")
	put("/suite/tasks/one/starter/README.md", "starter")
	put(
		"/suite/tasks/two/task.json",
		Fakes.json {
			schemaVersion = 1,
			id = "two",
			title = "Change request",
			brief = "brief.md",
			from = "one",
			checks = { { id = "extra", kind = "command", argv = { "need", "{workspace}/extra.luau" } } },
		}
	)
	put("/suite/tasks/two/brief.md", "Add the extra thing.")
end

type Calls = { requests: { AgentEval.AgentRequest } }

local function replay(calls: Calls): AgentEval.Adapter
	return AgentEval.adapters.replay {
		decode = Lute.parse,
		respond = function(request: AgentEval.AgentRequest): AgentEval.ReplayResponse
			table.insert(calls.requests, request)
			local files: { [string]: string } = {}
			if request.task == "one" then
				files["main.luau"] = "return {}"
			elseif request.arm == "treatment" then
				files["extra.luau"] = "return {}"
			end
			local output = if request.arm == "treatment" then 100 else 300
			return {
				files = files,
				lines = Fakes.stream { session = request.run, turns = 2, output = output },
			}
		end,
	}
end

local function suiteOf(memory: Fakes.Memory): AgentEval.Suite
	local loader = Fakes.loader(memory.files)
	return AgentEval.decodeSuite(Lute.parse(memory.files.read "/suite/eval.json"), "/suite/eval.json", loader)
end

local function execute(
	memory: Fakes.Memory,
	calls: Calls,
	options: { selection: AgentEval.Selection?, adapters: { [string]: AgentEval.Adapter }? }?
): AgentEval.RunSummary
	local given: { selection: AgentEval.Selection?, adapters: { [string]: AgentEval.Adapter }? } = options or {}
	local services = Fakes.services(memory.files, {
		write = function(job, files)
			local path = job.argv[2]
			local text = job.argv[3]
			if string.find(path, "dump-", 1, true) ~= nil then
				text = dump(if string.find(text, "treatment", 1, true) ~= nil then 60 else 30)
			elseif text == "PNG" then
				text = PNG
			end
			files.write(path, text)
			return Fakes.exited(0)
		end,
	})
	return AgentEval.run {
		suite = suiteOf(memory),
		loader = Fakes.loader(memory.files),
		services = services,
		adapters = given.adapters or { replay = replay(calls) },
		evidence = "/evidence",
		encode = Lute.encode,
		decode = Lute.parse,
		selection = given.selection,
	}
end

local function find(summary: AgentEval.RunSummary, id: string): AgentEval.RunResult
	for _, result in summary.results do
		if result.id == id then
			return result
		end
	end
	error("no result " .. id, 0)
end

local function check(result: AgentEval.RunResult, id: string): AgentEval.CheckResult
	for _, entry in result.checks do
		if entry.id == id then
			return entry
		end
	end
	error("no check " .. id, 0)
end

return function(suite: Verify.Harness)
	suite:case("scoped Studio provisioning is per run and closes when an adapter raises", function(context)
		local memory = Fakes.memory()
		corpus(memory)
		local configured = suiteOf(memory)
		for _, arm in configured.arms do
			arm.setup.mcp = nil
			arm.setup.studio = { place = "{evidence}/agent.rbxlx", build = { "build", "{workspace}" } }
		end
		local services = Fakes.services(memory.files, {})
		local opened, closed = 0, 0
		services.studio = function(workspace, directory, place, build, _seconds)
			opened += 1
			context:expect(place):toBe(directory .. "/agent.rbxlx")
			context:expect(build[2]):toBe(workspace)
			local config = directory .. "/mcp.json"
			memory.files.write(config, "scoped")
			return {
				config = config,
				close = function()
					closed += 1
				end,
			}
		end
		local summary = AgentEval.run {
			suite = configured,
			loader = Fakes.loader(memory.files),
			services = services,
			adapters = {
				replay = {
					id = "replay",
					run = function(request)
						context:expect(request.mcpConfig):toBe(request.directory .. "/mcp.json")
						error "adapter failed"
					end,
				},
			},
			evidence = "/evidence",
			encode = Lute.encode,
			decode = Lute.parse,
			selection = { tasks = { "one" } },
		}
		context:expect(#summary.results):toBe(2)
		context:expect(opened):toBe(2)
		context:expect(closed):toBe(2)
	end)
	suite:suite("agent evaluation runner", function()
		suite:case("provisions each run, runs hidden checks and records metrics", function(context)
			local memory = Fakes.memory()
			corpus(memory)
			local calls: Calls = { requests = {} }
			local summary = execute(memory, calls)
			context:expect(#summary.results):toBe(4)
			context:expect(summary.ran):toBe(4)
			local ids: { string } = {}
			for _, result in summary.results do
				table.insert(ids, result.id)
			end
			context:expect(ids):toEqual {
				"one/treatment/agent/1",
				"one/baseline/agent/1",
				"two/treatment/agent/1",
				"two/baseline/agent/1",
			}

			local treatment = find(summary, "one/treatment/agent/1")
			context:expect(treatment.status):toBe "completed"
			context:expect(treatment.checksPassed):toBe(true)
			context:expect(treatment.passed):toBe(true)
			context:expect(treatment.metrics.turns):toBe(2)
			context:expect(treatment.metrics.outputTokens):toBe(200)
			context:expect(treatment.metrics.totalTokens):toBe(2420)
			context:expect(treatment.metrics.turnLatencies):toEqual { 2, 2 }
			context:expect(treatment.metrics.toolCalls):toBe(2)
			context:expect(treatment.session.model):toBe "claude-opus-5-5"
			context:expect(treatment.timeToPassSeconds):toBe(7)

			local cases = check(treatment, "cases")
			context:expect(cases.passed):toBe(true)
			context:expect(cases.cases):toEqual {
				{ id = "loads", status = "passed" },
				{ id = "works", status = "passed" },
			}
			context:expect(check(treatment, "optional").passed):toBe(false)
			context:expect(check(treatment, "optional").required):toBe(false)
			context:expect(treatment.scores["score.lines"]):toBe(3)
			context:expect(treatment.scores["interface.phone.score"]):toBe(100)
			context:expect(check(treatment, "interface.console").device):toBe "console"
			context:expect(#treatment.audits):toBe(2)
			context:expect(#treatment.captures):toBe(2)
			context:expect(treatment.captures[1].label):toBe "main"
			context:expect(treatment.captures[1].size):toBe(#PNG)

			local request = calls.requests[1]
			context:expect(request.instructions):toBe "Read GUIDE.md."
			context:expect(request.allowedTools):toEqual { "Read", "Write" }
			context:expect(request.workspace):toBe "/live/suite/runs/one/treatment/agent/seed-1"
			local mcp = memory.files.read "/evidence/runs/one/treatment/agent/seed-1/mcp.json"
			context:expect(string.find(mcp, "/live/suite/runs/one/treatment/agent/seed-1", 1, true) ~= nil):toBe(true)
			context
				:expect(memory.files.read "/evidence/runs/one/treatment/agent/seed-1/prompt.md")
				:toBe "Build the first thing."
			context
				:expect(memory.files.exists "/evidence/runs/one/treatment/agent/seed-1/workspace/GUIDE.md")
				:toBe(true)
			context
				:expect(memory.files.exists "/evidence/runs/one/baseline/agent/seed-1/workspace/GUIDE.md")
				:toBe(false)
			context
				:expect(memory.files.exists "/evidence/runs/one/treatment/agent/seed-1/workspace/README.md")
				:toBe(true)
			context:expect(memory.files.exists "/live/suite/runs/one/treatment/agent/seed-1"):toBe(false)
			context
				:expect(memory.files.read "/evidence/runs/one/treatment/agent/seed-1/checks/devices.txt")
				:toBe "phone,console"
			local transcript = memory.files.read "/evidence/runs/one/treatment/agent/seed-1/transcript.jsonl"
			context:expect(string.sub(transcript, 1, 9)):toBe "0.500000\t"

			local baseline = find(summary, "one/baseline/agent/1")
			context:expect(baseline.checksPassed):toBe(true)
			context:expect(baseline.exceeded):toEqual { "maxOutputTokens" }
			context:expect(baseline.passed):toBe(false)
			context:expect(baseline.scores["interface.phone.score"] < 100):toBe(true)
			context:expect(calls.requests[2].instructions):toBe(nil)

			context:expect(find(summary, "two/treatment/agent/1").passed):toBe(true)
			context:expect(find(summary, "two/treatment/agent/1").parent):toBe "one/treatment/agent/1"
			context
				:expect(memory.files.exists "/evidence/runs/two/treatment/agent/seed-1/workspace/main.luau")
				:toBe(true)
			context:expect(check(find(summary, "two/baseline/agent/1"), "extra").passed):toBe(false)

			local index = Lute.parse(memory.files.read "/evidence/index.json") :: { runs: { { id: string } } }
			context:expect(#index.runs):toBe(4)
			local loaded = AgentEval.load("/evidence", memory.files, Lute.parse)
			context:expect(#loaded):toBe(4)
			context:expect(loaded[1]):toEqual(treatment)
		end)

		suite:case("resumes completed runs and repeats a run whose inputs changed", function(context)
			local memory = Fakes.memory()
			corpus(memory)
			local calls: Calls = { requests = {} }
			execute(memory, calls)
			context:expect(#calls.requests):toBe(4)
			local again = execute(memory, calls)
			context:expect(again.reused):toBe(4)
			context:expect(again.ran):toBe(0)
			context:expect(#calls.requests):toBe(4)
			memory.files.write("/suite/tasks/one/brief.md", "Build the first thing better.")
			local changed = execute(memory, calls)
			context:expect(changed.ran):toBe(4)
			context:expect(#calls.requests):toBe(8)
			context:expect(calls.requests[5].prompt):toBe "Build the first thing better."
		end)

		suite:case("blocks a follow-up whose earlier run is absent and reports a missing adapter", function(context)
			local memory = Fakes.memory()
			corpus(memory)
			local calls: Calls = { requests = {} }
			local summary = execute(memory, calls, { selection = { tasks = { "two" } } })
			context:expect(#summary.results):toBe(2)
			context:expect(summary.results[1].status):toBe "blocked"
			context:expect(summary.results[1].passed):toBe(false)
			context:expect(#calls.requests):toBe(0)
			local other = Fakes.memory()
			corpus(other)
			local missing = execute(other, calls, { adapters = {}, selection = { tasks = { "one" } } })
			context:expect(missing.results[1].status):toBe "unsupported"
			context:expect(missing.results[1].detail):toBe "no adapter is named replay"
		end)

		suite:case("records an agent timeout and a raising adapter without losing the run", function(context)
			local memory = Fakes.memory()
			corpus(memory)
			local timed = AgentEval.adapters.replay {
				decode = Lute.parse,
				respond = function(request: AgentEval.AgentRequest): AgentEval.ReplayResponse
					if request.arm == "baseline" then
						error("adapter exploded", 0)
					end
					return {
						files = { ["main.luau"] = "return {}" },
						lines = Fakes.stream { session = "s", turns = 1, output = 10, result = false },
						timedOut = true,
						seconds = 60,
					}
				end,
			}
			local summary = execute(memory, { requests = {} }, {
				adapters = { replay = timed },
				selection = { tasks = { "one" } },
			})
			local first = find(summary, "one/treatment/agent/1")
			context:expect(first.status):toBe "timed_out"
			context:expect(first.exceeded):toEqual { "wallSeconds" }
			context:expect(first.checksPassed):toBe(true)
			context:expect(first.passed):toBe(false)
			context:expect(first.metrics.wallSeconds):toBe(60)
			local second = find(summary, "one/baseline/agent/1")
			context:expect(second.status):toBe "provision_failed"
			context:expect(second.detail):toBe "adapter exploded"
			context:expect(memory.files.exists "/evidence/runs/one/baseline/agent/seed-1/result.json"):toBe(true)
		end)

		suite:case("waits for an earlier run before it starts a follow-up in parallel", function(context)
			local memory = Fakes.memory()
			corpus(memory)
			local calls: Calls = { requests = {} }
			local services = Fakes.services(memory.files, {
				write = function(job, files)
					files.write(job.argv[2], if job.argv[3] == "PNG" then PNG else dump(60))
					return Fakes.exited(0)
				end,
			})
			local queue: { () -> () } = {}
			local active = 0
			local peak = 0
			services.spawn = function(body: () -> ())
				table.insert(queue, function()
					active += 1
					peak = math.max(peak, active)
					body()
					active -= 1
				end)
			end
			services.wait = function(_seconds: number)
				local pending = table.clone(queue)
				table.clear(queue)
				for _, body in pending do
					body()
				end
			end
			local order: { string } = {}
			local adapter = replay(calls)
			local tracked: AgentEval.Adapter = {
				id = "replay",
				run = function(request, given)
					table.insert(order, request.run)
					return adapter.run(request, given)
				end,
			}
			local summary = AgentEval.run {
				suite = suiteOf(memory),
				loader = Fakes.loader(memory.files),
				services = services,
				adapters = { replay = tracked },
				evidence = "/evidence",
				encode = Lute.encode,
				decode = Lute.parse,
				parallelism = 2,
			}
			context:expect(#summary.results):toBe(4)
			local position: { [string]: number } = {}
			for index, id in order do
				position[id] = index
			end
			context:expect(position["two/treatment/agent/1"] > position["one/treatment/agent/1"]):toBe(true)
			context:expect(position["two/baseline/agent/1"] > position["one/baseline/agent/1"]):toBe(true)
			context:expect(find(summary, "two/treatment/agent/1").status):toBe "completed"
		end)
	end)
end
