--!strict

local Adapters = require "./adapters"
local Audit = require "../roblox/ui-audit"
local Gate = require "../gate"
local Model = require "./model"
local Paths = require "./paths"
local Result = require "./result"
local Schema = require "./schema"
local Services = require "./services"
local Transcript = require "./transcript"

export type Options = {
	suite: Model.Suite,
	loader: Model.Loader,
	services: Services.Services,
	adapters: { [string]: Adapters.Adapter },
	evidence: string,
	encode: (value: unknown) -> string,
	decode: (text: string) -> unknown,
	selection: Model.Selection?,
	parallelism: number?,
	resume: boolean?,
	log: ((line: string) -> ())?,
}

export type Summary = {
	index: Result.Index,
	results: { Result.RunResult },
	ran: number,
	reused: number,
}

type Instance = {
	id: string,
	check: Model.Check,
	device: Model.Device?,
}

local IMAGE_EXTENSIONS: { [string]: boolean } = { png = true, jpg = true, jpeg = true }

local function copyTree(files: Services.Files, from: string, to: string)
	if not files.isDirectory(from) then
		files.makeDirectory(Paths.parent(to))
		files.copy(from, to)
		return
	end
	files.makeDirectory(to)
	for _, entry in files.list(from) do
		local source = Paths.join(from, entry.name)
		local target = Paths.join(to, entry.name)
		if entry.kind == "directory" then
			copyTree(files, source, target)
		else
			files.copy(source, target)
		end
	end
end

local function moveTree(files: Services.Files, from: string, to: string)
	if files.exists(to) then
		files.remove(to)
	end
	files.makeDirectory(Paths.parent(to))
	local moved = pcall(files.move, from, to)
	if not moved or not files.exists(to) then
		copyTree(files, from, to)
		files.remove(from)
	end
end

local function expandChecks(task: Model.Task): { Instance }
	local result: { Instance } = {}
	for _, check in task.checks do
		if check.perDevice then
			for _, device in task.devices do
				table.insert(result, { id = check.id .. "." .. device.id, check = check, device = device })
			end
		else
			table.insert(result, { id = check.id, check = check, device = nil })
		end
	end
	return result
end

local function dependencies(instance: Instance, all: { Instance }): { string }
	local result: { string } = {}
	for _, name in instance.check.after do
		for _, other in all do
			if other.check.id == name then
				if instance.device == nil or other.device == nil or other.device == instance.device then
					table.insert(result, other.id)
				end
			end
		end
	end
	return result
end

local function substitute(word: string, values: { [string]: string }): string
	return (
		string.gsub(word, "{([%w_]+)}", function(name: string): string
			return values[name] or ("{" .. name .. "}")
		end)
	)
end

local function placeholders(
	spec: Model.RunSpec,
	workspace: string,
	directory: string,
	instance: Instance
): { [string]: string }
	local values: { [string]: string } = {
		workspace = workspace,
		task = spec.task.directory,
		evidence = directory,
		outputs = Paths.join(directory, "checks"),
		captures = Paths.join(directory, "captures"),
		scores = Paths.join(directory, ("checks/%s.scores.json"):format(instance.id)),
		seed = tostring(spec.seed),
	}
	if instance.device ~= nil then
		local device = instance.device :: Model.Device
		values.device = device.id
		values.width = tostring(device.width)
		values.height = tostring(device.height)
		values.scale = tostring(device.scale)
		values.input = table.concat(device.input, ",")
	end
	return values
end

