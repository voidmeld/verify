--!strict

local Published = require "@self/published-source"
local Platform = require "@self/platform"
local Place = require "@self/place"
local Attachments = require "@self/attachments"
local Evidence = require "@self/evidence"
local EvidenceStore = require "@self/evidence-store"
local Player = require "@self/player"
local Studio = require "@self/studio"
local Attach = require "@self/studio-attach"
local Mcp = require "@self/studio-mcp"
local OpenCloud = require "@self/open-cloud"
local Fixture = require "@self/fixture"
local TypePolicy = require "@self/type-policy"
local Batch = require "@self/batch"
local Bounded = require "@self/bounded"
local Gate = require "@self/gate"
local WindowCapture = require "@self/window-capture"
local Corpus = require "@self/corpus"
local Host = require "@self/host"
local Lock = require "@self/lock"
local Wire = require "@self/wire"
local Worker = require "@self/worker"

export type AttachmentSink = Attachments.Sink
export type AttachmentOptions = Attachments.Options
export type PlatformOptions = Platform.Options
export type PlatformResult = Platform.Result
export type EvidenceRequirement = Evidence.Requirement
export type EvidenceResult = Evidence.Result
export type EvidenceSealOptions = EvidenceStore.SealOptions
export type EvidenceValidateOptions = EvidenceStore.ValidateOptions
export type PlaceOptions = Place.Options
export type PublishedOptions = Published.Options
export type PlayerOptions = Player.Options
export type PlayerBackend = Player.Backend
export type PlayerSession = Player.Session
export type StudioOptions = Studio.Options
export type StudioHostOptions = Studio.HostOptions
export type StudioInfo = Attach.StudioInfo
export type StudioAttachOptions = Attach.Options
export type StudioRequest = Attach.Request
export type StudioAuthorization = Attach.Authorization
export type StudioTransport = Attach.Transport
export type StudioExchange = Mcp.Exchange
export type StudioAttachRefusal = Attach.Refusal
export type StudioResponse = Attach.Response
export type StudioReportResponse = Attach.ReportResponse
export type StudioCaptureOptions = Attach.CaptureOptions
export type StudioCleanup = Attach.Cleanup
export type StudioSession = Attach.Session
export type OpenCloudOptions = OpenCloud.Options
export type OpenCloudCall = OpenCloud.Call
export type OpenCloudExchange = OpenCloud.Exchange
export type OpenCloudTransport = OpenCloud.Transport
export type OpenCloudHandle = OpenCloud.Handle
export type OpenCloudOutcome = OpenCloud.Outcome
export type OpenCloudSession = OpenCloud.Session
export type FixtureOptions = Fixture.Options
export type OpenCloudBinding = OpenCloud.Binding
export type OpenCloudSubmission = OpenCloud.Submission
export type OpenCloudLogs = OpenCloud.LogsOutcome
export type OpenCloudHostOptions = OpenCloud.HostOptions

export type WindowCaptureWindow = WindowCapture.Window
export type WindowCaptureList = WindowCapture.WindowList
export type WindowCaptureSelection = WindowCapture.Selection
export type WindowCaptureViewportTarget = WindowCapture.ViewportTarget
export type WindowCaptureViewportRect = WindowCapture.ViewportRect
export type WindowCaptureCropOutcome = WindowCapture.CropOutcome
export type WindowCaptureFrame = WindowCapture.Frame
export type WindowCaptureDeps = WindowCapture.CaptureDeps
export type WindowCaptureReasons = WindowCapture.CaptureReasons
export type WindowCaptureLimits = WindowCapture.CaptureLimits
export type WindowCaptureOptions = WindowCapture.CaptureOptions
export type WindowCaptureChangeDeps = WindowCapture.ChangeDeps
export type WindowCaptureChangeReasons = WindowCapture.ChangeReasons
export type WindowCaptureCheckpointFrame = WindowCapture.CheckpointFrame
export type WindowCaptureCheckpointFramesOptions = WindowCapture.CheckpointFramesOptions
export type CaptureRecord = WindowCapture.CaptureRecord
export type CaptureRecordOutcome = WindowCapture.RecordOutcome
export type CaptureRecordOptions = WindowCapture.RecordOptions
export type CaptureCheckOptions = WindowCapture.CheckCaptureOptions

export type BoundedResult = Bounded.Result
export type GateOptions = Gate.Options
export type HostOptions = Host.Options
export type CorpusRule = Corpus.Rule
export type CorpusDiscovery = Corpus.Discovery
export type CorpusQuery = Corpus.Query
export type LockSection = Corpus.LockSection
export type LockField = Corpus.LockField
export type WorkerOperations = Worker.Operations
export type WorkerOptions = Worker.Options
export type WorkerArguments = Worker.Arguments
export type LoadDisposition = Worker.LoadDisposition
export type Registrar = Worker.Registrar
export type SelfRegisteringWorkerOperations = Worker.SelfRegisteringOperations

return {
	platform = Platform,
	place = Place,
	attachments = Attachments,
	evidence = Evidence,
	evidenceStore = EvidenceStore,
	player = Player,
	studio = Studio,
	openCloud = OpenCloud,
	fixture = Fixture,
	gate = Gate,
	typePolicy = TypePolicy,
	encode = Wire.encode,
	parse = Wire.parse,
	decode = Wire.decode,

	segmentReport = Wire.segmentReport,
	reassembleReport = Wire.reassembleReport,

	host = Host.create,
	runBounded = Bounded.run,
	directoryLock = Lock.directoryLock,

	worker = Worker.main,
	workerArguments = Worker.arguments,
	runWorkerBatch = Worker.runBatch,

	selfRegisteringWorker = Worker.mainSelfRegistering,
	runSelfRegisteringWorkerBatch = Worker.runBatchSelfRegistering,
	encodeBatch = Batch.encode,
	decodeBatch = Batch.decode,
	HOST_CAPABILITIES = Host.DEFAULT_CAPABILITIES,

	corpus = Corpus,
	windowCapture = WindowCapture,
}
