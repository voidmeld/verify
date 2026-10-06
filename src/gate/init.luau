--!strict

local Gate = require "@self/gate"
local GateTypes = require "@self/gate-types"

export type Draft = GateTypes.GateDraft
export type ProducerDraft = GateTypes.ProducerDraft
export type ShardOptions = Gate.ShardOptions
export type PolicyDraft = GateTypes.PolicyDraft
export type Definition = GateTypes.Gate
export type Selection = GateTypes.Selection
export type Reuse = GateTypes.Reuse
export type Job = GateTypes.Job
export type JobOutcome = GateTypes.JobOutcome
export type Task = GateTypes.Task
export type Executor = GateTypes.Executor
export type RunOptions = GateTypes.RunOptions
export type ExitClass = GateTypes.ExitClass
export type ReportExpectation = GateTypes.ReportExpectation
export type Record = GateTypes.ProducerRecord
export type Acceptance = GateTypes.Acceptance
export type Scope = GateTypes.Scope
export type Outcome = GateTypes.Outcome

return {
	SCHEMA_VERSION = Gate.SCHEMA_VERSION,
	define = Gate.define,
	shard = Gate.shard,
	testCases = Gate.testCases,
	run = Gate.run,
	format = Gate.format,
	explain = Gate.explain,
	list = Gate.list,
	rerun = Gate.rerun,
}
