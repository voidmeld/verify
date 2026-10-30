--!strict

local Types = require "./place-types"
local Environment = require "./environment"
local DeviceCatalog = require "./device-catalog"
local Datatypes = require "./datatypes"
local HttpJson = require "./http-json"
type Instance = Environment.Instance

local function install<B>(
	engine: Types.Engine,
	runtime: Types.ServiceRuntime,
	options: Types.Options<B>,
	context: () -> string
)
	local environment = engine.environment
	local scheduler = environment.scheduler
	local host = options.host
	local contextActionGui: Instance? = nil
	local contextActionButtons: { [string]: Instance } = {}

	local function contextActionButton(name: string): Instance?
		local player = runtime.localPlayer
		local playerGui = if player ~= nil then player:FindFirstChild "PlayerGui" else nil
		if playerGui == nil then
			return nil
		end
		if contextActionGui == nil or contextActionGui.Parent ~= playerGui then
			local gui = engine.newInstance "ScreenGui"
			gui.Name = "ContextActionGui"
			gui.Parent = playerGui
			local frame = engine.newInstance "Frame"
			frame.Name = "ContextButtonFrame"
			frame.Parent = gui
			contextActionGui = gui
			table.clear(contextActionButtons)
		end
		local existing = contextActionButtons[name]
		if existing ~= nil then
			return existing
		end
		local button = engine.newInstance "ImageButton"
		button.Name = name
		button.Parent = (contextActionGui :: Instance):FindFirstChild "ContextButtonFrame"
		local title = engine.newInstance "TextLabel"
		title.Name = "ActionTitle"
		title.Parent = button
		contextActionButtons[name] = button
		return button
	end

	local deviceResult: () -> DeviceCatalog.Device
	local areaResult: (Instance) -> { x: number, y: number, width: number, height: number }
	do
		local function bindAction(_service: Instance, name: string, _handler: unknown, createTouchButton: unknown)
			if createTouchButton == true then
				contextActionButton(name)
			end
		end
		local overrides: { [string]: { [string]: unknown } } = {}
		overrides.ContextActionService = {
			BindAction = bindAction,
			BindActionAtPriority = bindAction,
			UnbindAction = function(_service: Instance, name: string)
				local button = contextActionButtons[name]
				if button ~= nil then
					contextActionButtons[name] = nil
					button:Destroy()
				end
			end,
			GetButton = function(_service: Instance, name: string): unknown
				return contextActionButtons[name]
			end,
			SetTitle = function(_service: Instance, name: string, title: string)
				local button = contextActionButtons[name]
				local label = if button ~= nil then button:FindFirstChild "ActionTitle" else nil
				if label ~= nil then
					label.Text = title
				end
			end,
			SetPosition = function(_service: Instance, name: string, position: unknown)
				local button = contextActionButtons[name]
				if button ~= nil then
					button.Position = position
				end
			end,
			SetImage = function() end,
		}
		overrides.DataModel = {
			GetService = function(_self: Instance, name: string): unknown
				return engine.service(name)
			end,
			FindService = function(_self: Instance, name: string): unknown
				return engine.service(name)
			end,
			BindToClose = function(_self: Instance, callback: () -> ())
				runtime.closeHandlers[#runtime.closeHandlers + 1] = callback
			end,
			IsLoaded = function(): boolean
				return true
			end,
			GetFullName = function(): string
				return ""
			end,
		}
		overrides.ReplicatedFirst = {
			RemoveDefaultLoadingScreen = function() end,
		}
		local humanoidStates: { [Instance]: Datatypes.EnumMember } = {}
		setmetatable(humanoidStates, { __mode = "k" })
		local disabledStates: { [Instance]: { [string]: boolean } } = {}
		setmetatable(disabledStates, { __mode = "k" })
		local function validateHumanoidState(state: Datatypes.EnumMember)
			assert(
				Datatypes.typeName(state) == "EnumItem" and Datatypes.enumType(state) == "HumanoidStateType",
				"HumanoidStateType required"
			)
		end
		local function humanoidState(object: Instance): Datatypes.EnumMember
			local parent = object.Parent
			if parent == nil or not parent:IsA "Model" or not object:IsDescendantOf(engine.service "Workspace") then
				humanoidStates[object] = nil
				return engine.datatypes.Enum.HumanoidStateType.None
			end
			return humanoidStates[object] or engine.datatypes.Enum.HumanoidStateType.Running
		end
		overrides.Humanoid = {
			GetState = humanoidState,
			GetStateEnabled = function(object: Instance, state: Datatypes.EnumMember): boolean
				validateHumanoidState(state)
				local disabled = disabledStates[object]
				return disabled == nil or disabled[state.Name] ~= true
			end,
			SetStateEnabled = function(object: Instance, state: Datatypes.EnumMember, enabled: boolean)
				validateHumanoidState(state)
				assert(type(enabled) == "boolean", "state enabled flag must be boolean")
				if state.Name == "None" then
					return
				end
				local disabled = disabledStates[object] or {}
				disabledStates[object] = disabled
				disabled[state.Name] = not enabled
				environment.fire(object, "StateEnabledChanged", state, enabled)
			end,
			ChangeState = function(object: Instance, state: Datatypes.EnumMember)
				validateHumanoidState(state)
				if humanoidState(object) == engine.datatypes.Enum.HumanoidStateType.None then
					return
				end
				scheduler.defer(function()
					local previous = humanoidState(object)
					if previous ~= engine.datatypes.Enum.HumanoidStateType.None and previous ~= state then
						humanoidStates[object] = state
						environment.fire(object, "StateChanged", previous, state)
					end
				end)
			end,
		}
		overrides.RunService = {
			IsServer = function(): boolean
				return context() == "server"
			end,
			IsClient = function(): boolean
				return context() == "client"
			end,
			IsStudio = function(): boolean
				return false
			end,
			IsRunning = function(): boolean
				return true
			end,
			IsRunMode = function(): boolean
				return true
			end,
			IsEdit = function(): boolean
				return false
			end,
			BindToRenderStep = function(_service: Instance, name: string, _priority: number, callback: (number) -> ())
				runtime.renderSteps[name] = callback
			end,
			UnbindFromRenderStep = function(_service: Instance, name: string)
				runtime.renderSteps[name] = nil
			end,
		}
		overrides.Workspace = {
			GetServerTimeNow = function(): number
				return scheduler.clock()
			end,
		}
		local lastInput = engine.datatypes.Enum.UserInputType.None
		overrides.UserInputService = {
			GetLastInputType = function(): Datatypes.EnumMember
				return lastInput
			end,
			GetMouseButtonsPressed = function(): { Instance }
				return {}
			end,
			IsGamepadButtonDown = function(): boolean
				return false
			end,
		}
		local current: DeviceCatalog.Device? = if options.client
			then DeviceCatalog.desktop(options.client.viewport.x, options.client.viewport.y)
			else nil
		local function device(api: string): DeviceCatalog.Device
			local active = current
			if active == nil then
				error("unsupported_method: " .. api .. " needs a client device", 0)
			end
			return active
		end
		local function area(values: DeviceCatalog.Area): unknown
			return engine.datatypes.Rect.new(values[1], values[2], values[3], values[4])
		end
		local function apply(entry: DeviceCatalog.Device)
			current = entry
			local Enum = engine.datatypes.Enum
			local input = engine.service "UserInputService"
			environment.poke(input, "PreferredInput", Enum.PreferredInput[entry.preferredInput])
			environment.poke(input, "TouchEnabled", entry.touch)
			environment.poke(input, "KeyboardEnabled", entry.keyboard)
			environment.poke(input, "MouseEnabled", entry.mouse)
			environment.poke(input, "GamepadEnabled", entry.gamepad)
			environment.poke(engine.service "GuiService", "TopbarInset", area(entry.topbar))
			local camera = engine.service("Workspace"):FindFirstChildOfClass "Camera"
			if camera then
				environment.poke(
					camera,
					"ViewportSize",
					engine.datatypes.Vector2.new(entry.viewport[1], entry.viewport[2])
				)
			end
		end
		if current then
			apply(current)
		end
		deviceResult = function(): DeviceCatalog.Device
			return device "the simulated device"
		end
		areaResult = function(screen: Instance): { x: number, y: number, width: number, height: number }
			local active = device "ScreenGui layout"
			local mode = environment.propertyOf(screen, "ScreenInsets")
			local insets = engine.datatypes.Enum.ScreenInsets
			local values = if mode == insets.None
				then active.none
				elseif mode == insets.DeviceSafeInsets then active.device
				elseif mode == insets.TopbarSafeInsets then {
					active.topbar[1],
					active.topbar[2] - active.guiInset[2],
					active.topbar[3],
					active.topbar[4] - active.guiInset[2],
				}
				else active.coreUI
			return { x = values[1], y = values[2], width = values[3] - values[1], height = values[4] - values[2] }
		end
		local inputOverrides = overrides.UserInputService
		local gamepads = engine.datatypes.Enum.UserInputType
		inputOverrides.GetNavigationGamepads = function(): { unknown }
			local all: { unknown } = {}
			for index = 1, 8 do
				table.insert(all, gamepads:FromName("Gamepad" .. index))
			end
			return all
		end
		inputOverrides.GetConnectedGamepads = function(): { unknown }
			return if device("UserInputService.GetConnectedGamepads").gamepad then { gamepads.Gamepad1 } else {}
		end
		inputOverrides.GetGamepadConnected = function(_service: Instance, gamepad: unknown): boolean
			return gamepad == gamepads.Gamepad1 and device("UserInputService.GetGamepadConnected").gamepad
		end
		inputOverrides.GamepadSupports = function(): boolean
			return false
		end
		overrides.GuiService = {
			IsTenFootInterface = function(): boolean
				return device("GuiService.IsTenFootInterface").tenFoot
			end,
			GetGuiInset = function(): (unknown, unknown)
				local inset = device("GuiService.GetGuiInset").guiInset
				return engine.datatypes.Vector2.new(inset[1], inset[2]),
					engine.datatypes.Vector2.new(inset[3], inset[4])
			end,
			GetInsetArea = function(_service: Instance, screenInsets: Datatypes.EnumMember): unknown
				local active = device "GuiService.GetInsetArea"
				local insets = engine.datatypes.Enum.ScreenInsets
				return area(
					if screenInsets == insets.CoreUISafeInsets
						then active.coreUI
						elseif screenInsets == insets.DeviceSafeInsets then active.device
						else active.none
				)
			end,
		}
		overrides.StudioDeviceSimulatorService = {
			SetDeviceAsync = function(_service: Instance, id: string)
				apply(DeviceCatalog.device(id))
			end,
			SetOrientationAsync = function(_service: Instance, orientation: unknown)
				local name = string.match(tostring(orientation), "([^%.]+)$")
				if name == nil or engine.datatypes.Enum.ScreenOrientation:FromName(name) == nil then
					error("Unable to cast string to ScreenOrientation", 0)
				end
				apply(DeviceCatalog.oriented(device "StudioDeviceSimulatorService.SetOrientationAsync", name))
			end,
			GetOrientationAsync = function(): unknown
				local orientation = device("StudioDeviceSimulatorService.GetOrientationAsync").orientation
				return engine.datatypes.Enum.ScreenOrientation:FromName(orientation or "LandscapeLeft")
			end,
			SetResolutionAsync = function(_service: Instance, width: number, height: number)
				apply(DeviceCatalog.resized(device "StudioDeviceSimulatorService.SetResolutionAsync", width, height))
			end,
			StopSimulationAsync = function()
				local client = options.client
				if client then
					apply(DeviceCatalog.desktop(client.viewport.x, client.viewport.y))
				end
			end,
		}
		overrides.Players = {
			GetPlayers = function(service: Instance): { Instance }
				local out: { Instance } = {}
				for _, child in service:GetChildren() do
					if child.ClassName == "Player" then
						out[#out + 1] = child
					end
				end
				return out
			end,
			GetPlayerFromCharacter = function(service: Instance, character: Instance): unknown
				for _, player in ((service.GetPlayers :: unknown) :: (Instance) -> { Instance })(service) do
					if player.Character == character then
						return player
					end
				end
				return nil
			end,
			GetPlayerByUserId = function(service: Instance, userId: number): unknown
				for _, player in ((service.GetPlayers :: unknown) :: (Instance) -> { Instance })(service) do
					if player.UserId == userId then
						return player
					end
				end
				return nil
			end,
		}
		local function signalOn(object: Instance, name: string): Environment.Signal
			return object[name] :: Environment.Signal
		end
		local function callbackOf(object: Instance, name: string): unknown
			return environment.propertyOf(object, name)
		end
		overrides.RemoteEvent = {
			FireServer = function(object: Instance, ...: unknown)
				signalOn(object, "OnServerEvent"):Fire(runtime.localPlayer, ...)
			end,
			FireClient = function(object: Instance, _player: unknown, ...: unknown)
				signalOn(object, "OnClientEvent"):Fire(...)
			end,
			FireAllClients = function(object: Instance, ...: unknown)
				signalOn(object, "OnClientEvent"):Fire(...)
			end,
		}
		overrides.UnreliableRemoteEvent = overrides.RemoteEvent
		overrides.RemoteFunction = {
			InvokeServer = function(object: Instance, ...: unknown): ...unknown
				local callback = callbackOf(object, "OnServerInvoke")
				if callback == nil then
					error(
						("Attempt to call a RemoteFunction %s with no OnServerInvoke"):format(object:GetFullName()),
						2
					)
				end
				return (callback :: (Instance?, ...unknown) -> ...unknown)(runtime.localPlayer, ...)
			end,
			InvokeClient = function(object: Instance, _player: unknown, ...: unknown): ...unknown
				local callback = callbackOf(object, "OnClientInvoke")
				if callback == nil then
					error(
						("Attempt to call a RemoteFunction %s with no OnClientInvoke"):format(object:GetFullName()),
						2
					)
				end
				return (callback :: (...unknown) -> ...unknown)(...)
			end,
		}
		overrides.BindableEvent = {
			Fire = function(object: Instance, ...: unknown)
				signalOn(object, "Event"):Fire(...)
			end,
		}
		overrides.BindableFunction = {
			Invoke = function(object: Instance, ...: unknown): ...unknown
				local callback = callbackOf(object, "OnInvoke")
				if callback == nil then
					error(("Attempt to call a BindableFunction %s with no OnInvoke"):format(object:GetFullName()), 2)
				end
				return (callback :: (...unknown) -> ...unknown)(...)
			end,
		}
		overrides.HttpService = {
			GenerateGUID = function(_service: Instance, wrapInCurlyBraces: boolean?): string
				runtime.guidCount += 1
				local body = ("%08x-0000-4000-8000-%012x"):format(runtime.guidCount, runtime.guidCount)
				if wrapInCurlyBraces == false then
					return body
				end
				return "{" .. body .. "}"
			end,
			JSONEncode = function(_service: Instance, value: unknown): string
				return HttpJson.encode(value, host.encodeJson, engine.typeName)
			end,
			JSONDecode = function(_service: Instance, text: string): unknown
				return host.decodeJson(text)
			end,
		}
		local pendingDetach: { [Instance]: boolean } = {}
		do
			local weak = pendingDetach
			setmetatable(weak, { __mode = "k" })
		end
		local function tagged(tag: string): { Instance }
			local out: { Instance } = {}
			local candidates = engine.game:GetDescendants()
			table.insert(candidates, 1, engine.game)
			for _, object in candidates do
				if not pendingDetach[object] and table.find(environment.tagsOf(object), tag) then
					table.insert(out, object)
				end
			end
			return out
		end
		if options.methodDoubles == nil or table.find(options.methodDoubles, "CollectionService") then
			local function notify(object: Instance, present: boolean)
				for _, tag in environment.tagsOf(object) do
					local signals: { [string]: Environment.Signal } = if present
						then runtime.tagAdded
						else runtime.tagRemoved
					local signal = signals[tag]
					if signal then
						signal:Fire(object)
					end
				end
			end
			local added = engine.game.DescendantAdded:Connect(function(object)
				pendingDetach[object] = nil
				notify(object, true)
			end)
			local removed = engine.game.DescendantRemoving:Connect(function(object)
				pendingDetach[object] = true
				notify(object, false)
			end)
			local tags = environment.tagChanged:Connect(function(object, tag, present)
				if not pendingDetach[object] and (object == engine.game or object:IsDescendantOf(engine.game)) then
					local signals: { [string]: Environment.Signal } = if present
						then runtime.tagAdded
						else runtime.tagRemoved
					local signal = signals[tag]
					if signal then
						signal:Fire(object)
					end
				end
			end)
			table.insert(runtime.closeHandlers, function()
				added:Disconnect()
				removed:Disconnect()
				tags:Disconnect()
				for _, map in { runtime.tagAdded, runtime.tagRemoved } do
					for _, signal in map do
						signal:DisconnectAll()
					end
					table.clear(map)
				end
				table.clear(pendingDetach)
			end)
		end
		overrides.CollectionService = {
			AddTag = function(_service: Instance, object: Instance, tag: string)
				environment.setTag(object, tag, true)
			end,
			RemoveTag = function(_service: Instance, object: Instance, tag: string)
				environment.setTag(object, tag, false)
			end,
			HasTag = function(_service: Instance, object: Instance, tag: string): boolean
				return table.find(environment.tagsOf(object), tag) ~= nil
			end,
			GetTagged = function(_service: Instance, tag: string): { Instance }
				return tagged(tag)
			end,
			GetInstanceAddedSignal = function(_service: Instance, tag: string): unknown
				local existing = runtime.tagAdded[tag]
				if existing == nil then
					existing = environment.newSignal()
					runtime.tagAdded[tag] = existing
				end
				return existing
			end,
			GetInstanceRemovedSignal = function(_service: Instance, tag: string): unknown
				local existing = runtime.tagRemoved[tag]
				if existing == nil then
					existing = environment.newSignal()
					runtime.tagRemoved[tag] = existing
				end
				return existing
			end,
		}
		overrides.TweenService = {
			Create = function(
				_service: Instance,
				target: Instance,
				_info: unknown,
				goal: { [string]: unknown }
			): unknown
				local tween = engine.newInstance("Tween", true)
				environment.poke(tween, "Instance", target)
				environment.fakeOn(tween, "Play", function(instance: Environment.Instance)
					for key, value in goal do
						target[key] = value
					end
					environment.fire(instance, "Completed", engine.datatypes.Enum.PlaybackState.Completed)
				end)
				environment.fakeOn(tween, "Cancel", function() end)
				environment.fakeOn(tween, "Pause", function() end)
				return tween
			end,
			GetValue = function(_service: Instance, alpha: number): number
				return alpha
			end,
		}
		overrides.Debris = {
			AddItem = function(_service: Instance, object: Instance, lifetime: number?)
				scheduler.delay(lifetime or 10, function()
					object:Destroy()
				end)
			end,
		}
		overrides.ContentProvider = {
			PreloadAsync = function(
				_service: Instance,
				instances: { Instance | string },
				callback: ((string, Datatypes.EnumMember) -> ())?
			)
				local success = engine.datatypes.Enum.AssetFetchStatus.Success
				local function fetched(content: string)
					if callback and content ~= "" then
						callback(content, success)
					end
				end
				for _, entry in instances do
					if type(entry) == "string" then
						fetched(entry)
						continue
					end
					local objects = entry:GetDescendants()
					table.insert(objects, 1, entry)
					for _, object in objects do
						for _, property in { "Image", "Texture", "TextureID", "MeshId", "SoundId", "AnimationId" } do
							local value = environment.propertyOf(object, property)
							if type(value) == "string" then
								fetched(value)
							end
						end
						local face = environment.propertyOf(object, "FontFace")
						if engine.datatypes.typeName(face) == "Font" then
							fetched((face :: Datatypes.FontValue).Family)
						end
					end
				end
			end,
		}
		overrides.AssetService = {
			CreateMeshPartAsync = function(_service: Instance, content: unknown): unknown
				local uri = if engine.datatypes.typeName(content) == "Content"
					then (content :: Datatypes.ContentValue).Uri
					else content
				assert(type(uri) == "string" and uri ~= "", "mesh content must have a non-empty URI")
				local part = engine.newInstance("MeshPart", true)
				environment.poke(part, "MeshId", uri)
				return part
			end,
		}
		overrides.PhysicsService = {
			RegisterCollisionGroup = function() end,
			CollisionGroupSetCollidable = function() end,
			IsCollisionGroupRegistered = function(): boolean
				return true
			end,
		}
		overrides.StarterGui = {
			SetCoreGuiEnabled = function() end,
			GetCoreGuiEnabled = function(): boolean
				return true
			end,
			SetCore = function() end,
			GetCore = function(): unknown
				return nil
			end,
		}
		local hashMaps: { [string]: Instance } = {}
		overrides.MemoryStoreService = {
			GetHashMap = function(service: Instance, value: unknown): Instance
				local gameId = engine.game.GameId
				assert(
					type(gameId) == "number" and gameId > 0,
					"You must publish this place to use MemoryStoreService."
				)
				local name = if type(value) == "number" then tostring(value) else value
				assert(type(name) == "string", "MemoryStoreService.GetHashMap requires a string name")
				local map = hashMaps[name]
				if map == nil then
					map = engine.newInstance("MemoryStoreHashMap", true)
					map.Name = "Instance"
					map.Parent = service
					hashMaps[name] = map
				end
				return map
			end,
		}
		overrides.DataStoreService = {
			GetDataStore = function(): unknown
				return runtime.dataStore
			end,
			GetOrderedDataStore = function(): unknown
				return runtime.dataStore
			end,
			GetGlobalDataStore = function(): unknown
				return runtime.dataStore
			end,
		}
		local allowed: { [string]: boolean }? = nil
		if options.methodDoubles then
			allowed = {}
			for _, name in options.methodDoubles do
				assert(allowed)[name] = true
			end
		end
		local function install(object: Environment.Object)
			local methods = overrides[object.ClassName]
			if methods and (allowed == nil or allowed[object.ClassName]) then
				for name, method in methods do
					if not environment.hasFake(Environment.assertInstance(object), name) then
						table.insert(
							runtime.closeHandlers,
							environment.fakeOn(object, name, method :: Environment.Method)
						)
					end
				end
				if object.ClassName == "UserInputService" then
					local service = Environment.assertInstance(object)
					for _, event in { "InputBegan", "InputChanged", "InputEnded" } do
						local connection = (service[event] :: Environment.Signal):Connect(function(input: unknown)
							assert(engine.isInstance(input), "input event requires an InputObject")
							local inputType =
								environment.propertyOf(Environment.assertInstance(input), "UserInputType") :: Datatypes.EnumMember
							if inputType ~= lastInput then
								lastInput = inputType
								environment.fire(service, "LastInputTypeChanged", inputType)
							end
						end)
						table.insert(runtime.closeHandlers, function()
							connection:Disconnect()
						end)
					end
				end
			end
		end
		install(engine.game)
		for _, object in engine.game:GetDescendants() do
			install(object)
		end
		local created = environment.onCreate(install)
		table.insert(runtime.closeHandlers, function()
			created:Disconnect()
		end)
	end
	return deviceResult, areaResult
end

return install
