--!strict

local Bridge = require "../src/roblox/fixture-bridge"
local Environment = require "../src/roblox/environment"
local Reflection = require "../src/roblox/reflection"
local UiFakes = require "../src/roblox/ui-fakes"
local Verify = require "../src/core"

type ClassTable = { [string]: Reflection.Class }

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
	return {
		Name = name,
		Superclass = super,
		Properties = declared,
		DefaultProperties = {},
		Tags = tags or {},
	}
end

local function database(withMedia: boolean): Reflection.Database
	local classes: ClassTable = {
		Instance = class("Instance", nil, { property("Name", "String") }, { "NotCreatable" }),
		Folder = class("Folder", "Instance"),
		GuiObject = class(
			"GuiObject",
			"Instance",
			{ property("Visible", "Bool"), property("Selectable", "Bool") },
			{ "NotCreatable" }
		),
		Frame = class("Frame", "GuiObject"),
		TextButton = class("TextButton", "GuiObject", { property("Text", "String") }),
		TextBox = class("TextBox", "GuiObject", { property("Text", "String"), property("ClearTextOnFocus", "Bool") }),
		GuiService = class("GuiService", "Instance", { property("SelectedObject", "Ref") }, { "Service" }),
		TextService = class("TextService", "Instance", nil, { "Service" }),
		StyleSheet = class("StyleSheet", "Instance"),
		StyleRule = class("StyleRule", "Instance", { property("Selector", "String") }),
	}
	if withMedia then
		classes.Path2D = class("Path2D", "Instance")
		classes.VideoFrame = class("VideoFrame", "GuiObject")
		classes.UIPageLayout = class("UIPageLayout", "Instance")
	end
	classes.UserInputService = class("UserInputService", "Instance", nil, { "Service" })
	return {
		GetClassNames = function()
			local names: { string } = {}
			for name in classes do
				table.insert(names, name)
			end
			table.sort(names)
			return names
		end,
		GetClass = function(_, name)
			return classes[name]
		end,
	}
end

local function create(withMedia: boolean, ui: UiFakes.Options?): Bridge.Bridge
	return Bridge.create {
		database = database(withMedia),
		typeName = typeof,
		ui = ui,
	}
end

local function succeeds(body: () -> unknown): boolean
	return (pcall(body))
end

local function signal(object: Environment.Instance, name: string): Environment.Signal<...unknown>
	return object[name] :: Environment.Signal<...unknown>
end

local function call(object: Environment.Instance, name: string, ...: unknown): unknown
	return (object[name] :: Environment.Method)(object, ...)
end

