--!strict

local Environment = require "./environment"
local Adapter = require "./environment-engine"
local InstanceHost = require "./instance-host"
local Reflection = require "./reflection"
local UiFakes = require "./ui-fakes"
local UiLayout = require "./ui-layout"
local PlaceRuntime = require "./place-runtime"
local Datatypes = require "./datatypes"
local ContentFakes = require "./content-fakes"
local LocalizationFakes = require "./localization-fakes"
local LogFakes = require "./log-fakes"
local TextContent = require "./text-content"

local SERVICE_DEFAULTS: { [string]: { [string]: unknown } } = {
	GuiService = {
		AutoSelectGuiEnabled = true,
		GuiNavigationEnabled = true,
		TouchControlsEnabled = true,
		MenuIsOpen = false,
		IsModalDialog = false,
		IsWindows = false,
	},
	UserInputService = { MouseIconEnabled = true, MouseDeltaSensitivity = 1, ModalEnabled = false },
}

type Vector2 = Adapter.Vector2
type Vector3 = Adapter.Vector3
type Color3 = Adapter.Color3
type UDim = Adapter.UDim
type UDim2 = Adapter.UDim2
type CFrame = Adapter.CFrame

export type Options<V2 = Vector2, V3 = Vector3, C3 = Color3, U1 = UDim, U2 = UDim2, CF = CFrame> = {
	content: ContentFakes.Options?,
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
	layout: UiLayout.Options?,
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
	created: { Environment.Object },
	cloned: { { source: Environment.Instance, copy: Environment.Instance } },
	stop: () -> (),
}

