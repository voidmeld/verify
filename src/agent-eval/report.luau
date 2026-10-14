--!strict

local Core = require "../core"
local Judge = require "./judge"
local Random = require "./random"
local Result = require "./result"
local Schema = require "./schema"
local Stats = require "./stats"

export type Statistic = "difference" | "ratio" | "level"

export type Rule = {
	id: string,
	metric: string,
	lower: number?,
	upper: number?,
	agent: string?,
}

export type Thresholds = {
	treatment: string,
	baseline: string,
	confidence: number,
	resamples: number,
	seed: number,
	minimumTasks: number,
	rules: { Rule },
}

export type ArmSummary = {
	arm: string,
	runs: number,
	tasks: number,
	statuses: { [string]: number },
	passRate: number?,
	auditScore: number?,
	judgeWinRate: number?,
	judgments: number,
	inputTokens: number?,
	cacheCreationTokens: number?,
	cacheReadTokens: number?,
	outputTokens: number?,
	totalTokens: number?,
	costUsd: number?,
	turns: number?,
	turnLatencyP50: number?,
	turnLatencyP95: number?,
	wallSeconds: number?,
	timeToFirstPassSeconds: number?,
}

export type Comparison = {
	metric: string,
	statistic: Statistic,
	estimate: number?,
	lower: number?,
	upper: number?,
	tasks: number,
	valid: number,
}

export type RuleOutcome = {
	id: string,
	agent: string,
	metric: string,
	statistic: Statistic,
	bound: "lower" | "upper",
	threshold: number,
	value: number?,
	estimate: number?,
	tasks: number,
	passed: boolean,
	reason: string,
}

export type AgentSection = {
	agent: string,
	treatment: string,
	baseline: string,
	pairedTasks: number,
	unpaired: { string },
	arms: { ArmSummary },
	comparisons: { Comparison },
	rules: { RuleOutcome },
}

export type EvalReport = {
	schemaVersion: number,
	suite: string,
	runs: number,
	judgments: number,
	verdict: "PASS" | "FAIL",
	thresholds: Thresholds,
	agents: { AgentSection },
	calibration: Judge.Calibration?,
	limitations: { string },
}

type MetricSpec = { name: string, statistic: Statistic, rank: number? }

type ArmTask = {
	runs: { Result.RunResult },
	values: { [string]: number? },
	latencies: { number },
}

type TaskData = {
	task: string,
	arms: { [string]: ArmTask },
	judge: number?,
}

local METRICS: { MetricSpec } = {
	{ name = "passRate", statistic = "difference" },
	{ name = "auditScore", statistic = "difference" },
	{ name = "judgeWinRate", statistic = "level" },
	{ name = "inputTokens", statistic = "ratio" },
	{ name = "cacheCreationTokens", statistic = "ratio" },
	{ name = "cacheReadTokens", statistic = "ratio" },
	{ name = "outputTokens", statistic = "ratio" },
	{ name = "totalTokens", statistic = "ratio" },
	{ name = "costUsd", statistic = "ratio" },
	{ name = "turns", statistic = "ratio" },
	{ name = "turnLatencyP50", statistic = "ratio", rank = 50 },
	{ name = "turnLatencyP95", statistic = "ratio", rank = 95 },
	{ name = "wallSeconds", statistic = "ratio" },
	{ name = "timeToFirstPassSeconds", statistic = "ratio" },
}

local function metricSpec(name: string): MetricSpec?
	for _, spec in METRICS do
		if spec.name == name then
			return spec
		end
	end
	return nil
end

