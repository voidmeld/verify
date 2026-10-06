--!strict

local Environment = require "./environment"
local Adapter = require "./environment-engine"
local InstanceHost = require "./instance-host"
local Reflection = require "./reflection"
local UiFakes = require "./ui-fakes"

type Vector2 = Adapter.Vector2
type Vector3 = Adapter.Vector3
type Color3 = Adapter.Color3
type UDim = Adapter.UDim
type UDim2 = Adapter.UDim2
type CFrame = Adapter.CFrame

export type Options<V2 = Vector2, V3 = Vector3, C3 = Color3, U1 = UDim, U2 = UDim2, CF = CFrame> = {
	database: Reflection.Database,
	typeName: (unknown) -> string,
	enumType: ((unknown) -> string)?,
	library: Adapter.Library<V2, V3, C3, U1, U2, CF>?,
	classes: { [string]: Environment.ClassSpec }?,
	referenceClass: ((className: string, property: string) -> string?)?,
	validateProperty: ((className: string, property: string, value: unknown, operation: "set" | "poke") -> ...unknown)?,
	defaultProperty: ((className: string, property: string) -> unknown)?,
	handlerErrors: Environment.HandlerErrors?,
	computed: { [string]: Environment.Computed }?,
	undeclaredWrites: boolean?,
	undeclaredReads: ("raise" | "nil")?,
	functionDoubles: boolean?,
	ui: (UiFakes.Options | false)?,
}

export type Accounting = {
	objects: number,
	connections: number,
	pendingFaults: number,
}

export type Faults = {
	inject: (operation: Environment.Operation, times: number?) -> (),
	pending: () -> number,
	clear: () -> (),
	assertConsumed: () -> (),
}

export type Tracking = {
	created: { Environment.Instance },
	cloned: { { source: Environment.Instance, copy: Environment.Instance } },
	stop: () -> (),
}

export type Bridge = {
	environment: Environment.Environment,
	engine: Adapter.Engine,
	ui: UiFakes.Controller?,
	unavailable: { string },
	faults: Faults,
	hasClass: (className: string) -> boolean,
	observe: (listener: (event: Environment.Event) -> ()) -> Environment.Connection,
	track: () -> Tracking,
	record: () -> { events: { Environment.Event }, stop: () -> () },
	instanceHost: (actor: string) -> InstanceHost.Simulated,
	accounting: () -> Accounting,
	close: () -> Accounting,
}

local function overlays(options: Options, unavailable: { string }): { [string]: Environment.ClassSpec }
	local result: { [string]: Environment.ClassSpec } = {}
	for name, spec in Environment.BASIC_CLASSES do
		if spec.events ~= nil and options.database:GetClass(name) ~= nil then
			result[name] = { events = spec.events }
		end
	end
	if options.ui ~= false then
		local names: { string } = {}
		for name in UiFakes.classes do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			if options.database:GetClass(name) ~= nil then
				result[name] = UiFakes.classes[name]
			else
				table.insert(unavailable, name)
			end
		end
	end
	local supplied: { [string]: Environment.ClassSpec } = options.classes or {}
	for name, spec in supplied do
		result[name] = spec
	end
	return result
end

local function create<V2, V3, C3, U1, U2, CF>(options: Options<V2, V3, C3, U1, U2, CF>): Bridge
	local settings = (options :: unknown) :: Options
	local unavailable: { string } = {}
	local ui = settings.ui
	local validate = if type(ui) == "table" then ui.validate else nil
	local uiValidates = ui ~= false and validate ~= false
	local selectUi = if type(validate) == "function" then validate else nil
	local supplied = settings.validateProperty
	local selection = UiFakes.selection(if type(ui) == "table" then ui else nil)
	local validator: ((className: string, property: string, value: unknown, operation: "set" | "poke") -> ...unknown)? =
		nil
	if uiValidates then
		validator = function(className, property, value, operation)
			if property == "SelectedObject" and (selectUi == nil or selectUi(className, property)) then
				if selection.validate(className, property, value, operation) == false then
					return false
				end
			end
			if supplied ~= nil then
				return supplied(className, property, value, operation)
			end
			return nil
		end
	else
		validator = supplied
	end
	local environment = Reflection.create {
		database = settings.database,
		typeName = settings.typeName,
		enumType = settings.enumType,
		classes = overlays(settings, unavailable),
		referenceClass = settings.referenceClass,
		validateProperty = validator,
		defaultProperty = settings.defaultProperty,
		handlerErrors = settings.handlerErrors,
		computed = settings.computed,
		undeclaredWrites = settings.undeclaredWrites,
		undeclaredReads = settings.undeclaredReads,
		functionDoubles = settings.functionDoubles,
	}
	local controller: UiFakes.Controller? = if ui ~= false
		then UiFakes.attach(environment, ui :: UiFakes.Options?, selection)
		else nil
	local library = (settings.library :: unknown) :: Adapter.Library<V2, V3, C3, U1, U2, CF>?
	local engine = Adapter.create(environment, library)

	local function accounting(): Accounting
		return {
			objects = environment.liveObjects(),
			connections = environment.liveConnections(),
			pendingFaults = environment.pendingFailures(),
		}
	end

	local faults: Faults = {
		inject = environment.failNext,
		pending = environment.pendingFailures,
		clear = environment.clearFailures,
		assertConsumed = function()
			local pending = environment.pendingFailures()
			assert(pending == 0, ("%d injected failure(s) never fired"):format(pending))
		end,
	}

	local function record(): { events: { Environment.Event }, stop: () -> () }
		local events: { Environment.Event } = {}
		local connection = environment.observe(function(event: Environment.Event)
			table.insert(events, event)
		end)
		return {
			events = events,
			stop = function()
				connection:Disconnect()
			end,
		}
	end

	local function track(): Tracking
		local created: { Environment.Instance } = {}
		local cloned: { { source: Environment.Instance, copy: Environment.Instance } } = {}
		local creating = environment.onCreate(function(object: Environment.Instance)
			table.insert(created, object)
		end)
		local cloning = environment.onClone(function(source: Environment.Instance, copy: Environment.Instance)
			table.insert(cloned, { source = source, copy = copy })
		end)
		return {
			created = created,
			cloned = cloned,
			stop = function()
				creating:Disconnect()
				cloning:Disconnect()
			end,
		}
	end

	return {
		environment = environment,
		engine = engine,
		ui = controller,
		unavailable = unavailable,
		faults = faults,
		hasClass = function(className: string): boolean
			return settings.database:GetClass(className) ~= nil
		end,
		observe = environment.observe,
		track = track,
		record = record,
		instanceHost = function(actor: string): InstanceHost.Simulated
			return InstanceHost.simulated(actor, environment)
		end,
		accounting = accounting,
		close = function(): Accounting
			if controller ~= nil then
				controller.close()
			end
			return accounting()
		end,
	}
end

return {
	create = create,
}
