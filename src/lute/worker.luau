--!strict

local Core = require "../runtime/worker"
local Runtime = require "./runtime"

local bound = Core.create(Runtime)

export type Load = Core.Load
export type Registrar = Core.Registrar
export type LoadDisposition = Core.LoadDisposition
export type Operations = Core.Operations
export type SelfRegisteringOperations = Core.SelfRegisteringOperations
export type Options = Core.Options
export type Arguments = Core.Arguments

return {
	DEFAULT_CAPABILITIES = bound.DEFAULT_CAPABILITIES,
	arguments = bound.arguments,
	runBatch = bound.runBatch,
	runBatchSelfRegistering = bound.runBatchSelfRegistering,
	main = bound.main,
	mainSelfRegistering = bound.mainSelfRegistering,
}
