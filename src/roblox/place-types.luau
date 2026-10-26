--!strict

local Environment = require "./environment"
local Datatypes = require "./datatypes"
local DeviceCatalog = require "./device-catalog"

export type Chunk = () -> unknown
export type Instance = Environment.Instance
export type Diagnostic = { kind: string, text: string, source: string }
export type Engine = {
	game: Instance,
	environment: Environment.Environment,
	newInstance: (string, boolean?) -> Instance,
	service: (string) -> Instance,
	setSourceResolver: (() -> string) -> (),
	currentSource: () -> string,
	record: (string, string, string) -> (),
	isInstance: (unknown) -> boolean,
	datatypes: typeof(Datatypes),
	typeName: (unknown) -> string,
	diagnostics: { Diagnostic },
	surface: {
		services: { [string]: boolean },
		memberKind: (string, string) -> string?,
		memberType: (string, string) -> string?,
	},
}
export type ServiceRuntime = {
	localPlayer: Instance?,
	closeHandlers: { () -> () },
	renderSteps: { [string]: (number) -> () },
	tagAdded: { [string]: Environment.Signal },
	tagRemoved: { [string]: Environment.Signal },
	guidCount: number,
	dataStore: {
		GetAsync: () -> unknown,
		SetAsync: () -> unknown,
		UpdateAsync: (unknown, string, (unknown) -> unknown) -> unknown,
		RemoveAsync: () -> unknown,
		OnUpdate: () -> { Disconnect: () -> () },
	},
}

export type Runtime = ServiceRuntime & {
	globals: { [string]: unknown },
	requireInstance: (unknown) -> unknown,
	runScript: (Instance, string) -> thread?,
	step: (seconds: number) -> (),
	screenArea: (screen: Instance) -> { x: number, y: number, width: number, height: number },
	device: () -> DeviceCatalog.Device,
}

export type Host<B = unknown, C = Chunk> = {
	readFile: (path: string) -> string,
	compile: (source: string) -> B,
	load: (bytecode: B, chunkName: string, environment: { [string]: unknown }) -> C,
	encodeJson: (value: unknown) -> string,
	decodeJson: (text: string) -> unknown,
}

export type Cache<B = unknown, C = Chunk> = {
	read: (path: string) -> string,
	bytecode: (path: string) -> B,
	load: (path: string, environment: { [string]: unknown }) -> C,
}

export type Mounted = {
	root: Instance,
	scripts: { Instance },
	sources: { [Instance]: string },
}

export type Client = { name: string, userId: number, viewport: { x: number, y: number } }

export type Options<B = unknown> = {
	aliases: { [string]: string },
	cache: Cache<B>,
	host: Host<B>,
	methodDoubles: { string }?,
	client: Client?,
	beforeRender: (() -> ())?,
}

return {}
