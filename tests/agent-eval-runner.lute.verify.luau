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
		files.makeDirectory(assert(string.match(path, "^(.*)/[^/]+$")))
		files.write(path, text)
	end
	put(
		"/suite/eval.json",
		Fakes.json {
			schemaVersion = 1,
			id = "suite",
			tasks = { "tasks/one", "tasks/two" },
			arms = {
				object {
					id = "treatment",
					overlay = { "arms/treatment" },
					instructions = "arms/treatment.md",
					mcp = "arms/mcp.json",
					allowedTools = { "Read", "Write" },
				},
				{ id = "baseline" },
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
				object { id = "module", kind = "command", argv = { "need", "{workspace}/main.luau" } },
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
				},
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
	options: {
		selection: AgentEval.Selection?,
		adapters: { [string]: AgentEval.Adapter }?,
		checksOnly: boolean?,
	}?
): AgentEval.RunSummary
	local given: { selection: AgentEval.Selection?, adapters: { [string]: AgentEval.Adapter }?, checksOnly: boolean? } = options
		or {}
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
		checksOnly = given.checksOnly,
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

it("keeps an early provisioning failure when its evidence directory can be created afterward", function()
	local memory = Fakes.memory()
	corpus(memory)
	local directory = "/evidence/runs/one/treatment/agent/seed-1"
	local makeDirectory = memory.files.makeDirectory
	local refused = false
	memory.files.makeDirectory = function(path: string)
		if path == directory and not refused then
			refused = true
			error("initial directory creation failed", 0)
		end
		makeDirectory(path)
	end
	local calls: Calls = { requests = {} }
	local summary = execute(memory, calls, { selection = { tasks = { "one" }, arms = { "treatment" } } })
	expect(#calls.requests):toBe(0)
	expect(#summary.results):toBe(1)
	local result = summary.results[1]
	expect(result.status):toBe "provision_failed"
	expect(result.passed):toBe(false)
	expect(result.detail):toBe "initial directory creation failed"
	expect(Lute.parse(memory.files.read(directory .. "/result.json"))):toEqual(result)
end)

it("reports the original setup fault when its failed result cannot be persisted", function()
	local memory = Fakes.memory()
	corpus(memory)
	local directory = "/evidence/runs/one/treatment/agent/seed-1"
	local makeDirectory = memory.files.makeDirectory
	memory.files.makeDirectory = function(path: string)
		if path == directory then
			error("evidence directory is unavailable", 0)
		end
		makeDirectory(path)
	end
	local calls: Calls = { requests = {} }
	local messages: { string } = {}
	local summary = AgentEval.run {
		suite = suiteOf(memory),
		loader = Fakes.loader(memory.files),
		services = Fakes.services(memory.files, {}),
		adapters = { replay = replay(calls) },
		evidence = "/evidence",
		encode = Lute.encode,
		decode = Lute.parse,
		selection = { tasks = { "one" }, arms = { "treatment" } },
		log = function(message: string)
			table.insert(messages, message)
		end,
	}
	expect(#calls.requests):toBe(0)
	expect(summary.results[1].status):toBe "provision_failed"
	expect(summary.results[1].passed):toBe(false)
	expect(summary.results[1].detail):toBe "evidence directory is unavailable"
	expect(memory.files.exists(directory .. "/result.json")):toBe(false)
	expect(table.concat(messages, "\n")):toContain "result could not be kept"
	expect(table.concat(messages, "\n")):toContain "evidence directory is unavailable"
end)

it("rechecks saved workspaces without calling an adapter or changing agent metrics", function()
	local memory = Fakes.memory()
	corpus(memory)
	local calls: Calls = { requests = {} }
	local before = execute(memory, calls, { selection = { tasks = { "one" } } })
	local count = #calls.requests
	local after = execute(memory, calls, { selection = { tasks = { "one" } }, checksOnly = true })
	expect(#calls.requests):toBe(count)
	expect(after.ran):toBe(0)
	for index, result in after.results do
		expect(result.metrics):toEqual(before.results[index].metrics)
		expect(result.session):toEqual(before.results[index].session)
		expect(result.startedAt):toBe(before.results[index].startedAt)
		expect(result.finishedAt):toBe(before.results[index].finishedAt)
		expect(#check(result, "cases").cases):toBe(2)
	end
end)
it("rechecks a saved deadline stop without counting it as a pass", function()
	local memory = Fakes.memory()
	corpus(memory)
	local calls: Calls = { requests = {} }
	local before = execute(memory, calls, { selection = { tasks = { "one" } } })
	for _, result in before.results do
		local path = result.directory .. "/result.json"
		local saved = Lute.parse(memory.files.read(path)) :: { [string]: unknown }
		saved.status = "timed_out"
		saved.exceeded = { "wallSeconds" }
		memory.files.write(path, Lute.encode(saved))
	end
	local count = #calls.requests
	local after = execute(memory, calls, { selection = { tasks = { "one" } }, checksOnly = true })
	expect(#calls.requests):toBe(count)
	for _, result in after.results do
		expect(result.status):toBe "timed_out"
		expect(result.passed):toBe(false)
		expect(result.timeToPassSeconds):toBe(nil)
		expect(#check(result, "cases").cases):toBe(2)
	end
end)
it("refuses to recheck a saved run that did not complete or reach its deadline", function()
	local memory = Fakes.memory()
	corpus(memory)
	local calls: Calls = { requests = {} }
	local before = execute(memory, calls, { selection = { tasks = { "one" } } })
	local path = before.results[1].directory .. "/result.json"
	local saved = Lute.parse(memory.files.read(path)) :: { [string]: unknown }
	saved.status = "failed"
	memory.files.write(path, Lute.encode(saved))
	local ok, problem = pcall(execute, memory, calls, { selection = { tasks = { "one" } }, checksOnly = true })
	expect(ok):toBe(false)
	expect(tostring(problem)):toContain "checks-only requires a completed or deadline-stopped saved run"
end)
it("scoped Studio releases before checks and never keeps an adapter error", function()
	for _, configuration in
		{
			{ raises = false, keep = false },
			{ raises = true, keep = false },
			{ raises = false, keep = true },
			{ raises = true, keep = true },
		}
	do
		local raises = configuration.raises
		local memory = Fakes.memory()
		corpus(memory)
		local configured = suiteOf(memory)
		for _, arm in configured.arms do
			arm.setup.mcp = nil
			arm.setup.studio = {
				place = "{evidence}/agent.rbxlx",
				build = { "build", "{workspace}" },
				keep = configuration.keep,
			}
		end
		local services = Fakes.services(memory.files, {})
		local opened, closed = 0, 0
		services.studio = function(workspace, directory, place, build, _seconds)
			opened += 1
			expect(place):toBe(directory .. "/agent.rbxlx")
			expect(build[2]):toBe(workspace)
			local config = directory .. "/mcp.json"
			memory.files.write(config, "scoped")
			return {
				config = config,
				close = function(keep)
					expect(keep):toBe(configuration.keep and not raises)
					closed += 1
				end,
			}
		end
		local checks = services.checks
		services.checks = function(gate, directory, runId)
			expect(closed):toBe(opened)
			return checks(gate, directory, runId)
		end
		local adapter = replay { requests = {} }
		local summary = AgentEval.run {
			suite = configured,
			loader = Fakes.loader(memory.files),
			services = services,
			adapters = {
				replay = {
					id = "replay",
					run = function(request, given)
						expect(request.mcpConfig):toBe(request.directory .. "/mcp.json")
						if raises then
							error "adapter failed"
						end
						return adapter.run(request, given)
					end,
				},
			},
			evidence = "/evidence",
			encode = Lute.encode,
			decode = Lute.parse,
			selection = { tasks = { "one" } },
		}
		expect(#summary.results):toBe(2)
		expect(opened):toBe(2)
		expect(closed):toBe(2)
	end
end)
describe("agent evaluation runner", function()
	it("provisions each run, runs hidden checks and records metrics", function()
		local memory = Fakes.memory()
		corpus(memory)
		local calls: Calls = { requests = {} }
		local summary = execute(memory, calls)
		expect(#summary.results):toBe(4)
		expect(summary.ran):toBe(4)
		local ids: { string } = {}
		for _, result in summary.results do
			table.insert(ids, result.id)
		end
		expect(ids):toEqual {
			"one/treatment/agent/1",
			"one/baseline/agent/1",
			"two/treatment/agent/1",
			"two/baseline/agent/1",
		}

		local treatment = find(summary, "one/treatment/agent/1")
		expect(treatment.status):toBe "completed"
		expect(treatment.checksPassed):toBe(true)
		expect(treatment.passed):toBe(true)
		expect(treatment.metrics.turns):toBe(2)
		expect(treatment.metrics.outputTokens):toBe(200)
		expect(treatment.metrics.totalTokens):toBe(2420)
		expect(treatment.metrics.turnLatencies):toEqual { 2, 2 }
		expect(treatment.metrics.toolCalls):toBe(2)
		expect(treatment.session.model):toBe "claude-opus-5-5"
		expect(treatment.timeToPassSeconds):toBe(7)

		local cases = check(treatment, "cases")
		expect(cases.passed):toBe(true)
		expect(cases.cases):toEqual {
			{ id = "loads", status = "passed" },
			{ id = "works", status = "passed" },
		}
		expect(check(treatment, "optional").passed):toBe(false)
		expect(check(treatment, "optional").required):toBe(false)
		expect(treatment.scores["score.lines"]):toBe(3)
		expect(treatment.scores["interface.phone.score"]):toBe(100)
		expect(check(treatment, "interface.console").device):toBe "console"
		expect(#treatment.audits):toBe(2)
		expect(#treatment.captures):toBe(2)
		expect(treatment.captures[1].label):toBe "main"
		expect(treatment.captures[1].size):toBe(#PNG)

		local request = calls.requests[1]
		expect(request.instructions):toBe "Read GUIDE.md."
		expect(request.allowedTools):toEqual { "Read", "Write" }
		expect(request.workspace):toBe "/live/suite/runs/one/treatment/agent/seed-1"
		local mcp = memory.files.read "/evidence/runs/one/treatment/agent/seed-1/mcp.json"
		expect(string.find(mcp, "/live/suite/runs/one/treatment/agent/seed-1", 1, true) ~= nil):toBe(true)
		expect(memory.files.read "/evidence/runs/one/treatment/agent/seed-1/prompt.md"):toBe "Build the first thing."
		expect(memory.files.exists "/evidence/runs/one/treatment/agent/seed-1/workspace/GUIDE.md"):toBe(true)
		expect(memory.files.exists "/evidence/runs/one/baseline/agent/seed-1/workspace/GUIDE.md"):toBe(false)
		expect(memory.files.exists "/evidence/runs/one/treatment/agent/seed-1/workspace/README.md"):toBe(true)
		expect(memory.files.exists "/live/suite/runs/one/treatment/agent/seed-1"):toBe(false)
		expect(memory.files.read "/evidence/runs/one/treatment/agent/seed-1/checks/devices.txt"):toBe "phone,console"
		local transcript = memory.files.read "/evidence/runs/one/treatment/agent/seed-1/transcript.jsonl"
		expect(string.sub(transcript, 1, 9)):toBe "0.500000\t"

		local baseline = find(summary, "one/baseline/agent/1")
		expect(baseline.checksPassed):toBe(true)
		expect(baseline.exceeded):toEqual { "maxOutputTokens" }
		expect(baseline.passed):toBe(false)
		expect(baseline.scores["interface.phone.score"] < 100):toBe(true)
		expect(calls.requests[2].instructions):toBe(nil)

		expect(find(summary, "two/treatment/agent/1").passed):toBe(true)
		expect(find(summary, "two/treatment/agent/1").parent):toBe "one/treatment/agent/1"
		expect(memory.files.exists "/evidence/runs/two/treatment/agent/seed-1/workspace/main.luau"):toBe(true)
		expect(check(find(summary, "two/baseline/agent/1"), "extra").passed):toBe(false)

		local index = Lute.parse(memory.files.read "/evidence/index.json") :: { runs: { { id: string } } }
		expect(#index.runs):toBe(4)
		local loaded = AgentEval.load("/evidence", memory.files, Lute.parse)
		expect(#loaded):toBe(4)
		expect(loaded[1]):toEqual(treatment)
	end)

	it("resumes completed runs and repeats a run whose inputs changed", function()
		local memory = Fakes.memory()
		corpus(memory)
		local calls: Calls = { requests = {} }
		execute(memory, calls)
		expect(#calls.requests):toBe(4)
		local again = execute(memory, calls)
		expect(again.reused):toBe(4)
		expect(again.ran):toBe(0)
		expect(#calls.requests):toBe(4)
		memory.files.write("/suite/tasks/one/brief.md", "Build the first thing better.")
		local changed = execute(memory, calls)
		expect(changed.ran):toBe(4)
		expect(#calls.requests):toBe(8)
		expect(calls.requests[5].prompt):toBe "Build the first thing better."
	end)

	it("blocks a follow-up whose earlier run is absent and reports a missing adapter", function()
		local memory = Fakes.memory()
		corpus(memory)
		local calls: Calls = { requests = {} }
		local summary = execute(memory, calls, { selection = { tasks = { "two" } } })
		expect(#summary.results):toBe(2)
		expect(summary.results[1].status):toBe "blocked"
		expect(summary.results[1].passed):toBe(false)
		expect(#calls.requests):toBe(0)
		local other = Fakes.memory()
		corpus(other)
		local missing = execute(other, calls, { adapters = {}, selection = { tasks = { "one" } } })
		expect(missing.results[1].status):toBe "unsupported"
		expect(missing.results[1].detail):toBe "no adapter is named replay"
	end)

	it("retains passing checks without passing an author failure", function()
		local memory = Fakes.memory()
		corpus(memory)
		local adapter = AgentEval.adapters.replay {
			decode = Lute.parse,
			parse = AgentEval.transcript.parseCodexStream,
			respond = function(_request: AgentEval.AgentRequest): AgentEval.ReplayResponse
				return {
					files = { ["main.luau"] = "return {}" },
					exitcode = 0,
					lines = {
						{ at = 0, text = Fakes.json { type = "turn.started" } },
						{
							at = 1,
							text = Fakes.json {
								type = "error",
								message = "Selected model is at capacity. Please try a different model.",
							},
						},
						{
							at = 1.1,
							text = Fakes.json {
								type = "turn.failed",
								error = { message = "Selected model is at capacity. Please try a different model." },
							},
						},
					},
				}
			end,
		}
		local summary = execute(memory, { requests = {} }, {
			adapters = { replay = adapter },
			selection = { tasks = { "one" } },
		})
		local result = find(summary, "one/treatment/agent/1")
		expect(result.status):toBe "failed"
		expect(result.checksPassed):toBe(true)
		expect(result.passed):toBe(false)
		expect(result.timeToPassSeconds):toBe(nil)
		expect(#result.checks > 0):toBe(true)
	end)

	it("records an agent timeout and a raising adapter without losing the run", function()
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
		expect(first.status):toBe "timed_out"
		expect(first.exceeded):toEqual { "wallSeconds" }
		expect(first.checksPassed):toBe(true)
		expect(first.passed):toBe(false)
		expect(first.metrics.wallSeconds):toBe(60)
		local second = find(summary, "one/baseline/agent/1")
		expect(second.status):toBe "provision_failed"
		expect(second.detail):toBe "adapter exploded"
		expect(memory.files.exists "/evidence/runs/one/baseline/agent/seed-1/result.json"):toBe(true)
	end)

	it("waits for an earlier run before it starts a follow-up in parallel", function()
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
		expect(#summary.results):toBe(4)
		local position: { [string]: number } = {}
		for index, id in order do
			position[id] = index
		end
		expect(position["two/treatment/agent/1"] > position["one/treatment/agent/1"]):toBe(true)
		expect(position["two/baseline/agent/1"] > position["one/baseline/agent/1"]):toBe(true)
		expect(find(summary, "two/treatment/agent/1").status):toBe "completed"
	end)
end)

return nil
