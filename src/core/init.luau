--!strict

local Operations = require "@self/operations"
local Performance = require "@self/performance"

local Capability = require "@self/capability"
local Execution = require "@self/execution"
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
export type PerformanceInput = Performance.Input
export type PerformanceSummary = Performance.Summary
export type PerformanceLimits = Performance.Limits
export type PerformanceEvaluation = Performance.Evaluation

export type Status = Types.Status
export type Failure = Types.Failure
export type StepResult = Types.StepResult
export type Artifact = Types.Artifact
export type AttachmentLimits = Attachment.Limits
export type Checkpoint = Types.Checkpoint
export type Origin = Types.Origin
export type CaseResult = Types.CaseResult
export type ReportSource = Types.ReportSource
export type Report = Types.Report
export type ManifestEntry = Types.ManifestEntry
export type Manifest = Types.Manifest
export type SelectionSubject = Types.SelectionSubject
export type SelectionPredicate = Types.SelectionPredicate
export type ShardPayload = Types.ShardPayload
export type Expectation = Matchers.Expectation
export type Spy<A... = ...unknown> = Spy.Spy<A...>
export type SpyCall = Spy.Call

export type InvocationResult = HarnessModule.InvocationResult
export type Invoker = HarnessModule.Invoker
export type StepOptions = HarnessModule.StepOptions
export type Disposable<T = unknown> = HarnessModule.Disposable<T>
export type Resource<T = unknown> = HarnessModule.Resource<T>
export type Context = HarnessModule.Context
export type CaseRun = HarnessModule.CaseRun
export type CaseOptions = HarnessModule.CaseOptions
export type Selection = HarnessModule.Selection
export type RunOptions = HarnessModule.RunOptions
export type Harness = HarnessModule.Harness
export type SyntheticOptions = HarnessModule.SyntheticOptions

export type PlanUnit = Types.PlanUnit
export type PlanUnitDraft = Types.PlanUnitDraft
export type PlanPolicy = Types.PlanPolicy
export type RetryPolicy = Types.RetryPolicy
export type Plan = Types.Plan
export type PlanDraft = Types.PlanDraft
export type PlanSelection = Types.PlanSelection
export type PlanBatch = Types.PlanBatch
export type BatchingMode = Types.BatchingMode

export type BatchStatus = Types.BatchStatus
export type BatchOutcome = Types.BatchOutcome
export type AttemptRecord = Types.AttemptRecord
export type BatchRecord = Types.BatchRecord
export type Fact = Types.Fact
export type ExecutionProvenance = Types.ExecutionProvenance
export type ExecutionReport = Types.ExecutionReport
export type Host = Execution.Host
export type Fixture = Execution.Fixture
export type PlanAccount = Execution.Account
export type ExecutionOptions = Execution.Options

export type ReviewKind = Provenance.ReviewKind
export type EvidenceHasher = Provenance.Hasher
export type EvidenceBuild = Provenance.Build
export type EvidenceSubject = Provenance.Subject
export type ArtifactProvenance = Provenance.Provenance
export type EvidenceSink = Provenance.Sink
export type EvidenceMemorySink = Provenance.MemorySink
export type EvidenceContent = Provenance.Content
export type EvidenceMeta = Provenance.Meta
export type EvidenceStat = Provenance.Stat

export type Negotiation = Capability.Negotiation
export type Session<S = { [string]: unknown }> = SessionModule.Session<S>
export type SessionOptions<S = { [string]: unknown }> = SessionModule.Options<S>
export type SessionProvidedOptions<S> = SessionModule.ProvidedOptions<S>
export type TransportRecord = Transport.Record
export type Segment = Transport.Segment
export type ProgressEvent = Progress.Event
export type RunProgress = Progress.Progress

return {
	SCHEMA_VERSION = ReportModel.SCHEMA_VERSION,
	createHarness = HarnessModule.createHarness,
	runCase = HarnessModule.runCase,
	runCases = HarnessModule.runCases,
	syntheticReport = HarnessModule.syntheticReport,
	format = HarnessModule.format,
	createSession = SessionModule.create,
	execute = Execution.execute,
	expect = Matchers.expect,
	float32 = Matchers.float32,
	spy = Spy.on,
	operation = Operations.operation,
	bindOperation = Operations.bind,
	progress = Progress,
	performance = Performance,
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
