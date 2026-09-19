--!strict

local Capability = require "@self/capability"
local Execution = require "@self/execution"
local HarnessModule = require "@self/harness"
local Manifest = require "@self/manifest"
local Matchers = require "@self/matchers"
local Observation = require "@self/observation"
local Plan = require "@self/plan"
local Shape = require "@self/shape"
local ReportModel = require "@self/report"
local SessionModule = require "@self/session"
local Spy = require "@self/spy"
local Transport = require "@self/transport"
local Types = require "@self/types"
local Witness = require "@self/witness"

export type Status = Types.Status
export type Failure = Types.Failure
export type StepResult = Types.StepResult
export type Artifact = Types.Artifact
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
export type Spy = Spy.Spy
export type SpyCall = Spy.Call

export type InvocationResult = HarnessModule.InvocationResult
export type Invoker = HarnessModule.Invoker
export type StepOptions = HarnessModule.StepOptions
export type Disposable = HarnessModule.Disposable
export type Resource = HarnessModule.Resource
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
export type ExecutionOptions = Execution.Options

export type Negotiation = Capability.Negotiation
export type Bundle = Observation.Bundle
export type BundleDraft = Observation.Draft
export type BundleVerdict = Observation.Verdict
export type Session = SessionModule.Session
export type SessionOptions = SessionModule.Options
export type TransportRecord = Transport.Record
export type Segment = Transport.Segment

export type ClassifyConsoleOptions = Witness.ClassifyOptions

return {
	SCHEMA_VERSION = ReportModel.SCHEMA_VERSION,
	MANIFEST_SCHEMA_VERSION = Manifest.SCHEMA_VERSION,
	PLAN_SCHEMA_VERSION = Plan.SCHEMA_VERSION,
	EXECUTION_SCHEMA_VERSION = Execution.SCHEMA_VERSION,
	OBSERVATION_CONTRACT = Observation.CONTRACT,
	TIMING_FIELDS = ReportModel.TIMING_FIELDS,

	createHarness = HarnessModule.createHarness,
	syntheticReport = HarnessModule.syntheticReport,
	format = HarnessModule.format,
	expect = Matchers.expect,
	float32 = Matchers.float32,
	spy = Spy.on,

	validateManifest = Manifest.validate,

	validatePlan = Plan.validate,
	selectPlan = Plan.select,
	partitionPlan = Plan.partition,
	planDigest = Plan.digest,
	planFromManifest = Plan.fromManifest,
	caseId = Plan.caseId,

	negotiate = Capability.negotiate,
	explainCapabilities = Capability.explain,

	execute = Execution.execute,
	createSession = SessionModule.create,

	sealObservations = Observation.seal,
	isSealedBundle = Observation.isSealed,
	evaluateObservations = Observation.evaluate,
	observationVerdict = Observation.verdict,
	observationStringMap = Observation.stringMap,

	frame = Transport.frame,
	extract = Transport.extract,
	reassemble = Transport.reassemble,
	receipt = Transport.receipt,
	segment = Transport.segment,
	reassembleSegments = Transport.reassembleSegments,

	finite = Shape.finite,
	finiteNonnegative = Shape.finiteNonnegative,
	nonnegativeInteger = Shape.nonnegativeInteger,
	denseRows = Shape.denseRows,
	deeplyFinite = Shape.deeplyFinite,
	safeId = Shape.safeId,
	nonempty = Shape.nonempty,
	exact = Shape.exact,
	exactKeys = Shape.exactKeys,
	hasOnlyFields = Shape.hasOnlyFields,
	decode = ReportModel.decode,
	merge = ReportModel.merge,
	compose = ReportModel.compose,
	canonical = ReportModel.canonical,
	verdictDigest = ReportModel.verdictDigest,
	verdictDifferences = ReportModel.verdictDifferences,

	DEFAULT_WITNESS_ERROR_PATTERNS = Witness.DEFAULT_ERROR_PATTERNS,
	DEFAULT_WITNESS_BLOCK_BEGIN_PATTERNS = Witness.DEFAULT_BLOCK_BEGIN_PATTERNS,
	DEFAULT_WITNESS_BLOCK_END_PATTERNS = Witness.DEFAULT_BLOCK_END_PATTERNS,
	classifyConsole = Witness.classifyConsole,
	classifyConsoleText = Witness.classifyConsoleText,
	splitConsoleLines = Witness.splitConsoleLines,
}
