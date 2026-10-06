--!strict

local Environment = require "./environment"

type Instance = Environment.Instance
export type Options = {
	measureText: ((text: string, size: number, font: unknown, bounds: unknown) -> unknown)?,
	measureBounds: ((parameters: unknown) -> unknown)?,
	methods: { [string]: Environment.Method }?,
	validate: (((className: string, property: string) -> boolean) | false)?,
	selection: ("raise" | "ignore")?,
	requirePlayerGui: boolean?,
}
export type Rejection = { target: Instance, reason: string }
export type Controller = {
	focused: () -> Instance?,
	rejectedSelections: () -> { Rejection },
	close: () -> (),
}
export type Selection = {
	validate: (className: string, property: string, value: unknown, operation: "set" | "poke") -> boolean?,
	rejected: { Rejection },
}

local classes = (
	{
		Instance = { methods = { GetStyled = true, GetStyledPropertyChangedSignal = true } },
		TextBox = {
			super = "GuiObject",
			properties = { Text = "", ClearTextOnFocus = true },
			events = { "Focused", "FocusLost" },
			methods = { CaptureFocus = true, ReleaseFocus = true, IsFocused = true },
		},
		UserInputService = { super = "Instance", creatable = true, methods = { GetFocusedTextBox = true } },
		GuiService = { super = "Instance", creatable = true, properties = { SelectedObject = false } },
		TextService = {
			super = "Instance",
			creatable = true,
			methods = { GetTextSize = true, GetTextBoundsAsync = true },
		},
		StyleRule = {
			super = "Instance",
			properties = { Selector = "", Priority = 0 },
			methods = {
				GetProperties = true,
				SetProperties = true,
				GetProperty = true,
				SetProperty = true,
				GetPropertyTransitions = true,
				SetPropertyTransitions = true,
				SetPropertyTransition = true,
				GetDefaultPropertyTransition = true,
				SetDefaultPropertyTransition = true,
			},
		},
		StyleSheet = { super = "Instance", methods = { GetDerives = true, SetDerives = true } },
		VideoFrame = {
			super = "GuiObject",
			properties = { Playing = false, TimePosition = 0 },
			events = { "Played", "Paused" },
			methods = { Play = true, Pause = true },
		},
		Path2D = {
			super = "Instance",
			events = { "ControlPointChanged" },
			methods = {
				GetControlPoints = true,
				SetControlPoints = true,
				GetControlPoint = true,
				InsertControlPoint = true,
				RemoveControlPoint = true,
				UpdateControlPoint = true,
				GetLength = true,
				GetPositionOnCurve = true,
				GetPositionOnCurveArcLength = true,
				GetTangentOnCurve = true,
				GetTangentOnCurveArcLength = true,
				GetBoundingRect = true,
				GetMaxControlPoints = true,
			},
		},
		UIPageLayout = {
			super = "Instance",
			properties = { CurrentPage = false, Animated = false },
			events = { "PageEnter", "PageLeave", "Stopped" },
			methods = { JumpTo = true, JumpToIndex = true, Next = true, Previous = true },
		},
	} :: unknown
) :: { [string]: Environment.ClassSpec }

local function visible(object: Instance): boolean
	local current: Instance? = object
	while current do
		if current:IsA "GuiObject" and current.Visible == false then
			return false
		end
		if current:IsA "ScreenGui" and current.Enabled == false then
			return false
		end
		current = current.Parent
	end
	return true
end

