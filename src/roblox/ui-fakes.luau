--!strict

local Environment = require "./environment"
local Values = require "./ui-values"
local Style = require "./ui-style"
local Enum = require "./datatypes/enum"
local Datatypes = require "./datatypes"

type Instance = Environment.Instance
local function weaken<V>(values: { [Instance]: V })
	setmetatable(values, { __mode = "k" })
end

export type Options = {
	measureText: (((text: string, size: number, font: Enum.EnumItem, bounds: Values.Vector) -> unknown) | false)?,
	measureBounds: (((parameters: Values.TextParameters, unwrappedWidth: number?) -> unknown) | false)?,
	measureLineHeight: ((Values.TextParameters, number, number) -> number)?,
	truncateBounds: ((parameters: Values.TextParameters, mode: string, lines: number, wrapped: boolean) -> number?)?,
	methods: { [string]: Environment.Method }?,
	validate: (((className: string, property: string) -> boolean) | false)?,
	selection: ("raise" | "ignore" | "native")?,
	requirePlayerGui: boolean?,
}
export type Rejection = { target: Instance, reason: string }
export type Controller = {
	focused: () -> Instance?,
	styled: (Instance, string) -> unknown,
	component: (Instance, string, string) -> unknown,
	step: () -> (),
	cached: (() -> ()) -> (),
	rejectedSelections: () -> { Rejection },
	close: () -> (),
}
export type Selection = {
	validate: (className: string, property: string, value: unknown, operation: "set" | "poke") -> boolean?,
	rejected: { Rejection },
}

local instanceMethods: { [string]: unknown } = { GetStyled = true, GetStyledPropertyChangedSignal = true }
local textBoxProperties: { [string]: unknown } = { Text = "", ClearTextOnFocus = true }
local textBoxMethods: { [string]: unknown } = { CaptureFocus = true, ReleaseFocus = true, IsFocused = true }
local userInputServiceMethods: { [string]: unknown } = { GetFocusedTextBox = true }
local guiServiceProperties: { [string]: unknown } = { SelectedObject = false }
local guiServiceMethods: { [string]: unknown } = { GetGuiInset = true }
local textServiceMethods: { [string]: unknown } = { GetTextSize = true, GetTextBoundsAsync = true }
local styleRuleProperties: { [string]: unknown } = { Selector = "", Priority = 0 }
local styleRuleMethods: { [string]: unknown } = {
	GetProperties = true,
	SetProperties = true,
	GetProperty = true,
	SetProperty = true,
	GetPropertyTransitions = true,
	SetPropertyTransitions = true,
	SetPropertyTransition = true,
	GetDefaultPropertyTransition = true,
	SetDefaultPropertyTransition = true,
}
local styleLinkProperties: { [string]: unknown } = { StyleSheet = false }
local styleSheetMethods: { [string]: unknown } = { GetDerives = true, SetDerives = true }
local videoFrameProperties: { [string]: unknown } = { Playing = false, TimePosition = 0 }
local videoFrameMethods: { [string]: unknown } = { Play = true, Pause = true }
local path2DMethods: { [string]: unknown } = {
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
}
local uiPageLayoutProperties: { [string]: unknown } = { CurrentPage = false, Animated = false }
local uiPageLayoutMethods: { [string]: unknown } = { JumpTo = true, JumpToIndex = true, Next = true, Previous = true }

