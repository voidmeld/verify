--!strict

export type Status = "passed" | "failed" | "skipped" | "unsupported" | "timed_out" | "cancelled"

export type InvocationPhase = "setup" | "case" | "step" | "teardown" | "cleanup"
export type FailurePhase = "load" | "registration" | InvocationPhase | "executor"
export type FailureOutcome = "failed" | "timed_out" | "cancelled"

export type Failure = {
	phase: FailurePhase,
	outcome: FailureOutcome,
	message: string,
}

export type StepResult = {
	name: string,
	actor: string?,
	status: "passed" | "failed" | "timed_out" | "cancelled",
	durationMicros: number,
	message: string?,
}

export type Artifact = {
	name: string,
	reference: string,
	mediaType: string?,
}

export type Origin = {
	executor: string,
	environment: { [string]: string },
	capabilities: { string },
}

export type CaseResult = {
	id: string,
	source: string?,
	path: { string },
	name: string,
	status: Status,
	durationMicros: number,
	failures: { Failure },
	steps: { StepResult },
	artifacts: { Artifact },
	limitations: { string },
	missingCapabilities: { string },
	skipReason: string?,
	origin: Origin,
}

export type ReportSource = Origin

export type Report = {
	schemaVersion: number,
	executor: string,
	environment: { [string]: string },
	capabilities: { string },
	sources: { ReportSource },
	results: { CaseResult },
	passed: number,
	failed: number,
	skipped: number,
	unsupported: number,
	timedOut: number,
	cancelled: number,
	total: number,
	durationMicros: number,
}

export type ShardPayload = {
	id: string,
	report: unknown?,
	error: string?,
}

export type ManifestEntry = {
	id: string,
	source: string,
	group: string?,
	tags: { string }?,
	requires: { string }?,
}

export type Manifest = {
	schemaVersion: number,
	entries: { ManifestEntry },
}

export type SelectionSubject = {
	id: string,
	source: string?,
	path: { string },
	name: string,
	tags: { string },
	requires: { string },
}

export type SelectionPredicate = (subject: SelectionSubject) -> boolean

export type PlanUnit = {
	id: string,
	locator: string,
	group: string?,
	tags: { string },
	requires: { string },
	deadlineSeconds: number?,
	weight: number,
}

export type PlanUnitDraft = {
	id: string,
	locator: string,
	group: string?,
	tags: { string }?,
	requires: { string }?,
	deadlineSeconds: number?,
	weight: number?,
}

export type BatchingMode = "count" | "weighted"

export type RetryPolicy = {
	maxAttempts: number,
	on: { string },
}

export type PlanPolicy = {
	failFast: boolean,
	maxParallelBatches: number,
	batchCount: number?,
	deadlineSeconds: number?,
	runDeadlineSeconds: number?,
	retry: RetryPolicy,
	caseIdStyle: "unit-prefixed" | "bare",
}

export type PlanPolicyDraft = {
	failFast: boolean?,
	maxParallelBatches: number?,
	batchCount: number?,
	deadlineSeconds: number?,
	runDeadlineSeconds: number?,
	retry: RetryPolicy?,
	caseIdStyle: ("unit-prefixed" | "bare")?,
}

export type Plan = {
	schemaVersion: number,
	id: string,
	requires: { string },
	policy: PlanPolicy,
	units: { PlanUnit },
}

export type PlanDraft = {
	schemaVersion: number?,
	id: string,
	requires: { string }?,
	policy: PlanPolicyDraft?,
	units: { PlanUnitDraft },
}

export type PlanSelection = {
	ids: { string }?,
	tags: { string }?,
	groups: { string }?,
	capabilities: { string }?,
	predicate: SelectionPredicate?,
}

export type PlanBatch = {
	id: string,
	index: number,
	units: { PlanUnit },
	deadlineSeconds: number?,
}

export type BatchStatus = "returned" | "faulted" | "timed_out" | "cancelled"

export type BatchOutcome = {
	status: BatchStatus,
	report: unknown?,
	detail: string?,
}

export type AttemptRecord = {
	batchId: string,
	batchIndex: number,
	attempt: number,
	status: BatchStatus,
	detail: string?,
	produced: boolean,
	verdictDigest: string?,
	durationMicros: number,
	adopted: boolean,
}

export type BatchRecord = {
	id: string,
	index: number,
	units: { string },
	dispatched: boolean,
	attempts: number,
	outcome: BatchStatus?,
	reason: string?,
}

export type Fact = {
	code: string,
	subject: string,
	detail: string,
	severity: "failure" | "limitation",
}

export type ExecutionProvenance = {
	planId: string,
	planSchemaVersion: number,
	planDigest: string,
	unitCount: number,

	planUnitCount: number,
	complete: boolean,
	host: string,
	batchCount: number,
	parallelism: number,
	batching: BatchingMode,
}

export type ExecutionReport = {
	schemaVersion: number,
	provenance: ExecutionProvenance,
	capabilities: { string },
	batches: { BatchRecord },
	attempts: { AttemptRecord },
	facts: { Fact },
	report: Report,
}

return nil
