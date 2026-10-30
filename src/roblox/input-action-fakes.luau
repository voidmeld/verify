--!strict

local Environment = require "./environment-types"
local Datatypes = require "./datatypes"

type Instance = Environment.Instance
type State = { kind: string, value: unknown }
export type Controller = { changed: (Instance, string) -> () }

local function attach(environment: Environment.Environment)
	local states: { [Instance]: State } = {}
	setmetatable(states, { __mode = "k" })
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
	local function changed(object: Instance, property: string)
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
			for action in pairs(states) do
				if action == object or action:IsDescendantOf(object) then
					reset(action)
				end
			end
		end
	end
	return { changed = changed }
end

return { attach = attach }
