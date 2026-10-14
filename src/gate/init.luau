--!strict

local Gate = require "@self/gate"
local GateDefine = require "@self/gate-define"
local GateFormat = require "@self/gate-format"
local GateTypes = require "@self/gate-types"

export type Draft = GateTypes.GateDraft
export type ProducerDraft = GateTypes.ProducerDraft
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
	SCHEMA_VERSION = GateDefine.SCHEMA_VERSION,
	define = GateDefine.define,
	testCases = Gate.testCases,
	run = Gate.run,
	format = GateFormat.format,
	explain = GateFormat.explain,
	list = GateFormat.list,
	rerun = Gate.rerun,
}