export type Bridge = {
	environment: Environment.Environment,
	engine: Adapter.Engine,
	ui: UiFakes.Controller?,
	layout: UiLayout.Controller?,
	unavailable: { string },
	faults: Faults,
	hasClass: (className: string) -> boolean,
	observe: (listener: (event: Environment.Event) -> ()) -> Environment.Connection,
	track: () -> Tracking,
	record: () -> { events: { Environment.Event }, stop: () -> () },
	instanceHost: (actor: string) -> InstanceHost.Simulated,
	placeEngine: () -> PlaceRuntime.Engine,
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
				local spec = table.clone(UiFakes.classes[name])
				spec.creatable = nil
				result[name] = spec
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
	local serviceClasses: { [string]: boolean } = {}
	local resolveService: ((string) -> Environment.Instance)? = nil
	local computed: { [string]: Environment.Computed } = table.clone(settings.computed or {})
	for _, name in settings.database:GetClassNames() do
		local class = settings.database:GetClass(name)
		if class and table.find(class.Tags, "Service") then
			serviceClasses[name] = true
			local key = "DataModel." .. name
			if computed[key] == nil then
				computed[key] = function(): Environment.Instance?
					return if resolveService then resolveService(name) else nil
				end
			end
		end
	end
	if settings.ui ~= false then
		for _, className in { "TextLabel", "TextButton", "TextBox" } do
			local key = className .. ".ContentText"
			if computed[key] == nil then
				computed[key] = function(object: Environment.Instance): string
					local text = object.Text
					assert(type(text) == "string", "text content requires a string")
					return if object.RichText == true then TextContent.plain(text) else text
				end
			end
		end
	end
	local readInteractable: ((Environment.Instance) -> unknown)? = nil
	local nonInteractable: unknown = nil
	if computed["GuiObject.GuiState"] == nil then
		computed["GuiObject.GuiState"] = {
			get = function(object: Environment.Instance): unknown
				local read = readInteractable
				local current: Environment.Instance? = object
				while read and nonInteractable ~= nil and current do
					if current:IsA "GuiObject" and read(current) == false then
						return nonInteractable
					end
					current = current.Parent
				end
				return nil
			end,
			writable = true,
		}
	end
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
		computed = table.freeze(computed),
		undeclaredWrites = settings.undeclaredWrites,
		undeclaredReads = settings.undeclaredReads,
		functionDoubles = settings.functionDoubles,
	}
	local controller: UiFakes.Controller? = if ui ~= false
		then UiFakes.attach(environment, ui :: UiFakes.Options?, selection)
		else nil
	local content = if settings.content then table.clone(settings.content) else nil
	if content and content.library == nil and settings.library then
		content.library = ((settings.library :: unknown) :: { datatypes: Datatypes.Library }).datatypes
	end
	ContentFakes.attach(environment, content)
	LocalizationFakes.attach(environment)
	local library = (settings.library :: unknown) :: Adapter.Library<V2, V3, C3, U1, U2, CF>?
	if library then
		local found, member = pcall(function(): unknown
			return ((library.datatypes :: unknown) :: typeof(Datatypes)).Enum.GuiState.NonInteractable
		end)
		nonInteractable = if found then member else nil
		readInteractable = function(object: Environment.Instance): unknown
			return environment.propertyOf(object, "Interactable")
		end
	end
	local engine = Adapter.create(environment, library)
	local layoutOptions = if settings.layout then table.clone(settings.layout) else nil
	if layoutOptions and controller and layoutOptions.read == nil then
		layoutOptions.read = controller.styled
		layoutOptions.component = layoutOptions.component or controller.component
	end
	if
		layoutOptions
		and layoutOptions.measureBounds == nil
		and type(ui) == "table"
		and type(ui.measureBounds) == "function"
	then
		layoutOptions.measureBounds = ui.measureBounds
		layoutOptions.measureLineHeight = layoutOptions.measureLineHeight or ui.measureLineHeight
		layoutOptions.truncateBounds = ui.truncateBounds
	end
	local layout = if layoutOptions then UiLayout.attach(environment, layoutOptions) else nil
	if layout and controller then
		local step = layout.step
		local stepStyles = controller.step
		local cached = controller.cached
		layout.step = function()
			stepStyles()
			cached(step)
		end
	end
	local place: PlaceRuntime.Engine? = nil
	local function placeEngine(): PlaceRuntime.Engine
		if place then
			return place
		end
		local services: { [string]: Environment.Instance } = {}
		local diagnostics: { PlaceRuntime.Diagnostic } = {}
		local recordLog: ((string, string) -> ())? = nil
		local source = function(): string
			return "fixture"
		end
		local game = environment.createEngineInstance "DataModel"
		local function member(className: string, property: string): (string?, string?)
			local class = settings.database:GetClass(className)
			while class do
				local entry = class.Properties[property]
				if entry then
					return "property", entry.Datatype
				end
				if table.find(class.Events or {}, property) then
					return "event", nil
				end
				if table.find(class.Methods or {}, property) then
					return "method", nil
				end
				class = if class.Superclass then settings.database:GetClass(class.Superclass) else nil
			end
			return nil, nil
		end
		local value: PlaceRuntime.Engine = {
			environment = environment,
			game = game,
			newInstance = function(name: string, engineOwned: boolean?): Environment.Instance
				return if engineOwned then environment.createEngineInstance(name) else environment.createInstance(name)
			end,
			service = function(name: string): Environment.Instance
				assert(serviceClasses[name], "not a reflected service: " .. name)
				local existing = services[name]
				if existing then
					return existing
				end
				local object = environment.createEngineInstance(name)
				local defaults: { [string]: unknown } = SERVICE_DEFAULTS[name] or {}
				for property, value in defaults do
					if member(name, property) == "property" and environment.propertyOf(object, property) == nil then
						environment.poke(object, property, value)
					end
				end
				object.Parent = game
				services[name] = object
				return object
			end,
			setSourceResolver = function(resolve: () -> string)
				source = resolve
			end,
			currentSource = function(): string
				return source()
			end,
			record = function(kind: string, text: string, origin: string)
				table.insert(diagnostics, { kind = kind, text = text, source = origin })
				if recordLog then
					recordLog(kind, text)
				end
			end,
			isInstance = Environment.isInstance,
			datatypes = if settings.library
				then (settings.library.datatypes :: unknown) :: typeof(Datatypes)
				else Datatypes,
			typeName = settings.typeName,
			diagnostics = diagnostics,
			surface = {
				services = serviceClasses,
				memberKind = function(className: string, property: string): string?
					local kind = member(className, property)
					return kind
				end,
				memberType = function(className: string, property: string): string?
					local _, datatype = member(className, property)
					return datatype
				end,
			},
		}
		place = value
		resolveService = value.service
		if serviceClasses.LogService then
			recordLog = LogFakes.attach(environment, value.datatypes.Enum.MessageType, function()
				return value.service "LogService"
			end)
		end
		return value
	end

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
		local created: { Environment.Object } = {}
		local cloned: { { source: Environment.Instance, copy: Environment.Instance } } = {}
		local creating = environment.onCreate(function(object: Environment.Object)
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
		layout = layout,
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
		placeEngine = placeEngine,
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
