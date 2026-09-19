--!strict

local Batch = require "@self/batch"
local ViewportCorners = require "@self/viewport-corners"
local Corpus = require "@self/corpus"
local Host = require "@self/host"
local Pool = require "@self/pool"
local Wire = require "@self/wire"
local Worker = require "@self/worker"

export type ViewportCornerOptions = ViewportCorners.Options
export type ViewportCornerOutcome = ViewportCorners.Outcome

export type HostOptions = Host.Options
export type PoolOptions = Pool.Options
export type Pool = Pool.Pool
export type PoolStats = Pool.Stats
export type CorpusRule = Corpus.Rule
export type CorpusDiscovery = Corpus.Discovery
export type CorpusQuery = Corpus.Query
export type LockSection = Corpus.LockSection
export type LockField = Corpus.LockField
export type WorkerOperations = Worker.Operations
export type WorkerOptions = Worker.Options
export type LoadDisposition = Worker.LoadDisposition
export type Registrar = Worker.Registrar
export type SelfRegisteringWorkerOperations = Worker.SelfRegisteringOperations

return {
	encode = Wire.encode,
	decode = Wire.decode,

	segmentReport = Wire.segmentReport,
	reassembleReport = Wire.reassembleReport,

	host = Host.create,

	pool = Pool.create,
	worker = Worker.main,
	poolWorker = Worker.poolMain,
	runWorkerBatch = Worker.runBatch,

	selfRegisteringWorker = Worker.mainSelfRegistering,
	selfRegisteringPoolWorker = Worker.poolMainSelfRegistering,
	runSelfRegisteringWorkerBatch = Worker.runBatchSelfRegistering,
	encodeBatch = Batch.encode,
	decodeBatch = Batch.decode,
	HOST_CAPABILITIES = Host.DEFAULT_CAPABILITIES,
	POOL_CAPABILITIES = Pool.DEFAULT_CAPABILITIES,

	corpus = Corpus,
	detectViewportCorners = ViewportCorners.detect,
	VIEWPORT_CORNER_CAPABILITY = ViewportCorners.CAPABILITY,
}
