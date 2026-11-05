--!strict

local Environment = require "./environment-types"
local Datatypes = require "./datatypes"

type Instance = Environment.Instance
type State = { kind: string, value: unknown }
export type Controller = {
	changed: (Instance, string, boolean) -> (),
	destroying: (Instance) -> (),
	released: (Instance) -> (),
}

local function attach(environment: Environment.Environment)
	local states: { [Instance]: State } = {}
	setmetatable(states, { __mode = "k" })
	local actions: { [Instance]: boolean } = {}
	local owners: { [Instance]: Instance } = {}
	local destroying: { [Instance]: boolean } = {}
	setmetatable(actions, { __mode = "k" })
	setmetatable(owners, { __mode = "kv" })
	setmetatable(destroying, { __mode = "k" })
	local function preferred(action: Instance)
		if destroying[action] then
			return
		end
		actions[action] = true
		local root = action:FindFirstAncestorWhichIsA "DataModel"
		if root == nil then
			return
		end
		local input = root:FindFirstChildOfClass "UserInputService"
		local device = if input
			then tostring(environment.propertyOf(input, "PreferredInput")):match "([^%.]+)$"
			else nil
		local chosen: Instance? = nil
		for _, binding in action:GetChildren() do
			if not binding:IsA "InputBinding" then
				continue
			end
			owners[binding] = action
			local code = tostring(environment.propertyOf(binding, "KeyCode")):match "([^%.]+)$" or "None"
			local gamepad = code:match "^Button" ~= nil or code:match "^DPad" ~= nil or code:match "^Thumbstick" ~= nil
			if
				device == "Touch" and environment.propertyOf(binding, "UIButton") ~= nil
				or device == "Gamepad" and gamepad
				or (device == nil or device == "KeyboardAndMouse")
					and not gamepad
					and code ~= "None"
					and code ~= "Unknown"
			then
				chosen = binding
				break
			end
		end
		environment.publish(action, "PreferredBinding", chosen)
	end
	local defaults: { [string]: unknown } = {
		Bool = false,
		Direction1D = 0,
		Direction2D = Datatypes.Vector2.zero,
		Direction3D = Datatypes.Vector3.zero,
		ViewportPosition = Datatypes.Vector2.zero,
	}
	local types = {
		Bool = "boolean",
		Direction1D = "number",
		Direction2D = "Vector2",
		Direction3D = "Vector3",
		ViewportPosition = "Vector2",
	}
	local function state(action: Instance): State
		local kind = tostring(action.Type):match "([^%.]+)$" or ""
		assert(defaults[kind] ~= nil, "unsupported_input_action: " .. kind)
		local current = states[action]
		if current == nil or current.kind ~= kind then
			current = { kind = kind, value = defaults[kind] }
			states[action] = current
		end
		return current
	end
	local function update(action: Instance, current: State, value: unknown)
		if current.value == value then
			return
		end
		current.value = value
		if current.kind == "Bool" then
			environment.fire(action, if value == true then "Pressed" else "Released")
		end
		environment.fire(action, "StateChanged", value)
	end
	local function reset(action: Instance)
		local current = state(action)
		update(action, current, defaults[current.kind])
	end
	local function enabled(action: Instance): boolean
		if action.Enabled == false or action:FindFirstAncestorWhichIsA "DataModel" == nil then
			return false
		end
		local context = action:FindFirstAncestorWhichIsA "InputContext"
		return context == nil or context.Enabled ~= false
	end
	environment.fake("InputAction.GetState", function(action: Instance): unknown
		return state(action).value
	end)
	environment.fake("InputAction.Fire", function(action: Instance, value: unknown)
		local current = state(action)
		assert(Datatypes.typeof(value) == types[current.kind], "InputAction:Fire state must match Type")
		if not enabled(action) then
			return
		end
		update(action, current, value)
	end)
	local function changed(object: Instance, property: string, hasChildren: boolean)
		if
			property ~= "Parent"
			and property ~= "Type"
			and property ~= "Enabled"
			and property ~= "KeyCode"
			and property ~= "UIButton"
			and property ~= "PreferredInput"
		then
			return
		end
		if object:IsA "InputBinding" then
			local previous = owners[object]
			local parent = object.Parent
			owners[object] = if parent and parent:IsA "InputAction" then parent else nil
			if previous and environment.isAlive(previous) then
				preferred(previous)
			end
			if parent and parent:IsA "InputAction" and parent ~= previous then
				preferred(parent)
			end
		elseif object:IsA "InputAction" and property == "Parent" then
			preferred(object)
		elseif property == "PreferredInput" and object:IsA "UserInputService" then
			for action in actions do
				preferred(action)
			end
		elseif property == "Parent" and hasChildren then
			for action in actions do
				if action:IsDescendantOf(object) then
					preferred(action)
				end
			end
		end
		if property == "Type" and object:IsA "InputAction" then
			local current = state(object)
			current.value = defaults[current.kind]
			environment.fire(object, "StateChanged", current.value)
		elseif property == "Enabled" and object.Enabled == false then
			if object:IsA "InputAction" then
				reset(object)
			elseif object:IsA "InputContext" then
				for action in pairs(states) do
					if action:FindFirstAncestorWhichIsA "InputContext" == object then
						reset(action)
					end
				end
			end
		elseif property == "Parent" then
			if states[object] ~= nil then
				reset(object)
			end
			if hasChildren then
				for action in pairs(states) do
					if action ~= object and action:IsDescendantOf(object) then
						reset(action)
					end
				end
			end
		end
	end
	local function released(action: Instance)
		states[action] = nil
		actions[action] = nil
		owners[action] = nil
		destroying[action] = nil
	end
	return {
		changed = changed,
		destroying = function(object: Instance)
			if object:IsA "InputAction" then
				destroying[object] = true
				return
			elseif #environment.childrenOf(object) == 0 then
				return
			end
			for action in actions do
				if action == object or action:IsDescendantOf(object) then
					destroying[action] = true
				end
			end
		end,
		released = released,
	}
end

return { attach = attach }
