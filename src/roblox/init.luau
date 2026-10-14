--!strict

local CaseEntry = require "@self/case-entry"
local EnvironmentEngineAdapter = require "@self/environment-engine"
local Reflection = require "@self/reflection"
local UiFakes = require "@self/ui-fakes"
local FixtureBridge = require "@self/fixture-bridge"
local ReflectionSnapshot = require "@self/reflection-snapshot"
local Multiplayer = require "@self/multiplayer"
local InputHost = require "@self/input-host"
local PlayerHost = require "@self/player-host"
local ProgressChannel = require "@self/progress-channel"
local ReportChannel = require "@self/report-channel"
local InstanceHost = require "@self/instance-host"

local Performance = require "@self/performance"
local Network = require "@self/network"
local ExperienceHost = require "@self/experience-host"

local Datatypes = require "@self/datatypes"
local Environment = require "@self/environment"
local Scheduler = require "@self/scheduler"
local UiAudit = require "@self/ui-audit"
local UiAuditCollect = require "@self/ui-audit-collect"

export type CaseEntry = CaseEntry.Entry
export type CaseEntryFactory = CaseEntry.Factory
export type CaseHostName = CaseEntry.Host
export type MultiplayerConnection = Multiplayer.Connection
export type MultiplayerPlayer = Multiplayer.Player
export type MultiplayerRemote = Multiplayer.Remote
export type MultiplayerServerOptions = Multiplayer.ServerOptions
export type MultiplayerClientOptions = Multiplayer.ClientOptions
export type InputKey = InputHost.Key
export type InputPointer = InputHost.Pointer
export type InputBackend = InputHost.Backend
export type InputGuiTarget = InputHost.GuiTarget
export type EnvironmentEngine = EnvironmentEngineAdapter.Engine
export type EnvironmentEngineVector2 = EnvironmentEngineAdapter.Vector2
export type EnvironmentEngineVector3 = EnvironmentEngineAdapter.Vector3
export type EnvironmentEngineColor3 = EnvironmentEngineAdapter.Color3
export type EnvironmentEngineUDim = EnvironmentEngineAdapter.UDim
export type EnvironmentEngineUDim2 = EnvironmentEngineAdapter.UDim2
export type EnvironmentEngineCFrame = EnvironmentEngineAdapter.CFrame
export type EnvironmentEngineLibrary<
	V2 = EnvironmentEngineVector2,
	V3 = EnvironmentEngineVector3,
	C3 = EnvironmentEngineColor3,
	U1 = EnvironmentEngineUDim,
	U2 = EnvironmentEngineUDim2,
	CF = EnvironmentEngineCFrame
> = EnvironmentEngineAdapter.Library<V2, V3, C3, U1, U2, CF>
export type ReflectionOptions = Reflection.Options
export type ReflectionDatabase = Reflection.Database
export type ReflectionClass = Reflection.Class
export type UiFakeOptions = UiFakes.Options
export type FixtureBridgeOptions<
	V2 = EnvironmentEngineVector2,
	V3 = EnvironmentEngineVector3,
	C3 = EnvironmentEngineColor3,
	U1 = EnvironmentEngineUDim,
	U2 = EnvironmentEngineUDim2,
	CF = EnvironmentEngineCFrame
> = FixtureBridge.Options<V2, V3, C3, U1, U2, CF>
export type FixtureBridge = FixtureBridge.Bridge
export type ReflectionSnapshot = ReflectionSnapshot.Snapshot
export type ReflectionSnapshotClass = ReflectionSnapshot.ClassEntry
export type ReflectionSnapshotOptions = ReflectionSnapshot.Options
export type FixtureAccounting = FixtureBridge.Accounting
export type FixtureFaults = FixtureBridge.Faults
export type EnvironmentEvent = Environment.Event
export type EnvironmentCloneHook = Environment.CloneHook
export type UiFakeController = UiFakes.Controller
export type ExperienceEngine = ExperienceHost.Engine
export type ExperienceRegistry = ExperienceHost.Registry
export type ExperienceTransport = ExperienceHost.Transport

