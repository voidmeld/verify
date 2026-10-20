--!strict

local Adapters = require "./adapters"
local Audit = require "../roblox/ui-audit"
local Core = require "../core"
local Judge = require "./judge"
local Judging = require "./judging"
local Model = require "./model"
local Paths = require "../codec/path"
local Report = require "./report"
local Runner = require "./runner"
local Schema = require "./schema"
local Services = require "./services"

export type Context = {
	services: Services.Services,
	loader: Model.Loader,
	encode: (value: unknown) -> string,
	decode: (text: string) -> unknown,
	absolute: (path: string) -> string,
	writeVerifyReport: (path: string, runId: string, report: Core.Report) -> (),
	adapters: { [string]: Adapters.Adapter }?,
}

type Parsed = {
	command: string?,
	flags: { [string]: { string } },
	positional: { string },
	switches: { [string]: boolean },
}

local USAGE = table.concat({
	"usage: lute run tools/agent-eval.luau <command> [options]",
	"",
	"commands:",
	"  plan   --suite eval.json [--task id]... [--arm id]... [--agent id]... [--seed n]...",
	"  run    --suite eval.json [--evidence dir] [--workspaces dir] [--parallel n] [--fresh|--checks-only] [selection]",
	"  judge  --suite eval.json [--evidence dir] [--transport api|cli|codex] [--model id] [--effort level]",
	"         [--seed n] [--attempts n] [--fresh]",
	"  report --suite eval.json --thresholds thresholds.json [--evidence dir] [--labels labels.json]",
	"         [--out dir] [--verify-report path --run id]",
	"  audit  dump.json [--out audit.json] [--min-touch n] [--touch true|false] [--gamepad true|false]",
	"",
	"The judge command with --transport api reads the key from ANTHROPIC_API_KEY.",
}, "\n")

local SWITCHES: { [string]: boolean } = { fresh = true, help = true, ["checks-only"] = true }

local function parse(args: { string }): (Parsed?, string?)
	local parsed: Parsed = { command = nil, flags = {}, positional = {}, switches = {} }
	local index = 1
	while index <= #args do
		local word = args[index]
		local name = string.match(word, "^%-%-([%w%-]+)$")
		if name ~= nil then
			if SWITCHES[name] then
				parsed.switches[name] = true
			else
				local value = args[index + 1]
				if value == nil then
					return nil, ("--%s needs a value"):format(name)
				end
				parsed.flags[name] = parsed.flags[name] or {}
				table.insert(parsed.flags[name], value)
				index += 1
			end
		elseif parsed.command == nil then
			parsed.command = word
		else
			table.insert(parsed.positional, word)
		end
		index += 1
	end
	return parsed, nil
end

local function one(parsed: Parsed, name: string): string?
	local values = parsed.flags[name]
	if values == nil then
		return nil
	end
	if #values > 1 then
		error(("--%s accepts one value"):format(name), 0)
	end
	return values[1]
end

local function numberFlag(parsed: Parsed, name: string): number?
	local value = one(parsed, name)
	if value == nil then
		return nil
	end
	local converted = tonumber(value)
	if converted == nil then
		error(("--%s needs a number"):format(name), 0)
	end
	return converted
end

local function boolFlag(parsed: Parsed, name: string): boolean?
	local value = one(parsed, name)
	if value == nil then
		return nil
	end
	if value ~= "true" and value ~= "false" then
		error(("--%s needs true or false"):format(name), 0)
	end
	return value == "true"
end

local function selection(parsed: Parsed): Model.Selection
	local seeds: { number }? = nil
	if parsed.flags.seed ~= nil then
		local list: { number } = {}
		for _, value in parsed.flags.seed do
			local converted = tonumber(value)
			if converted == nil then
				error("--seed needs a number", 0)
			end
			table.insert(list, converted)
		end
		seeds = list
	end
	return { tasks = parsed.flags.task, arms = parsed.flags.arm, agents = parsed.flags.agent, seeds = seeds }
end

local function loadSuite(parsed: Parsed, context: Context): Model.Suite
	local path = one(parsed, "suite")
	if path == nil then
		error("--suite is required", 0)
	end
	local absolute = context.absolute(path :: string)
	local files = context.loader.files
	if not files.exists(absolute) then
		error(("no suite file at %s"):format(absolute), 0)
	end
	return Model.decodeSuite(context.decode(files.read(absolute)), absolute, context.loader)
end

