--!strict

local Wait = require "@self/wait"
local Operations = require "@self/operations"
local Performance = require "@self/performance"
local Shape = require "@self/shape"

local Execution = require "@self/execution"
local Format = require "@self/format"
local HarnessModule = require "@self/harness"
local Progress = require "@self/progress"
local Matchers = require "@self/matchers"
local Provenance = require "@self/provenance"
local ReportModel = require "@self/report"
local SessionModule = require "@self/session"
local Spy = require "@self/spy"
local Attachment = require "@self/attachment"
local Transport = require "@self/transport"
local Types = require "@self/types"

export type OperationRequest = Operations.Request
export type CaseHost = Operations.Host
export type Operation<I, O> = Operations.Operation<I, O>
export type NamedCase = HarnessModule.NamedCase

export type Status = Types.Status
export type Failure = Types.Failure
export type StepResult = Types.StepResult
export type Artifact = Types.Artifact
export type AttachmentLimits = Attachment.Limits
export type Checkpoint = Types.Checkpoint
export type CaseResult = Types.CaseResult
export type Report = Types.Report
export type SelectionSubject = Types.SelectionSubject
export type SelectionPredicate = Types.SelectionPredicate
export type Expectation = Matchers.Expectation
export type Spy<A... = ...unknown> = Spy.Spy<A...>

export type Resource<T = unknown> = HarnessModule.Resource<T>
export type Context = HarnessModule.Context
export type Selection = HarnessModule.Selection
export type RunOptions = HarnessModule.RunOptions
export type Harness = HarnessModule.Harness
export type SyntheticOptions = HarnessModule.SyntheticOptions

export type PlanUnit = Types.PlanUnit
export type PlanUnitDraft = Types.PlanUnitDraft
export type PlanPolicy = Types.PlanPolicy
export type Plan = Types.Plan
export type PlanDraft = Types.PlanDraft
export type PlanBatch = Types.PlanBatch

export type BatchStatus = Types.BatchStatus
export type BatchOutcome = Types.BatchOutcome
export type ExecutionReport = Types.ExecutionReport
export type Host = Execution.Host
export type Fixture = Execution.Fixture
export type ExecutionOptions = Execution.Options

export type ReviewKind = Provenance.ReviewKind
export type EvidenceBuild = Provenance.Build
export type EvidenceSubject = Provenance.Subject
export type ArtifactProvenance = Provenance.Provenance
export type EvidenceSink = Provenance.Sink
export type EvidenceContent = Provenance.Content
export type EvidenceMeta = Provenance.Meta
export type EvidenceStat = Provenance.Stat

export type Session<S = { [string]: unknown }> = SessionModule.Session<S>
export type SessionProvidedOptions<S> = SessionModule.ProvidedOptions<S>
export type Segment = Transport.Segment
export type ProgressEvent = Progress.Event
export type RunProgress = Progress.Progress

return {
	waitUntil = Wait.waitUntil,
	awaitValue = Wait.awaitValue,
	SCHEMA_VERSION = ReportModel.SCHEMA_VERSION,
	createHarness = HarnessModule.createHarness,
	runCase = HarnessModule.runCase,
	runCases = HarnessModule.runCases,
	syntheticReport = HarnessModule.syntheticReport,
	format = Format.format,
	createSession = SessionModule.create,
	execute = Execution.execute,
	expect = Matchers.expect,
	float32 = Matchers.float32,
	spy = Spy.on,
	operation = Operations.operation,
	bindOperation = Operations.bind,
	progress = Progress,
	performance = Performance,
	shape = {
		finite = Shape.finite,
		finiteNonnegative = Shape.finiteNonnegative,
		nonnegativeInteger = Shape.nonnegativeInteger,
		denseRows = Shape.denseRows,
	},
	memorySink = Provenance.memorySink,
	decode = ReportModel.decode,
	merge = ReportModel.merge,
	compose = ReportModel.compose,
	observationParity = ReportModel.observationParity,
	frame = Transport.frame,
	extract = Transport.extract,
	reassemble = Transport.reassemble,
	receipt = Transport.receipt,
	segment = Transport.segment,
	reassembleSegments = Transport.reassembleSegments,
}
