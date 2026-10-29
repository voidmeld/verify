--!strict

local Adapters = require "@self/adapters"
local Base64 = require "./codec/base64"
local Cli = require "@self/cli"
local Codex = require "@self/codex"
local Judge = require "@self/judge"
local Judging = require "@self/judging"
local Lute = require "@self/lute"
local Model = require "@self/model"
local Random = require "./core/random"
local Report = require "@self/report"
local Result = require "@self/result"
local Runner = require "@self/runner"
local Services = require "@self/services"
local Stats = require "@self/stats"
local Transcript = require "@self/transcript"
local ScopedMcp = require "@self/scoped-mcp"

export type Suite = Model.Suite
export type Task = Model.Task
export type Agent = Model.Agent
export type Check = Model.Check
export type Budgets = Model.Budgets
export type Selection = Model.Selection
export type Loader = Model.Loader
export type Services = Services.Services
export type Files = Services.Files
export type Entry = Services.Entry
export type Command = Services.Command
export type Execution = Services.Execution
export type Line = Services.Line
export type HttpRequest = Services.HttpRequest
export type HttpResponse = Services.HttpResponse
export type Adapter = Adapters.Adapter
export type AgentRequest = Adapters.Request
export type AgentOutcome = Adapters.Outcome
export type ReplayResponse = Adapters.ReplayResponse
export type Transcript = Transcript.Transcript
export type RunResult = Result.RunResult
export type CheckResult = Result.CheckResult
export type Capture = Result.Capture
export type RunOptions = Runner.Options
export type RunSummary = Runner.Summary
export type JudgeTransport = Judge.Transport
export type JudgeRequest = Judge.Request
export type JudgeComparison = Judge.Comparison
export type Judgment = Judge.Judgment
export type Label = Judge.Label
export type Verdict = Judge.Verdict
export type JudgeOptions = Judging.Options
export type Thresholds = Report.Thresholds
export type EvalReport = Report.EvalReport
export type CliContext = Cli.Context

return {
	scopedMcp = ScopedMcp,
	SCHEMA_VERSION = Model.SCHEMA_VERSION,
	decodeSuite = Model.decodeSuite,
	plan = Model.plan,
	run = Runner.run,
	load = Runner.load,
	adapters = {
		claudeCode = Adapters.claudeCode,
		claudeArguments = Adapters.claudeArguments,
		codex = Adapters.codex,
		codexArguments = Adapters.codexArguments,
		command = Adapters.command,
		replay = Adapters.replay,
		fixture = Adapters.fixture,
		parseStamped = Adapters.parseStamped,
	},
	transcript = {
		parseClaudeStream = Transcript.parseClaudeStream,
		parseCodexStream = Codex.parse,
		total = Transcript.total,
	},
	judge = {
		DEFAULT_MODEL = Judge.DEFAULT_MODEL,
		DEFAULT_CODEX_MODEL = Judge.DEFAULT_CODEX_MODEL,
		DEFAULT_CODEX_EFFORT = Judge.DEFAULT_CODEX_EFFORT,
		DEFAULT_RUBRIC = Judge.DEFAULT_RUBRIC,
		compare = Judge.compare,
		parseVerdict = Judge.parseVerdict,
		anthropic = Judge.anthropic,
		claudeCli = Judge.claudeCli,
		codexCli = Judge.codexCli,
		comparisons = Judging.comparisons,
		run = Judging.run,
		load = Judging.load,
		decodeLabels = Judge.decodeLabels,
		decodeRubric = Judge.decodeRubric,
		calibrate = Judge.calibrate,
	},
	stats = Stats,
	report = {
		METRICS = Report.METRICS,
		decodeThresholds = Report.decodeThresholds,
		build = Report.build,
		markdown = Report.markdown,
		verdict = Report.verdict,
	},
	base64 = Base64,
	random = Random,
	result = Result,
	cli = Cli.main,
	lute = Lute,
}