local function selection(options: Options?): Selection
	local settings: Options = options or {}
	local ignoring = settings.selection == "ignore"
	assert(
		settings.selection == nil or settings.selection == "raise" or ignoring,
		'selection must be "raise" or "ignore"'
	)
	local rejected: { Rejection } = {}
	local function validate(_className: string, property: string, value: unknown, _operation: "set" | "poke"): boolean?
		if property ~= "SelectedObject" or value == nil then
			return nil
		end
		assert(Environment.isInstance(value), "SelectedObject requires a simulated instance")
		local object = value :: Instance
		assert(object:IsA "GuiObject", "SelectedObject requires a GuiObject")
		if settings.requirePlayerGui == true then
			assert(
				object:FindFirstAncestorWhichIsA "PlayerGui" ~= nil,
				"SelectedObject requires a descendant of a PlayerGui"
			)
		end
		local reason: string? = nil
		if not visible(object) then
			reason = "SelectedObject cannot select a hidden control"
		else
			local ok, selectable = pcall(function(): unknown
				return object.Selectable
			end)
			if ok and selectable == false then
				reason = "SelectedObject requires a selectable control"
			end
		end
		if reason == nil then
			return nil
		end
		assert(ignoring, reason)
		table.insert(rejected, { target = object, reason = reason })
		return false
	end
	return { validate = validate, rejected = rejected }
end

local function validateProperty(className: string, property: string, value: unknown, operation: "set" | "poke")
	selection(nil).validate(className, property, value, operation)
end