local function auditOptions(raw: { [string]: unknown }, device: Model.Device?): (Audit.Options, number?)
	local label = "audit options"
	Schema.only(raw, label, {
		"minScore",
		"minTouchTarget",
		"touch",
		"gamepad",
		"contrast",
		"largeContrast",
		"largeTextSize",
		"largeBoldTextSize",
		"maxTypeSizes",
		"maxSpacingValues",
		"maxInstances",
		"pressFeedback",
		"ruleCap",
		"maxViolations",
	})
	local function optionalFlag(key: string): boolean?
		if Schema.absent(raw[key]) then
			return nil
		end
		return Schema.flag(raw[key], label .. "." .. key, false)
	end
	local options: Audit.Options = {
		minTouchTarget = Schema.optionalNumber(raw.minTouchTarget, label .. ".minTouchTarget", 0),
		touch = optionalFlag "touch",
		gamepad = optionalFlag "gamepad",
		contrast = Schema.optionalNumber(raw.contrast, label .. ".contrast", 1),
		largeContrast = Schema.optionalNumber(raw.largeContrast, label .. ".largeContrast", 1),
		largeTextSize = Schema.optionalNumber(raw.largeTextSize, label .. ".largeTextSize", 0),
		largeBoldTextSize = Schema.optionalNumber(raw.largeBoldTextSize, label .. ".largeBoldTextSize", 0),
		maxTypeSizes = Schema.optionalNumber(raw.maxTypeSizes, label .. ".maxTypeSizes", 0, true),
		maxSpacingValues = Schema.optionalNumber(raw.maxSpacingValues, label .. ".maxSpacingValues", 0, true),
		maxInstances = Schema.optionalNumber(raw.maxInstances, label .. ".maxInstances", 0, true),
		pressFeedback = optionalFlag "pressFeedback",
		weights = nil,
		ruleCap = Schema.optionalNumber(raw.ruleCap, label .. ".ruleCap", 0),
		maxViolations = Schema.optionalNumber(raw.maxViolations, label .. ".maxViolations", 0, true),
	}
	if device ~= nil and options.touch == nil and #device.input > 0 then
		options.touch = table.find(device.input, "touch") ~= nil
	end
	if device ~= nil and options.gamepad == nil and #device.input > 0 then
		options.gamepad = table.find(device.input, "gamepad") ~= nil
	end
	return options, Schema.optionalNumber(raw.minScore, label .. ".minScore", 0)
end