local classes: { [string]: Environment.ClassSpec } = {
	Instance = { methods = instanceMethods },
	TextBox = {
		super = "GuiObject",
		properties = textBoxProperties,
		events = { "Focused", "FocusLost" },
		methods = textBoxMethods,
	},
	UserInputService = { super = "Instance", creatable = true, methods = userInputServiceMethods },
	GuiService = {
		super = "Instance",
		creatable = true,
		properties = guiServiceProperties,
		methods = guiServiceMethods,
	},
	TextService = {
		super = "Instance",
		creatable = true,
		methods = textServiceMethods,
	},
	StyleRule = {
		super = "Instance",
		properties = styleRuleProperties,
		methods = styleRuleMethods,
	},
	StyleLink = { super = "Instance", properties = styleLinkProperties },
	StyleSheet = { super = "Instance", methods = styleSheetMethods },
	VideoFrame = {
		super = "GuiObject",
		properties = videoFrameProperties,
		events = { "Played", "Paused" },
		methods = videoFrameMethods,
	},
	Path2D = {
		super = "Instance",
		events = { "ControlPointChanged" },
		methods = path2DMethods,
	},
	UIPageLayout = {
		super = "Instance",
		properties = uiPageLayoutProperties,
		events = { "PageEnter", "PageLeave", "Stopped" },
		methods = uiPageLayoutMethods,
	},
}

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
	local native = settings.selection == "native"
	assert(
		settings.selection == nil or settings.selection == "raise" or ignoring or native,
		'selection must be "raise", "ignore" or "native"'
	)
	local rejected: { Rejection } = {}
	local function validate(_className: string, property: string, value: unknown, _operation: "set" | "poke"): boolean?
		if property ~= "SelectedObject" or value == nil then
			return nil
		end
		assert(Environment.isInstance(value), "SelectedObject requires a simulated instance")
		local object = Environment.assertInstance(value)
		assert(object:IsA "GuiObject", "SelectedObject requires a GuiObject")
		if native or settings.requirePlayerGui == true then
			assert(
				object:FindFirstAncestorWhichIsA "PlayerGui" ~= nil,
				"SelectedObject requires a descendant of a PlayerGui"
			)
		end
		if native then
			return nil
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
	local function focusEvent(object: Instance, event: string)
		local root = object:FindFirstAncestorWhichIsA "DataModel"
		local input = if root then root:FindFirstChildOfClass "UserInputService" else nil
		if input then
			env.fire(input, event, object)
		end
	end
	local function release(enterPressed: boolean?, cause: Instance?, transfer: boolean?)
		local previous = focused
		if not transfer then
			focused = nil
		end
		if focusConnection then
			focusConnection:Disconnect()
			focusConnection = nil
		end
		if previous and env.isAlive(previous) then
			env.fire(previous, "FocusLost", enterPressed == true, cause)
			if not transfer then
				focusEvent(previous, "TextBoxFocusReleased")
			end
		end
	end
	env.fake("TextBox.CaptureFocus", function(object: Instance)
		assert(env.isAlive(object) and visible(object), "cannot focus a destroyed or hidden TextBox")
		if focused == object then
			return
		end
		release(false, nil, true)
		focused = object
		focusConnection = object.Destroying:Connect(function()
			release(false)
		end)
		if object.ClearTextOnFocus == true then
			object.Text = ""
		end
		local text = tostring(object.Text)
		pcall(env.poke, object, "CursorPosition", (utf8.len(text) or #text) + 1)
		env.fire(object, "Focused")
		focusEvent(object, "TextBoxFocused")
	end)
	env.fake("TextBox.ReleaseFocus", function(object: Instance, enterPressed: boolean?, cause: Instance?)
		if focused == object then
			release(enterPressed, cause)
		end
	end)
	env.fake("TextBox.IsFocused", function(object: Instance): boolean
		return focused == object
	end)
	env.fake("ScrollingFrame.GetScrollVelocity", function(_object: Instance): Datatypes.Vector2Value
		return Datatypes.Vector2.zero
	end)
	env.fake("ScrollingFrame.ResetScrollVelocity", function(_object: Instance) end)
	env.fake("UserInputService.GetFocusedTextBox", function(_object: Instance): Instance?
		return focused
	end)
	if settings.measureText then
		local measure = settings.measureText
		env.fake(
			"TextService.GetTextSize",
			function(_object: Instance, text: string, size: number, font: Enum.EnumItem, bounds: Values.Vector): unknown
				return measure(text, size, font, bounds)
			end
		)
	end
	if settings.measureBounds then
		local measure = settings.measureBounds
		env.fake(
			"TextService.GetTextBoundsAsync",
			function(_object: Instance, parameters: Values.TextParameters): unknown
				return measure(parameters)
			end
		)
	end
	local invalidateStyle: () -> () = function() end
	local properties: Style.Properties = {}
	local transitions: Style.Properties = {}
	local derives: { [Instance]: { Instance } } = {}
	weaken(properties)
	weaken(transitions)
	weaken(derives)
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
			invalidateStyle()
			store[object] = table.clone(values)
			invalidateStyle()
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
		invalidateStyle()
		local values = store[object] or {}
		store[object] = values
		values[name] = value
		invalidateStyle()
	end
	env.fake("StyleRule.SetProperty", function(object: Instance, name: string, value: unknown)
		setValue(properties, object, name, value)
	end)
	env.fake("StyleRule.SetPropertyTransition", function(object: Instance, name: string, value: unknown)
		setValue(transitions, object, name, value)
	end)
	env.fake("StyleRule.GetDefaultPropertyTransition", function(object: Instance): unknown
		return (transitions[object] or {})["*"]
	end)
	env.fake("StyleRule.SetDefaultPropertyTransition", function(object: Instance, value: unknown)
		setValue(transitions, object, "*", value)
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
	local points: { [Instance]: { unknown } } = {}
	setmetatable(points, { __mode = "k" })
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
	local style = Style.create(env, properties, transitions, derives)
	invalidateStyle = style.invalidate
	env.fake("Instance.GetStyled", function(object: Instance, property: string, selector: unknown): unknown
		if selector == nil then
			return style.styled(object, property)
		end
		assert(type(selector) == "string", "GetStyled selector requires a string")
		return style.styled(object, property, selector)
	end)
	env.fake("Instance.GetStyledPropertyChangedSignal", style.signal)
	local methods: { [string]: Environment.Method } = settings.methods or {}
	for member, handler in methods do
		env.fake(member, handler)
	end
	return {
		styled = style.styled,
		component = style.component,
		step = style.step,
		cached = style.cached,
		focused = function(): Instance?
			return focused
		end,
		rejectedSelections = function(): { Rejection }
			return table.clone(selected.rejected)
		end,
		close = function()
			release(false)
			style.close()
		end,
	}
end

return { classes = classes, attach = attach, selection = selection, validateProperty = validateProperty }