local function attach(env: Environment.Environment, options: Options?, rule: Selection?): Controller
	local settings: Options = options or {}
	local selected = rule or selection(options)
	local focused: Instance? = nil
	local focusConnection: Environment.Connection? = nil
	local function release(enterPressed: boolean?)
		local previous = focused
		focused = nil
		if focusConnection then
			focusConnection:Disconnect()
			focusConnection = nil
		end
		if previous and env.isAlive(previous) then
			env.fire(previous, "FocusLost", enterPressed == true, nil)
		end
	end
	env.fake("TextBox.CaptureFocus", function(object: Instance)
		assert(env.isAlive(object) and visible(object), "cannot focus a destroyed or hidden TextBox")
		if focused == object then
			return
		end
		release(false)
		focused = object
		focusConnection = object.Destroying:Connect(function()
			release(false)
		end)
		if object.ClearTextOnFocus == true then
			object.Text = ""
		end
		env.fire(object, "Focused")
	end)
	env.fake("TextBox.ReleaseFocus", function(object: Instance, enterPressed: boolean?)
		if focused == object then
			release(enterPressed)
		end
	end)
	env.fake("TextBox.IsFocused", function(object: Instance): boolean
		return focused == object
	end)
	env.fake("UserInputService.GetFocusedTextBox", function(_object: Instance): Instance?
		return focused
	end)
	if settings.measureText then
		local measure = settings.measureText
		env.fake(
			"TextService.GetTextSize",
			function(_object: Instance, text: string, size: number, font: unknown, bounds: unknown): unknown
				return measure(text, size, font, bounds)
			end
		)
	end
	if settings.measureBounds then
		local measure = settings.measureBounds
		env.fake("TextService.GetTextBoundsAsync", function(_object: Instance, parameters: unknown): unknown
			return measure(parameters)
		end)
	end
	local properties = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: { [string]: unknown } }
	local transitions = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: { [string]: unknown } }
	local defaults = setmetatable({} :: { [Instance]: unknown }, { __mode = "k" })
	local derives = setmetatable({} :: { [Instance]: { Instance } }, { __mode = "k" })
	local function mapMethods(
		prefix: string,
		store: { [Instance]: { [string]: unknown } },
		getter: string,
		setter: string
	)
		env.fake(prefix .. "." .. getter, function(object: Instance): { [string]: unknown }
			return table.clone(store[object] or {})
		end)
		env.fake(prefix .. "." .. setter, function(object: Instance, values: { [string]: unknown })
			store[object] = table.clone(values)
		end)
	end
	mapMethods("StyleRule", properties, "GetProperties", "SetProperties")
	mapMethods("StyleRule", transitions, "GetPropertyTransitions", "SetPropertyTransitions")
	env.fake("StyleRule.GetProperty", function(object: Instance, name: string): unknown
		return (properties[object] or {})[name]
	end)
	local function setValue(
		store: { [Instance]: { [string]: unknown } },
		object: Instance,
		name: string,
		value: unknown
	)
		local values = store[object] or {}
		store[object] = values
		values[name] = value
	end
	env.fake("StyleRule.SetProperty", function(object: Instance, name: string, value: unknown)
		setValue(properties, object, name, value)
	end)
	env.fake("StyleRule.SetPropertyTransition", function(object: Instance, name: string, value: unknown)
		setValue(transitions, object, name, value)
	end)
	env.fake("StyleRule.GetDefaultPropertyTransition", function(object: Instance): unknown
		return defaults[object]
	end)
	env.fake("StyleRule.SetDefaultPropertyTransition", function(object: Instance, value: unknown)
		defaults[object] = value
	end)
	env.fake("StyleSheet.GetDerives", function(object: Instance): { Instance }
		return table.clone(derives[object] or {})
	end)
	env.fake("StyleSheet.SetDerives", function(object: Instance, values: { Instance })
		for _, value in values do
			assert(value:IsA "StyleSheet", "SetDerives requires StyleSheets")
		end
		derives[object] = table.clone(values)
	end)
	env.fake("VideoFrame.Play", function(object: Instance)
		env.poke(object, "Playing", true)
		env.fire(object, "Played", env.propertyOf(object, "Video"))
	end)
	env.fake("VideoFrame.Pause", function(object: Instance)
		env.poke(object, "Playing", false)
		env.fire(object, "Paused", env.propertyOf(object, "Video"))
	end)
	local points = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: { unknown } }
	env.fake("Path2D.SetControlPoints", function(object: Instance, values: { unknown })
		points[object] = table.clone(values)
		env.fire(object, "ControlPointChanged")
	end)
	env.fake("Path2D.GetControlPoints", function(object: Instance): { unknown }
		return table.clone(points[object] or {})
	end)
	env.fake("UIPageLayout.JumpTo", function(object: Instance, page: Instance)
		assert(object.Animated ~= true, "animated page transitions require an explicit fake")
		assert(
			page:IsA "GuiObject" and page.Parent ~= nil and page.Parent == object.Parent and visible(page),
			"page must be a visible GuiObject sibling"
		)
		local previous = env.propertyOf(object, "CurrentPage")
		if previous == page then
			return
		end
		env.poke(object, "CurrentPage", page)
		if Environment.isInstance(previous) then
			env.fire(object, "PageLeave", previous)
		end
		env.fire(object, "PageEnter", page)
	end)
	env.onClone(function(source: Instance, copy: Instance, remap: (Instance) -> Instance)
		local function copyTable(store: { [Instance]: { [string]: unknown } })
			if store[source] ~= nil then
				store[copy] = table.clone(store[source])
			end
		end
		copyTable(properties)
		copyTable(transitions)
		if defaults[source] ~= nil then
			defaults[copy] = defaults[source]
		end
		local derived = derives[source]
		if derived ~= nil then
			local mapped: { Instance } = {}
			for _, value in derived do
				table.insert(mapped, remap(value))
			end
			derives[copy] = mapped
		end
		if points[source] ~= nil then
			points[copy] = table.clone(points[source])
		end
	end)
	env.fake("Instance.GetStyled", function(object: Instance, property: string): unknown
		return object[property]
	end)
	env.fake("Instance.GetStyledPropertyChangedSignal", function(object: Instance, property: string): unknown
		return object:GetPropertyChangedSignal(property)
	end)
	local methods: { [string]: Environment.Method } = settings.methods or {}
	for member, handler in methods do
		env.fake(member, handler)
	end
	return {
		focused = function(): Instance?
			return focused
		end,
		rejectedSelections = function(): { Rejection }
			return table.clone(selected.rejected)
		end,
		close = function()
			release(false)
		end,
	}
end

return { classes = classes, attach = attach, selection = selection, validateProperty = validateProperty }