local function evidenceOf(parsed: Parsed, suite: Model.Suite, context: Context): string
	local declared = one(parsed, "evidence")
	if declared ~= nil then
		return context.absolute(declared :: string)
	end
	if suite.evidence ~= nil then
		return context.absolute(suite.evidence :: string)
	end
	return context.absolute(".verify/agent-eval/" .. suite.id)
end

local function adapters(context: Context): { [string]: Adapters.Adapter }
	local list: { [string]: Adapters.Adapter } = {
		["claude-code"] = Adapters.claudeCode(context.decode),
		codex = Adapters.codex(context.decode),
		fixture = Adapters.fixture(context.decode),
	}
	local extra: { [string]: Adapters.Adapter } = context.adapters or {}
	for name, adapter in extra do
		list[name] = adapter
	end
	return list
end

local function plan(parsed: Parsed, context: Context): number
	local suite = loadSuite(parsed, context)
	local say = context.services.print
	local specs = Model.plan(suite, context.loader, selection(parsed))
	for _, spec in specs do
		say(
			("%4d  %s  %s%s"):format(
				spec.order,
				spec.id,
				string.sub(spec.digest, 1, 12),
				if spec.parent ~= nil then "  after " .. (spec.parent :: string) else ""
			)
		)
	end
	say(("%d run(s)"):format(#specs))
	return 0
end

local function runCommand(parsed: Parsed, context: Context): number
	local suite = loadSuite(parsed, context)
	local evidence = evidenceOf(parsed, suite, context)
	local services = context.services
	local workspaces = one(parsed, "workspaces")
	if workspaces ~= nil then
		services = table.clone(services)
		services.workspaces = context.absolute(workspaces :: string)
	end
	local summary = Runner.run {
		suite = suite,
		loader = context.loader,
		services = services,
		adapters = adapters(context),
		evidence = evidence,
		encode = context.encode,
		decode = context.decode,
		selection = selection(parsed),
		parallelism = numberFlag(parsed, "parallel"),
		resume = not parsed.switches.fresh,
		checksOnly = parsed.switches["checks-only"],
	}
	local passed = 0
	local broken = 0
	for _, result in summary.results do
		if result.passed then
			passed += 1
		end
		if result.status == "provision_failed" or result.status == "unsupported" then
			broken += 1
		end
	end
	services.print(
		("agent-eval: %d run(s), %d ran, %d reused, %d passed, %d could not run; evidence in %s"):format(
			#summary.results,
			summary.ran,
			summary.reused,
			passed,
			broken,
			evidence
		)
	)
	return if broken > 0 then 1 else 0
end

local function judgeCommand(parsed: Parsed, context: Context): number
	local suite = loadSuite(parsed, context)
	local evidence = evidenceOf(parsed, suite, context)
	local services = context.services
	local results = Runner.load(evidence, context.loader.files, context.decode)
	local transportName = one(parsed, "transport") or "api"
	local model = one(parsed, "model")
		or (if type(suite.judge.model) == "string" then suite.judge.model :: string else nil)
		or (if transportName == "codex" then Judge.DEFAULT_CODEX_MODEL else Judge.DEFAULT_MODEL)
	local effort = one(parsed, "effort") or (if transportName == "codex" then Judge.DEFAULT_CODEX_EFFORT else nil)
	local transport: Judge.Transport
	if transportName == "api" then
		local key = services.environment "ANTHROPIC_API_KEY"
		if key == nil or key == "" then
			services.print "agent-eval: ANTHROPIC_API_KEY is not set"
			return 2
		end
		if services.request == nil then
			services.print "agent-eval: this host has no HTTP client"
			return 2
		end
		transport = Judge.anthropic {
			request = services.request :: (Services.HttpRequest) -> (Services.HttpResponse?, string?),
			apiKey = key :: string,
			read = context.loader.files.read,
			encode = context.encode,
			decode = context.decode,
			model = model,
			effort = one(parsed, "effort"),
		}
	elseif transportName == "cli" then
		transport = Judge.claudeCli {
			execute = services.execute,
			files = context.loader.files,
			directory = Paths.join(evidence, "judge-cli"),
			decode = context.decode,
			model = model,
		}
	elseif transportName == "codex" then
		local temporary = services.environment "TEMP" or services.environment "TMPDIR" or "/tmp"
		transport = Judge.codexCli {
			execute = services.execute,
			files = context.loader.files,
			directory = Paths.join(
				Paths.join(temporary, "verify-codex-judge"),
				services.hash(evidence .. tostring(services.now()))
			),
			decode = context.decode,
			encode = context.encode,
			model = model,
			effort = effort,
		}
	else
		services.print "agent-eval: --transport must be api, cli or codex"
		return 2
	end
	local seed = numberFlag(parsed, "seed")
		or (if type(suite.judge.seed) == "number" then suite.judge.seed :: number else nil)
		or 1
	local judgments = Judging.run {
		suite = suite,
		results = results,
		transport = transport,
		transportName = transportName .. ":" .. model .. (if transportName == "codex"
			then ":" .. assert(effort)
			else ""),
		files = context.loader.files,
		hash = services.hash,
		encode = context.encode,
		decode = context.decode,
		evidence = evidence,
		seed = seed,
		attempts = numberFlag(parsed, "attempts"),
		resume = not parsed.switches.fresh,
		log = services.print,
	}
	local failed = 0
	for _, judgment in judgments do
		if judgment.status == "failed" then
			failed += 1
		end
	end
	services.print(("agent-eval: %d comparison(s), %d failed"):format(#judgments, failed))
	return if failed > 0 then 1 else 0
end

local function reportCommand(parsed: Parsed, context: Context): number
	local suite = loadSuite(parsed, context)
	local evidence = evidenceOf(parsed, suite, context)
	local files = context.loader.files
	local thresholdsPath = one(parsed, "thresholds")
	if thresholdsPath == nil then
		error("--thresholds is required", 0)
	end
	local thresholds = Report.decodeThresholds(context.decode(files.read(context.absolute(thresholdsPath :: string))))
	local results = Runner.load(evidence, files, context.decode)
	local judgments = Judging.load(evidence, files, context.decode)
	local calibration: Judge.Calibration? = nil
	local labels = one(parsed, "labels")
	if labels ~= nil then
		calibration = Judge.calibrate(
			judgments,
			Judge.decodeLabels(context.decode(files.read(context.absolute(labels :: string))))
		)
	end
	local report = Report.build(suite.id, results, judgments, thresholds, calibration)
	local out = context.absolute(one(parsed, "out") or evidence)
	files.makeDirectory(out)
	files.write(Paths.join(out, "report.json"), context.encode(report))
	local text = Report.markdown(report)
	files.write(Paths.join(out, "report.md"), text)
	local verifyPath = one(parsed, "verify-report")
	if verifyPath ~= nil then
		local runId = one(parsed, "run")
		if runId == nil then
			error("--verify-report needs --run", 0)
		end
		context.writeVerifyReport(context.absolute(verifyPath :: string), runId :: string, Report.verdict(report))
	end
	context.services.print(text)
	return if report.verdict == "PASS" then 0 else 1
end

local function auditCommand(parsed: Parsed, context: Context): number
	local path = parsed.positional[1]
	if path == nil then
		error("audit needs a dump file", 0)
	end
	local files = context.loader.files
	local dump = Audit.decode(context.decode(files.read(context.absolute(path))))
	local report = Audit.analyze(dump, {
		minTouchTarget = numberFlag(parsed, "min-touch"),
		touch = boolFlag(parsed, "touch"),
		gamepad = boolFlag(parsed, "gamepad"),
	})
	local out = one(parsed, "out")
	if out ~= nil then
		files.write(context.absolute(out :: string), context.encode(report))
	end
	local say = context.services.print
	say(
		("ui audit: score %.1f, %d element(s), %d visible"):format(
			report.score,
			report.metrics.elements,
			report.metrics.visible
		)
	)
	for _, rule in Schema.sortedKeys(report.rules) do
		local summary = report.rules[rule]
		say(("  %-24s %4d  %-6s -%s"):format(rule, summary.count, summary.severity, tostring(summary.penalty)))
	end
	return 0
end

local function main(args: { string }, context: Context): number
	local parsed, problem = parse(args)
	local say = context.services.print
	if parsed == nil then
		say(tostring(problem))
		say(USAGE)
		return 2
	end
	local command = parsed.command
	if parsed.switches.help or command == nil then
		say(USAGE)
		return if parsed.switches.help then 0 else 2
	end
	local handlers: { [string]: (Parsed, Context) -> number } = {
		plan = plan,
		run = runCommand,
		judge = judgeCommand,
		report = reportCommand,
		audit = auditCommand,
	}
	local handler = handlers[command :: string]
	if handler == nil then
		say(("unknown command %s"):format(command :: string))
		say(USAGE)
		return 2
	end
	local ok, code = pcall(handler, parsed, context)
	if not ok then
		say("agent-eval: " .. tostring(code))
		return 2
	end
	return code
end

return {
	USAGE = USAGE,
	main = main,
	parse = parse,
}
