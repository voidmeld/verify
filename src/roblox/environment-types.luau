--!strict

local Scheduler = require "./scheduler"

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<A... = ...unknown> = {
	Connect: (self: Signal<A...>, handler: (A...) -> ()) -> Connection,
	Wait: (self: Signal<A...>) -> A...,
	Fire: (self: Signal<A...>, A...) -> (),
	DisconnectAll: (self: Signal<A...>) -> (),
}

export type Method<A... = ...unknown, R... = ...unknown> = (A...) -> R...
export type Object = {
	ClassName: string,
	IsA: (Object, string) -> boolean,
	GetPropertyChangedSignal: (Object, string) -> Signal<()>,
	Changed: Signal<string>,
}
export type Instance = {
	[string]: unknown,
	ClassName: string,
	Name: unknown,
	Parent: Instance?,
	Destroy: (Instance) -> (),
	Clone: (Instance) -> Instance?,
	AddTag: (Instance, string) -> (),
	RemoveTag: (Instance, string) -> (),
	HasTag: (Instance, string) -> boolean,
	GetTags: (Instance) -> { string },
	ClearAllChildren: (Instance) -> (),
	GetChildren: (Instance) -> { Instance },
	GetDescendants: (Instance) -> { Instance },
	FindFirstChild: (Instance, string, boolean?) -> Instance?,
	WaitForChild: (Instance, string, number?) -> Instance?,
	FindFirstChildOfClass: (Instance, string) -> Instance?,
	FindFirstChildWhichIsA: (Instance, string, boolean?) -> Instance?,
	FindFirstAncestorOfClass: (Instance, string) -> Instance?,
	FindFirstAncestorWhichIsA: (Instance, string) -> Instance?,
	FindFirstAncestor: (Instance, string) -> Instance?,
	GetFullName: (Instance) -> string,
	IsA: (Object, string) -> boolean,
	IsDescendantOf: (Instance, Instance) -> boolean,
	IsAncestorOf: (Instance, Instance) -> boolean,
	SetAttribute: (Instance, string, unknown) -> (),
	GetAttribute: (Instance, string) -> unknown,
	GetAttributes: (Instance) -> { [string]: unknown },
	GetPropertyChangedSignal: (Object, string) -> Signal<()>,
	GetAttributeChangedSignal: (Instance, string) -> Signal<()>,
	ResetPropertyToDefault: (Instance, string) -> (),
	IsPropertyModified: (Instance, string) -> boolean,
	Changed: Signal<string>,
	ChildAdded: Signal<Instance>,
	ChildRemoved: Signal<Instance>,
	DescendantAdded: Signal<Instance>,
	DescendantRemoving: Signal<Instance>,
	AncestryChanged: Signal<Instance, Instance?>,
	Destroying: Signal<()>,
	AttributeChanged: Signal<string>,
	StyledPropertiesChanged: Signal<()>,
}
export type Snapshot = {
	className: string,
	name: unknown,
	properties: { [string]: unknown },
	attributes: { [string]: unknown },
	children: { Snapshot },
}

export type ClassSpec<P = { [string]: unknown }, M = { [string]: unknown }> = {
	super: string?,
	creatable: boolean?,
	properties: P?,
	events: { string }?,
	methods: M?,
	access: { [string]: "read" | "write" | "none" | "callback" }?,
}

export type DefineOptions = {
	replace: boolean?,
}

export type Limits = {
	attributeNameLength: number?,
	attributeStringLength: number?,
}

export type HandlerErrors = "collect" | "raise"

export type Options<P = { [string]: unknown }, M = { [string]: unknown }, F = { [string]: unknown }> = {
	defaultProperty: ((className: string, property: string, fallback: unknown) -> unknown)?,
	validateProperty: ((className: string, property: string, value: unknown, operation: "set" | "poke") -> ...unknown)?,
	handlerErrors: HandlerErrors?,
	computed: { [string]: Computed }?,
	undeclaredWrites: boolean?,
	undeclaredReads: ("raise" | "nil")?,
	functionDoubles: boolean?,
	classes: { [string]: ClassSpec<P, M> }?,
	builtins: boolean?,
	fakes: F?,
	limits: Limits?,
}

export type Computed = ((object: Instance) -> unknown) | { get: (object: Instance) -> unknown, writable: boolean? }

export type Operation = "create" | "setProperty" | "setAttribute" | "setParent" | "destroy"

