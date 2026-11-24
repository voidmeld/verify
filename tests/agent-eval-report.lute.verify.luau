--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local AgentEval = require "../src/agent-eval"
local Fakes = require "./agent-eval-fakes"
local Lute = require "../src/lute"

type Object = { [string]: unknown }

type Shape = {
	passed: boolean,
	tokens: number,
	wall: number,
	latencies: { number },
	audit: number?,
	violations: number?,
	seed: number?,
	agent: string?,
}

local function result(task: string, arm: string, shape: Shape): AgentEval.RunResult
	local seed = shape.seed or 1
	local agent = shape.agent or "agent"
	return {
		schemaVersion = 1,
		id = ("%s/%s/%s/%d"):format(task, arm, agent, seed),
		digest = "d",
		suite = "suite",
		task = task,
		tier = "core",
		arm = arm,
		agent = agent,
		adapter = "replay",
		seed = seed,
		order = seed,
		status = "completed",
		passed = shape.passed,
		checksPassed = shape.passed,
		exceeded = {},
		metrics = {
			turns = shape.tokens / 1000,
			messages = shape.tokens / 1000,
			subagentMessages = 0,
			inputTokens = shape.tokens / 2,
			cacheCreationTokens = 0,
			cacheReadTokens = shape.tokens / 4,
			outputTokens = shape.tokens / 4,
			totalTokens = shape.tokens,
			costUsd = shape.tokens / 100000,
			wallSeconds = shape.wall,
			agentSeconds = shape.wall,
			turnLatencies = shape.latencies,
			turnIntervals = shape.latencies,
			toolCalls = 0,
			toolErrors = 0,
			permissionDenials = 0,
		},
		session = {
			finish = "success",
			usageSource = "result",
			tools = {},
			mcpServers = {},
			malformed = 0,
		},
		checks = {},
		scores = {},
		audits = if shape.audit ~= nil
			then {
				{
					device = "phone",
					score = shape.audit,
					path = "/a.json",
					rules = if shape.violations ~= nil then { ["text-truncated"] = shape.violations } else {},
				},
			}
			else {},
		captures = {},
		timeToPassSeconds = if shape.passed then shape.wall else nil,
		startedAt = 0,
		finishedAt = 0,
		directory = "/e",
	}
end

local function savedFixture()
	local memory = Fakes.memory()
	local files = memory.files
	local function put(path: string, text: string)
		files.makeDirectory(assert(string.match(path, "^(.*)/[^/]+$")))
		files.write(path, text)
	end
	put(
		"/s/eval.json",
		Fakes.json {
			schemaVersion = 1,
			id = "suite",
			tasks = { "tasks/t" },
			arms = { { id = "treatment" }, { id = "baseline" } },
			agents = { { id = "agent", adapter = "replay" } },
			devices = { { id = "phone", width = 800, height = 400, input = { "touch" } } },
		}
	)
	put(
		"/s/tasks/t/task.json",
		Fakes.json { schemaVersion = 1, id = "t", title = "T", brief = "brief.md", starter = "starter" }
	)
	put("/s/tasks/t/brief.md", "Make a shop.")
	put("/s/tasks/t/starter/a.txt", "a")
	local entries: { { path: string } } = {}
	local results: { AgentEval.RunResult } = {}
	for _, arm in { "treatment", "baseline" } do
		local saved = result("t", arm, { passed = true, tokens = 1, wall = 1, latencies = {} })
		local image = "/e/" .. arm .. "/main.png"
		put(image, "\137PNG\r\n\26\npixels")
		saved.captures = { { device = "phone", label = "main", path = image, sha256 = arm, size = 14 } }
		put("/e/" .. arm .. "/result.json", Fakes.json(saved))
		table.insert(results, saved)
		table.insert(entries, { path = arm })
	end
	put("/e/index.json", Fakes.json { runs = entries })
	return {
		files = files,
		suite = AgentEval.decodeSuite(Lute.parse(files.read "/s/eval.json"), "/s/eval.json", Fakes.loader(files)),
		results = results,
	}
end