return function(suite: Verify.Harness)
	suite:suite("generic fixture bridge", function()
		suite:case("composes reflection, event metadata and UI fakes over one environment", function(check)
			local bridge = create(true, nil)
			local env = bridge.environment
			check:expect(bridge.unavailable):toEqual {}
			check:expect(bridge.hasClass "TextBox"):toBe(true)
			check:expect(bridge.hasClass "Nonexistent"):toBe(false)
			local button = env.createInstance "TextButton"
			local activations = 0
			signal(button, "Activated"):Connect(function()
				activations += 1
			end)
			env.fire(button, "Activated")
			check:expect(activations):toBe(1)
			local box = env.createInstance "TextBox"
			call(box, "CaptureFocus")
			check:expect((bridge.ui :: UiFakes.Controller).focused() == box):toBe(true)
			check
				:expect(succeeds(function(): unknown
					box.Text = 3
					return nil
				end))
				:toBe(false)
			bridge.close()
		end)

		suite:case("names the UI fake classes the database does not know instead of inventing them", function(check)
			local bridge = create(false, nil)
			check:expect(table.find(bridge.unavailable, "Path2D") ~= nil):toBe(true)
			check:expect(table.find(bridge.unavailable, "VideoFrame") ~= nil):toBe(true)
			check
				:expect(succeeds(function(): unknown
					return bridge.environment.createInstance "Path2D"
				end))
				:toBe(false)
			check:expect(bridge.environment.createInstance("TextBox").ClassName):toBe "TextBox"
		end)

		suite:case("restricts focus and selection to visible selectable controls", function(check)
			local bridge = create(true, nil)
			local env = bridge.environment
			local panel = env.createInstance("Frame", { Visible = false })
			local box = env.createInstance("TextBox", { Parent = panel })
			local service = env.createInstance "GuiService"
			check
				:expect(succeeds(function(): unknown
					return call(box, "CaptureFocus")
				end))
				:toBe(false)
			check
				:expect(succeeds(function(): unknown
					service.SelectedObject = box
					return nil
				end))
				:toBe(false)
			check:expect(service.SelectedObject):toBe(nil)
			panel.Visible = true
			service.SelectedObject = box
			check:expect(service.SelectedObject == box):toBe(true)
		end)

		suite:case(
			"adds no validation call to a write unless it is the one property UI validation acts on",
			function(check)
				local selections = 0
				local acted = 0
				local original = UiFakes.selection
				UiFakes.selection = function(options: UiFakes.Options?): UiFakes.Selection
					local rule = original(options)
					local inner = rule.validate
					rule.validate = function(className, property, value, operation)
						acted += 1
						return inner(className, property, value, operation)
					end
					return rule
				end
				local counted = create(true, {
					validate = function(): boolean
						selections += 1
						return true
					end,
				})
				local frame = counted.environment.createInstance "Frame"
				for index = 1, 50 do
					frame.Visible = index % 2 == 0
				end
				local service = counted.environment.createInstance "GuiService"
				service.SelectedObject = nil
				check:expect(selections):toBe(1)
				check:expect(acted):toBe(1)
				local relaxed = create(true, {
					validate = false,
				})
				local hidden = relaxed.environment.createInstance("TextButton", { Visible = false })
				local target = relaxed.environment.createInstance "GuiService"
				target.SelectedObject = hidden
				check:expect(acted):toBe(1)
				check:expect(target.SelectedObject == hidden):toBe(true)
				local calls = 0
				local supplied = Bridge.create {
					database = database(true),
					typeName = typeof,
					ui = { validate = false },
					validateProperty = function()
						calls += 1
					end,
				}
				supplied.environment.createInstance("Frame").Visible = true
				check:expect(calls > 0):toBe(true)
				UiFakes.selection = original
			end
		)

		suite:case("keeps UI validation for selected properties while relaxing the rest", function(check)
			local seen: { string } = {}
			local kept = create(true, {
				validate = function(className: string, property: string): boolean
					table.insert(seen, className .. "." .. property)
					return property == "SelectedObject"
				end,
			})
			local hidden = kept.environment.createInstance("TextButton", { Visible = false })
			local service = kept.environment.createInstance "GuiService"
			check
				:expect(succeeds(function(): unknown
					service.SelectedObject = hidden
					return nil
				end))
				:toBe(false)
			check:expect(table.find(seen, "GuiService.SelectedObject") ~= nil):toBe(true)
			local relaxed = create(true, {
				validate = function(_className: string, property: string): boolean
					return property ~= "SelectedObject"
				end,
			})
			local target = relaxed.environment.createInstance("TextButton", { Visible = false })
			local other = relaxed.environment.createInstance "GuiService"
			other.SelectedObject = target
			check:expect(other.SelectedObject == target):toBe(true)
			check
				:expect(succeeds(function(): unknown
					call(relaxed.environment.createInstance("TextBox", { Visible = false }), "CaptureFocus")
					return nil
				end))
				:toBe(false)
		end)

		suite:case("tracks created and cloned objects until stopped", function(check)
			local bridge = create(true, nil)
			local env = bridge.environment
			local tracking = bridge.track()
			local folder = env.createInstance "Folder"
			local child = env.createInstance("Frame", { Parent = folder })
			check:expect(#tracking.created):toBe(2)
			check:expect(tracking.created[1] == folder):toBe(true)
			local copy = folder:Clone() :: Environment.Instance
			check:expect(#tracking.created):toBe(4)
			check:expect(#tracking.cloned):toBe(2)
			check:expect(tracking.cloned[1].source == folder and tracking.cloned[1].copy == copy):toBe(true)
			check:expect(tracking.cloned[2].source == child):toBe(true)
			tracking.stop()
			env.createInstance "Folder"
			check:expect(#tracking.created):toBe(4)
		end)

		suite:case("measures text only through injected providers", function(check)
			local refused = create(true, nil)
			local service = refused.environment.createInstance "TextService"
			check
				:expect(succeeds(function(): unknown
					return call(service, "GetTextSize", "abc", 10)
				end))
				:toBe(false)
			local measuring = create(true, {
				measureText = function(text: string, size: number): unknown
					return #text * size
				end,
			})
			local measured = measuring.environment.createInstance "TextService"
			check:expect(call(measured, "GetTextSize", "abc", 10)):toBe(30)
		end)

		suite:case("clones preserve applicable UI fake state with remapped references", function(check)
			local bridge = create(true, nil)
			local env = bridge.environment
			local root = env.createInstance "Folder"
			local base = env.createInstance("StyleSheet", { Parent = root })
			local derived = env.createInstance("StyleSheet", { Parent = root })
			local rule = env.createInstance("StyleRule", { Parent = derived })
			local path = env.createInstance("Path2D", { Parent = root })
			call(rule, "SetProperty", "Color", "red")
			call(rule, "SetPropertyTransition", "Color", "fast")
			call(rule, "SetDefaultPropertyTransition", "slow")
			call(derived, "SetDerives", { base })
			call(path, "SetControlPoints", { 1, 2 })
			local copy = root:Clone() :: Environment.Instance
			local copiedBase = copy:FindFirstChild "StyleSheet" :: Environment.Instance
			local copiedDerived = copy:GetChildren()[2]
			local copiedRule = copiedDerived:FindFirstChildOfClass "StyleRule" :: Environment.Instance
			check:expect(call(copiedRule, "GetProperty", "Color")):toBe "red"
			check:expect(call(copiedRule, "GetDefaultPropertyTransition")):toBe "slow"
			check:expect(call(copiedRule, "GetPropertyTransitions")):toEqual { Color = "fast" }
			local derives = call(copiedDerived, "GetDerives") :: { Environment.Instance }
			check:expect(derives[1] == copiedBase):toBe(true)
			check:expect(derives[1] == base):toBe(false)
			check
				:expect(call(copy:FindFirstChildOfClass "Path2D" :: Environment.Instance, "GetControlPoints"))
				:toEqual { 1, 2 }
			call(copiedRule, "SetProperty", "Color", "blue")
			check:expect(call(rule, "GetProperty", "Color")):toBe "red"
		end)

		suite:case("a clone is not focused and an outside derive reference stays unmapped", function(check)
			local bridge = create(true, nil)
			local env = bridge.environment
			local box = env.createInstance "TextBox"
			call(box, "CaptureFocus")
			local copy = box:Clone() :: Environment.Instance
			check:expect(call(copy, "IsFocused")):toBe(false)
			check:expect(call(box, "IsFocused")):toBe(true)
			local outside = env.createInstance "StyleSheet"
			local sheet = env.createInstance "StyleSheet"
			call(sheet, "SetDerives", { outside })
			local copied = sheet:Clone() :: Environment.Instance
			check:expect((call(copied, "GetDerives") :: { Environment.Instance })[1] == outside):toBe(true)
		end)

		suite:case("a failing clone hook leaves no leaked copies", function(check)
			local env = Environment.create()
			local connection = env.onClone(function()
				error("hook refused", 0)
			end)
			local object = env.createInstance "Folder"
			local before = env.liveObjects()
			check
				:expect(succeeds(function(): unknown
					return object:Clone()
				end))
				:toBe(false)
			check:expect(env.liveObjects()):toBe(before)
			connection:Disconnect()
			check:expect(object:Clone() ~= nil):toBe(true)
		end)

		suite:case("injected failures fire once and an unfired injection is refused", function(check)
			local bridge = create(true, nil)
			bridge.faults.inject("create", 1)
			check:expect(bridge.faults.pending()):toBe(1)
			check:expect(succeeds(bridge.faults.assertConsumed)):toBe(false)
			check
				:expect(succeeds(function(): unknown
					return bridge.environment.createInstance "Folder"
				end))
				:toBe(false)
			check:expect(bridge.faults.pending()):toBe(0)
			check:expect(succeeds(bridge.faults.assertConsumed)):toBe(true)
			check
				:expect(succeeds(function(): unknown
					return bridge.environment.createInstance "Folder"
				end))
				:toBe(true)
			bridge.faults.inject("destroy", 2)
			bridge.faults.clear()
			check:expect(bridge.faults.pending()):toBe(0)
		end)

		suite:case("observes operations including injected failures until stopped", function(check)
			local bridge = create(true, nil)
			local recording = bridge.record()
			local env = bridge.environment
			local folder = env.createInstance "Folder"
			local label = env.createInstance "TextButton"
			label.Parent = folder
			label.Text = "go"
			bridge.faults.inject("setProperty", 1)
			check
				:expect(succeeds(function(): unknown
					label.Text = "stop"
					return nil
				end))
				:toBe(false)
			recording.stop()
			label.Text = "unobserved"
			local seen: { string } = {}
			for _, event in recording.events do
				table.insert(
					seen,
					("%s:%s:%s"):format(event.operation, tostring(event.member), tostring(event.injected))
				)
			end
			check:expect(seen):toEqual {
				"create:nil:false",
				"create:nil:false",
				"setParent:nil:false",
				"setProperty:Text:false",
				"setProperty:Text:true",
			}
		end)

		suite:case("accounts live objects, connections and unfired faults at close", function(check)
			local bridge = create(true, nil)
			local env = bridge.environment
			local box = env.createInstance "TextBox"
			local connection = signal(box, "Changed"):Connect(function() end)
			call(box, "CaptureFocus")
			bridge.faults.inject("destroy", 1)
			local before = bridge.accounting()
			check:expect(before.objects >= 1):toBe(true)
			check:expect(before.pendingFaults):toBe(1)
			local closed = bridge.close()
			check:expect(closed.connections < before.connections):toBe(true)
			check:expect(closed.pendingFaults):toBe(1)
			connection:Disconnect()
		end)

		suite:case("shares the environment with the simulated instance host and engine seam", function(check)
			local bridge = create(true, nil)
			local simulation = bridge.instanceHost "server"
			check:expect(simulation.environment == bridge.environment):toBe(true)
			check:expect(table.find(simulation.host.capabilities, "action:instance.create") ~= nil):toBe(true)
			local object = bridge.engine.new "Folder"
			check:expect(Environment.isInstance(object)):toBe(true)
			check
				:expect(succeeds(function(): unknown
					return bridge.engine.new "GuiObject"
				end))
				:toBe(false)
		end)
	end)
end