local function create(options: Options): () -> Summary
	local services = options.services
	local files = services.files
	local suite = options.suite
	local evidence = options.evidence
	local resume = options.resume ~= false
	local log = options.log or services.print
	local specs = Model.plan(suite, options.loader, options.selection)
	local inPlan: { [string]: boolean } = {}
	for _, spec in specs do
		inPlan[spec.id] = true
	end

	local function write(path: string, value: unknown)
		files.makeDirectory(Paths.parent(path))
		local temporary = path .. ".tmp"
		files.write(temporary, options.encode(value))
		if files.exists(path) then
			files.remove(path)
		end
		files.move(temporary, path)
	end

	local function stampedText(lines: { Services.Line }): string
		local out: { string } = {}
		for _, line in lines do
			if line.at ~= nil then
				table.insert(out, ("%.6f\t%s"):format(line.at :: number, line.text))
			else
				table.insert(out, line.text)
			end
		end
		return table.concat(out, "\n") .. (if #out > 0 then "\n" else "")
	end

	local function emptyMetrics(): Result.Metrics
		return {
			turns = 0,
			messages = 0,
			subagentMessages = 0,
			inputTokens = 0,
			cacheCreationTokens = 0,
			cacheReadTokens = 0,
			outputTokens = 0,
			totalTokens = 0,
			costUsd = nil,
			wallSeconds = 0,
			agentSeconds = nil,
			apiSeconds = nil,
			toolSeconds = nil,
			startupSeconds = nil,
			turnLatencies = {},
			turnIntervals = {},
			toolCalls = 0,
			toolErrors = 0,
			permissionDenials = 0,
		}
	end

	local function baseResult(spec: Model.RunSpec, directory: string, startedAt: number): Result.RunResult
		return {
			schemaVersion = Result.SCHEMA_VERSION,
			id = spec.id,
			digest = spec.digest,
			suite = suite.id,
			task = spec.task.id,
			tier = spec.task.tier,
			arm = spec.arm.id,
			agent = spec.agent.id,
			adapter = spec.agent.adapter,
			model = spec.agent.model,
			seed = spec.seed,
			order = spec.order,
			parent = spec.parent,
			status = "provision_failed",
			detail = nil,
			passed = false,
			checksPassed = false,
			exceeded = {},
			metrics = emptyMetrics(),
			session = {
				model = nil,
				session = nil,
				version = nil,
				finish = nil,
				usageSource = "none",
				tools = {},
				mcpServers = {},
				result = nil,
				malformed = 0,
			},
			checks = {},
			scores = {},
			audits = {},
			captures = {},
			timeToPassSeconds = nil,
			startedAt = startedAt,
			finishedAt = startedAt,
			directory = directory,
		}
	end

	local function runChecks(spec: Model.RunSpec, workspace: string, directory: string, result: Result.RunResult)
		local instances = expandChecks(spec.task)
		local producers: { Gate.ProducerDraft } = {}
		local byId: { [string]: Instance } = {}
		for _, instance in instances do
			byId[instance.id] = instance
			if instance.check.kind ~= "audit" then
				local values = placeholders(spec, workspace, directory, instance)
				local argv: { string } = {}
				for _, word in instance.check.argv do
					table.insert(argv, substitute(word, values))
				end
				local env: { [string]: string } = {}
				for key, value in instance.check.env do
					env[key] = substitute(value, values)
				end
				local expectation: Gate.ReportExpectation? = nil
				if instance.check.report ~= nil then
					local declared = instance.check.report :: Model.ReportExpectation
					expectation = { cases = declared.cases, minimum = declared.minimum, exact = declared.exact }
				end
				table.insert(producers, {
					id = instance.id,
					kind = "command",
					argv = argv,
					env = env,
					cwd = workspace,
					after = dependencies(instance, instances),
					deadlineSeconds = instance.check.deadlineSeconds,
					report = expectation,
				})
			end
		end
		files.makeDirectory(Paths.join(directory, "checks"))
		files.makeDirectory(Paths.join(directory, "captures"))
		for _, device in spec.task.devices do
			files.makeDirectory(Paths.join(directory, "captures/" .. device.id))
		end
		local statuses: { [string]: string } = {}
		if #producers > 0 then
			local gate = Gate.define {
				id = "agent-eval-checks",
				producers = producers,
				policy = { concurrency = 1, failFast = false, commandDeadlineSeconds = 600 },
			}
			local runId = ("checks-%s"):format(
				string.sub(services.hash(spec.id .. "\0" .. tostring(services.clock())), 1, 16)
			)
			local outcome = services.checks(gate, Paths.join(directory, "checks/gate"), runId)
			for _, record in outcome.producers do
				local instance = byId[record.id]
				statuses[record.id] = record.status
				local cases: { Result.CaseOutcome } = {}
				for _, case in outcome.execution.report.results do
					if string.sub(case.id, 1, #record.id + 1) == record.id .. ":" then
						table.insert(
							cases,
							{ id = string.sub(case.id, #record.id + 2), status = tostring(case.status) }
						)
					end
				end
				local check: Result.CheckResult = {
					id = record.id,
					check = instance.check.id,
					device = if instance.device ~= nil then (instance.device :: Model.Device).id else nil,
					kind = instance.check.kind,
					required = instance.check.required,
					status = record.status,
					passed = record.status == "passed",
					seconds = record.durationMicros / 1e6,
					detail = record.detail,
					cases = cases,
					scores = {},
				}
				if instance.check.scores then
					local path = Paths.join(directory, ("checks/%s.scores.json"):format(instance.id))
					if files.exists(path) then
						local parsed, value = pcall(function(): { [string]: number }
							local raw = Schema.record(options.decode(files.read(path)), "scores")
							local collected: { [string]: number } = {}
							for key, item in raw do
								collected[key] = Schema.number(item, "scores." .. key)
							end
							return collected
						end)
						if parsed then
							check.scores = value
						else
							check.detail = "the scores file is invalid: " .. tostring(value)
							check.passed = false
							check.status = "failed"
						end
					elseif check.passed then
						check.detail = "the check wrote no scores file"
						check.passed = false
						check.status = "failed"
					end
				end
				for name, value in check.scores do
					result.scores[record.id .. "." .. name] = value
				end
				table.insert(result.checks, check)
			end
		end
		for _, instance in instances do
			if instance.check.kind ~= "audit" then
				continue
			end
			local check: Result.CheckResult = {
				id = instance.id,
				check = instance.check.id,
				device = if instance.device ~= nil then (instance.device :: Model.Device).id else nil,
				kind = "audit",
				required = instance.check.required,
				status = "failed",
				passed = false,
				seconds = nil,
				detail = nil,
				cases = {},
				scores = {},
			}
			local blocked: string? = nil
			for _, dependency in dependencies(instance, instances) do
				if statuses[dependency] ~= "passed" then
					blocked = dependency
				end
			end
			if blocked ~= nil then
				check.status = "blocked"
				check.detail = ("blocked by %s (%s)"):format(
					blocked :: string,
					statuses[blocked :: string] or "not run"
				)
			else
				local values = placeholders(spec, workspace, directory, instance)
				local dumpPath = substitute(instance.check.dump :: string, values)
				local ok, problem = pcall(function(): string?
					if not files.exists(dumpPath) then
						error(("no interface dump at %s"):format(dumpPath), 0)
					end
					local dump = Audit.decode(options.decode(files.read(dumpPath)))
					local auditSettings, minimum = auditOptions(instance.check.audit, instance.device)
					local report = Audit.analyze(dump, auditSettings)
					local reportPath = Paths.join(directory, ("checks/%s.audit.json"):format(instance.id))
					write(reportPath, report)
					local rules: { [string]: number } = {}
					for rule, summary in report.rules do
						rules[rule] = summary.count
					end
					table.insert(result.audits, {
						device = check.device,
						score = report.score,
						path = reportPath,
						rules = rules,
					})
					check.scores.score = report.score
					result.scores[instance.id .. ".score"] = report.score
					if minimum ~= nil and report.score < minimum then
						check.detail = ("audit score %.1f is below %.1f"):format(report.score, minimum)
					else
						check.status = "passed"
						check.passed = true
						check.detail = ("audit score %.1f"):format(report.score)
					end
					return nil
				end)
				if not ok then
					check.detail = tostring(problem)
				end
			end
			statuses[instance.id] = check.status
			table.insert(result.checks, check)
		end
		result.checksPassed = true
		for _, check in result.checks do
			if check.required and not check.passed then
				result.checksPassed = false
			end
		end
		for _, device in spec.task.devices do
			local folder = Paths.join(directory, "captures/" .. device.id)
			if files.isDirectory(folder) then
				local entries = files.list(folder)
				table.sort(entries, function(left, right)
					return left.name < right.name
				end)
				for _, entry in entries do
					local stem, extension = string.match(entry.name, "^(.+)%.([%w]+)$")
					if entry.kind == "file" and stem ~= nil and IMAGE_EXTENSIONS[string.lower(extension :: string)] then
						local path = Paths.join(folder, entry.name)
						local bytes = files.read(path)
						if #bytes > 0 then
							table.insert(result.captures, {
								device = device.id,
								label = stem :: string,
								path = path,
								sha256 = services.hash(bytes),
								size = #bytes,
							})
						end
					end
				end
			end
		end
	end

	local function finishMetrics(result: Result.RunResult, outcome: Adapters.Outcome)
		local transcript = outcome.transcript
		local metrics = result.metrics
		metrics.turns = transcript.turns
		metrics.messages = transcript.messages
		metrics.subagentMessages = transcript.subagentMessages
		metrics.inputTokens = transcript.usage.input
		metrics.cacheCreationTokens = transcript.usage.cacheCreation
		metrics.cacheReadTokens = transcript.usage.cacheRead
		metrics.outputTokens = transcript.usage.output
		metrics.totalTokens = Transcript.total(transcript.usage)
		metrics.costUsd = transcript.costUsd
		metrics.wallSeconds = outcome.seconds
		metrics.agentSeconds = transcript.durationSeconds
		metrics.apiSeconds = transcript.apiSeconds
		metrics.toolSeconds = transcript.toolSeconds
		metrics.startupSeconds = transcript.startupSeconds
		metrics.turnLatencies = transcript.turnLatencies
		metrics.turnIntervals = transcript.turnIntervals
		metrics.toolCalls = transcript.toolCalls
		metrics.toolErrors = transcript.toolErrors
		metrics.permissionDenials = transcript.permissionDenials
		result.session = {
			model = transcript.model,
			session = transcript.session,
			version = transcript.version,
			finish = transcript.subtype,
			usageSource = transcript.usageSource,
			tools = transcript.tools,
			mcpServers = transcript.mcpServers,
			result = transcript.result,
			malformed = transcript.malformed,
		}
	end

	local function exceeded(result: Result.RunResult, budgets: Model.Budgets, status: Adapters.Status): { string }
		local list: { string } = {}
		if status == "timed_out" then
			table.insert(list, "wallSeconds")
		end
		if budgets.maxTurns ~= nil and result.metrics.turns > (budgets.maxTurns :: number) then
			table.insert(list, "maxTurns")
		end
		if budgets.maxOutputTokens ~= nil and result.metrics.outputTokens > (budgets.maxOutputTokens :: number) then
			table.insert(list, "maxOutputTokens")
		end
		if
			budgets.maxCostUsd ~= nil
			and result.metrics.costUsd ~= nil
			and (result.metrics.costUsd :: number) > (budgets.maxCostUsd :: number)
		then
			table.insert(list, "maxCostUsd")
		end
		return list
	end

	local function runOne(spec: Model.RunSpec): Result.RunResult
		local directory = Paths.join(evidence, spec.path)
		local startedAt = services.clock()
		local result = baseResult(spec, directory, startedAt)
		if files.exists(directory) then
			files.remove(directory)
		end
		files.makeDirectory(directory)
		local workspace = Paths.join(services.workspaces, ("%s/%s"):format(suite.id, spec.path))
		local finished = false
		local ok, problem = pcall(function(): string?
			local source = spec.task.starter
			if spec.task.from ~= nil then
				local parentDirectory =
					Paths.join(evidence, Model.runPath(spec.task.from :: string, spec.arm.id, spec.agent.id, spec.seed))
				local parentWorkspace = Paths.join(parentDirectory, "workspace")
				if
					not files.exists(Paths.join(parentDirectory, "result.json"))
					or not files.isDirectory(parentWorkspace)
				then
					result.status = "blocked"
					result.detail = ("the follow-up needs the workspace of %s"):format(
						spec.parent or (spec.task.from :: string)
					)
					return nil
				end
				source = parentWorkspace
			end
			if files.exists(workspace) then
				files.remove(workspace)
			end
			copyTree(files, source :: string, workspace)
			for _, overlay in spec.arm.setup.overlay do
				if files.isDirectory(overlay) then
					copyTree(files, overlay, workspace)
				else
					copyTree(files, overlay, Paths.join(workspace, Paths.leaf(overlay)))
				end
			end
			local promptFile = Paths.join(directory, "prompt.md")
			files.write(promptFile, spec.task.briefText)
			local mcpConfig: string? = nil
			if spec.arm.setup.mcp ~= nil then
				mcpConfig = Paths.join(directory, "mcp.json")
				local values = { workspace = workspace, evidence = directory }
				files.write(mcpConfig :: string, substitute(files.read(spec.arm.setup.mcp :: string), values))
			end
			local adapter = options.adapters[spec.agent.adapter]
			if adapter == nil then
				result.status = "unsupported"
				result.detail = ("no adapter is named %s"):format(spec.agent.adapter)
				return nil
			end
			local instructions: string? = nil
			if #spec.arm.setup.instructions > 0 then
				instructions = table.concat(spec.arm.setup.instructions, "\n\n")
			end
			local request: Adapters.Request = {
				run = spec.id,
				task = spec.task.id,
				arm = spec.arm.id,
				workspace = workspace,
				directory = directory,
				suiteDirectory = suite.directory,
				prompt = spec.task.briefText,
				promptFile = promptFile,
				instructions = instructions,
				mcpConfig = mcpConfig,
				allowedTools = spec.arm.setup.allowedTools,
				disallowedTools = spec.arm.setup.disallowedTools,
				env = spec.arm.setup.env,
				model = spec.agent.model,
				seed = spec.seed,
				budgets = spec.task.budgets,
				options = spec.agent.options,
			}
			log(("run %s: agent %s started"):format(spec.id, adapter.id))
			local outcome = adapter.run(request, services)
			files.write(Paths.join(directory, "transcript.jsonl"), stampedText(outcome.lines))
			files.write(Paths.join(directory, "agent.stderr.txt"), outcome.stderr)
			finishMetrics(result, outcome)
			result.status = outcome.status
			result.detail = outcome.detail
			if outcome.status ~= "unsupported" then
				runChecks(spec, workspace, directory, result)
			end
			result.exceeded = exceeded(result, spec.task.budgets, outcome.status)
			result.passed = result.status == "completed" and result.checksPassed and #result.exceeded == 0
			if result.passed then
				result.timeToPassSeconds = outcome.seconds
			end
			finished = true
			return nil
		end)
		if not ok then
			result.detail = tostring(problem)
			if not finished then
				result.passed = false
				if result.status == "completed" then
					result.status = "failed"
				end
			end
		end
		if files.isDirectory(workspace) then
			local moved, reason = pcall(function(): string?
				moveTree(files, workspace, Paths.join(directory, "workspace"))
				return nil
			end)
			if not moved then
				result.detail = (if result.detail ~= nil then result.detail .. "; " else "")
					.. "the workspace could not be kept: "
					.. tostring(reason)
			end
		end
		result.finishedAt = services.clock()
		write(Paths.join(directory, "result.json"), result)
		return result
	end

	local function reusable(spec: Model.RunSpec): Result.RunResult?
		if not resume then
			return nil
		end
		local path = Paths.join(evidence, spec.path .. "/result.json")
		if not files.exists(path) then
			return nil
		end
		local ok, decoded = pcall(function(): Result.RunResult
			return Result.decode(options.decode(files.read(path)))
		end)
		if ok and decoded.digest == spec.digest and decoded.id == spec.id then
			return decoded
		end
		return nil
	end

	return function(): Summary
		local results: { [string]: Result.RunResult } = {}
		local reusedIds: { [string]: boolean } = {}
		local ran = 0
		local reused = 0
		files.makeDirectory(evidence)
		local planned: { { id: string, digest: string, path: string } } = {}
		for _, spec in specs do
			table.insert(planned, { id = spec.id, digest = spec.digest, path = spec.path })
		end
		write(Paths.join(evidence, "plan.json"), { schemaVersion = 1, suite = suite.id, runs = planned })

		local function indexOf(): Result.Index
			local entries: { Result.IndexEntry } = {}
			for _, spec in specs do
				local result = results[spec.id]
				if result ~= nil then
					table.insert(entries, {
						id = spec.id,
						path = spec.path,
						task = spec.task.id,
						arm = spec.arm.id,
						agent = spec.agent.id,
						seed = spec.seed,
						status = result.status,
						passed = result.passed,
						reused = reusedIds[spec.id] == true,
					})
				end
			end
			return { schemaVersion = 1, suite = suite.id, runs = entries }
		end

		local pending = table.clone(specs)
		local running = 0
		local limit = math.max(1, options.parallelism or suite.parallelism)
		local function ready(spec: Model.RunSpec): boolean
			return spec.parent == nil or not inPlan[spec.parent :: string] or results[spec.parent :: string] ~= nil
		end
		while #pending > 0 or running > 0 do
			local launched = false
			if running < limit then
				for index, spec in pending do
					if ready(spec) then
						table.remove(pending, index)
						local previous = reusable(spec)
						if previous ~= nil then
							results[spec.id] = previous
							reusedIds[spec.id] = true
							reused += 1
							log(("run %s: reused (%s)"):format(spec.id, previous.status))
						else
							running += 1
							ran += 1
							services.spawn(function()
								local done, value = pcall(runOne, spec)
								if done then
									results[spec.id] = value
								else
									local failed = baseResult(spec, Paths.join(evidence, spec.path), services.clock())
									failed.detail = tostring(value)
									results[spec.id] = failed
								end
								local finishedResult = results[spec.id]
								log(
									("run %s: %s, passed=%s, %.1fs"):format(
										spec.id,
										finishedResult.status,
										tostring(finishedResult.passed),
										finishedResult.metrics.wallSeconds
									)
								)
								pcall(write, Paths.join(evidence, "index.json"), indexOf())
								running -= 1
							end)
						end
						launched = true
						break
					end
				end
			end
			if not launched then
				services.wait(0.05)
			end
		end
		local index = indexOf()
		write(Paths.join(evidence, "index.json"), index)
		local ordered: { Result.RunResult } = {}
		for _, spec in specs do
			table.insert(ordered, results[spec.id])
		end
		return { index = index, results = ordered, ran = ran, reused = reused }
	end
end

local function run(options: Options): Summary
	return create(options)()
end

local function load(evidence: string, files: Services.Files, decode: (text: string) -> unknown): { Result.RunResult }
	local indexPath = Paths.join(evidence, "index.json")
	if not files.exists(indexPath) then
		error(("no run index at %s"):format(indexPath), 0)
	end
	local raw = Schema.record(decode(files.read(indexPath)), "index")
	local results: { Result.RunResult } = {}
	for position, item in Schema.list(raw.runs, "index.runs") do
		local entry = Schema.record(item, ("index.runs[%d]"):format(position))
		local path = Paths.join(evidence, Schema.text(entry.path, "index.runs.path") .. "/result.json")
		table.insert(results, Result.decode(decode(files.read(path))))
	end
	return results
end

return {
	run = run,
	load = load,
	copyTree = copyTree,
	expandChecks = expandChecks,
}