describe("agent evaluation statistics", function()
	it("computes nearest-rank percentiles and medians", function()
		local stats = AgentEval.stats
		local values = { 5, 1, 4, 2, 3, 6, 7, 8, 9, 10 }
		expect(stats.percentile(values, 50)):toBe(5)
		expect(stats.percentile(values, 95)):toBe(10)
		expect(stats.percentile({}, 50)):toBe(nil)
		expect(stats.median(values)):toBe(5.5)
		expect(stats.median { 3, 1, 2 }):toBe(2)
		expect(stats.mean { 1, 2, 3 }):toBe(2)
		expect(values[1]):toBe(5)
	end)

	it("draws a seeded paired bootstrap interval", function()
		local units: { number } = {}
		for index = 1, 40 do
			table.insert(units, index % 2)
		end
		local function mean(sample: { number }): number?
			return AgentEval.stats.mean(sample)
		end
		local first = AgentEval.stats.bootstrap { units = units, statistic = mean, resamples = 500, seed = 5 }
		local second = AgentEval.stats.bootstrap { units = units, statistic = mean, resamples = 500, seed = 5 }
		expect(first):toEqual(second)
		expect(first.estimate):toBe(0.5)
		expect(assert(first.lower) < 0.5 and assert(first.upper) > 0.5):toBe(true)
		expect(assert(first.lower) > 0.25 and assert(first.upper) < 0.75):toBe(true)
		expect(first.valid):toBe(500)
		local other = AgentEval.stats.bootstrap { units = units, statistic = mean, resamples = 500, seed = 6 }
		expect(other.lower == first.lower and other.upper == first.upper):toBe(false)
		local constant = AgentEval.stats.bootstrap { units = { 2, 2, 2 }, statistic = mean, resamples = 50, seed = 1 }
		expect(constant.lower):toBe(2)
		expect(constant.upper):toBe(2)
		local empty = AgentEval.stats.bootstrap { units = {}, statistic = mean, seed = 1 }
		expect(empty.estimate):toBe(nil)
	end)
end)

describe("saved agent judgments", function()
	it("loads saved runs and refuses missing indexes and malformed results", function()
		local fixture = savedFixture()
		local files = fixture.files
		expect(AgentEval.load("/e", files, Lute.parse)):toEqual(fixture.results)
		expect(function()
			AgentEval.load("/missing", files, Lute.parse)
		end):toThrow "no run index"
		files.write("/e/treatment/result.json", "{}")
		expect(function()
			AgentEval.load("/e", files, Lute.parse)
		end):toThrow()
	end)

	it("judges captured screenshots once and reuses unchanged judgments", function()
		local fixture = savedFixture()
		local files, decoded = fixture.files, fixture.suite
		local left, right = fixture.results[1], fixture.results[2]
		local comparisons = AgentEval.judge.comparisons(decoded, { left, right })
		expect(#comparisons):toBe(1)
		expect(comparisons[1].id):toBe "t/agent/seed-1/phone/treatment~baseline"
		expect(comparisons[1].brief):toBe "Make a shop."
		expect(comparisons[1].deviceText):toBe "phone, 800x400 pixels at scale 1, touch"
		local calls = 0
		local transport: AgentEval.JudgeTransport = function(request)
			calls += 1
			local first = ""
			for _, part in request.parts do
				if part.image ~= nil then
					first = part.image
					break
				end
			end
			local criteria: Object = {}
			local choice = if first == left.captures[1].path then "first" else "second"
			for _, criterion in AgentEval.judge.DEFAULT_RUBRIC.criteria do
				criteria[criterion.id] = choice
			end
			return {
				text = Fakes.json { criteria = criteria, overall = choice, confidence = 1, reasons = { "clear" } },
				model = "judge",
			}
		end
		local options: AgentEval.JudgeOptions = {
			suite = decoded,
			results = { left, right },
			transport = transport,
			transportName = "fake",
			files = files,
			hash = Fakes.hash,
			encode = Lute.encode,
			decode = Lute.parse,
			evidence = "/e",
			seed = 9,
		}
		local first = AgentEval.judge.run(options)
		expect(calls):toBe(2)
		expect(first[1].winner):toBe "treatment"
		expect(first[1].consistent):toBe(true)
		local again = AgentEval.judge.run(options)
		expect(calls):toBe(2)
		expect(again[1].winner):toBe "treatment"
		expect(#again[1].presentations):toBe(2)
		options.transportName = "codex:model-a:medium"
		AgentEval.judge.run(options)
		expect(calls):toBe(4)
		options.transportName = "codex:model-b:high"
		AgentEval.judge.run(options)
		expect(calls):toBe(6)
		options.transportName = "fake"
		AgentEval.judge.run(options)
		expect(calls):toBe(6)
		expect(#files.list "/e/judgments"):toBe(3)
		left.captures[1].sha256 = "changed"
		AgentEval.judge.run(options)
		expect(calls):toBe(8)
		local loaded = AgentEval.judge.load("/e", files, Lute.parse)
		expect(#loaded):toBe(1)
		expect(loaded[1].scoreA):toBe(1)
		expect(loaded[1].presentations[1].verdict ~= nil):toBe(true)
	end)
end)

return nil