local function decodeThresholds(value: unknown): Thresholds
	local raw = Schema.record(value, "thresholds")
	Schema.only(raw, "thresholds", {
		"schemaVersion",
		"treatment",
		"baseline",
		"confidence",
		"resamples",
		"seed",
		"minimumTasks",
		"rules",
	})
	if raw.schemaVersion ~= 1 then
		Schema.fail("thresholds.schemaVersion", "must be 1")
	end
	local rules: { Rule } = {}
	local ids: { string } = {}
	for index, item in Schema.list(raw.rules, "thresholds.rules") do
		local where = ("thresholds.rules[%d]"):format(index)
		local entry = Schema.record(item, where)
		Schema.only(entry, where, { "id", "metric", "lower", "upper", "agent", "why" })
		local metric = Schema.text(entry.metric, where .. ".metric")
		if metricSpec(metric) == nil then
			Schema.fail(where .. ".metric", ("names an unknown metric %q"):format(metric))
		end
		local rule: Rule = {
			id = Schema.identifier(entry.id, where .. ".id"),
			metric = metric,
			lower = Schema.optionalNumber(entry.lower, where .. ".lower"),
			upper = Schema.optionalNumber(entry.upper, where .. ".upper"),
			agent = if Schema.absent(entry.agent) then nil else Schema.identifier(entry.agent, where .. ".agent"),
		}
		if (rule.lower == nil) == (rule.upper == nil) then
			Schema.fail(where, "must declare exactly one of lower or upper")
		end
		table.insert(ids, rule.id)
		table.insert(rules, rule)
	end
	if #rules == 0 then
		Schema.fail("thresholds.rules", "must declare at least one rule")
	end
	Schema.unique(ids, "thresholds.rules")
	local confidence = Schema.optionalNumber(raw.confidence, "thresholds.confidence", 0) or 0.95
	if confidence <= 0 or confidence >= 1 then
		Schema.fail("thresholds.confidence", "must be between 0 and 1")
	end
	local treatment = Schema.identifier(raw.treatment, "thresholds.treatment")
	local baseline = Schema.identifier(raw.baseline, "thresholds.baseline")
	if treatment == baseline then
		Schema.fail("thresholds", "must compare two different arms")
	end
	return {
		treatment = treatment,
		baseline = baseline,
		confidence = confidence,
		resamples = Schema.optionalNumber(raw.resamples, "thresholds.resamples", 1, true) or 2000,
		seed = Schema.optionalNumber(raw.seed, "thresholds.seed", 0, true) or 1,
		minimumTasks = Schema.optionalNumber(raw.minimumTasks, "thresholds.minimumTasks", 1, true) or 1,
		rules = rules,
	}
end

local function runValue(result: Result.RunResult, name: string): number?
	local metrics = result.metrics
	if name == "passRate" then
		return if result.passed then 1 else 0
	elseif name == "auditScore" then
		if #result.audits == 0 then
			return nil
		end
		local sum = 0
		for _, audit in result.audits do
			sum += audit.score
		end
		return sum / #result.audits
	elseif name == "inputTokens" then
		return metrics.inputTokens
	elseif name == "cacheCreationTokens" then
		return metrics.cacheCreationTokens
	elseif name == "cacheReadTokens" then
		return metrics.cacheReadTokens
	elseif name == "outputTokens" then
		return metrics.outputTokens
	elseif name == "totalTokens" then
		return metrics.totalTokens
	elseif name == "costUsd" then
		return metrics.costUsd
	elseif name == "turns" then
		return metrics.turns
	elseif name == "wallSeconds" then
		return metrics.wallSeconds
	end
	return nil
end

local function meanOf(runs: { Result.RunResult }, name: string): number?
	local values: { number } = {}
	for _, run in runs do
		local value = runValue(run, name)
		if value ~= nil then
			table.insert(values, value)
		end
	end
	return Stats.mean(values)
end

local function timeToFirstPass(runs: { Result.RunResult }): number?
	if #runs == 0 then
		return nil
	end
	local ordered = table.clone(runs)
	table.sort(ordered, function(left, right)
		if left.seed ~= right.seed then
			return left.seed < right.seed
		end
		return left.order < right.order
	end)
	local elapsed = 0
	for _, run in ordered do
		if run.passed then
			return elapsed + (run.timeToPassSeconds or run.metrics.wallSeconds)
		end
		elapsed += run.metrics.wallSeconds
	end
	return elapsed
end

