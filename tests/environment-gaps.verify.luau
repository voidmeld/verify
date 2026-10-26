--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local function asString(value: unknown): string
	assert(type(value) == "string")
	return value
end

local Fixture = require "./reflection-fixture"

local Bridge = require "../src/roblox/fixture-bridge"
local Datatypes = require "../src/roblox/datatypes"
local Environment = require "../src/roblox/environment"
local Reflection = require "../src/roblox/reflection"
local UiFakes = require "../src/roblox/ui-fakes"

local function thrown(callback: () -> ...unknown): string
	local ok, message = pcall(callback)
	assert(not ok, "expected the call to raise")
	return tostring(message)
end

local function succeeds(callback: () -> ...unknown): boolean
	return (pcall(callback))
end

local property, class = Fixture.property, Fixture.class

local function database(): Reflection.Database
	local classes: { [string]: Reflection.Class } = {
		Instance = class("Instance", nil, { property("Name", "String") }, { "NotCreatable" }),
		Folder = class("Folder", "Instance"),
		PlayerGui = class("PlayerGui", "Instance"),
		GuiObject = class(
			"GuiObject",
			"Instance",
			{ property("Visible", "Bool"), property("Selectable", "Bool") },
			{ "NotCreatable" }
		),
		Frame = class("Frame", "GuiObject"),
		TextLabel = class("TextLabel", "GuiObject", {
			property("Text", "String"),
			property("TextBounds", "Vector2"),
			{ Name = "TextFits", Datatype = "Bool", Scriptability = "Read", Tags = { "ReadOnly" } },
			property("Mass", "float"),
		}),
		GuiService = class("GuiService", "Instance", { property("SelectedObject", "Ref") }, { "Service" }),
	}
	classes.GuiObject.DefaultProperties.Visible = true
	classes.GuiObject.DefaultProperties.Selectable = true
	classes.TextLabel.DefaultProperties.Text = "Label"
	return Fixture.database(classes)
end

type Extra = {
	defaultProperty: ((className: string, property: string) -> unknown)?,
	handlerErrors: Environment.HandlerErrors?,
	computed: { [string]: Environment.Computed }?,
	undeclaredWrites: boolean?,
	functionDoubles: boolean?,
	ui: UiFakes.Options?,
}

local function bridge(extra: Extra?): Bridge.Bridge
	local settings: Extra = extra or {}
	return Bridge.create {
		database = database(),
		typeName = Environment.typeName,
		enumType = Datatypes.enumType,
		defaultProperty = settings.defaultProperty,
		handlerErrors = settings.handlerErrors,
		computed = settings.computed,
		undeclaredWrites = settings.undeclaredWrites,
		functionDoubles = settings.functionDoubles,
		ui = settings.ui,
	}
end

local function plain(options: Environment.Options?): Environment.Environment
	local settings: Environment.Options = options or {}
	local properties: { [string]: unknown } = { Count = 0 }
	local widget: Environment.ClassSpec = { super = "Instance", properties = properties, events = { "Pinged" } }
	settings.classes = { Widget = widget }
	return Environment.create(settings)
end

local function getters(entries: { [string]: Environment.Computed }): { [string]: Environment.Computed }
	return entries
end

local function pinged(object: Environment.Instance): Environment.Signal<()>
	return object.Pinged :: Environment.Signal<()>
end

local function raisingHandler(): () -> ()
	return function()
		error("handler failed", 0)
	end
end

