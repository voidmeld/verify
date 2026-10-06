--!strict

local Api = require "@self/api"

export type GateOptions = Api.GateOptions
export type Runtime = Api.Runtime
export type HostOptions = Api.HostOptions
export type WorkerOperations = Api.WorkerOperations
export type WorkerOptions = Api.WorkerOptions
export type WorkerArguments = Api.WorkerArguments
export type LoadDisposition = Api.LoadDisposition
export type Registrar = Api.Registrar
export type SelfRegisteringWorkerOperations = Api.SelfRegisteringWorkerOperations
export type BoundedResult = Api.BoundedResult
export type ReceiptVerdict = Api.ReceiptVerdict
export type FixtureOptions = Api.FixtureOptions
export type FixtureBridge = Api.FixtureBridge

return Api
