--!strict

local Bridge = require "../src/roblox/fixture-bridge"
local Datatypes = require "../src/roblox/datatypes"
local Environment = require "../src/roblox/environment"
local Reflection = require "../src/roblox/reflection"
local UiFakes = require "../src/roblox/ui-fakes"
local Verify = require "../src/core"

local function thrown(callback: () -> ...unknown): string
	local ok, message = pcall(callback)
	assert(not ok, "expected the call to raise")
	return tostring(message)
end

local function succeeds(callback: () -> ...unknown): boolean
	return (pcall(callback))
end

local function property(name: string, datatype: string): Reflection.Property
	return { Name = name, Datatype = datatype, Scriptability = "ReadWrite", Tags = {} }
end

local function class(
	name: string,
	super: string?,
	properties: { Reflection.Property }?,
	tags: { string }?
): Reflection.Class
	local declared: { [string]: Reflection.Property } = {}
	for _, item in (properties or {}) :: { Reflection.Property } do
		declared[item.Name] = item
	end
	return { Name = name, Superclass = super, Properties = declared, DefaultProperties = {}, Tags = tags or {} }
end

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
	local names: { string } = {}
	for name in classes do
		table.insert(names, name)
	end
	table.sort(names)
	return {
		GetClassNames = function(): { string }
			return names
		end,
		GetClass = function(_: Reflection.Database, name: string): Reflection.Class?
			return classes[name]
		end,
	}
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
	local widget = { super = "Instance", properties = { Count = 0 }, events = { "Pinged" } }
	settings.classes = { Widget = (widget :: unknown) :: Environment.ClassSpec }
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