describe("member access", function()
	it("callback members stay write-only before and after assignment with permissive doubles", function()
		local env = Environment.create { functionDoubles = true, undeclaredWrites = true, undeclaredReads = "nil" }
		local callbacks: { [string]: { string } } = {
			RemoteFunction = { "OnServerInvoke", "OnClientInvoke" },
			BindableFunction = { "OnInvoke" },
			TextChannel = { "ShouldDeliverCallback" },
		}
		for className, members in callbacks do
			local object = env.createInstance(className)
			for _, member in members do
				local expected = member
					.. " is a callback member of "
					.. className
					.. "; you can only set the callback value, get is not available"
				for _, assigned in { false, true } do
					if assigned then
						object[member] = function() end
					end
					expect(string.find(
						thrown(function()
							return object[member]
						end),
						expected,
						1,
						true
					) ~= nil):toBe(true)
				end
				expect(succeeds(function()
					object[member] = nil
				end)):toBe(true)
				local assignedValues: { unknown } = { true, 1, "value", {} }
				for _, value in assignedValues do
					object[member] = value
					expect(env.propertyOf(object, member) == value):toBe(true)
					expect(succeeds(function()
						return object[member]
					end)):toBe(false)
				end
			end
		end
	end)
end)
describe("handler errors", function()
	it("collect is the default and keeps the errors", function()
		local env = plain()
		local widget = env.createInstance "Widget"
		widget:GetPropertyChangedSignal("Count"):Connect(raisingHandler())
		widget.Count = 1
		expect(widget.Count):toBe(1)
		expect(#env.errors):toBe(1)
	end)

	it("raise rethrows after each kind of operation and clears the list", function()
		local env = plain { handlerErrors = "raise" }
		local widget = env.createInstance "Widget"
		local other = env.createInstance "Widget"
		widget:GetPropertyChangedSignal("Count"):Connect(raisingHandler())
		widget:GetPropertyChangedSignal("Parent"):Connect(raisingHandler())
		widget:GetAttributeChangedSignal("Mark"):Connect(raisingHandler())
		pinged(widget):Connect(raisingHandler())
		expect(thrown(function()
			widget.Count = 1
		end)):toBe "handler failed"
		expect(widget.Count):toBe(1)
		expect(#env.errors):toBe(0)
		expect(thrown(function()
			widget.Parent = env.root
		end)):toBe "handler failed"
		expect(widget.Parent == env.root):toBe(true)
		expect(thrown(function()
			widget:SetAttribute("Mark", 1)
		end)):toBe "handler failed"
		expect(thrown(function()
			env.poke(widget, "Count", 2)
		end)):toBe "handler failed"
		expect(thrown(function()
			env.fire(widget, "Pinged")
		end)):toBe "handler failed"
		expect(thrown(function()
			pinged(widget):Fire()
		end)):toBe "handler failed"
		widget:GetAttributeChangedSignal("Other"):Connect(raisingHandler())
		expect(thrown(function()
			widget:SetAttribute("Other", 1)
		end)):toBe "handler failed"
		expect(succeeds(function()
			other.Count = 3
		end)):toBe(true)
	end)

	it("raise joins every handler message and still runs every handler", function()
		local env = plain { handlerErrors = "raise" }
		local widget = env.createInstance "Widget"
		local ran = 0
		local signal = widget:GetPropertyChangedSignal "Count"
		signal:Connect(function()
			ran += 1
			error("first", 0)
		end)
		signal:Connect(function()
			ran += 1
			error("second", 0)
		end)
		expect(thrown(function()
			widget.Count = 1
		end)):toBe "first\nsecond"
		expect(ran):toBe(2)
	end)

	it("raise reports a method that fires through a signal and nested writes once", function()
		local env = plain { handlerErrors = "raise" }
		local widget = env.createInstance "Widget"
		local child = env.createInstance("Widget", { Parent = widget })
		child.Destroying:Connect(raisingHandler())
		widget:GetPropertyChangedSignal("Count"):Connect(function()
			child.Count = 9
		end)
		child:GetPropertyChangedSignal("Count"):Connect(raisingHandler())
		expect(thrown(function()
			widget.Count = 1
		end)):toBe "handler failed"
		expect(thrown(function()
			child:Destroy()
		end)):toBe "handler failed"
		local heartbeat = env.heartbeat
		heartbeat:Connect(raisingHandler())
		expect(thrown(function()
			env.step(0.1)
		end)):toBe "handler failed"
	end)

	it("an operation error wins and an invalid mode is refused", function()
		local env = plain { handlerErrors = "raise" }
		local widget = env.createInstance "Widget"
		expect(thrown(function()
			widget.Missing = 1
		end)):toContain "is not a valid member"
		expect(thrown(function()
			plain { handlerErrors = ("ignore" :: unknown) :: "raise" }
		end)):toContain "handlerErrors"
	end)

	it("the bridge passes the mode through", function()
		local built = bridge { handlerErrors = "raise" }
		local frame = built.environment.createInstance "Frame"
		frame:GetPropertyChangedSignal("Visible"):Connect(raisingHandler())
		expect(thrown(function()
			frame.Visible = false
		end)):toBe "handler failed"
	end)
end)

describe("connection counts for any signal", function()
	it("counts property, attribute, heartbeat and new signals", function()
		local env = plain()
		local widget = env.createInstance "Widget"
		local changed = widget:GetPropertyChangedSignal "Count"
		local attribute = widget:GetAttributeChangedSignal "Mark"
		local own = env.newSignal()
		expect(env.connectionsOf(changed)):toBe(0)
		local connection = changed:Connect(function() end)
		attribute:Connect(function() end)
		own:Connect(function() end)
		env.heartbeat:Connect(function() end)
		expect(env.connectionsOf(changed)):toBe(1)
		expect(env.connectionsOf(attribute)):toBe(1)
		expect(env.connectionsOf(own)):toBe(1)
		expect(env.connectionsOf((env.heartbeat :: unknown) :: Environment.Signal)):toBe(1)
		widget.Count = 1
		widget.Count = 2
		expect(env.firesOf(changed)):toBe(2)
		own:Fire()
		expect(env.firesOf(own)):toBe(1)
		env.step(1)
		expect(env.firesOf((env.heartbeat :: unknown) :: Environment.Signal)):toBe(1)
		connection:Disconnect()
		expect(env.connectionsOf(changed)):toBe(0)
	end)

	it("totals the connections of one instance and drops them on destroy", function()
		local env = plain()
		local widget = env.createInstance "Widget"
		local bystander = env.createInstance "Widget"
		expect(env.connectionsOfInstance(widget)):toBe(0)
		pinged(widget):Connect(function() end)
		widget.Changed:Connect(function() end)
		widget:GetPropertyChangedSignal("Count"):Connect(function() end)
		widget:GetAttributeChangedSignal("Mark"):Connect(function() end)
		pinged(bystander):Connect(function() end)
		expect(env.connectionsOfInstance(widget)):toBe(4)
		expect(env.connectionsOfInstance(bystander)):toBe(1)
		widget:Destroy()
		expect(env.connectionsOfInstance(widget)):toBe(0)
	end)

	it("refuses a signal that the environment did not make", function()
		local env = plain()
		local foreign = plain().newSignal()
		expect(thrown(function()
			return env.connectionsOf(foreign)
		end)):toContain "not created by this environment"
		expect(thrown(function()
			return env.firesOf(({}) :: Environment.Signal)
		end)):toContain "not created by this environment"
	end)
end)

describe("per-instance method doubles", function()
	it("fakeOn installs an undeclared member for one instance with the instance as self", function()
		local env = plain()
		local first = env.createInstance "Widget"
		local second = env.createInstance "Widget"
		local seen: { unknown } = {}
		env.fakeOn(first, "IsKeyDown", function(self: Environment.Instance, key: string): boolean
			table.insert(seen, self)
			return key == "A"
		end)
		local call = first.IsKeyDown :: (Environment.Instance, string) -> boolean
		expect(call(first, "A")):toBe(true)
		expect(call(first, "B")):toBe(false)
		expect(seen[1] == first):toBe(true)
		expect(thrown(function()
			return second.IsKeyDown
		end)):toContain "is not a valid member"
		env.fakeOn(first, "IsKeyDown", function(): boolean
			return false
		end)
		expect((first.IsKeyDown :: (Environment.Instance, string) -> boolean)(first, "A")):toBe(false)
	end)

	it("fakeOn refuses a property, an event and Parent", function()
		local env = plain()
		local widget = env.createInstance "Widget"
		for _, name in { "Count", "Pinged", "Parent", "ClassName" } do
			expect(thrown(function()
				env.fakeOn(widget, name, function() end)
			end)):toContain "cannot be a method double"
		end
	end)

	it("assigning a function is refused unless functionDoubles is on", function()
		local strict = plain()
		local widget = strict.createInstance "Widget"
		expect(thrown(function()
			widget.GetGuiInset = function() end
		end)):toContain "is not a valid member"
	end)

	it("assigning a function installs a replaceable double when functionDoubles is on", function()
		local env = plain { functionDoubles = true }
		local widget = env.createInstance "Widget"
		local other = env.createInstance "Widget"
		widget.GetFocusedTextBox = function(self: Environment.Instance): unknown
			return self
		end
		expect((widget.GetFocusedTextBox :: (Environment.Instance) -> unknown)(widget) == widget):toBe(true)
		widget.GetFocusedTextBox = function(): unknown
			return "second"
		end
		expect((widget.GetFocusedTextBox :: (Environment.Instance) -> unknown)(widget)):toBe "second"
		expect(thrown(function()
			return other.GetFocusedTextBox
		end)):toContain "is not a valid member"
		expect(thrown(function()
			widget.Missing = 5
		end)):toContain "is not a valid member"
		expect(thrown(function()
			widget.Pinged = function() end
		end)):toContain "is not a valid member"
	end)

	it("a function written to a declared property still fails validation", function()
		local label = bridge({ functionDoubles = true }).environment.createInstance "TextLabel"
		expect(thrown(function()
			label.Text = function() end
		end)):toContain "requires"
	end)

	it("a double does not survive Clone", function()
		local env = plain()
		local widget = env.createInstance "Widget"
		env.fakeOn(widget, "Probe", function(): number
			return 1
		end)
		local copy = (widget.Clone :: (Environment.Instance) -> Environment.Instance)(widget)
		expect(thrown(function()
			return copy.Probe
		end)):toContain "is not a valid member"
	end)
end)

describe("rejected selection", function()
	local function ui(selection: unknown, requirePlayerGui: boolean?): Bridge.Bridge
		return bridge { ui = { selection = selection :: "raise" | "ignore"?, requirePlayerGui = requirePlayerGui } }
	end

	it("raise stays the default", function()
		local built = ui(nil)
		local env = built.environment
		local frame = env.createInstance("Frame", { Visible = false })
		local service = env.createEngineInstance "GuiService"
		expect(thrown(function()
			service.SelectedObject = frame
		end)):toContain "hidden"
		expect(service.SelectedObject):toBe(nil)
		local controller = assert(built.ui)
		expect(#controller.rejectedSelections()):toBe(0)
	end)

	it("ignore drops the write silently and records it", function()
		local built = ui "ignore"
		local env = built.environment
		local hidden = env.createInstance("Frame", { Visible = false })
		local shown = env.createInstance("Frame", { Parent = hidden })
		local locked = env.createInstance("Frame", { Selectable = false })
		local open = env.createInstance "Frame"
		local service = env.createEngineInstance "GuiService"
		local fired = 0
		service:GetPropertyChangedSignal("SelectedObject"):Connect(function()
			fired += 1
		end)
		service.SelectedObject = shown
		service.SelectedObject = locked
		expect(service.SelectedObject):toBe(nil)
		expect(fired):toBe(0)
		local controller = assert(built.ui)
		local rejected = controller.rejectedSelections()
		expect(#rejected):toBe(2)
		expect(rejected[1].target == shown):toBe(true)
		expect(rejected[1].reason):toContain "hidden"
		expect(rejected[2].reason):toContain "selectable"
		service.SelectedObject = open
		expect(service.SelectedObject == open):toBe(true)
		expect(fired):toBe(1)
		expect(#controller.rejectedSelections()):toBe(2)
	end)

	it("ignore keeps raising for a value that is not a GuiObject", function()
		local built = ui "ignore"
		local env = built.environment
		local service = env.createEngineInstance "GuiService"
		expect(thrown(function()
			service.SelectedObject = env.createInstance "Folder"
		end)):toContain "GuiObject"
		expect(thrown(function()
			service.SelectedObject = 5
		end)):toContain "requires"
	end)

	it("requirePlayerGui raises outside a PlayerGui in either mode", function()
		for _, mode in { "raise", "ignore" } do
			local built = ui(mode, true)
			local env = built.environment
			local service = env.createEngineInstance "GuiService"
			local loose = env.createInstance "Frame"
			expect(thrown(function()
				service.SelectedObject = loose
			end)):toContain "PlayerGui"
			local gui = env.createInstance "PlayerGui"
			local inside = env.createInstance("Frame", { Parent = gui })
			service.SelectedObject = inside
			expect(service.SelectedObject == inside):toBe(true)
		end
	end)

	it("an invalid selection mode is refused", function()
		expect(thrown(function()
			return ui "drop"
		end)):toContain "selection must be"
	end)

	it("validateProperty returning false vetoes a write silently", function()
		local env = plain {
			validateProperty = function(_className: string, property: string, value: unknown): boolean?
				if property == "Count" and value == 99 then
					return false
				end
				return nil
			end,
		}
		local widget = env.createInstance "Widget"
		local fired = 0
		widget:GetPropertyChangedSignal("Count"):Connect(function()
			fired += 1
		end)
		widget.Count = 99
		expect(widget.Count):toBe(0)
		expect(fired):toBe(0)
		env.poke(widget, "Count", 99)
		expect(widget.Count):toBe(0)
		widget.Count = 3
		expect(widget.Count):toBe(3)
		expect(fired):toBe(1)
	end)

	it("GetStyled raw writes do not fire style notifications", function()
		local built = bridge()
		local label = built.environment.createInstance "TextLabel"
		local styled = label.GetStyled :: (Environment.Instance, string) -> unknown
		local signal = (
			label.GetStyledPropertyChangedSignal :: (Environment.Instance, string) -> Environment.Signal<()>
		)(label, "Text")
		local fired = 0
		signal:Connect(function()
			fired += 1
		end)
		expect(styled(label, "Text")):toBe "Label"
		label.Text = "changed"
		expect(styled(label, "Text")):toBe "changed"
		expect(fired):toBe(0)
		expect(thrown(function()
			return styled(label, "Nope")
		end)):toContain "is not a valid member"
	end)
end)

describe("datatype shells", function()
	it("TweenInfo has readable fields, engine defaults and value equality", function()
		local defaults = Datatypes.TweenInfo.new()
		expect(defaults.Time):toBe(1)
		expect(defaults.EasingStyle == Datatypes.Enum.EasingStyle.Quad):toBe(true)
		expect(defaults.EasingDirection == Datatypes.Enum.EasingDirection.Out):toBe(true)
		expect(defaults.RepeatCount):toBe(0)
		expect(defaults.Reverses):toBe(false)
		expect(defaults.DelayTime):toBe(0)
		local full = Datatypes.TweenInfo.new(
			2,
			Datatypes.Enum.EasingStyle.Linear,
			Datatypes.Enum.EasingDirection.In,
			3,
			true,
			0.5
		)
		expect(full.Time):toBe(2)
		expect(full.RepeatCount):toBe(3)
		expect(full.Reverses):toBe(true)
		expect(full.DelayTime):toBe(0.5)
		expect(Datatypes.TweenInfo.new(1) == defaults):toBe(true)
		expect(Datatypes.TweenInfo.new(2) == defaults):toBe(false)
		expect(Datatypes.typeName(full)):toBe "TweenInfo"
	end)

	it("TweenInfo is an attribute value and its fields survive", function()
		local env = plain()
		local widget = env.createInstance "Widget"
		widget:SetAttribute("Info", Datatypes.TweenInfo.new(4))
		local info = widget:GetAttribute "Info" :: Datatypes.TweenInfoValue
		expect(info.Time):toBe(4)
		expect(thrown(function()
			widget:SetAttribute("Key", Datatypes.FloatCurveKey.new(0, 1, Datatypes.Enum.KeyInterpolationMode.Linear))
		end)):toContain "FloatCurveKey"
	end)

	it("FloatCurveKey has readable fields and value equality", function()
		local linear = Datatypes.Enum.KeyInterpolationMode.Linear
		local key = Datatypes.FloatCurveKey.new(0.5, 2, linear)
		expect(key.Time):toBe(0.5)
		expect(key.Value):toBe(2)
		expect(key.Interpolation == linear):toBe(true)
		expect(key == Datatypes.FloatCurveKey.new(0.5, 2, linear)):toBe(true)
		expect(key == Datatypes.FloatCurveKey.new(0.5, 3, linear)):toBe(false)
		expect(Datatypes.typeName(key)):toBe "FloatCurveKey"
	end)

	it("Path2DControlPoint has readable fields, default tangents and value equality", function()
		local position = Datatypes.UDim2.new(0.5, 1, 0.25, 2)
		local point = Datatypes.Path2DControlPoint.new(position)
		expect(point.Position == position):toBe(true)
		expect(point.LeftTangent == Datatypes.UDim2.new(0, 0, 0, 0)):toBe(true)
		expect(point.RightTangent == Datatypes.UDim2.new(0, 0, 0, 0)):toBe(true)
		local tangent = Datatypes.UDim2.new(0, 3, 0, 4)
		local full = Datatypes.Path2DControlPoint.new(position, tangent, tangent)
		expect(full.LeftTangent.X.Offset):toBe(3)
		expect(full == Datatypes.Path2DControlPoint.new(position, tangent, tangent)):toBe(true)
		expect(full == point):toBe(false)
		expect(Datatypes.typeName(point)):toBe "Path2DControlPoint"
	end)
end)

describe("defaults the database does not store", function()
	it("the hook is consulted when the database has no default", function()
		local asked: { string } = {}
		local built = bridge {
			defaultProperty = function(className: string, property: string): unknown
				table.insert(asked, className .. "." .. property)
				if property == "Mass" then
					return 5
				end
				return nil
			end,
		}
		local label = built.environment.createInstance "TextLabel"
		expect(label.Mass):toBe(5)
		expect(label.Text):toBe "Label"
		expect(label.TextBounds):toBe(nil)
		expect(table.find(asked, "TextLabel.Text")):toBe(nil)
		expect(table.find(asked, "TextLabel.TextBounds") ~= nil):toBe(true)
	end)

	it("without a hook a declaration is never a default", function()
		local label = bridge().environment.createInstance "TextLabel"
		expect(label.Mass):toBe(nil)
	end)

	it("ResetPropertyToDefault restores the stored, hooked or empty default", function()
		local built = bridge {
			defaultProperty = function(_className: string, property: string): unknown
				if property == "Mass" then
					return 5
				end
				return nil
			end,
		}
		local label = built.environment.createInstance "TextLabel"
		local fired = 0
		label:GetPropertyChangedSignal("Mass"):Connect(function()
			fired += 1
		end)
		label.Mass = 9
		label.Text = "x"
		local reset = label.ResetPropertyToDefault
		reset(label, "Mass")
		reset(label, "Text")
		expect(label.Mass):toBe(5)
		expect(label.Text):toBe "Label"
		expect(fired):toBe(2)
		reset(label, "Mass")
		expect(fired):toBe(2)
		label.TextBounds = Datatypes.Vector2.new(1, 1)
		reset(label, "TextBounds")
		expect(label.TextBounds):toBe(nil)
		expect(thrown(function()
			reset(label, "Nope")
		end)):toContain "is not a valid member"
	end)

	it("ResetPropertyToDefault works on a plain environment", function()
		local env = plain()
		local widget = env.createInstance "Widget"
		widget.Count = 4
		(widget.ResetPropertyToDefault)(widget, "Count")
		expect(widget.Count):toBe(0)
	end)
end)

describe("computed property reads", function()
	it("the getter answers the read and tracks the instance", function()
		local built = bridge {
			computed = getters {
				["TextLabel.TextBounds"] = function(object: Environment.Instance): unknown
					return Datatypes.Vector2.new(#(asString(object.Text)) * 8, 16)
				end,
			},
		}
		local label = built.environment.createInstance("TextLabel", { Text = "abc" })
		local bounds = label.TextBounds :: Datatypes.Vector2Value
		expect(bounds.X):toBe(24)
		label.Text = "abcd"
		expect((label.TextBounds :: Datatypes.Vector2Value).X):toBe(32)
		expect(built.environment.createInstance("Frame").Visible):toBe(true)
	end)

	it("a getter on a superclass applies to a subclass and writes are refused", function()
		local env = plain {
			computed = getters {
				["Instance.Depth"] = function(object: Environment.Instance): unknown
					local depth = 0
					local walk = object.Parent
					while walk ~= nil do
						depth += 1
						walk = walk.Parent
					end
					return depth
				end,
			},
		}
		local widget = env.createInstance("Widget", { Parent = env.createInstance "Folder" })
		expect(widget.Depth):toBe(1)
		expect(thrown(function()
			widget.Depth = 3
		end)):toContain "read-only"
		expect(thrown(function()
			env.poke(widget, "Depth", 3)
		end)):toContain "computed"
		expect(succeeds(function()
			widget:GetPropertyChangedSignal "Depth"
		end)):toBe(true)
	end)

	it("clones an instance and its descendants that carry computed properties", function()
		local seen: { Environment.Instance } = {}
		local built = bridge {
			ui = {},
			computed = getters {
				["TextLabel.TextBounds"] = function(object: Environment.Instance): unknown
					table.insert(seen, object)
					return Datatypes.Vector2.new(#(asString(object.Text)) * 8, 16)
				end,
				["TextLabel.TextFits"] = function(_object: Environment.Instance): unknown
					return true
				end,
			},
		}
		local hooked: { Environment.Instance } = {}
		local connection = built.environment.onClone(function(_source: Environment.Instance, copy: Environment.Instance)
			table.insert(hooked, copy)
		end)
		local parent = built.environment.createInstance "Frame"
		local label = built.environment.createInstance("TextLabel", { Text = "abc", Parent = parent })
		expect(label.TextFits):toBe(true)
		local copy = assert(label:Clone())
		expect(copy.TextFits):toBe(true)
		expect((copy.TextBounds :: Datatypes.Vector2Value).X):toBe(24)
		expect(seen[#seen] == copy):toBe(true)
		expect(hooked[1] == copy):toBe(true)
		local tree = assert(parent:Clone())
		local child = tree:GetChildren()[1]
		expect(child ~= label):toBe(true)
		expect(child.TextFits):toBe(true)
		expect((child.TextBounds :: Datatypes.Vector2Value).X):toBe(24)
		expect(seen[#seen] == child):toBe(true)
		expect(#hooked):toBe(3)
		connection:Disconnect()
	end)

	it("a plain computed getter stays read-only for a write and a poke", function()
		local env = plain {
			computed = getters {
				["Widget.Count"] = function(_object: Environment.Instance): unknown
					return 1
				end,
			},
		}
		local widget = env.createInstance "Widget"
		expect(thrown(function()
			widget.Count = 2
		end)):toContain "read-only"
		expect(thrown(function()
			env.poke(widget, "Count", 2)
		end)):toContain "computed"
	end)

	it("a writable computed property stores, notifies, reads and clones", function()
		local answer: unknown = true
		local env = plain {
			computed = getters {
				["Widget.Fits"] = {
					get = function(_object: Environment.Instance): unknown
						return answer
					end,
					writable = true,
				},
			},
		}
		local widget = env.createInstance "Widget"
		local fired = 0
		widget:GetPropertyChangedSignal("Fits"):Connect(function()
			fired += 1
		end)
		widget.Fits = false
		expect(fired):toBe(1)
		expect(widget.Fits):toBe(true)
		expect(env.propertyOf(widget, "Fits")):toBe(false)
		widget.Fits = true
		expect(fired):toBe(2)
		widget.Fits = false
		widget.Fits = true
		expect(fired):toBe(4)
		widget.Fits = true
		expect(fired):toBe(4)
		env.poke(widget, "Fits", 7)
		expect(fired):toBe(5)
		expect(env.propertyOf(widget, "Fits")):toBe(7)
		answer = nil
		expect(widget.Fits):toBe(7)
		local copy = assert(widget:Clone())
		expect(env.propertyOf(copy, "Fits")):toBe(7)
		expect(copy.Fits):toBe(7)
	end)

	it("a class without a getter keeps the unknown read error", function()
		local env = plain {
			computed = getters {
				["Folder.Depth"] = function(_object: Environment.Instance): unknown
					return 1
				end,
			},
		}
		local widget = env.createInstance "Widget"
		expect(thrown(function()
			return widget.Depth
		end)):toContain "is not a valid member"
	end)
end)

describe("undeclared writes", function()
	it("a write to an unknown property is refused by default", function()
		local env = plain()
		local widget = env.createInstance "Widget"
		expect(thrown(function()
			widget.Extra = 1
		end)):toContain "is not a valid member"
		expect(thrown(function()
			env.poke(widget, "Extra", 1)
		end)):toContain "is not a valid member"
	end)

	it("undeclaredReads returns nil for an undeclared member and keeps declared reads", function()
		local relaxed = Environment.create { undeclaredReads = "nil" }
		local parent = relaxed.createInstance("Folder", { Name = "relaxed" })
		local child = relaxed.createInstance("Folder", { Name = "Child", Parent = parent })
		expect(parent.Missing):toBeNil()
		local indexed = (parent :: unknown) :: { [number]: unknown }
		expect(indexed[1]):toBeNil()
		expect(parent.Child):toBe(child)
		expect(parent.Name):toBe "relaxed"
		expect(thrown(function()
			parent.Missing = 1
		end)):toContain "is not a valid member"
		local strict = Environment.create {}
		local folder = strict.createInstance("Folder", { Name = "strict" })
		expect(thrown(function()
			return folder.Missing
		end)):toContain "is not a valid member"
	end)

	it("undeclaredWrites stores, reads, signals and clones the value", function()
		local env = plain { undeclaredWrites = true }
		local widget = env.createInstance "Widget"
		local fired = 0
		widget:GetPropertyChangedSignal("Extra"):Connect(function()
			fired += 1
		end)
		widget.Extra = 1
		expect(widget.Extra):toBe(1)
		expect(fired):toBe(1)
		env.poke(widget, "Extra", 2)
		expect(widget.Extra):toBe(2)
		expect(fired):toBe(2)
		local copy = (widget.Clone :: (Environment.Instance) -> Environment.Instance)(widget)
		expect(copy.Extra):toBe(2)
		expect(thrown(function()
			return widget.NeverWritten
		end)):toContain "is not a valid member"
		expect(thrown(function()
			widget.Pinged = 1
		end)):toContain "is not a valid member"
		expect(thrown(function()
			widget.ClassName = "Other"
		end)):toContain "is not a valid member"
	end)

	it("the bridge keeps validating declared properties when undeclared writes are on", function()
		local built = bridge { undeclaredWrites = true }
		local label = built.environment.createInstance "TextLabel"
		label.Extra = "free"
		expect(label.Extra):toBe "free"
		expect(succeeds(function()
			label.Text = 5
		end)):toBe(false)
	end)
end)

describe("observation identity", function()
	it("events carry the object and the value for each operation", function()
		local env = plain()
		local events: { Environment.Event } = {}
		env.observe(function(event: Environment.Event)
			table.insert(events, event)
		end)
		local first = env.createInstance "Widget"
		local second = env.createInstance "Widget"
		local folder = env.createInstance "Folder"
		first.Count = 1
		first.Count = 2
		second.Count = 5
		first:SetAttribute("mark", "a")
		first:SetAttribute("mark", nil)
		first.Parent = folder
		first:Destroy()
		local writes: { [Environment.Instance]: number } = {}
		for _, event in events do
			expect(event.object ~= nil):toBe(true)
			if event.operation == "setProperty" then
				writes[event.object] = (writes[event.object] or 0) + 1
			end
		end
		expect(writes[first]):toBe(2)
		expect(writes[second]):toBe(1)
		expect(events[1].operation):toBe "create"
		expect(events[1].object == first):toBe(true)
		expect(events[4].member):toBe "Count"
		expect(events[4].value):toBe(1)
		expect(events[7].operation):toBe "setAttribute"
		expect(events[7].value):toBe "a"
		expect(events[8].value):toBe(nil)
		expect(events[9].operation):toBe "setParent"
		expect(events[9].value == folder):toBe(true)
		expect(events[10].operation):toBe "destroy"
		expect(events[10].object == first):toBe(true)
		expect(events[1].subject):toBe "Widget"
	end)

	it("a clone create event carries the copy and an injected failure keeps the object", function()
		local built = bridge()
		local recorder = built.record()
		local label = built.environment.createInstance("TextLabel", { Text = "x" })
		local copy = label:Clone()
		local created: { Environment.Instance } = {}
		for _, event in recorder.events do
			if event.operation == "create" then
				table.insert(created, event.object)
			end
		end
		expect(created[1] == label):toBe(true)
		expect(created[2] == copy):toBe(true)
		built.faults.inject("setProperty", 1)
		expect(succeeds(function()
			label.Text = "y"
		end)):toBe(false)
		local last = recorder.events[#recorder.events]
		expect(last.injected):toBe(true)
		expect(last.object == label):toBe(true)
		expect(last.value):toBe "y"
		recorder.stop()
	end)
end)

return nil