local function armTask(runs: { Result.RunResult }): ArmTask
	local values: { [string]: number? } = {}
	for _, spec in METRICS do
		if spec.rank == nil and spec.name ~= "judgeWinRate" and spec.name ~= "timeToFirstPassSeconds" then
			values[spec.name] = meanOf(runs, spec.name)
		end
	end
	values.timeToFirstPassSeconds = timeToFirstPass(runs)
	local latencies: { number } = {}
	for _, run in runs do
		for _, latency in run.metrics.turnLatencies do
			table.insert(latencies, latency)
		end
	end
	return { runs = runs, values = values, latencies = latencies }
end

local function judgeScore(judgment: Judge.Judgment, arm: string, other: string?): number?
	if judgment.scoreA == nil or (judgment.status ~= "judged" and judgment.status ~= "forfeit") then
		return nil
	end
	if judgment.a == arm and (other == nil or judgment.b == other) then
		return judgment.scoreA
	end
	if judgment.b == arm and (other == nil or judgment.a == other) then
		return 1 - (judgment.scoreA :: number)
	end
	return nil
end

local function mean(values: { number }): number?
	return Stats.mean(values)
end

local function build(
	suite: string,
	results: { Result.RunResult },
	judgments: { Judge.Judgment },
	thresholds: Thresholds,
	calibration: Judge.Calibration?
): EvalReport
	local agents: { string } = {}
	local agentSeen: { [string]: boolean } = {}
	local armOrder: { string } = {}
	local armSeen: { [string]: boolean } = {}
	for _, result in results do
		if not agentSeen[result.agent] then
			agentSeen[result.agent] = true
			table.insert(agents, result.agent)
		end
		if not armSeen[result.arm] then
			armSeen[result.arm] = true
			table.insert(armOrder, result.arm)
		end
	end
	local limitations: { string } = {}
	if not armSeen[thresholds.treatment] then
		table.insert(limitations, ("no run belongs to the treatment arm %s"):format(thresholds.treatment))
	end
	if not armSeen[thresholds.baseline] then
		table.insert(limitations, ("no run belongs to the baseline arm %s"):format(thresholds.baseline))
	end
	local sections: { AgentSection } = {}
	local allPassed = #agents > 0
	for _, agent in agents do
		local byTask: { [string]: { [string]: { Result.RunResult } } } = {}
		local taskOrder: { string } = {}
		for _, result in results do
			if result.agent == agent then
				if byTask[result.task] == nil then
					byTask[result.task] = {}
					table.insert(taskOrder, result.task)
				end
				local arms = byTask[result.task]
				arms[result.arm] = arms[result.arm] or {}
				table.insert(arms[result.arm], result)
			end
		end
		local data: { TaskData } = {}
		local unpaired: { string } = {}
		for _, task in taskOrder do
			local arms: { [string]: ArmTask } = {}
			for arm, runs in byTask[task] do
				arms[arm] = armTask(runs)
			end
			local scores: { number } = {}
			for _, judgment in judgments do
				if judgment.agent == agent and judgment.task == task then
					local value = judgeScore(judgment, thresholds.treatment, thresholds.baseline)
					if value ~= nil then
						table.insert(scores, value)
					end
				end
			end
			table.insert(data, { task = task, arms = arms, judge = mean(scores) })
			if arms[thresholds.treatment] == nil or arms[thresholds.baseline] == nil then
				table.insert(unpaired, task)
			end
		end
		local paired: { TaskData } = {}
		for _, item in data do
			if item.arms[thresholds.treatment] ~= nil and item.arms[thresholds.baseline] ~= nil then
				table.insert(paired, item)
			end
		end
		local summaries: { ArmSummary } = {}
		for _, arm in armOrder do
			local runs: { Result.RunResult } = {}
			local tasks = 0
			local statuses: { [string]: number } = {}
			local latencies: { number } = {}
			local ttfp: { number } = {}
			for _, item in data do
				local entry = item.arms[arm]
				if entry ~= nil then
					tasks += 1
					for _, run in entry.runs do
						table.insert(runs, run)
						statuses[run.status] = (statuses[run.status] or 0) + 1
					end
					for _, latency in entry.latencies do
						table.insert(latencies, latency)
					end
					local value = entry.values.timeToFirstPassSeconds
					if value ~= nil then
						table.insert(ttfp, value)
					end
				end
			end
			local wins: { number } = {}
			for _, judgment in judgments do
				if judgment.agent == agent then
					local value = judgeScore(judgment, arm, nil)
					if value ~= nil then
						table.insert(wins, value)
					end
				end
			end
			if #runs > 0 then
				table.insert(summaries, {
					arm = arm,
					runs = #runs,
					tasks = tasks,
					statuses = statuses,
					passRate = meanOf(runs, "passRate"),
					auditScore = meanOf(runs, "auditScore"),
					judgeWinRate = mean(wins),
					judgments = #wins,
					inputTokens = meanOf(runs, "inputTokens"),
					cacheCreationTokens = meanOf(runs, "cacheCreationTokens"),
					cacheReadTokens = meanOf(runs, "cacheReadTokens"),
					outputTokens = meanOf(runs, "outputTokens"),
					totalTokens = meanOf(runs, "totalTokens"),
					costUsd = meanOf(runs, "costUsd"),
					turns = meanOf(runs, "turns"),
					turnLatencyP50 = Stats.percentile(latencies, 50),
					turnLatencyP95 = Stats.percentile(latencies, 95),
					wallSeconds = meanOf(runs, "wallSeconds"),
					timeToFirstPassSeconds = mean(ttfp),
				})
			end
		end
		local comparisons: { Comparison } = {}
		local byMetric: { [string]: Comparison } = {}
		for _, spec in METRICS do
			local units: { TaskData } = {}
			for _, item in paired do
				if spec.statistic == "level" then
					if item.judge ~= nil then
						table.insert(units, item)
					end
				elseif spec.rank ~= nil then
					if
						#item.arms[thresholds.treatment].latencies > 0
						and #item.arms[thresholds.baseline].latencies > 0
					then
						table.insert(units, item)
					end
				elseif
					item.arms[thresholds.treatment].values[spec.name] ~= nil
					and item.arms[thresholds.baseline].values[spec.name] ~= nil
				then
					table.insert(units, item)
				end
			end
			local function statistic(sample: { TaskData }): number?
				if spec.statistic == "level" then
					local values: { number } = {}
					for _, item in sample do
						table.insert(values, item.judge :: number)
					end
					return mean(values)
				end
				if spec.rank ~= nil then
					local left: { number } = {}
					local right: { number } = {}
					for _, item in sample do
						for _, value in item.arms[thresholds.treatment].latencies do
							table.insert(left, value)
						end
						for _, value in item.arms[thresholds.baseline].latencies do
							table.insert(right, value)
						end
					end
					local top = Stats.percentile(left, spec.rank :: number)
					local bottom = Stats.percentile(right, spec.rank :: number)
					if top == nil or bottom == nil or bottom == 0 then
						return nil
					end
					return top / bottom
				end
				local left: { number } = {}
				local right: { number } = {}
				for _, item in sample do
					table.insert(left, item.arms[thresholds.treatment].values[spec.name] :: number)
					table.insert(right, item.arms[thresholds.baseline].values[spec.name] :: number)
				end
				local top = mean(left)
				local bottom = mean(right)
				if top == nil or bottom == nil then
					return nil
				end
				if spec.statistic == "difference" then
					return top - bottom
				end
				if bottom == 0 then
					return nil
				end
				return top / bottom
			end
			local interval = Stats.bootstrap {
				units = units,
				statistic = statistic,
				resamples = thresholds.resamples,
				seed = Random.derive(thresholds.seed, agent .. "/" .. spec.name),
				confidence = thresholds.confidence,
			}
			local comparison: Comparison = {
				metric = spec.name,
				statistic = spec.statistic,
				estimate = interval.estimate,
				lower = interval.lower,
				upper = interval.upper,
				tasks = #units,
				valid = interval.valid,
			}
			byMetric[spec.name] = comparison
			table.insert(comparisons, comparison)
		end
		local outcomes: { RuleOutcome } = {}
		for _, rule in thresholds.rules do
			if rule.agent ~= nil and rule.agent ~= agent then
				continue
			end
			local comparison = byMetric[rule.metric]
			local bound: "lower" | "upper" = if rule.lower ~= nil then "lower" else "upper"
			local threshold = (rule.lower or rule.upper) :: number
			local value = if bound == "lower" then comparison.lower else comparison.upper
			local outcome: RuleOutcome = {
				id = rule.id,
				agent = agent,
				metric = rule.metric,
				statistic = comparison.statistic,
				bound = bound,
				threshold = threshold,
				value = value,
				estimate = comparison.estimate,
				tasks = comparison.tasks,
				passed = false,
				reason = "",
			}
			if comparison.tasks < thresholds.minimumTasks then
				outcome.reason = ("%d paired task(s) carry this metric; the thresholds need %d"):format(
					comparison.tasks,
					thresholds.minimumTasks
				)
			elseif value == nil then
				outcome.reason = "the interval is undefined"
			elseif bound == "lower" then
				outcome.passed = (value :: number) > threshold
				outcome.reason = ("the %d%% lower bound %.4g %s %.4g"):format(
					math.floor(thresholds.confidence * 100 + 0.5),
					value :: number,
					if outcome.passed then "is above" else "is not above",
					threshold
				)
			else
				outcome.passed = (value :: number) < threshold
				outcome.reason = ("the %d%% upper bound %.4g %s %.4g"):format(
					math.floor(thresholds.confidence * 100 + 0.5),
					value :: number,
					if outcome.passed then "is below" else "is not below",
					threshold
				)
			end
			if not outcome.passed then
				allPassed = false
			end
			table.insert(outcomes, outcome)
		end
		if #unpaired > 0 then
			table.sort(unpaired)
			table.insert(
				limitations,
				("agent %s: %d task(s) lack a run of both arms and are excluded from paired statistics"):format(
					agent,
					#unpaired
				)
			)
		end
		table.insert(sections, {
			agent = agent,
			treatment = thresholds.treatment,
			baseline = thresholds.baseline,
			pairedTasks = #paired,
			unpaired = unpaired,
			arms = summaries,
			comparisons = comparisons,
			rules = outcomes,
		})
	end
	local judged = 0
	for _, judgment in judgments do
		if judgment.status == "judged" or judgment.status == "forfeit" then
			judged += 1
		end
	end
	if judged == 0 then
		table.insert(limitations, "no judgment is available, so judgeWinRate is undefined")
	end
	if calibration == nil then
		table.insert(limitations, "no human labels were supplied, so the judge is not calibrated")
	end
	table.insert(
		limitations,
		"Intervals resample tasks with replacement. They describe this task corpus, not every possible task."
	)
	return {
		schemaVersion = 1,
		suite = suite,
		runs = #results,
		judgments = judged,
		verdict = if allPassed then "PASS" else "FAIL",
		thresholds = thresholds,
		agents = sections,
		calibration = calibration,
		limitations = limitations,
	}