return function(suite: Verify.Harness)
	suite:suite("handler errors", function()
		suite:case("collect is the default and keeps the errors", function(check)
			local env = plain()
			local widget = env.createInstance "Widget"
			widget:GetPropertyChangedSignal("Count"):Connect(raisingHandler())
			widget.Count = 1
			check:expect(widget.Count):toBe(1)
			check:expect(#env.errors):toBe(1)
		end)

		suite:case("raise rethrows after each kind of operation and clears the list", function(check)
			local env = plain { handlerErrors = "raise" }
			local widget = env.createInstance "Widget"
			local other = env.createInstance "Widget"
			widget:GetPropertyChangedSignal("Count"):Connect(raisingHandler())
			widget:GetPropertyChangedSignal("Parent"):Connect(raisingHandler())
			widget:GetAttributeChangedSignal("Mark"):Connect(raisingHandler())
			pinged(widget):Connect(raisingHandler())
			check
				:expect(thrown(function()
					widget.Count = 1
				end))
				:toBe "handler failed"
			check:expect(widget.Count):toBe(1)
			check:expect(#env.errors):toBe(0)
			check
				:expect(thrown(function()
					widget.Parent = env.root
				end))
				:toBe "handler failed"
			check:expect(widget.Parent == env.root):toBe(true)
			check
				:expect(thrown(function()
					widget:SetAttribute("Mark", 1)
				end))
				:toBe "handler failed"
			check
				:expect(thrown(function()
					env.poke(widget, "Count", 2)
				end))
				:toBe "handler failed"
			check
				:expect(thrown(function()
					env.fire(widget, "Pinged")
				end))
				:toBe "handler failed"
			check
				:expect(thrown(function()
					pinged(widget):Fire()
				end))
				:toBe "handler failed"
			widget:GetAttributeChangedSignal("Other"):Connect(raisingHandler())
			check
				:expect(thrown(function()
					widget:SetAttribute("Other", 1)
				end))
				:toBe "handler failed"
			check
				:expect(succeeds(function()
					other.Count = 3
				end))
				:toBe(true)
		end)

		suite:case("raise joins every handler message and still runs every handler", function(check)
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
			check
				:expect(thrown(function()
					widget.Count = 1
				end))
				:toBe "first\nsecond"
			check:expect(ran):toBe(2)
		end)

		suite:case("raise reports a method that fires through a signal and nested writes once", function(check)
			local env = plain { handlerErrors = "raise" }
			local widget = env.createInstance "Widget"
			local child = env.createInstance("Widget", { Parent = widget })
			child.Destroying:Connect(raisingHandler())
			widget:GetPropertyChangedSignal("Count"):Connect(function()
				child.Count = 9
			end)
			child:GetPropertyChangedSignal("Count"):Connect(raisingHandler())
			check
				:expect(thrown(function()
					widget.Count = 1
				end))
				:toBe "handler failed"
			check
				:expect(thrown(function()
					child:Destroy()
				end))
				:toBe "handler failed"
			local heartbeat = env.heartbeat
			heartbeat:Connect(raisingHandler())
			check
				:expect(thrown(function()
					env.step(0.1)
				end))
				:toBe "handler failed"
		end)

		suite:case("an operation error wins and an invalid mode is refused", function(check)
			local env = plain { handlerErrors = "raise" }
			local widget = env.createInstance "Widget"
			check
				:expect(thrown(function()
					widget.Missing = 1
				end))
				:toContain "is not a valid member"
			check
				:expect(thrown(function()
					plain { handlerErrors = ("ignore" :: unknown) :: "raise" }
				end))
				:toContain "handlerErrors"
		end)

		suite:case("the bridge passes the mode through", function(check)
			local built = bridge { handlerErrors = "raise" }
			local frame = built.environment.createInstance "Frame"
			frame:GetPropertyChangedSignal("Visible"):Connect(raisingHandler())
			check
				:expect(thrown(function()
					frame.Visible = false
				end))
				:toBe "handler failed"
		end)
	end)

	suite:suite("connection counts for any signal", function()
		suite:case("counts property, attribute, heartbeat and new signals", function(check)
			local env = plain()
			local widget = env.createInstance "Widget"
			local changed = widget:GetPropertyChangedSignal "Count"
			local attribute = widget:GetAttributeChangedSignal "Mark"
			local own = env.newSignal()
			check:expect(env.connectionsOf(changed)):toBe(0)
			local connection = changed:Connect(function() end)
			attribute:Connect(function() end)
			own:Connect(function() end)
			env.heartbeat:Connect(function() end)
			check:expect(env.connectionsOf(changed)):toBe(1)
			check:expect(env.connectionsOf(attribute)):toBe(1)
			check:expect(env.connectionsOf(own)):toBe(1)
			check:expect(env.connectionsOf((env.heartbeat :: unknown) :: Environment.Signal)):toBe(1)
			widget.Count = 1
			widget.Count = 2
			check:expect(env.firesOf(changed)):toBe(2)
			own:Fire()
			check:expect(env.firesOf(own)):toBe(1)
			env.step(1)
			check:expect(env.firesOf((env.heartbeat :: unknown) :: Environment.Signal)):toBe(1)
			connection:Disconnect()
			check:expect(env.connectionsOf(changed)):toBe(0)
		end)

		suite:case("totals the connections of one instance and drops them on destroy", function(check)
			local env = plain()
			local widget = env.createInstance "Widget"
			local bystander = env.createInstance "Widget"
			check:expect(env.connectionsOfInstance(widget)):toBe(0)
			pinged(widget):Connect(function() end)
			widget.Changed:Connect(function() end)
			widget:GetPropertyChangedSignal("Count"):Connect(function() end)
			widget:GetAttributeChangedSignal("Mark"):Connect(function() end)
			pinged(bystander):Connect(function() end)
			check:expect(env.connectionsOfInstance(widget)):toBe(4)
			check:expect(env.connectionsOfInstance(bystander)):toBe(1)
			widget:Destroy()
			check:expect(env.connectionsOfInstance(widget)):toBe(0)
		end)

		suite:case("refuses a signal that the environment did not make", function(check)
			local env = plain()
			local foreign = plain().newSignal()
			check
				:expect(thrown(function()
					return env.connectionsOf(foreign)
				end))
				:toContain "not created by this environment"
			check
				:expect(thrown(function()
					return env.firesOf((({}) :: unknown) :: Environment.Signal)
				end))
				:toContain "not created by this environment"
		end)
	end)

	suite:suite("per-instance method doubles", function()
		suite:case("fakeOn installs an undeclared member for one instance with the instance as self", function(check)
			local env = plain()
			local first = env.createInstance "Widget"
			local second = env.createInstance "Widget"
			local seen: { unknown } = {}
			env.fakeOn(first, "IsKeyDown", function(self: Environment.Instance, key: string): boolean
				table.insert(seen, self)
				return key == "A"
			end)
			local call = first.IsKeyDown :: (Environment.Instance, string) -> boolean
			check:expect(call(first, "A")):toBe(true)
			check:expect(call(first, "B")):toBe(false)
			check:expect(seen[1] == first):toBe(true)
			check
				:expect(thrown(function()
					return second.IsKeyDown
				end))
				:toContain "is not a valid member"
			env.fakeOn(first, "IsKeyDown", function(): boolean
				return false
			end)
			check:expect((first.IsKeyDown :: (Environment.Instance, string) -> boolean)(first, "A")):toBe(false)
		end)

		suite:case("fakeOn refuses a property, an event and Parent", function(check)
			local env = plain()
			local widget = env.createInstance "Widget"
			for _, name in { "Count", "Pinged", "Parent", "ClassName" } do
				check
					:expect(thrown(function()
						env.fakeOn(widget, name, function() end)
					end))
					:toContain "cannot be a method double"
			end
		end)

		suite:case("assigning a function is refused unless functionDoubles is on", function(check)
			local strict = plain()
			local widget = strict.createInstance "Widget"
			check
				:expect(thrown(function()
					widget.GetGuiInset = function() end
				end))
				:toContain "is not a valid member"
		end)

		suite:case("assigning a function installs a replaceable double when functionDoubles is on", function(check)
			local env = plain { functionDoubles = true }
			local widget = env.createInstance "Widget"
			local other = env.createInstance "Widget"
			widget.GetFocusedTextBox = function(self: Environment.Instance): unknown
				return self
			end
			check:expect((widget.GetFocusedTextBox :: (Environment.Instance) -> unknown)(widget) == widget):toBe(true)
			widget.GetFocusedTextBox = function(): unknown
				return "second"
			end
			check:expect((widget.GetFocusedTextBox :: (Environment.Instance) -> unknown)(widget)):toBe "second"
			check
				:expect(thrown(function()
					return other.GetFocusedTextBox
				end))
				:toContain "is not a valid member"
			check
				:expect(thrown(function()
					widget.Missing = 5
				end))
				:toContain "is not a valid member"
			check
				:expect(thrown(function()
					widget.Pinged = function() end
				end))
				:toContain "is not a valid member"
		end)

		suite:case("a function written to a declared property still fails validation", function(check)
			local label = bridge({ functionDoubles = true }).environment.createInstance "TextLabel"
			check
				:expect(thrown(function()
					label.Text = function() end
				end))
				:toContain "requires"
		end)

		suite:case("a double does not survive Clone", function(check)
			local env = plain()
			local widget = env.createInstance "Widget"
			env.fakeOn(widget, "Probe", function(): number
				return 1
			end)
			local copy = (widget.Clone :: (Environment.Instance) -> Environment.Instance)(widget)
			check
				:expect(thrown(function()
					return copy.Probe
				end))
				:toContain "is not a valid member"
		end)
	end)

	suite:suite("rejected selection", function()
		local function ui(selection: unknown, requirePlayerGui: boolean?): Bridge.Bridge
			return bridge { ui = { selection = selection :: "raise" | "ignore"?, requirePlayerGui = requirePlayerGui } }
		end

		suite:case("raise stays the default", function(check)
			local built = ui(nil)
			local env = built.environment
			local frame = env.createInstance("Frame", { Visible = false })
			local service = env.createInstance "GuiService"
			check
				:expect(thrown(function()
					service.SelectedObject = frame
				end))
				:toContain "hidden"
			check:expect(service.SelectedObject):toBe(nil)
			local controller = built.ui :: UiFakes.Controller
			check:expect(#controller.rejectedSelections()):toBe(0)
		end)

		suite:case("ignore drops the write silently and records it", function(check)
			local built = ui "ignore"
			local env = built.environment
			local hidden = env.createInstance("Frame", { Visible = false })
			local shown = env.createInstance("Frame", { Parent = hidden })
			local locked = env.createInstance("Frame", { Selectable = false })
			local open = env.createInstance "Frame"
			local service = env.createInstance "GuiService"
			local fired = 0
			service:GetPropertyChangedSignal("SelectedObject"):Connect(function()
				fired += 1
			end)
			service.SelectedObject = shown
			service.SelectedObject = locked
			check:expect(service.SelectedObject):toBe(nil)
			check:expect(fired):toBe(0)
			local controller = built.ui :: UiFakes.Controller
			local rejected = controller.rejectedSelections()
			check:expect(#rejected):toBe(2)
			check:expect(rejected[1].target == shown):toBe(true)
			check:expect(rejected[1].reason):toContain "hidden"
			check:expect(rejected[2].reason):toContain "selectable"
			service.SelectedObject = open
			check:expect(service.SelectedObject == open):toBe(true)
			check:expect(fired):toBe(1)
			check:expect(#controller.rejectedSelections()):toBe(2)
		end)

		suite:case("ignore keeps raising for a value that is not a GuiObject", function(check)
			local built = ui "ignore"
			local env = built.environment
			local service = env.createInstance "GuiService"
			check
				:expect(thrown(function()
					service.SelectedObject = env.createInstance "Folder"
				end))
				:toContain "GuiObject"
			check
				:expect(thrown(function()
					service.SelectedObject = 5
				end))
				:toContain "requires"
		end)

		suite:case("requirePlayerGui raises outside a PlayerGui in either mode", function(check)
			for _, mode in { "raise", "ignore" } do
				local built = ui(mode, true)
				local env = built.environment
				local service = env.createInstance "GuiService"
				local loose = env.createInstance "Frame"
				check
					:expect(thrown(function()
						service.SelectedObject = loose
					end))
					:toContain "PlayerGui"
				local gui = env.createInstance "PlayerGui"
				local inside = env.createInstance("Frame", { Parent = gui })
				service.SelectedObject = inside
				check:expect(service.SelectedObject == inside):toBe(true)
			end
		end)

		suite:case("an invalid selection mode is refused", function(check)
			check
				:expect(thrown(function()
					return ui "drop"
				end))
				:toContain "selection must be"
		end)

		suite:case("validateProperty returning false vetoes a write silently", function(check)
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
			check:expect(widget.Count):toBe(0)
			check:expect(fired):toBe(0)
			env.poke(widget, "Count", 99)
			check:expect(widget.Count):toBe(0)
			widget.Count = 3
			check:expect(widget.Count):toBe(3)
			check:expect(fired):toBe(1)
		end)

		suite:case("GetStyled reads the plain property and its changed signal", function(check)
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
			check:expect(styled(label, "Text")):toBe "Label"
			label.Text = "changed"
			check:expect(styled(label, "Text")):toBe "changed"
			check:expect(fired):toBe(1)
			check
				:expect(thrown(function()
					return styled(label, "Nope")
				end))
				:toContain "is not a valid member"
		end)
	end)

	suite:suite("datatype shells", function()
		suite:case("TweenInfo has readable fields, engine defaults and value equality", function(check)
			local defaults = Datatypes.TweenInfo.new()
			check:expect(defaults.Time):toBe(1)
			check:expect(defaults.EasingStyle == Datatypes.Enum.EasingStyle.Quad):toBe(true)
			check:expect(defaults.EasingDirection == Datatypes.Enum.EasingDirection.Out):toBe(true)
			check:expect(defaults.RepeatCount):toBe(0)
			check:expect(defaults.Reverses):toBe(false)
			check:expect(defaults.DelayTime):toBe(0)
			local full = Datatypes.TweenInfo.new(
				2,
				Datatypes.Enum.EasingStyle.Linear,
				Datatypes.Enum.EasingDirection.In,
				3,
				true,
				0.5
			)
			check:expect(full.Time):toBe(2)
			check:expect(full.RepeatCount):toBe(3)
			check:expect(full.Reverses):toBe(true)
			check:expect(full.DelayTime):toBe(0.5)
			check:expect(Datatypes.TweenInfo.new(1) == defaults):toBe(true)
			check:expect(Datatypes.TweenInfo.new(2) == defaults):toBe(false)
			check:expect(Datatypes.typeName(full)):toBe "TweenInfo"
		end)

		suite:case("TweenInfo is an attribute value and its fields survive", function(check)
			local env = plain()
			local widget = env.createInstance "Widget"
			widget:SetAttribute("Info", Datatypes.TweenInfo.new(4))
			local info = widget:GetAttribute "Info" :: Datatypes.TweenInfoValue
			check:expect(info.Time):toBe(4)
			check
				:expect(thrown(function()
					widget:SetAttribute(
						"Key",
						Datatypes.FloatCurveKey.new(0, 1, Datatypes.Enum.KeyInterpolationMode.Linear)
					)
				end))
				:toContain "FloatCurveKey"
		end)

		suite:case("FloatCurveKey has readable fields and value equality", function(check)
			local linear = Datatypes.Enum.KeyInterpolationMode.Linear
			local key = Datatypes.FloatCurveKey.new(0.5, 2, linear)
			check:expect(key.Time):toBe(0.5)
			check:expect(key.Value):toBe(2)
			check:expect(key.Interpolation == linear):toBe(true)
			check:expect(key == Datatypes.FloatCurveKey.new(0.5, 2, linear)):toBe(true)
			check:expect(key == Datatypes.FloatCurveKey.new(0.5, 3, linear)):toBe(false)
			check:expect(Datatypes.typeName(key)):toBe "FloatCurveKey"
		end)

		suite:case("Path2DControlPoint has readable fields, default tangents and value equality", function(check)
			local position = Datatypes.UDim2.new(0.5, 1, 0.25, 2)
			local point = Datatypes.Path2DControlPoint.new(position)
			check:expect(point.Position == position):toBe(true)
			check:expect(point.LeftTangent == Datatypes.UDim2.new(0, 0, 0, 0)):toBe(true)
			check:expect(point.RightTangent == Datatypes.UDim2.new(0, 0, 0, 0)):toBe(true)
			local tangent = Datatypes.UDim2.new(0, 3, 0, 4)
			local full = Datatypes.Path2DControlPoint.new(position, tangent, tangent)
			check:expect(full.LeftTangent.X.Offset):toBe(3)
			check:expect(full == Datatypes.Path2DControlPoint.new(position, tangent, tangent)):toBe(true)
			check:expect(full == point):toBe(false)
			check:expect(Datatypes.typeName(point)):toBe "Path2DControlPoint"
		end)
	end)

	suite:suite("defaults the database does not store", function()
		suite:case("the hook is consulted when the database has no default", function(check)
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
			check:expect(label.Mass):toBe(5)
			check:expect(label.Text):toBe "Label"
			check:expect(label.TextBounds):toBe(nil)
			check:expect(table.find(asked, "TextLabel.Text")):toBe(nil)
			check:expect(table.find(asked, "TextLabel.TextBounds") ~= nil):toBe(true)
		end)

		suite:case("without a hook a declaration is never a default", function(check)
			local label = bridge().environment.createInstance "TextLabel"
			check:expect(label.Mass):toBe(nil)
		end)

		suite:case("ResetPropertyToDefault restores the stored, hooked or empty default", function(check)
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
			local reset = label.ResetPropertyToDefault :: (Environment.Instance, string) -> ()
			reset(label, "Mass")
			reset(label, "Text")
			check:expect(label.Mass):toBe(5)
			check:expect(label.Text):toBe "Label"
			check:expect(fired):toBe(2)
			reset(label, "Mass")
			check:expect(fired):toBe(2)
			label.TextBounds = Datatypes.Vector2.new(1, 1)
			reset(label, "TextBounds")
			check:expect(label.TextBounds):toBe(nil)
			check
				:expect(thrown(function()
					reset(label, "Nope")
				end))
				:toContain "is not a valid member"
		end)

		suite:case("ResetPropertyToDefault works on a plain environment", function(check)
			local env = plain()
			local widget = env.createInstance "Widget"
			widget.Count = 4
			(widget.ResetPropertyToDefault :: (Environment.Instance, string) -> ())(widget, "Count")
			check:expect(widget.Count):toBe(0)
		end)
	end)

	suite:suite("computed property reads", function()
		suite:case("the getter answers the read and tracks the instance", function(check)
			local built = bridge {
				computed = getters {
					["TextLabel.TextBounds"] = function(object: Environment.Instance): unknown
						return Datatypes.Vector2.new(#(object.Text :: string) * 8, 16)
					end,
				},
			}
			local label = built.environment.createInstance("TextLabel", { Text = "abc" })
			local bounds = label.TextBounds :: Datatypes.Vector2Value
			check:expect(bounds.X):toBe(24)
			label.Text = "abcd"
			check:expect((label.TextBounds :: Datatypes.Vector2Value).X):toBe(32)
			check:expect(built.environment.createInstance("Frame").Visible):toBe(true)
		end)

		suite:case("a getter on a superclass applies to a subclass and writes are refused", function(check)
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
			check:expect(widget.Depth):toBe(1)
			check
				:expect(thrown(function()
					widget.Depth = 3
				end))
				:toContain "read-only"
			check
				:expect(thrown(function()
					env.poke(widget, "Depth", 3)
				end))
				:toContain "computed"
			check
				:expect(succeeds(function()
					widget:GetPropertyChangedSignal "Depth"
				end))
				:toBe(true)
		end)

		suite:case("clones an instance and its descendants that carry computed properties", function(check)
			local seen: { Environment.Instance } = {}
			local built = bridge {
				ui = {},
				computed = getters {
					["TextLabel.TextBounds"] = function(object: Environment.Instance): unknown
						table.insert(seen, object)
						return Datatypes.Vector2.new(#(object.Text :: string) * 8, 16)
					end,
					["TextLabel.TextFits"] = function(_object: Environment.Instance): unknown
						return true
					end,
				},
			}
			local hooked: { Environment.Instance } = {}
			local connection = built.environment.onClone(
				function(_source: Environment.Instance, copy: Environment.Instance)
					table.insert(hooked, copy)
				end
			)
			local parent = built.environment.createInstance "Frame"
			local label = built.environment.createInstance("TextLabel", { Text = "abc", Parent = parent })
			check:expect(label.TextFits):toBe(true)
			local copy = label:Clone() :: Environment.Instance
			check:expect(copy.TextFits):toBe(true)
			check:expect((copy.TextBounds :: Datatypes.Vector2Value).X):toBe(24)
			check:expect(seen[#seen] == copy):toBe(true)
			check:expect(hooked[1] == copy):toBe(true)
			local tree = parent:Clone() :: Environment.Instance
			local child = tree:GetChildren()[1]
			check:expect(child ~= label):toBe(true)
			check:expect(child.TextFits):toBe(true)
			check:expect((child.TextBounds :: Datatypes.Vector2Value).X):toBe(24)
			check:expect(seen[#seen] == child):toBe(true)
			check:expect(#hooked):toBe(3)
			connection:Disconnect()
		end)

		suite:case("a plain computed getter stays read-only for a write and a poke", function(check)
			local env = plain {
				computed = getters {
					["Widget.Count"] = function(_object: Environment.Instance): unknown
						return 1
					end,
				},
			}
			local widget = env.createInstance "Widget"
			check
				:expect(thrown(function()
					widget.Count = 2
				end))
				:toContain "read-only"
			check
				:expect(thrown(function()
					env.poke(widget, "Count", 2)
				end))
				:toContain "computed"
		end)

		suite:case("a writable computed property stores, notifies, reads and clones", function(check)
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
			check:expect(fired):toBe(1)
			check:expect(widget.Fits):toBe(true)
			check:expect(env.propertyOf(widget, "Fits")):toBe(false)
			widget.Fits = true
			check:expect(fired):toBe(2)
			widget.Fits = false
			widget.Fits = true
			check:expect(fired):toBe(4)
			widget.Fits = true
			check:expect(fired):toBe(4)
			env.poke(widget, "Fits", 7)
			check:expect(fired):toBe(5)
			check:expect(env.propertyOf(widget, "Fits")):toBe(7)
			answer = nil
			check:expect(widget.Fits):toBe(7)
			local copy = widget:Clone() :: Environment.Instance
			check:expect(env.propertyOf(copy, "Fits")):toBe(7)
			check:expect(copy.Fits):toBe(7)
		end)

		suite:case("a class without a getter keeps the unknown read error", function(check)
			local env = plain {
				computed = getters {
					["Folder.Depth"] = function(_object: Environment.Instance): unknown
						return 1
					end,
				},
			}
			local widget = env.createInstance "Widget"
			check
				:expect(thrown(function()
					return widget.Depth
				end))
				:toContain "is not a valid member"
		end)
	end)

	suite:suite("undeclared writes", function()
		suite:case("a write to an unknown property is refused by default", function(check)
			local env = plain()
			local widget = env.createInstance "Widget"
			check
				:expect(thrown(function()
					widget.Extra = 1
				end))
				:toContain "is not a valid member"
			check
				:expect(thrown(function()
					env.poke(widget, "Extra", 1)
				end))
				:toContain "is not a valid member"
		end)

		suite:case("undeclaredReads returns nil for an undeclared member and keeps declared reads", function(check)
			local relaxed = Environment.create { undeclaredReads = "nil" }
			local parent = relaxed.createInstance("Folder", { Name = "relaxed" })
			local child = relaxed.createInstance("Folder", { Name = "Child", Parent = parent })
			check:expect(parent.Missing):toBeNil()
			local indexed = (parent :: unknown) :: { [number]: unknown }
			check:expect(indexed[1]):toBeNil()
			check:expect(parent.Child):toBe(child)
			check:expect(parent.Name):toBe "relaxed"
			check
				:expect(thrown(function()
					parent.Missing = 1
				end))
				:toContain "is not a valid member"
			local strict = Environment.create {}
			local folder = strict.createInstance("Folder", { Name = "strict" })
			check
				:expect(thrown(function()
					return folder.Missing
				end))
				:toContain "is not a valid member"
		end)

		suite:case("undeclaredWrites stores, reads, signals and clones the value", function(check)
			local env = plain { undeclaredWrites = true }
			local widget = env.createInstance "Widget"
			local fired = 0
			widget:GetPropertyChangedSignal("Extra"):Connect(function()
				fired += 1
			end)
			widget.Extra = 1
			check:expect(widget.Extra):toBe(1)
			check:expect(fired):toBe(1)
			env.poke(widget, "Extra", 2)
			check:expect(widget.Extra):toBe(2)
			check:expect(fired):toBe(2)
			local copy = (widget.Clone :: (Environment.Instance) -> Environment.Instance)(widget)
			check:expect(copy.Extra):toBe(2)
			check
				:expect(thrown(function()
					return widget.NeverWritten
				end))
				:toContain "is not a valid member"
			check
				:expect(thrown(function()
					widget.Pinged = 1
				end))
				:toContain "is not a valid member"
			check
				:expect(thrown(function()
					widget.ClassName = "Other"
				end))
				:toContain "is not a valid member"
		end)

		suite:case("the bridge keeps validating declared properties when undeclared writes are on", function(check)
			local built = bridge { undeclaredWrites = true }
			local label = built.environment.createInstance "TextLabel"
			label.Extra = "free"
			check:expect(label.Extra):toBe "free"
			check
				:expect(succeeds(function()
					label.Text = 5
				end))
				:toBe(false)
		end)
	end)

	suite:suite("observation identity", function()
		suite:case("events carry the object and the value for each operation", function(check)
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
				check:expect(event.object ~= nil):toBe(true)
				if event.operation == "setProperty" then
					writes[event.object] = (writes[event.object] or 0) + 1
				end
			end
			check:expect(writes[first]):toBe(2)
			check:expect(writes[second]):toBe(1)
			check:expect(events[1].operation):toBe "create"
			check:expect(events[1].object == first):toBe(true)
			check:expect(events[4].member):toBe "Count"
			check:expect(events[4].value):toBe(1)
			check:expect(events[7].operation):toBe "setAttribute"
			check:expect(events[7].value):toBe "a"
			check:expect(events[8].value):toBe(nil)
			check:expect(events[9].operation):toBe "setParent"
			check:expect(events[9].value == folder):toBe(true)
			check:expect(events[10].operation):toBe "destroy"
			check:expect(events[10].object == first):toBe(true)
			check:expect(events[1].subject):toBe "Widget"
		end)

		suite:case("a clone create event carries the copy and an injected failure keeps the object", function(check)
			local built = bridge()
			local recorder = built.record()
			local label = built.environment.createInstance("TextLabel", { Text = "x" })
			local copy = label:Clone() :: Environment.Instance
			local created: { Environment.Instance } = {}
			for _, event in recorder.events do
				if event.operation == "create" then
					table.insert(created, event.object)
				end
			end
			check:expect(created[1] == label):toBe(true)
			check:expect(created[2] == copy):toBe(true)
			built.faults.inject("setProperty", 1)
			check
				:expect(succeeds(function()
					label.Text = "y"
				end))
				:toBe(false)
			local last = recorder.events[#recorder.events]
			check:expect(last.injected):toBe(true)
			check:expect(last.object == label):toBe(true)
			check:expect(last.value):toBe "y"
			recorder.stop()
		end)
	end)
end