export type Network = Network.Network
export type NetworkOptions = Network.Options
export type NetworkPayload = Network.Payload
export type ExperienceHostOptions = ExperienceHost.Options
export type ExperienceEndpoint = ExperienceHost.Endpoint

export type EnvironmentOptions<P = { [string]: unknown }, M = { [string]: unknown }, F = { [string]: unknown }> =
	Environment.Options<P, M, F>
export type EnvironmentDefineOptions = Environment.DefineOptions
export type EnvironmentClass<P = { [string]: unknown }, M = { [string]: unknown }> = Environment.ClassSpec<P, M>
export type EnvironmentLimits = Environment.Limits
export type EnvironmentOperation = Environment.Operation
export type Environment = Environment.Environment
export type Instance = Environment.Instance
export type EnvironmentSnapshot = Environment.Snapshot
export type EnvironmentMethod = Environment.Method
export type Signal<A... = ...unknown> = Environment.Signal<A...>
export type Connection = Environment.Connection
export type DatatypeVector2 = Datatypes.Vector2Value
export type DatatypeVector3 = Datatypes.Vector3Value
export type DatatypeCFrame = Datatypes.CFrameValue
export type DatatypeColor3 = Datatypes.Color3Value
export type DatatypeUDim = Datatypes.UDimValue
export type DatatypeUDim2 = Datatypes.UDim2Value
export type DatatypeEnum = Datatypes.EnumValue
export type DatatypeEnumCategory = Datatypes.EnumCategory
export type DatatypeEnumItem = Datatypes.EnumMember
export type DatatypeVector2int16 = Datatypes.Vector2int16Value
export type DatatypeVector3int16 = Datatypes.Vector3int16Value
export type DatatypeRect = Datatypes.RectValue
export type DatatypeNumberRange = Datatypes.NumberRangeValue
export type DatatypeNumberSequence = Datatypes.NumberSequenceValue
export type DatatypeColorSequence = Datatypes.ColorSequenceValue
export type DatatypeBrickColor = Datatypes.BrickColorValue
export type DatatypeFont = Datatypes.FontValue
export type DatatypeTweenInfo = Datatypes.TweenInfoValue
export type DatatypeContent = Datatypes.ContentValue
export type DatatypeCatalog = Datatypes.Catalog
export type DatatypeLibrary = Datatypes.Library
export type VirtualScheduler = Scheduler.Scheduler
export type VirtualTask<A... = ...unknown, R... = ...unknown> = Scheduler.Task<A..., R...>
export type VirtualCallback<A... = ...unknown, R... = ...unknown> = Scheduler.Callback<A..., R...>
export type UiAuditDump = UiAudit.Dump
export type UiAuditElement = UiAudit.Element
export type UiAuditOptions = UiAudit.Options
export type UiAuditReport = UiAudit.Report
export type UiAuditViolation = UiAudit.Violation
export type UiAuditCollectOptions = UiAuditCollect.Options

return {
	environmentEngine = EnvironmentEngineAdapter.create,
	reflection = Reflection,
	uiFakes = UiFakes,
	fixtureBridge = FixtureBridge.create,
	reflectionSnapshot = ReflectionSnapshot,
	multiplayer = Multiplayer,
	inputHost = InputHost,
	reportChannel = ReportChannel,
	progressChannel = ProgressChannel,
	playerHost = PlayerHost,
	instanceHost = InstanceHost,
	performance = Performance,
	network = Network,
	experienceHost = ExperienceHost,
	testEnvironment = Environment.create,
	datatypes = Datatypes,
	isInstance = Environment.isInstance,
	typeName = Environment.typeName,
	uiAudit = {
		SCHEMA_VERSION = UiAudit.SCHEMA_VERSION,
		RULES = UiAudit.RULES,
		collect = UiAuditCollect.collect,
		decode = UiAudit.decode,
		analyze = UiAudit.analyze,
		contrastRatio = UiAudit.contrastRatio,
	},
}