end

local function show(value: number?, digits: number?): string
	if value == nil then
		return "n/a"
	end
	local places = digits or 3
	return string.format("%." .. tostring(places) .. "f", value :: number)
end

local function markdown(report: EvalReport): string
	local lines: { string } = {
		("# Agent evaluation: %s"):format(report.suite),
		"",
		("Verdict: **%s**. Runs: %d. Judgments: %d. Confidence: %d%%. Resamples: %d. Seed: %d."):format(
			report.verdict,
			report.runs,
			report.judgments,
			math.floor(report.thresholds.confidence * 100 + 0.5),
			report.thresholds.resamples,
			report.thresholds.seed
		),
		"",
		("Treatment arm: `%s`. Baseline arm: `%s`."):format(report.thresholds.treatment, report.thresholds.baseline),
	}
	for _, section in report.agents do
		table.insert(lines, "")
		table.insert(lines, ("## Agent `%s`"):format(section.agent))
		table.insert(lines, "")
		table.insert(lines, ("Paired tasks: %d."):format(section.pairedTasks))
		table.insert(lines, "")
		table.insert(
			lines,
			"| Arm | Runs | Pass rate | Audit score | Judge win rate | Total tokens | Output tokens | Cost (USD) | Turns | Turn latency p50 (s) | Turn latency p95 (s) | Wall time (s) | Time to first pass (s) |"
		)
		table.insert(
			lines,
			"| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
		)
		for _, arm in section.arms do
			table.insert(
				lines,
				("| `%s` | %d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |"):format(
					arm.arm,
					arm.runs,
					show(arm.passRate),
					show(arm.auditScore, 1),
					show(arm.judgeWinRate),
					show(arm.totalTokens, 0),
					show(arm.outputTokens, 0),
					show(arm.costUsd, 4),
					show(arm.turns, 1),
					show(arm.turnLatencyP50, 2),
					show(arm.turnLatencyP95, 2),
					show(arm.wallSeconds, 1),
					show(arm.timeToFirstPassSeconds, 1)
				)
			)
		end
		table.insert(lines, "")
		table.insert(lines, ("### `%s` compared with `%s`"):format(section.treatment, section.baseline))
		table.insert(lines, "")
		table.insert(lines, "| Metric | Statistic | Estimate | Lower | Upper | Tasks |")
		table.insert(lines, "| --- | --- | ---: | ---: | ---: | ---: |")
		for _, comparison in section.comparisons do
			table.insert(
				lines,
				("| %s | %s | %s | %s | %s | %d |"):format(
					comparison.metric,
					comparison.statistic,
					show(comparison.estimate),
					show(comparison.lower),
					show(comparison.upper),
					comparison.tasks
				)
			)
		end
		table.insert(lines, "")
		table.insert(lines, "### Thresholds")
		table.insert(lines, "")
		table.insert(lines, "| Rule | Metric | Bound | Threshold | Value | Result | Reason |")
		table.insert(lines, "| --- | --- | --- | ---: | ---: | --- | --- |")
		for _, rule in section.rules do
			table.insert(
				lines,
				("| `%s` | %s | %s | %s | %s | %s | %s |"):format(
					rule.id,
					rule.metric,
					rule.bound,
					show(rule.threshold),
					show(rule.value),
					if rule.passed then "PASS" else "FAIL",
					rule.reason
				)
			)
		end
	end
	if report.calibration ~= nil then
		local calibration = report.calibration :: Judge.Calibration
		table.insert(lines, "")
		table.insert(lines, "## Judge calibration")
		table.insert(lines, "")
		table.insert(
			lines,
			("Compared: %d. Agreement: %s. Cohen's kappa: %s. Unlabeled judgments: %d. Labels without a judgment: %d."):format(
				calibration.compared,
				show(calibration.agreement),
				show(calibration.kappa),
				#calibration.unlabeled,
				#calibration.unjudged
			)
		)
	end
	table.insert(lines, "")
	table.insert(lines, "## Limitations")
	table.insert(lines, "")
	for _, limitation in report.limitations do
		table.insert(lines, "- " .. limitation)
	end
	table.insert(lines, "")
	return table.concat(lines, "\n")
end

local function verdict(report: EvalReport): Core.Report
	local tick = 0
	local harness = Core.createHarness {
		now = function(): number
			tick += 0.001
			return tick
		end,
		source = "agent-eval:" .. report.suite,
		prefixIds = false,
	}
	harness:suite(report.suite, function()
		for _, section in report.agents do
			for _, rule in section.rules do
				harness:case(("%s %s"):format(section.agent, rule.id), {
					id = ("%s:%s"):format(section.agent, rule.id),
					limitations = { "the verdict is a statistic over the recorded runs" },
					run = function(context: Core.Context)
						context:expect(rule.passed):toBeTrueWith(rule.reason)
					end,
				})
			end
		end
		if #report.agents == 0 then
			harness:case("runs exist", function(context: Core.Context)
				context:expect(false):toBeTrueWith "the evaluation has no runs"
			end)
		end
	end)
	return harness:run {
		executor = "agent-eval",
		environment = { suite = report.suite, verdict = tostring(report.verdict) },
	}
end

return {
	METRICS = METRICS,
	decodeThresholds = decodeThresholds,
	build = build,
	markdown = markdown,
	verdict = verdict,
}
