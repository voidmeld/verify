--!strict

local Batch = require "../runtime/batch"
local Binding = require "../runtime/binding"
local Bounded = require "../runtime/bounded"
local Gate = require "../runtime/gate"
local FixtureBridge = require "../roblox/fixture-bridge"
local ReflectionExport = require "./reflection-export"
local Host = require "../runtime/host"
local LuneReflection = require "./reflection"
local Receipt = require "../runtime/receipt"
local Wire = require "../runtime/wire"
local Worker = require "../runtime/worker"
local Runtime = require "./runtime"
local Verify = require "../core"

export type Runtime = Binding.Runtime
export type HostOptions = Host.Options
export type WorkerOperations = Worker.Operations
export type WorkerOptions = Worker.Options
export type WorkerArguments = Worker.Arguments
export type LoadDisposition = Worker.LoadDisposition
export type Registrar = Worker.Registrar
export type SelfRegisteringWorkerOperations = Worker.SelfRegisteringOperations
export type BoundedResult = Bounded.Result
export type ReceiptVerdict = Receipt.Verdict
export type FixtureOptions = LuneReflection.Options
export type FixtureBridge = FixtureBridge.Bridge

export type GateOptions = Gate.Options

local worker = Worker.create(Runtime)
local gate = Gate.create(Runtime, "bound")
local wire = Wire.create(Runtime.json)
local batch = Batch.create(Runtime.json)

local function host(options: HostOptions): Verify.Host
	local settings = table.clone(options)
	settings.receipts = options.receipts or "bound"
	return Host.create(Runtime, settings)
end

local function runBounded(argv: { string }, seconds: number): Bounded.Result
	return Bounded.run(argv, seconds, Runtime.process.run)
end

return {
	runtime = Runtime,
	host = host,
	gate = gate,
	runBounded = runBounded,
	worker = worker.main,
	workerArguments = worker.arguments,
	selfRegisteringWorker = worker.mainSelfRegistering,
	runWorkerBatch = worker.runBatch,
	runSelfRegisteringWorkerBatch = worker.runBatchSelfRegistering,
	encode = wire.encode,
	parse = wire.parse,
	decode = wire.decode,
	encodeBatch = batch.encode,
	decodeBatch = batch.decode,
	checkReceipt = Receipt.check,
	encodeReceipt = Receipt.encode,
	fixture = LuneReflection.create,
	exportReflection = ReflectionExport.create,
	serializeSnapshot = ReflectionExport.serialize,
	fixtureFrom = LuneReflection.createFrom,
	HOST_CAPABILITIES = Host.DEFAULT_CAPABILITIES,
}
