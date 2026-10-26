--!strict

local PlaceBoot = require "@self/place-boot"
local PlaceRuntime = require "@self/place-runtime"
local ContentFacts = require "@self/content-facts"

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
export type InputGuiTarget = InputHost.GuiTarget
export type EnvironmentEngineVector3 = EnvironmentEngineAdapter.Vector3
export type EnvironmentEngineCFrame = EnvironmentEngineAdapter.CFrame
export type FixtureBridge = FixtureBridge.Bridge
export type ReflectionSnapshot = ReflectionSnapshot.Snapshot
export type ReflectionSnapshotClass = ReflectionSnapshot.ClassEntry
export type ReflectionSnapshotOptions = ReflectionSnapshot.Options

export type Network = Network.Network

export type EnvironmentOptions<P = { [string]: unknown }, M = { [string]: unknown }, F = { [string]: unknown }> =
	Environment.Options<P, M, F>
export type EnvironmentDefineOptions = Environment.DefineOptions
export type Environment = Environment.Environment
export type Instance = Environment.Instance
export type Object = Environment.Object
export type EnvironmentSnapshot = Environment.Snapshot
export type EnvironmentMethod = Environment.Method
export type Signal<A... = ...unknown> = Environment.Signal<A...>
export type Connection = Environment.Connection
export type DatatypeVector3 = Datatypes.Vector3Value
export type DatatypeCFrame = Datatypes.CFrameValue
export type DatatypeColor3 = Datatypes.Color3Value
export type DatatypeUDim2 = Datatypes.UDim2Value
export type DatatypeEnumCategory = Datatypes.EnumCategory
export type DatatypeFont = Datatypes.FontValue
export type DatatypeCatalog = Datatypes.Catalog
export type DatatypeLibrary = Datatypes.Library
export type VirtualScheduler = Scheduler.Scheduler
export type VirtualTask<A... = ...unknown, R... = ...unknown> = Scheduler.Task<A..., R...>
export type VirtualCallback<A... = ...unknown, R... = ...unknown> = Scheduler.Callback<A..., R...>

export type PlaceBootStage = PlaceBoot.Stage
export type PlaceRuntimeEngine = PlaceRuntime.Engine
export type PlaceRuntime = PlaceRuntime.Runtime
export type PlaceBootEngine = PlaceBoot.Engine
export type PlaceBootView = PlaceBoot.View
export type PlaceBootHost<B = unknown, C = () -> unknown> = PlaceBoot.Host<B, C>

return {
	contentFacts = ContentFacts,
	bootPlace = PlaceBoot.run,
	buildPlaceTree = PlaceBoot.buildTree,
	createPlaceCache = PlaceBoot.createCache,
	createPlaceRuntime = PlaceBoot.createRuntime,
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
	assertInstance = Environment.assertInstance,
	typeName = Environment.typeName,
	uiAudit = {
		SCHEMA_VERSION = UiAudit.SCHEMA_VERSION,
		RULES = UiAudit.RULES,
		collect = UiAuditCollect.collect,
		decode = UiAudit.decode,
		analyze = UiAudit.analyze,
		contrastRatio = UiAudit.contrastRatio,
		isAbove = UiAudit.isAbove,
	},
}
