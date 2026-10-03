--!strict

local Batch = require "@self/batch"
local ViewportCorners = require "@self/viewport-corners"
local Corpus = require "@self/corpus"
local Host = require "@self/host"
local Wire = require "@self/wire"
local Worker = require "@self/worker"

export type ViewportCornerOptions = ViewportCorners.Options
export type ViewportCornerOutcome = ViewportCorners.Outcome

export type HostOptions = Host.Options
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

	worker = Worker.main,
	runWorkerBatch = Worker.runBatch,

	selfRegisteringWorker = Worker.mainSelfRegistering,
	runSelfRegisteringWorkerBatch = Worker.runBatchSelfRegistering,
	encodeBatch = Batch.encode,
	decodeBatch = Batch.decode,
	HOST_CAPABILITIES = Host.DEFAULT_CAPABILITIES,

	corpus = Corpus,
	detectViewportCorners = ViewportCorners.detect,
	VIEWPORT_CORNER_CAPABILITY = ViewportCorners.CAPABILITY,
}
