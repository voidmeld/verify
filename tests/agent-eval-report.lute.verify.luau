--!strict

local AgentEval = require "../src/agent-eval"
local Fakes = require "./agent-eval-fakes"
local Lute = require "../src/lute"
local Verify = require "../src/core"

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
		model = nil,
		seed = seed,
		order = seed,
		parent = nil,
		status = "completed",
		detail = nil,
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
			apiSeconds = nil,
			toolSeconds = nil,
			startupSeconds = nil,
			turnLatencies = shape.latencies,
			turnIntervals = shape.latencies,
			toolCalls = 0,
			toolErrors = 0,
			permissionDenials = 0,
		},
		session = {
			model = nil,
			session = nil,
			version = nil,
			finish = "success",
			usageSource = "result",
			tools = {},
			mcpServers = {},
			result = nil,
			malformed = 0,
		},
		checks = {},
		scores = {},
		audits = if shape.audit ~= nil
			then {
				{
					device = "phone",
					score = shape.audit :: number,
					path = "/a.json",
					rules = if shape.violations ~= nil then { ["text-truncated"] = shape.violations :: number } else {},
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

local function judgment(task: string, scoreA: number, seed: number?): AgentEval.Judgment
	return {
		id = ("%s/agent/seed-%d/phone/treatment~baseline"):format(task, seed or 1),
		task = task,
		agent = "agent",
		seed = seed or 1,
		device = "phone",
		a = "treatment",
		b = "baseline",
		status = "judged",
		order = "a-first",
		presentations = {},
		scoreA = scoreA,
		criteria = {},
		winner = if scoreA > 0.5 then "treatment" elseif scoreA < 0.5 then "baseline" else "tie",
		consistent = true,
		detail = nil,
	}
end

local function thresholds(rules: { Object }, extra: unknown): AgentEval.Thresholds
	local value: Object = {
		schemaVersion = 1,
		treatment = "treatment",
		baseline = "baseline",
		resamples = 400,
		seed = 11,
		rules = rules,
	}
	local additions: Object = if extra ~= nil then extra :: Object else {}
	for key, item in additions do
		value[key] = item
	end
	return AgentEval.report.decodeThresholds(Lute.parse(Fakes.json(value)))
end

local function corpus(): ({ AgentEval.RunResult }, { AgentEval.Judgment })
	local results: { AgentEval.RunResult } = {}
	local judgments: { AgentEval.Judgment } = {}
	for index = 1, 8 do
		local task = "task-" .. index
		for seed = 1, 2 do
			table.insert(
				results,
				result(task, "treatment", {
					passed = index ~= 8,
					tokens = 4000 + 100 * index,
					wall = 50 + index,
					latencies = { 2, 3, 2 + index / 10 },
					audit = 90 + index % 3,
					violations = index % 2,
					seed = seed,
				})
			)
			table.insert(
				results,
				result(task, "baseline", {
					passed = index % 2 == 0 and seed == 2,
					tokens = 9000 + 300 * index,
					wall = 90 + index,
					latencies = { 3, 4, 3 + index / 10 },
					audit = 70 + index % 5,
					violations = 4 + index % 3,
					seed = seed,
				})
			)
			table.insert(judgments, judgment(task, if index == 3 then 0.5 else 1, seed))
		end
	end
	return results, judgments
end

local function rule(report: AgentEval.EvalReport, id: string): { passed: boolean, value: number?, reason: string }
	for _, section in report.agents do
		for _, outcome in section.rules do
			if outcome.id == id then
				return outcome
			end
		end
	end
	error("no rule " .. id, 0)
end

local function comparison(
	report: AgentEval.EvalReport,
	metric: string
): { estimate: number?, lower: number?, upper: number?, tasks: number }
	for _, entry in report.agents[1].comparisons do
		if entry.metric == metric then
			return entry
		end
	end
	error("no metric " .. metric, 0)
end

return function(suite: Verify.Harness)
	suite:suite("agent evaluation statistics", function()
		suite:case("computes nearest-rank percentiles and medians", function(context)
			local stats = AgentEval.stats
			local values = { 5, 1, 4, 2, 3, 6, 7, 8, 9, 10 }
			context:expect(stats.percentile(values, 50)):toBe(5)
			context:expect(stats.percentile(values, 95)):toBe(10)
			context:expect(stats.percentile({}, 50)):toBe(nil)
			context:expect(stats.median(values)):toBe(5.5)
			context:expect(stats.median { 3, 1, 2 }):toBe(2)
			context:expect(stats.mean { 1, 2, 3 }):toBe(2)
			context:expect(values[1]):toBe(5)
		end)

		suite:case("draws a seeded paired bootstrap interval", function(context)
			local units: { number } = {}
			for index = 1, 40 do
				table.insert(units, index % 2)
			end
			local function mean(sample: { number }): number?
				return AgentEval.stats.mean(sample)
			end
			local first = AgentEval.stats.bootstrap { units = units, statistic = mean, resamples = 500, seed = 5 }
			local second = AgentEval.stats.bootstrap { units = units, statistic = mean, resamples = 500, seed = 5 }
			context:expect(first):toEqual(second)
			context:expect(first.estimate):toBe(0.5)
			context:expect((first.lower :: number) < 0.5 and (first.upper :: number) > 0.5):toBe(true)
			context:expect((first.lower :: number) > 0.25 and (first.upper :: number) < 0.75):toBe(true)
			context:expect(first.valid):toBe(500)
			local other = AgentEval.stats.bootstrap { units = units, statistic = mean, resamples = 500, seed = 6 }
			context:expect(other.lower == first.lower and other.upper == first.upper):toBe(false)
			local constant =
				AgentEval.stats.bootstrap { units = { 2, 2, 2 }, statistic = mean, resamples = 50, seed = 1 }
			context:expect(constant.lower):toBe(2)
			context:expect(constant.upper):toBe(2)
			local empty = AgentEval.stats.bootstrap { units = {}, statistic = mean, seed = 1 }
			context:expect(empty.estimate):toBe(nil)
		end)
	end)

	suite:suite("agent evaluation report", function()
		suite:case("pairs runs by task and evaluates pre-registered thresholds", function(context)
			local results, judgments = corpus()
			local report = AgentEval.report.build(
				"suite",
				results,
				judgments,
				thresholds({
					{ id = "quality", metric = "judgeWinRate", lower = 0.6 },
					{ id = "passes", metric = "passRate", lower = 0 },
					{ id = "tokens", metric = "totalTokens", upper = 0.8 },
					{ id = "audit", metric = "auditScore", lower = 5 },
					{ id = "latency", metric = "turnLatencyP50", upper = 1 },
					{ id = "time", metric = "timeToFirstPassSeconds", upper = 1 },
				}, { minimumTasks = 6 }),
				nil
			)
			context:expect(report.verdict):toBe "PASS"
			context:expect(report.runs):toBe(32)
			context:expect(report.agents[1].pairedTasks):toBe(8)
			context:expect(rule(report, "quality").passed):toBe(true)
			context:expect(rule(report, "tokens").passed):toBe(true)
			context:expect(comparison(report, "judgeWinRate").estimate):toBeCloseTo(15 / 16)
			context:expect(comparison(report, "passRate").estimate):toBeCloseTo(0.875 - 0.25)
			local treatment = report.agents[1].arms[1]
			context:expect(treatment.arm):toBe "treatment"
			context:expect(treatment.runs):toBe(16)
			context:expect(treatment.passRate):toBe(0.875)
			context:expect(treatment.judgeWinRate):toBeCloseTo(15 / 16)
			context:expect(report.agents[1].arms[2].judgeWinRate):toBeCloseTo(1 / 16)
			context:expect(treatment.turnLatencyP50):toBeCloseTo(2.4)
			local markdown = AgentEval.report.markdown(report)
			context:expect(markdown):toContain "Verdict: **PASS**"
			context:expect(markdown):toContain "| `quality` | judgeWinRate | lower |"
			local verdict = AgentEval.report.verdict(report)
			context:expect(Verify.decode(verdict).total):toBe(6)
			context:expect(verdict.passed):toBe(6)
			context:expect(verdict.results[1].id):toBe "agent:quality"
		end)

		suite:case("fails a threshold whose bound misses and names the reason", function(context)
			local results, judgments = corpus()
			local report = AgentEval.report.build(
				"suite",
				results,
				judgments,
				thresholds {
					{ id = "quality", metric = "judgeWinRate", lower = 0.99 },
					{ id = "tokens", metric = "totalTokens", upper = 0.1 },
				},
				nil
			)
			context:expect(report.verdict):toBe "FAIL"
			context:expect(rule(report, "quality").passed):toBe(false)
			context:expect(rule(report, "quality").reason):toContain "is not above 0.99"
			context:expect(rule(report, "tokens").reason):toContain "is not below 0.1"
			local few = AgentEval.report.build(
				"suite",
				results,
				judgments,
				thresholds({ { id = "few", metric = "passRate", lower = 0 } }, { minimumTasks = 9 }),
				nil
			)
			context:expect(rule(few, "few").reason):toBe "8 paired task(s) carry this metric; the thresholds need 9"
			context:expect(few.verdict):toBe "FAIL"
			local verdict = AgentEval.report.verdict(report)
			context:expect(verdict.failed):toBe(2)
			context:expect(verdict.results[1].failures[1].message):toContain "is not above 0.99"
		end)

		suite:case("evaluates bounds on the estimate and the ratio of audit violations", function(context)
			local results, judgments = corpus()
			local report = AgentEval.report.build(
				"suite",
				results,
				judgments,
				thresholds {
					{ id = "gain", metric = "passRate", atLeast = 0.25 },
					{ id = "gain-interval", metric = "passRate", lower = 0 },
					{ id = "fewer-violations", metric = "auditViolations", atMost = 0.4 },
					{ id = "no-violations", metric = "auditViolations", atMost = 0.01 },
					{ id = "large-gain", metric = "passRate", atLeast = 0.9 },
				},
				nil
			)
			local gain = rule(report, "gain")
			context:expect(gain.passed):toBe(true)
			context:expect(gain.value):toBeCloseTo(0.625)
			context:expect(gain.reason):toBe "the estimate 0.625 is at least 0.25"
			context:expect(rule(report, "gain-interval").passed):toBe(true)
			context:expect(comparison(report, "auditViolations").estimate):toBeCloseTo(0.5 / 5.125)
			context:expect(rule(report, "fewer-violations").passed):toBe(true)
			context:expect(rule(report, "no-violations").reason):toContain "is above 0.01"
			context:expect(rule(report, "large-gain").reason):toBe "the estimate 0.625 is below 0.9"
			context:expect(report.verdict):toBe "FAIL"
			context:expect(report.agents[1].arms[1].auditViolations):toBe(0.5)
			local markdown = AgentEval.report.markdown(report)
			context:expect(markdown):toContain "| `gain` | passRate | atLeast | 0.250 | 0.625 | PASS |"
			context:expect(markdown):toContain "Audit violations"
		end)

		suite:case("excludes unpaired tasks and counts censored time to first pass", function(context)
			local results: { AgentEval.RunResult } = {
				result("both", "treatment", { passed = false, tokens = 1000, wall = 10, latencies = {}, seed = 1 }),
				result("both", "treatment", { passed = true, tokens = 1000, wall = 20, latencies = {}, seed = 2 }),
				result("both", "baseline", { passed = false, tokens = 2000, wall = 30, latencies = {}, seed = 1 }),
				result("both", "baseline", { passed = false, tokens = 2000, wall = 40, latencies = {}, seed = 2 }),
				result("alone", "treatment", { passed = true, tokens = 1000, wall = 5, latencies = {} }),
			}
			local report = AgentEval.report.build(
				"suite",
				results,
				{},
				thresholds { { id = "time", metric = "timeToFirstPassSeconds", upper = 1 } },
				nil
			)
			local section = report.agents[1]
			context:expect(section.pairedTasks):toBe(1)
			context:expect(section.unpaired):toEqual { "alone" }
			context:expect(comparison(report, "timeToFirstPassSeconds").estimate):toBe(30 / 70)
			context:expect(comparison(report, "turnLatencyP50").tasks):toBe(0)
			context:expect(comparison(report, "judgeWinRate").estimate):toBe(nil)
			context:expect(section.arms[1].timeToFirstPassSeconds):toBe(17.5)
			local limitations = table.concat(report.limitations, "\n")
			context:expect(limitations):toContain "1 task(s) lack a run of both arms"
			context:expect(limitations):toContain "no judgment is available"
		end)

		suite:case("refuses malformed thresholds", function(context)
			local function refusal(value: Object): string
				local ok, problem = pcall(AgentEval.report.decodeThresholds, Lute.parse(Fakes.json(value)))
				context:expect(ok):toBe(false)
				return tostring(problem)
			end
			local base: Object = { schemaVersion = 1, treatment = "a", baseline = "b" }
			local unknown = table.clone(base)
			unknown.rules = { { id = "x", metric = "happiness", lower = 0 } }
			context:expect(refusal(unknown)):toContain 'unknown metric "happiness"'
			local both = table.clone(base)
			both.rules = { { id = "x", metric = "passRate", lower = 0, upper = 1 } }
			context:expect(refusal(both)):toContain "exactly one of lower, upper, atLeast or atMost"
			local same = table.clone(base)
			same.baseline = "a"
			same.rules = { { id = "x", metric = "passRate", lower = 0 } }
			context:expect(refusal(same)):toContain "two different arms"
			local none = table.clone(base)
			none.rules = {}
			context:expect(refusal(none)):toContain "at least one rule"
		end)

		suite:case("judges captured screenshots once and reuses unchanged judgments", function(context)
			local memory = Fakes.memory()
			local files = memory.files
			local function put(path: string, text: string)
				files.makeDirectory(string.match(path, "^(.*)/[^/]+$") :: string)
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
			put("/e/a/phone/main.png", "A")
			put("/e/b/phone/main.png", "B")
			local loader = Fakes.loader(files)
			local decoded = AgentEval.decodeSuite(Lute.parse(files.read "/s/eval.json"), "/s/eval.json", loader)
			local left = result("t", "treatment", { passed = true, tokens = 1, wall = 1, latencies = {} })
			local right = result("t", "baseline", { passed = true, tokens = 1, wall = 1, latencies = {} })
			left.captures =
				{ { device = "phone", label = "main", path = "/e/a/phone/main.png", sha256 = "aa", size = 1 } }
			right.captures =
				{ { device = "phone", label = "main", path = "/e/b/phone/main.png", sha256 = "bb", size = 1 } }
			local comparisons = AgentEval.judge.comparisons(decoded, { left, right })
			context:expect(#comparisons):toBe(1)
			context:expect(comparisons[1].id):toBe "t/agent/seed-1/phone/treatment~baseline"
			context:expect(comparisons[1].brief):toBe "Make a shop."
			context:expect(comparisons[1].deviceText):toBe "phone, 800x400 pixels at scale 1, touch"
			local calls = 0
			local transport: AgentEval.JudgeTransport = function(request)
				calls += 1
				local first = ""
				for _, part in request.parts do
					if part.image ~= nil then
						first = part.image :: string
						break
					end
				end
				local criteria: Object = {}
				local choice = if first == "/e/a/phone/main.png" then "first" else "second"
				for _, criterion in AgentEval.judge.DEFAULT_RUBRIC.criteria do
					criteria[criterion.id] = choice
				end
				return {
					text = Fakes.json { criteria = criteria, overall = choice, confidence = 1, reasons = { "clear" } },
					error = nil,
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
			context:expect(calls):toBe(2)
			context:expect(first[1].winner):toBe "treatment"
			context:expect(first[1].consistent):toBe(true)
			local again = AgentEval.judge.run(options)
			context:expect(calls):toBe(2)
			context:expect(again[1].winner):toBe "treatment"
			context:expect(#again[1].presentations):toBe(2)
			left.captures[1].sha256 = "changed"
			AgentEval.judge.run(options)
			context:expect(calls):toBe(4)
			local loaded = AgentEval.judge.load("/e", files, Lute.parse)
			context:expect(#loaded):toBe(1)
			context:expect(loaded[1].scoreA):toBe(1)
			context:expect(loaded[1].presentations[1].verdict ~= nil):toBe(true)
		end)
	end)
end
