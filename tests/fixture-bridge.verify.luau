--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Fixture = require "./reflection-fixture"

local Bridge = require "../src/roblox/fixture-bridge"
local Environment = require "../src/roblox/environment"
local Reflection = require "../src/roblox/reflection"
local UiFakes = require "../src/roblox/ui-fakes"

type ClassTable = { [string]: Reflection.Class }

local property, class = Fixture.property, Fixture.class

local function database(withMedia: boolean): Reflection.Database
	local classes: ClassTable = {
		Instance = class("Instance", nil, { property("Name", "String") }, { "NotCreatable" }),
		DataModel = class("DataModel", "Instance", nil, { "NotCreatable" }),
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
		StyleLink = class("StyleLink", "Instance", { property("StyleSheet", "Ref") }),
		StyleRule = class("StyleRule", "Instance", { property("Selector", "String") }),
	}
	if withMedia then
		classes.Path2D = class("Path2D", "Instance")
		classes.VideoFrame = class("VideoFrame", "GuiObject")
		classes.UIPageLayout = class("UIPageLayout", "Instance")
	end
	classes.UserInputService = class("UserInputService", "Instance", nil, { "Service" })
	return Fixture.database(classes)
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

describe("generic fixture bridge", function()
	it("place engines reuse one environment and validate reflected services", function()
		local bridge = create(false, nil)
		local engine = bridge.placeEngine()
		expect(bridge.placeEngine()):toBe(engine)
		expect(engine.environment):toBe(bridge.environment)
		local gui = engine.service "GuiService"
		expect(engine.service "GuiService"):toBe(gui)
		expect(gui.Parent):toBe(engine.game)
		expect(engine.surface.memberKind("TextButton", "Name")):toBe "property"
		expect(engine.surface.memberType("TextButton", "Name")):toBe "String"
		expect((pcall(engine.service, "Folder"))):toBe(false)
		expect((pcall(engine.service, "Missing"))):toBe(false)
		expect((pcall(engine.newInstance, "GuiService"))):toBe(false)
		expect(engine.newInstance("GuiService", true).ClassName):toBe "GuiService"
		engine.setSourceResolver(function(): string
			return "module"
		end)
		engine.record("error", "failure", engine.currentSource())
		expect(engine.diagnostics[1]):toEqual { kind = "error", text = "failure", source = "module" }
		bridge.close()
	end)
	it("internal UI fakes preserve creation restrictions and explicit overrides", function()
		local bridge = create(false, nil)
		for _, name in { "GuiService", "TextService", "UserInputService" } do
			expect(succeeds(function()
				bridge.engine.new(name)
				return nil
			end)):toBe(false)
			expect(bridge.environment.createEngineInstance(name).ClassName):toBe(name)
		end
		bridge.close()
		local configured = Bridge.create {
			database = database(false),
			typeName = typeof,
			classes = { GuiService = { creatable = true } },
		}
		expect(configured.engine.new("GuiService").ClassName):toBe "GuiService"
		configured.close()
	end)
	it("composes reflection, event metadata and UI fakes over one environment", function()
		local bridge = create(true, nil)
		local env = bridge.environment
		expect(bridge.unavailable):toEqual {}
		expect(bridge.hasClass "TextBox"):toBe(true)
		expect(bridge.hasClass "Nonexistent"):toBe(false)
		local button = env.createInstance "TextButton"
		local activations = 0
		signal(button, "Activated"):Connect(function()
			activations += 1
		end)
		env.fire(button, "Activated")
		expect(activations):toBe(1)
		local box = env.createInstance "TextBox"
		call(box, "CaptureFocus")
		expect((assert(bridge.ui)).focused() == box):toBe(true)
		expect(succeeds(function(): unknown
			box.Text = 3
			return nil
		end)):toBe(false)
		bridge.close()
	end)

	it("names the UI fake classes the database does not know instead of inventing them", function()
		local bridge = create(false, nil)
		expect(table.find(bridge.unavailable, "Path2D") ~= nil):toBe(true)
		expect(table.find(bridge.unavailable, "VideoFrame") ~= nil):toBe(true)
		expect(succeeds(function(): unknown
			return bridge.environment.createInstance "Path2D"
		end)):toBe(false)
		expect(bridge.environment.createInstance("TextBox").ClassName):toBe "TextBox"
	end)

	it("restricts focus and selection to visible selectable controls", function()
		local bridge = create(true, nil)
		local env = bridge.environment
		local panel = env.createInstance("Frame", { Visible = false })
		local box = env.createInstance("TextBox", { Parent = panel })
		local service = env.createEngineInstance "GuiService"
		expect(succeeds(function(): unknown
			return call(box, "CaptureFocus")
		end)):toBe(false)
		expect(succeeds(function(): unknown
			service.SelectedObject = box
			return nil
		end)):toBe(false)
		expect(service.SelectedObject):toBe(nil)
		panel.Visible = true
		service.SelectedObject = box
		expect(service.SelectedObject == box):toBe(true)
	end)

	it("adds no validation call to a write unless it is the one property UI validation acts on", function()
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
		local service = counted.environment.createEngineInstance "GuiService"
		service.SelectedObject = nil
		expect(selections):toBe(1)
		expect(acted):toBe(1)
		local relaxed = create(true, {
			validate = false,
		})
		local hidden = relaxed.environment.createInstance("TextButton", { Visible = false })
		local target = relaxed.environment.createEngineInstance "GuiService"
		target.SelectedObject = hidden
		expect(acted):toBe(1)
		expect(target.SelectedObject == hidden):toBe(true)
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
		expect(calls > 0):toBe(true)
		UiFakes.selection = original
	end)

	it("keeps UI validation for selected properties while relaxing the rest", function()
		local seen: { string } = {}
		local kept = create(true, {
			validate = function(className: string, property: string): boolean
				table.insert(seen, className .. "." .. property)
				return property == "SelectedObject"
			end,
		})
		local hidden = kept.environment.createInstance("TextButton", { Visible = false })
		local service = kept.environment.createEngineInstance "GuiService"
		expect(succeeds(function(): unknown
			service.SelectedObject = hidden
			return nil
		end)):toBe(false)
		expect(table.find(seen, "GuiService.SelectedObject") ~= nil):toBe(true)
		local relaxed = create(true, {
			validate = function(_className: string, property: string): boolean
				return property ~= "SelectedObject"
			end,
		})
		local target = relaxed.environment.createInstance("TextButton", { Visible = false })
		local other = relaxed.environment.createEngineInstance "GuiService"
		other.SelectedObject = target
		expect(other.SelectedObject == target):toBe(true)
		expect(succeeds(function(): unknown
			call(relaxed.environment.createInstance("TextBox", { Visible = false }), "CaptureFocus")
			return nil
		end)):toBe(false)
	end)

	it("tracks created and cloned objects until stopped", function()
		local bridge = create(true, nil)
		local env = bridge.environment
		local tracking = bridge.track()
		local folder = env.createInstance "Folder"
		local child = env.createInstance("Frame", { Parent = folder })
		expect(#tracking.created):toBe(2)
		expect(tracking.created[1] == folder):toBe(true)
		local copy = folder:Clone()
		expect(#tracking.created):toBe(4)
		expect(#tracking.cloned):toBe(2)
		expect(tracking.cloned[1].source == folder and tracking.cloned[1].copy == copy):toBe(true)
		expect(tracking.cloned[2].source == child):toBe(true)
		tracking.stop()
		env.createInstance "Folder"
		expect(#tracking.created):toBe(4)
	end)

	it("measures text only through injected providers", function()
		local refused = create(true, nil)
		local service = refused.environment.createEngineInstance "TextService"
		expect(succeeds(function(): unknown
			return call(service, "GetTextSize", "abc", 10)
		end)):toBe(false)
		local measuring = create(true, {
			measureText = function(text: string, size: number): unknown
				return #text * size
			end,
		})
		local measured = measuring.environment.createEngineInstance "TextService"
		expect(call(measured, "GetTextSize", "abc", 10)):toBe(30)
	end)

	it("clones preserve applicable UI fake state with remapped references", function()
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
		local copy = assert(root:Clone())
		local copiedBase = copy:FindFirstChild "StyleSheet"
		local copiedDerived = copy:GetChildren()[2]
		local copiedRule = assert(copiedDerived:FindFirstChildOfClass "StyleRule")
		expect(call(copiedRule, "GetProperty", "Color")):toBe "red"
		expect(call(copiedRule, "GetDefaultPropertyTransition")):toBe "slow"
		expect(call(copiedRule, "GetPropertyTransitions")):toEqual { Color = "fast", ["*"] = "slow" }
		local derives = call(copiedDerived, "GetDerives") :: { Environment.Instance }
		expect(derives[1] == copiedBase):toBe(true)
		expect(derives[1] == base):toBe(false)
		expect(call(assert(copy:FindFirstChildOfClass "Path2D"), "GetControlPoints")):toEqual { 1, 2 }
		call(copiedRule, "SetProperty", "Color", "blue")
		expect(call(rule, "GetProperty", "Color")):toBe "red"
	end)

	it("a clone is not focused and an outside derive reference stays unmapped", function()
		local bridge = create(true, nil)
		local env = bridge.environment
		local box = env.createInstance "TextBox"
		call(box, "CaptureFocus")
		local copy = assert(box:Clone())
		expect(call(copy, "IsFocused")):toBe(false)
		expect(call(box, "IsFocused")):toBe(true)
		local outside = env.createInstance "StyleSheet"
		local sheet = env.createInstance "StyleSheet"
		call(sheet, "SetDerives", { outside })
		local copied = assert(sheet:Clone())
		expect((call(copied, "GetDerives") :: { Environment.Instance })[1] == outside):toBe(true)
	end)

	it("a failing clone hook leaves no leaked copies", function()
		local env = Environment.create()
		local connection = env.onClone(function()
			error("hook refused", 0)
		end)
		local object = env.createInstance "Folder"
		local before = env.liveObjects()
		expect(succeeds(function(): unknown
			return object:Clone()
		end)):toBe(false)
		expect(env.liveObjects()):toBe(before)
		connection:Disconnect()
		expect(object:Clone() ~= nil):toBe(true)
	end)

	it("injected failures fire once and an unfired injection is refused", function()
		local bridge = create(true, nil)
		bridge.faults.inject("create", 1)
		expect(bridge.faults.pending()):toBe(1)
		expect(succeeds(bridge.faults.assertConsumed)):toBe(false)
		expect(succeeds(function(): unknown
			return bridge.environment.createInstance "Folder"
		end)):toBe(false)
		expect(bridge.faults.pending()):toBe(0)
		expect(succeeds(bridge.faults.assertConsumed)):toBe(true)
		expect(succeeds(function(): unknown
			return bridge.environment.createInstance "Folder"
		end)):toBe(true)
		bridge.faults.inject("destroy", 2)
		bridge.faults.clear()
		expect(bridge.faults.pending()):toBe(0)
	end)

	it("observes operations including injected failures until stopped", function()
		local bridge = create(true, nil)
		local recording = bridge.record()
		local env = bridge.environment
		local folder = env.createInstance "Folder"
		local label = env.createInstance "TextButton"
		label.Parent = folder
		label.Text = "go"
		bridge.faults.inject("setProperty", 1)
		expect(succeeds(function(): unknown
			label.Text = "stop"
			return nil
		end)):toBe(false)
		recording.stop()
		label.Text = "unobserved"
		local seen: { string } = {}
		for _, event in recording.events do
			table.insert(seen, ("%s:%s:%s"):format(event.operation, tostring(event.member), tostring(event.injected)))
		end
		expect(seen):toEqual {
			"create:nil:false",
			"create:nil:false",
			"setParent:nil:false",
			"setProperty:Text:false",
			"setProperty:Text:true",
		}
	end)

	it("accounts live objects, connections and unfired faults at close", function()
		local bridge = create(true, nil)
		local env = bridge.environment
		local box = env.createInstance "TextBox"
		local connection = signal(box, "Changed"):Connect(function() end)
		call(box, "CaptureFocus")
		bridge.faults.inject("destroy", 1)
		local before = bridge.accounting()
		expect(before.objects >= 1):toBe(true)
		expect(before.pendingFaults):toBe(1)
		local closed = bridge.close()
		expect(closed.connections < before.connections):toBe(true)
		expect(closed.pendingFaults):toBe(1)
		connection:Disconnect()
	end)

	it("shares the environment with the simulated instance host and engine seam", function()
		local bridge = create(true, nil)
		local simulation = bridge.instanceHost "server"
		expect(simulation.environment == bridge.environment):toBe(true)
		expect(table.find(simulation.host.capabilities, "action:instance.create") ~= nil):toBe(true)
		local object = bridge.engine.new "Folder"
		expect(Environment.isInstance(object)):toBe(true)
		expect(succeeds(function(): unknown
			return bridge.engine.new "GuiObject"
		end)):toBe(false)
	end)
end)

return nil