export type Event = {
	operation: Operation,
	subject: string,
	member: string?,
	injected: boolean,
	object: Instance,
	value: unknown,
}

export type ObserveFilter = {
	operations: { Operation }?,
	members: { string }?,
}

export type CloneHook = (source: Instance, copy: Instance, remap: (Instance) -> Instance) -> ()
export type CreateHook = (object: Object) -> ()

export type SignalHandle = {
	fire: (...unknown) -> (),
	connections: () -> number,
	fires: () -> number,
}

export type Environment = {
	root: Instance,
	heartbeat: Signal<number>,
	tagChanged: Signal<Instance, string, boolean>,
	scheduler: Scheduler.Scheduler,
	task: {
		spawn: <A..., R...>(callback: Scheduler.Task<A..., R...>, A...) -> thread,
		defer: <A..., R...>(callback: Scheduler.Task<A..., R...>, A...) -> thread,
		delay: <A..., R...>(seconds: number, callback: Scheduler.Task<A..., R...>, A...) -> thread,
		wait: (seconds: number?) -> number,
		cancel: (thread: thread) -> (),
	},
	errors: { string },
	defineClass: <P, M>(className: string, spec: ClassSpec<P, M>, options: DefineOptions?) -> (),
	fake: <A..., R...>(member: string, handler: (Instance, A...) -> R...) -> (),
	hasFake: (object: Instance, member: string) -> boolean,
	fakeOn: <O, A..., R...>(object: O, name: string, handler: (O, A...) -> R...) -> () -> (),
	createInstance: (className: string, props: { [unknown]: unknown }?) -> Instance,
	createEngineInstance: (className: string, props: { [unknown]: unknown }?) -> Instance,
	createEngineObject: (className: string, props: { [unknown]: unknown }?) -> Object,
	releaseObject: (object: Object) -> (),
	snapshot: (object: Instance) -> Snapshot,
	newSignal: <A...>() -> Signal<A...>,
	step: (seconds: number) -> (),
	now: () -> number,
	childrenOf: (object: Instance) -> { Instance },
	parentOf: (object: Instance) -> Instance?,
	descendantOrderOf: (ancestor: Instance, object: Instance) -> number?,
	propertyOf: (object: Object, key: string) -> unknown,
	defaultPropertyOf: (object: Instance, key: string) -> unknown,
	defaultClassProperty: (className: string, key: string) -> unknown,
	tagsOf: (object: Instance) -> { string },
	setTag: (object: Instance, tag: string, present: boolean) -> (),
	attributeOf: (object: Instance, name: string) -> unknown,
	isAlive: (object: Object) -> boolean,
	liveObjects: () -> number,
	liveConnections: () -> number,
	poke: (object: Instance, key: string, value: unknown) -> (),
	fire: (object: Instance, event: string, ...unknown) -> (),
	failNext: (operation: Operation, times: number?) -> (),
	clearFailures: () -> (),
	pendingFailures: () -> number,
	observe: (listener: (event: Event) -> (), filter: ObserveFilter?) -> Connection,
	publish: (object: Instance, key: string, value: unknown) -> (),
	touch: () -> (),
	revision: () -> (number, number),
	onClone: (hook: CloneHook) -> Connection,
	onCreate: (hook: CreateHook) -> Connection,
	signalOf: (object: Instance, event: string) -> SignalHandle,
	connectionsOf: (signal: Signal) -> number,
	firesOf: (signal: Signal) -> number,
	connectionsOfInstance: (object: Instance) -> number,
}

export type Resolved = {
	instance: boolean,
	creatable: boolean,
	access: { [string]: "read" | "write" | "none" | "callback" },
	properties: { [string]: unknown },
	events: { [string]: true },
	methods: { [string]: unknown },
}

export type State = {
	worldPivotSet: boolean?,
	className: string,
	class: Resolved,
	values: { [string]: unknown },
	children: { Instance },
	parent: Instance?,
	ancestryOrders: { [Instance]: number },
	attributes: { [string]: unknown },
	tags: { [string]: boolean },
	signals: { [string]: Signal },
	signalFires: { [string]: number },
	extras: { [string]: boolean },
	doubles: { [string]: unknown },
	bound: { [string]: unknown }?,
	destroyed: boolean,
	destroying: boolean,
	removing: boolean,
}

return {}
