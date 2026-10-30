--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local Environment = require "../src/roblox/environment"
local Datatypes = require "../src/roblox/datatypes"

type Fixture = Environment.Instance & {
	Count: number,
	Data: { [string]: unknown },
	Pinged: Environment.Signal<()>,
	Stopped: Environment.Signal<()>,
	Ended: Environment.Signal<()>,
	Double: (Environment.Instance, number) -> number,
	Ping: (Environment.Instance) -> unknown,
	Twice: (Environment.Instance, number) -> number,
	WaitForChild: (Environment.Instance, string) -> Environment.Instance,
	GetTextSize: (Environment.Instance, string, number) -> Datatypes.Vector2Value,
	CaptureFocus: (Environment.Instance) -> (),
	ApplyStyle: (Environment.Instance, string) -> (),
	Clone: (Environment.Instance) -> Fixture,
	LoadAnimation: (Environment.Instance, Environment.Instance) -> Fixture,
	Play: (Environment.Instance) -> (),
	Stop: (Environment.Instance) -> (),
	AdjustSpeed: (Environment.Instance, number) -> (),
}

local function thrown(callback: () -> ...unknown): string
	local ok, message = pcall(callback)
	assert(not ok, "expected the call to raise")
	return tostring(message)
end

local function environment(): Roblox.Environment
	local options = {
		classes = {
			Widget = {
				super = "Instance",
				properties = { Label = "", Count = 0 },
				events = { "Pinged" },
				methods = {
					Ping = true,
					Double = function(self: Fixture, value: number): number
						return value * 2 + self.Count
					end,
				},
			},
		},
	}
	return Roblox.testEnvironment((options :: unknown) :: Roblox.EnvironmentOptions)
end

describe("roblox test environment", function()
	it("class defaults require declared properties and allocate no instances", function()
		local env = environment()
		local before = env.liveObjects()
		expect(env.defaultClassProperty("Widget", "Count")):toBe(0)
		expect(env.defaultClassProperty("Widget", "Archivable")):toBe(true)
		expect(env.liveObjects()):toBe(before)
		expect((pcall(env.defaultClassProperty, "Missing", "Count"))):toBe(false)
		expect((pcall(env.defaultClassProperty, "Widget", "Missing"))):toBe(false)
	end)
	it("checked instance lookup preserves identity and rejects unregistered values", function()
		local env = environment()
		local widget = env.createInstance "Widget"
		local value: unknown = widget
		local instance = Roblox.assertInstance(value)
		expect(instance):toBe(widget)
		env.poke(instance, "Count", 7)
		expect(widget.Count):toBe(7)
		widget:Destroy()
		expect(Roblox.assertInstance(value)):toBe(widget)
		local invalidValues: { unknown } =
			{ false, 1, "Instance", {}, { ClassName = "Widget" }, Datatypes.Vector2.zero }
		for _, invalid in invalidValues do
			expect(thrown(function()
				Roblox.assertInstance(invalid)
			end)):toContain "expected a simulated Instance"
		end
		expect(thrown(function()
			Roblox.assertInstance(nil)
		end)):toContain "expected a simulated Instance"
	end)
	it("native signal and connection type identity belongs only to authoritative signals", function()
		local env = environment()
		local signal = env.newSignal()
		local connection = signal:Connect(function() end)
		expect(Environment.typeName(signal)):toBe "RBXScriptSignal"
		expect(Environment.typeName(connection)):toBe "RBXScriptConnection"
		expect(Environment.typeName(env.heartbeat)):toBe "RBXScriptSignal"
		local widget = env.createInstance "Widget"
		expect(Environment.typeName(widget.Pinged)):toBe "RBXScriptSignal"
		expect(Environment.typeName { Connect = function() end, Wait = function() end }):toBe "table"
		expect(Environment.typeName { Connect = signal.Connect, Wait = signal.Wait }):toBe "table"
		expect(Environment.typeName { Connected = true, Disconnect = connection.Disconnect }):toBe "table"
		connection:Disconnect()
		expect(Environment.typeName(connection)):toBe "RBXScriptConnection"
		expect(env.liveConnections()):toBe(0)
		widget:Destroy()
		expect(Environment.typeName(widget)):toBe "Instance"
		expect(Environment.isInstance(widget)):toBe(true)
	end)
	it("Studio 0.744 Objects inherit only Object members and use environment-owned cleanup", function()
		local options: Environment.Options = {
			classes = { VirtualInput = { super = "Object", creatable = false } },
		}
		local env = Environment.create(options)
		local object = env.createEngineObject "VirtualInput"
		expect(object.ClassName):toBe "VirtualInput"
		expect(object:IsA "VirtualInput"):toBe(true)
		expect(object:IsA "Object"):toBe(true)
		expect(object:IsA "Instance"):toBe(false)
		expect(Environment.isInstance(object)):toBe(false)
		expect(thrown(function()
			Roblox.assertInstance(object)
		end)):toContain "expected a simulated Instance"
		local members = (object :: unknown) :: { [string]: unknown }
		for _, name in { "Name", "Archivable", "Parent", "Destroy", "GetChildren", "ChildAdded", "Destroying" } do
			expect(thrown(function(): unknown
				return members[name]
			end)):toContain "not a valid member"
		end
		expect(thrown(function()
			members.Parent = env.root
		end)):toContain "not a valid member"
		expect(thrown(function()
			env.createInstance "VirtualInput"
		end)):toContain "Unable to create"
		expect(thrown(function()
			env.createEngineInstance "VirtualInput"
		end)):toContain "requires an Instance class"
		expect(thrown(function()
			env.createEngineObject "Missing"
		end)):toContain "Unable to create"
		expect(Environment.typeName(object)):toBe "Object"
		local changed = object.Changed:Connect(function() end)
		local signal = object:GetPropertyChangedSignal "ClassName"
		expect(signal):toBe(object:GetPropertyChangedSignal "ClassName")
		expect(env.liveConnections()):toBe(1)
		expect(env.liveObjects()):toBe(1)
		local other = Environment.create()
		expect(thrown(function()
			other.releaseObject(object)
		end)):toContain "must belong to this environment"
		env.releaseObject(object)
		env.releaseObject(object)
		expect(Environment.typeName(object)):toBe "Object"
		expect(Environment.isInstance(object)):toBe(false)
		expect(changed.Connected):toBe(false)
		expect(env.liveConnections()):toBe(0)
		expect(env.liveObjects()):toBe(0)
	end)
	it("scoped method doubles restore active predecessors without resurrecting disposed layers", function()
		local env = environment()
		local object = env.createInstance "Folder"
		local baseline = env.fakeOn(object, "Read", function(): number
			return 1
		end)
		local first = env.fakeOn(object, "Read", function(): number
			return 2
		end)
		local second = env.fakeOn(object, "Read", function(): number
			return 3
		end)
		local function read(): unknown
			return (object.Read :: Environment.Method)(object)
		end
		expect(read()):toEqual(3)
		first()
		expect(read()):toEqual(3)
		second()
		expect(read()):toEqual(1)
		second()
		first()
		expect(read()):toEqual(1)
		baseline()
		expect((pcall(read))):toEqual(false)
	end)
	it("scoped method cleanup preserves a later explicit method assignment", function()
		local env = Environment.create { functionDoubles = true }
		local object = env.createInstance "Folder"
		object.Read = function(): number
			return 7
		end
		local dispose = env.fakeOn(object, "Read", function(): number
			return 9
		end)
		object.Read = function(): number
			return 11
		end
		dispose()
		expect((object.Read :: Environment.Method)(object)):toEqual(11)
	end)
	it("yielding signal listeners do not suspend the emitter or other listeners", function()
		local env = environment()
		local signal: Environment.Signal<number> = env.newSignal()
		local waiting: thread? = nil
		local completed, observed = 0, 0
		signal:Connect(function(value: number)
			env.scheduler.block(function(thread: thread)
				waiting = thread
			end)
			completed = value
		end)
		signal:Connect(function(value: number)
			observed = value
		end)
		signal:Fire(7)
		expect(observed):toBe(7)
		expect(completed):toBe(0)
		signal:DisconnectAll()
		env.scheduler.resume(assert(waiting))
		env.scheduler.drain(20)
		expect(completed):toBe(7)
		expect(env.scheduler.failures):toHaveLength(0)
	end)
	it("Signal.Wait returns the next argument tuple once including nil values", function()
		local env = environment()
		local signal: Environment.Signal = env.newSignal()
		signal:Fire "past"
		local result: { [number]: unknown, n: number }? = nil
		local waiter = env.task.spawn(function()
			result = table.pack(signal:Wait())
		end)
		env.scheduler.drain(20)
		expect(result):toEqual(nil)
		expect(env.liveConnections()):toEqual(1)
		signal:Fire("next", nil, 3, nil)
		signal:Fire "later"
		expect(env.liveConnections()):toEqual(0)
		env.scheduler.drain(20)
		local values = assert(result)
		expect(values.n):toEqual(4)
		expect(values[1]):toEqual "next"
		expect(values[2]):toEqual(nil)
		expect(values[3]):toEqual(3)
		expect(values[4]):toEqual(nil)
		expect(coroutine.status(waiter)):toEqual "dead"
		expect(env.scheduler.failures):toHaveLength(0)
	end)
	it("canceling Signal.Wait releases its listener before any future event", function()
		local env = environment()
		local signal: Environment.Signal = env.newSignal()
		local resumed = false
		local waiter = env.task.spawn(function()
			signal:Wait()
			resumed = true
		end)
		env.scheduler.drain(20)
		expect(env.liveConnections()):toEqual(1)
		env.task.cancel(waiter)
		expect(env.liveConnections()):toEqual(0)
		signal:Fire(1)
		env.scheduler.drain(20)
		expect(resumed):toEqual(false)
		expect(env.scheduler.failures):toHaveLength(0)
		expect(env.scheduler.pending()):toEqual(0)
	end)
	it("Signal.Wait resumes all current waiters with their own scheduler context", function()
		local env = environment()
		local signal: Environment.Signal = env.newSignal()
		local results: { string } = {}
		for _, tag in { "first", "second" } do
			env.scheduler.spawnTagged(tag, function()
				local value = signal:Wait()
				table.insert(results, tostring(env.scheduler.context()) .. ":" .. tostring(value))
			end)
		end
		env.scheduler.drain(20)
		signal:Fire(7)
		env.scheduler.drain(20)
		expect(results):toEqual { "first:7", "second:7" }
		expect(env.liveConnections()):toEqual(0)
	end)
	it("scheduler block cleanup runs once on resume and cancel", function()
		local env = environment()
		local cleanups, completed = 0, false
		local waiter = env.task.spawn(function()
			env.scheduler.block(function()
				return function()
					cleanups += 1
				end
			end)
			completed = true
		end)
		env.scheduler.resume(waiter)
		expect(cleanups):toBe(1)
		env.step(0)
		expect(completed):toBe(true)
		env.task.cancel(waiter)
		expect(cleanups):toBe(1)
		local canceled = env.task.spawn(function()
			env.scheduler.block(function()
				return function()
					cleanups += 1
				end
			end)
		end)
		env.task.cancel(canceled)
		env.task.cancel(canceled)
		expect(cleanups):toBe(2)
		expect(#env.scheduler.failures):toBe(0)
	end)

	it("scheduler block releases cleanup when registration synchronously queues its waiter", function()
		local env = environment()
		local cleanups, completed = 0, false
		env.task.spawn(function()
			env.scheduler.block(function(waiter: thread)
				env.scheduler.resume(waiter)
				return function()
					cleanups += 1
				end
			end)
			completed = true
		end)
		env.step(0)
		expect(completed):toBe(true)
		expect(cleanups):toBe(1)
	end)

	it("scheduler cancellation still closes a waiter when its cleanup fails", function()
		local env = environment()
		local waiter = env.task.spawn(function()
			env.scheduler.block(function()
				return function()
					error "cleanup fixture failure"
				end
			end)
		end)
		env.task.cancel(waiter)
		expect(coroutine.status(waiter)):toBe "dead"
		expect(#env.scheduler.failures):toBe(1)
		expect(env.scheduler.failures[1]):toContain "cleanup fixture failure"
	end)
	it("propertyOf inspects declared callbacks while instance reads remain forbidden", function()
		local env = environment()
		local callbackProperties: { [string]: unknown } = { OnInvoke = false }
		local callbackAccess: { [string]: "read" | "write" | "callback" | "none" } = { OnInvoke = "callback" }
		local callbackClass: Environment.ClassSpec = {
			super = "Instance",
			properties = callbackProperties,
			access = callbackAccess,
		}
		env.defineClass("CallbackFixture", callbackClass)
		local object = env.createInstance "CallbackFixture"
		local callback = function(): number
			return 42
		end
		object.OnInvoke = callback
		expect(env.propertyOf(object, "OnInvoke") == callback):toBe(true)
		expect(thrown(function()
			return object.OnInvoke
		end)):toContain "you can only set the callback value"
		env.fakeOn(object, "Handler", callback)
		expect(env.propertyOf(object, "Handler")):toBe(nil)
	end)
	it("computed lookup honors an empty table with a dynamic getter", function()
		local computed: { [string]: Environment.Computed } = {}
		local settings: Environment.Options = { computed = computed }
		setmetatable(computed, {
			__index = function(_: unknown, key: string): Environment.Computed?
				if key == "Folder.Count" then
					return function(): unknown
						return 7
					end
				end
				return nil
			end,
		})
		local env = Environment.create(settings)
		expect(env.createInstance("Folder").Count):toEqual(7)
	end)

	it("a frozen computed table caches lookups until a class changes inheritance", function()
		local computed: { [string]: Environment.Computed } = {
			["Folder.Count"] = function(): unknown
				return 1
			end,
			["Basis.Count"] = function(): unknown
				return 2
			end,
		}
		local env = Environment.create { computed = table.freeze(computed) }
		env.defineClass("Basis", { super = "Folder", properties = { Count = 0 } })
		env.defineClass("Probe", { super = "Folder", properties = { Count = 0 } })
		local probe = env.createInstance "Probe"
		expect(probe.Count):toEqual(1)
		expect(probe.Count):toEqual(1)
		env.defineClass("Probe", { super = "Basis", properties = { Count = 0 } }, { replace = true })
		expect(env.createInstance("Probe").Count):toEqual(2)
	end)

	it("computed lookup sees replacement, removal and changed inheritance", function()
		local computed: { [string]: Environment.Computed } = {}
		local env = Environment.create { computed = computed }
		env.defineClass("Probe", { super = "Folder", properties = { Count = 0 } })
		local probe = env.createInstance "Probe"
		expect(probe.Count):toEqual(0)
		computed["Folder.Count"] = function(): unknown
			return 1
		end
		expect(probe.Count):toEqual(1)
		expect(thrown(function()
			probe.Count = 2
		end)):toContain "read-only"
		local entry = {
			get = function(): unknown
				return nil
			end,
			writable = true,
		}
		computed["Folder.Count"] = entry
		probe.Count = 2
		expect(probe.Count):toEqual(2)
		entry.writable = false
		expect(probe.Count):toEqual(nil)
		computed["Folder.Count"] = nil
		probe.Count = 3
		expect(probe.Count):toEqual(3)
		computed["Basis.Count"] = function(): unknown
			return 4
		end
		env.defineClass("Probe", { super = "Basis", properties = { Count = 0 } }, { replace = true })
		expect(probe.Count):toEqual(4)
	end)

	it("retains unobserved fires when signals are first read and connected", function()
		local env = environment()
		local widget = env.createInstance "Widget"
		widget.Count = 1
		widget.Count = 2
		widget:SetAttribute("Probe", 1)
		env.fire(widget, "Pinged", "before")
		local changed = widget:GetPropertyChangedSignal "Count"
		local attribute = widget:GetAttributeChangedSignal "Probe"
		local pinged = widget.Pinged :: Environment.Signal
		expect(env.firesOf(changed)):toEqual(2)
		expect(env.firesOf(attribute)):toEqual(1)
		expect(env.signalOf(widget, "Pinged").fires()):toEqual(1)
		expect(env.liveConnections()):toEqual(0)
		local calls: { string } = {}
		changed:Connect(function()
			table.insert(calls, "property")
		end)
		attribute:Connect(function()
			table.insert(calls, "attribute")
		end)
		local connection = pinged:Connect(function(value: unknown)
			table.insert(calls, tostring(value))
		end)
		expect(calls):toEqual {}
		widget.Count = 3
		widget:SetAttribute("Probe", 2)
		env.fire(widget, "Pinged", "after")
		expect(calls):toEqual { "property", "attribute", "after" }
		expect(env.firesOf(changed)):toEqual(3)
		widget:Destroy()
		expect(connection.Connected):toEqual(false)
		expect(env.liveConnections()):toEqual(0)
		expect(env.signalOf(widget, "Destroying").fires()):toEqual(1)
	end)

	it("materializes a later signal during an earlier notification", function()
		local env = environment()
		local widget = env.createInstance "Widget"
		widget.Count = 1
		local changes: { string } = {}
		widget:GetPropertyChangedSignal("Count"):Connect(function()
			expect(env.signalOf(widget, "Changed").fires()):toEqual(1)
			widget.Changed:Connect(function(property: string)
				table.insert(changes, property)
			end)
		end)
		widget.Count = 2
		expect(changes):toEqual { "Count" }
		expect(env.signalOf(widget, "Changed").fires()):toEqual(2)
	end)

	it("retains unobserved hierarchy fires through removal and destruction", function()
		local env = environment()
		local parent = env.createInstance "Folder"
		local child = env.createInstance("Folder", { Parent = parent })
		child.Parent = nil
		expect(env.signalOf(parent, "ChildAdded").fires()):toEqual(1)
		expect(env.signalOf(parent, "ChildRemoved").fires()):toEqual(1)
		expect(env.signalOf(parent, "DescendantAdded").fires()):toEqual(1)
		expect(env.signalOf(parent, "DescendantRemoving").fires()):toEqual(1)
		expect(env.signalOf(child, "AncestryChanged").fires()):toEqual(2)
		expect(env.firesOf(child:GetPropertyChangedSignal "Parent")):toEqual(2)
		child:Destroy()
		expect(env.signalOf(child, "Destroying").fires()):toEqual(1)
	end)

	it("lets a class override a builtin with its own method", function()
		local env = environment()
		local calls = 0
		env.defineClass("Probe", {
			super = "Instance",
			methods = {
				Clone = function(): number
					calls += 1
					return calls
				end,
			},
		})
		local probe = env.createInstance "Probe"
		expect(((probe.Clone :: unknown) :: (Environment.Instance) -> number)(probe)):toEqual(1)
		expect(calls):toEqual(1)
		expect(env.createInstance("Folder"):Clone() ~= nil):toEqual(true)
	end)

	it("clones archivable trees and remaps only internal instance references", function()
		local env = environment()
		env.defineClass("Link", { super = "Instance", properties = { Target = false } })
		local root = env.createInstance "Model"
		local child = env.createInstance("Link", { Parent = root })
		local external = env.createInstance "Folder"
		local excluded = env.createInstance("Folder", { Parent = root, Archivable = false })
		local sibling = env.createInstance("Link", { Parent = root, Target = external })
		child.Target = sibling
		root.PrimaryPart = child
		child:SetAttribute("Count", 3)
		child:AddTag "selected"
		local clone = root:Clone()
		assert(clone)
		local children = clone:GetChildren()
		expect(#children):toEqual(2)
		expect(clone.Parent == nil and clone.PrimaryPart == children[1]):toEqual(true)
		expect(children[1].Target == children[2]):toEqual(true)
		expect(children[2].Target == external):toEqual(true)
		expect(children[1]:GetAttribute "Count"):toEqual(3)
		expect(children[1]:HasTag "selected"):toEqual(true)
		children[1]:RemoveTag "selected"
		expect(child:HasTag "selected"):toEqual(true)
		expect(excluded:Clone()):toEqual(nil)
		clone:Destroy()
		expect(env.isAlive(child)):toEqual(true)
	end)

	it("recursive class lookup and ancestor lookup distinguish inheritance", function()
		local env = environment()
		env.defineClass("Special", { super = "Widget" })
		local parent = env.createInstance("Special", { Parent = env.root })
		local folder = env.createInstance("Folder", { Parent = parent })
		local child = env.createInstance("Special", { Parent = folder })
		expect(parent:FindFirstChildWhichIsA "Widget"):toEqual(nil)
		expect(parent:FindFirstChildWhichIsA("Widget", true) == child):toEqual(true)
		expect(child:FindFirstAncestorWhichIsA "Widget" == parent):toEqual(true)
		expect(child:FindFirstAncestorOfClass "Widget"):toEqual(nil)
		expect(child:FindFirstAncestorOfClass "Special" == parent):toEqual(true)
	end)

	it("creates declared classes with inherited defaults and refuses undeclared members", function()
		local env = environment()
		local widget = (env.createInstance("Widget", { Label = "go" }))
		expect(widget.ClassName):toEqual "Widget"
		expect(widget.Name):toEqual "Widget"
		expect(widget.Label):toEqual "go"
		expect(widget.Count):toEqual(0)
		expect(widget:IsA "Instance"):toEqual(true)
		expect(thrown(function()
			return env.createInstance "Missing"
		end)):toContain 'Unable to create an Instance of type "Missing"'
		expect(thrown(function()
			return env.createInstance "Instance"
		end)):toContain 'Unable to create an Instance of type "Instance"'
		expect(thrown(function()
			widget.Lable = "x"
		end)):toContain 'Lable is not a valid member of Widget "Widget"'
	end)

	it("reading an unknown name returns the first child with that name, as the engine does", function()
		local env = environment()
		local parent = (env.createInstance("Widget", { Parent = env.root }))
		local first = (env.createInstance("Folder", { Name = "Slot", Parent = parent }))
		env.createInstance("Folder", { Name = "Slot", Parent = parent })
		local other = (env.createInstance("Folder", { Name = "Other", Parent = parent }))
		expect(parent.Slot == first):toEqual(true)
		local key = "Other"
		expect(parent[key] == other):toEqual(true)
		expect(parent:FindFirstChild "Slot" == first):toEqual(true)
		expect(parent:FindFirstChild "Absent"):toEqual(nil)
		expect(thrown(function()
			return parent.Absent
		end)):toContain 'Absent is not a valid member of Widget "Widget"'
		expect(parent:WaitForChild "Slot" == first):toBe(true)
	end)

	it("WaitForChild returns an existing direct child without yielding or scheduling", function()
		local env = environment()
		local parent = env.createInstance "Folder"
		local child = env.createInstance("Folder", { Name = "Ready", Parent = parent })
		expect(parent:WaitForChild("Ready", 1) == child):toBe(true)
		expect(env.scheduler.pending()):toBe(0)
		expect(env.liveConnections()):toBe(0)
	end)

	it("matches Studio 0.744 rejection of nonpositive WaitForChild timeouts", function()
		local env = environment()
		local parent = env.createInstance "Folder"
		for _, timeout in { 0, -1 } do
			expect(thrown(function()
				parent:WaitForChild("Ready", timeout)
			end)):toContain "illegal argument #2 (timeOut must be greater than 0)"
		end
		env.createInstance("Folder", { Name = "Ready", Parent = parent })
		expect(thrown(function()
			parent:WaitForChild("Ready", 0)
		end)):toContain "illegal argument #2 (timeOut must be greater than 0)"
		expect(env.liveConnections()):toBe(0)
	end)

	it("matches Studio 0.744 WaitForChild waking when an existing child is renamed", function()
		local env = environment()
		local parent = env.createInstance "Folder"
		local child = env.createInstance("Folder", { Name = "Other", Parent = parent })
		local result: Environment.Instance?
		env.task.spawn(function()
			result = parent:WaitForChild("Ready", 2)
		end)
		child.Name = "Ready"
		env.step(0)
		expect(result == child):toBe(true)
		expect(env.liveConnections()):toBe(0)
		expect(env.scheduler.pending()):toBe(0)
	end)

	it("WaitForChild observes newly added child renames and detaches removed children", function()
		local env = environment()
		local parent = env.createInstance "Folder"
		local result: Environment.Instance?
		env.task.spawn(function()
			result = parent:WaitForChild("Ready", 2)
		end)
		local removed = env.createInstance("Folder", { Name = "Other", Parent = parent })
		removed.Parent = nil
		removed.Name = "Ready"
		env.step(0)
		expect(result):toBe(nil)
		local child = env.createInstance("Folder", { Name = "Other", Parent = parent })
		child.Name = "Ready"
		env.step(0)
		expect(result == child):toBe(true)
		expect(env.liveConnections()):toBe(0)
	end)

	it("WaitForChild yields for its named direct child and cancels its timeout", function()
		local env = environment()
		local parent = env.createInstance "Folder"
		local result: Environment.Instance?
		local completed = false
		env.task.spawn(function()
			result = parent:WaitForChild("Ready", 10)
			completed = true
		end)
		local other = env.createInstance("Folder", { Name = "Other", Parent = parent })
		env.createInstance("Folder", { Name = "Ready", Parent = other })
		env.step(1)
		expect(completed):toBe(false)
		local child = env.createInstance("Folder", { Name = "Ready", Parent = parent })
		env.step(0)
		expect(result == child):toBe(true)
		expect(completed):toBe(true)
		expect(env.scheduler.pending()):toBe(0)
		expect(env.liveConnections()):toBe(0)
	end)

	it("WaitForChild timeout returns nil once and disconnects its listener", function()
		local env = environment()
		local parent = env.createInstance "Folder"
		local result: Environment.Instance? = parent
		local completions = 0
		env.task.spawn(function()
			result = parent:WaitForChild("Ready", 2)
			completions += 1
		end)
		env.step(1)
		expect(completions):toBe(0)
		env.step(1)
		expect(result):toBe(nil)
		expect(completions):toBe(1)
		env.createInstance("Folder", { Name = "Ready", Parent = parent })
		env.step(10)
		expect(completions):toBe(1)
		expect(env.liveConnections()):toBe(0)
	end)

	it("WaitForChild with nil timeout stays suspended until the named child arrives", function()
		local env = environment()
		local parent = env.createInstance "Folder"
		local result: Environment.Instance?
		env.task.spawn(function()
			result = parent:WaitForChild("Ready", nil)
		end)
		env.step(20)
		expect(result):toBe(nil)
		local child = env.createInstance("Folder", { Name = "Ready", Parent = parent })
		env.step(0)
		expect(result == child):toBe(true)
		expect(env.liveConnections()):toBe(0)
	end)

	it("a canceled WaitForChild is not resumed when its child arrives", function()
		local env = environment()
		local parent = env.createInstance "Folder"
		local resumed = false
		local waiter = env.task.spawn(function()
			parent:WaitForChild "Ready"
			resumed = true
		end)
		env.task.cancel(waiter)
		expect(env.liveConnections()):toBe(0)
		env.createInstance("Folder", { Name = "Ready", Parent = parent })
		env.step(0)
		expect(resumed):toBe(false)
		expect(#env.scheduler.failures):toBe(0)
		expect(env.liveConnections()):toBe(0)
		expect(env.scheduler.pending()):toBe(0)
	end)

	it("a canceled WaitForChild timeout releases its listeners without resuming the thread", function()
		local env = environment()
		local parent = env.createInstance "Folder"
		local resumed = false
		local waiter = env.task.spawn(function()
			parent:WaitForChild("Ready", 1)
			resumed = true
		end)
		env.task.cancel(waiter)
		expect(env.liveConnections()):toBe(0)
		expect(env.scheduler.pending()):toBe(0)
		env.step(1)
		expect(resumed):toBe(false)
		expect(#env.scheduler.failures):toBe(0)
		expect(env.liveConnections()):toBe(0)
		expect(env.scheduler.pending()):toBe(0)
	end)

	it("a property, event or method wins over a child of the same name", function()
		local env = environment()
		local parent = (env.createInstance("Widget", { Label = "own", Parent = env.root })) :: Fixture
		env.createInstance("Folder", { Name = "Label", Parent = parent })
		env.createInstance("Folder", { Name = "Pinged", Parent = parent })
		env.createInstance("Folder", { Name = "Double", Parent = parent })
		env.createInstance("Folder", { Name = "Destroy", Parent = parent })
		expect(parent.Label):toEqual "own"
		expect((parent.Pinged).Connect ~= nil):toEqual(true)
		expect((parent.Double :: (Environment.Instance, number) -> number)(parent, 1)):toEqual(2)
		expect(type(parent.Destroy)):toEqual "function"
		expect(parent.ClassName):toEqual "Widget"
	end)

	it("a renamed, destroyed or reparented child is found only while it holds that name and parent", function()
		local env = environment()
		local parent = (env.createInstance("Widget", { Parent = env.root }))
		local elsewhere = (env.createInstance("Widget", { Parent = env.root }))
		local child = (env.createInstance("Folder", { Name = "Before", Parent = parent }))
		expect(parent.Before == child):toEqual(true)
		child.Name = "After"
		expect(parent.After == child):toEqual(true)
		expect(thrown(function()
			return parent.Before
		end)):toContain "Before is not a valid member"
		child.Parent = elsewhere
		expect(thrown(function()
			return parent.After
		end)):toContain "After is not a valid member"
		expect(elsewhere.After == child):toEqual(true)
		child:Destroy()
		expect(thrown(function()
			return elsewhere.After
		end)):toContain "After is not a valid member"
	end)

	it("writing an unknown name stays an error even when a child has that name", function()
		local env = environment()
		local parent = (env.createInstance("Widget", { Parent = env.root }))
		env.createInstance("Folder", { Name = "Slot", Parent = parent })
		expect(thrown(function()
			parent.Slot = env.createInstance "Folder"
		end)):toContain 'Slot is not a valid member of Widget "Widget"'
	end)

	it("a builtin class is redefined only on explicit request", function()
		local env = environment()
		expect(thrown(function()
			env.defineClass("Frame", { super = "GuiObject", properties = { Extra = 1 } })
		end)):toContain 'class "Frame" is already defined'
		env.defineClass("Frame", { super = "GuiObject", properties = { Extra = 1 } }, { replace = true })
		local frame = (env.createInstance "Frame")
		expect(frame.Extra):toEqual(1)
		expect(frame.Visible):toEqual(true)
		env.defineClass("Fresh", { super = "Instance" }, { replace = true })
		expect(env.createInstance("Fresh").ClassName):toEqual "Fresh"
	end)

	it("a declared method needs a simulation or a configured fake and never invents a result", function()
		local env = environment()
		local widget = (env.createInstance "Widget")
		expect((widget.Double :: (Environment.Instance, number) -> number)(widget, 4)):toEqual(8)
		expect(thrown(function()
			return (widget.Ping :: (Environment.Instance) -> unknown)(widget)
		end)):toContain "unsupported_method: Widget.Ping is declared but has no simulation or configured fake"
		env.fake("Widget.Ping", function(): string
			return "pong"
		end)
		expect((widget.Ping :: (Environment.Instance) -> unknown)(widget)):toEqual "pong"
		local settings = {
			classes = { Widget = { super = "Instance", methods = { Ping = true } } },
			fakes = {
				["Widget.Ping"] = function(): number
					return 7
				end,
			},
		}
		local configured = Roblox.testEnvironment((settings :: unknown) :: Roblox.EnvironmentOptions)
		local configuredWidget = configured.createInstance "Widget"
		expect((configuredWidget.Ping :: (Environment.Instance) -> unknown)(configuredWidget)):toEqual(7)
	end)

	it("opt-in defaults preserve false and allocate fresh property values per instance", function()
		local env = Roblox.testEnvironment {
			classes = { Record = { super = "Instance", properties = { Data = {} } } },
			defaultProperty = function(_className: string, property: string, fallback: unknown): unknown
				if property == "Visible" then
					return false
				elseif property == "Data" then
					return {}
				end
				return fallback
			end,
		}
		expect(env.createInstance("Frame").Visible):toEqual(false)
		local first = (env.createInstance "Record") :: Fixture
		local second = (env.createInstance "Record") :: Fixture
		first.Data.Key = "first"
		expect(second.Data.Key):toEqual(nil)
		expect(first.Name):toEqual "Record"
	end)

	it("opt-in validation rejects writes before mutation and distinguishes engine-side poke", function()
		local env = Roblox.testEnvironment {
			classes = { Record = { super = "Instance", properties = { Count = 0, Label = "" } } },
			validateProperty = function(
				_className: string,
				property: string,
				value: unknown,
				operation: "set" | "poke"
			)
				if property == "Count" and type(value) ~= "number" then
					error "Count requires a number"
				elseif property == "Label" then
					if type(value) ~= "string" then
						error "Label requires a string"
					elseif operation == "set" then
						error "Label is read-only"
					end
				end
			end,
		}
		local record = (env.createInstance "Record")
		local changed = 0
		record.Changed:Connect(function()
			changed += 1
		end)
		expect(thrown(function()
			(assert(record)).Count = "wrong"
		end)):toContain "Count requires a number"
		expect(thrown(function()
			record.Label = "wrong"
		end)):toContain "Label is read-only"
		expect(record.Count):toEqual(0)
		expect(record.Label):toEqual ""
		expect(changed):toEqual(0)
		env.poke(record, "Label", "engine")
		expect(thrown(function()
			env.poke(record, "Label", false)
		end)):toContain "Label requires a string"
		expect(record.Label):toEqual "engine"
		expect(changed):toEqual(1)
	end)

	it("Parent validation preserves ancestry safety and rejects a move before its events", function()
		local forbidden: Environment.Instance? = nil
		local env = Roblox.testEnvironment {
			validateProperty = function(
				_className: string,
				property: string,
				value: unknown,
				_operation: "set" | "poke"
			)
				if property == "Parent" and value == forbidden then
					error "destination refused"
				end
			end,
		}
		local previous = (env.createInstance "Folder")
		forbidden = env.createInstance "Folder"
		local branch = (env.createInstance("Folder", { Parent = previous }))
		local events = 0
		previous.DescendantRemoving:Connect(function()
			events += 1
		end)
		branch.AncestryChanged:Connect(function()
			events += 1
		end)
		expect(thrown(function()
			branch.Parent = forbidden
		end)):toContain "destination refused"
		expect(thrown(function()
			branch.Parent = branch
		end)):toContain "own ancestor"
		expect(branch.Parent == previous):toEqual(true)
		expect(events):toEqual(0)
	end)

	it("explicit fixture methods supply measurement, focus and style behavior", function()
		local env = environment()
		env.defineClass("TextService", { super = "Instance", methods = { GetTextSize = true } })
		env.fake(
			"TextService.GetTextSize",
			function(_self: Environment.Instance, text: string, size: number): Datatypes.Vector2Value
				return Roblox.datatypes.Vector2.new(#text * size, size)
			end
		)
		env.defineClass("FixtureControl", {
			super = "Widget",
			properties = { CanFocus = true, HasFocus = false, Style = "plain" },
			methods = {
				CaptureFocus = function(self: Fixture)
					if not self.CanFocus then
						error "focus is disabled"
					end
					self.HasFocus = true
				end,
				ApplyStyle = function(self: Fixture, style: string)
					self.Style = style
				end,
			},
		})
		local service = (env.createInstance "TextService")
		expect(
			(service.GetTextSize :: (Environment.Instance, string, number) -> Datatypes.Vector2Value)(service, "abc", 2)
				== Roblox.datatypes.Vector2.new(6, 2)
		):toEqual(true)
		local control = (env.createInstance("FixtureControl", { Label = "source", CanFocus = false }))
		expect(thrown(function()
			(control.CaptureFocus :: (Environment.Instance) -> ())(control)
		end)):toContain "focus is disabled"
		control.CanFocus = true
		local focus = control.CaptureFocus :: (Environment.Instance) -> ()
		local apply = control.ApplyStyle :: (Environment.Instance, string) -> ()
		focus(control)
		apply(control, "accent")
		local copy = (control.Clone :: (Environment.Instance) -> Fixture)(control)
		expect(control.HasFocus):toEqual(true)
		expect(copy ~= control and copy.Parent == nil):toEqual(true)
		expect(copy.Label):toEqual "source"
		expect(copy.Style):toEqual "accent"
		copy.Label = "copy"
		expect(control.Label):toEqual "source"
	end)

	it("fires signals in connect order and honors a disconnect made during the fire", function()
		local env = environment()
		local signal = env.newSignal()
		local order: { string } = {}
		local second: Roblox.Connection
		signal:Connect(function()
			table.insert(order, "first")
			second:Disconnect()
		end)
		second = signal:Connect(function()
			table.insert(order, "second")
		end)
		signal:Connect(function()
			table.insert(order, "third")
		end)
		signal:Fire()
		expect(order):toEqual { "first", "third" }
		expect(second.Connected):toEqual(false)
		expect(env.liveConnections()):toEqual(2)
	end)

	it("a failing handler does not stop later handlers and is recorded", function()
		local env = environment()
		local signal = env.newSignal()
		local reached = false
		signal:Connect(function()
			error "handler broke"
		end)
		signal:Connect(function()
			reached = true
		end)
		signal:Fire()
		expect(reached):toEqual(true)
		expect(env.errors[1]):toContain "handler broke"
	end)

	it("reparenting reports child events and Destroy locks, disconnects and cascades", function()
		local env = environment()
		local parent = (env.createInstance("Folder", { Parent = env.root }))
		local seen: { string } = {}
		parent.ChildAdded:Connect(function(child: Environment.Instance)
			table.insert(seen, "added " .. tostring(child.Name))
		end)
		parent.ChildRemoved:Connect(function(child: Environment.Instance)
			table.insert(seen, "removed " .. tostring(child.Name))
		end)
		local child = (env.createInstance("Widget", { Name = "w", Parent = parent }))
		local grandchild = (env.createInstance("Folder", { Name = "g", Parent = child }))
		local destroyed = 0
		child.Destroying:Connect(function()
			destroyed += 1
		end)
		expect(env.liveObjects()).never:toEqual(0)
		child:Destroy()
		expect(seen):toEqual { "added w", "removed w" }
		expect(destroyed):toEqual(1)
		expect(env.isAlive(child)):toEqual(false)
		expect(env.isAlive(grandchild)):toEqual(false)
		expect(child.Parent):toEqual(nil)
		expect(thrown(function()
			child.Parent = parent
		end)):toContain "locked"
		child:Destroy()
		expect(#parent:GetChildren()):toEqual(0)
	end)

	it("subtree parenting notifies every gained ancestor after the final parent is visible", function()
		local env = environment()
		local destination = (env.createInstance("Folder", { Parent = env.root }))
		local branch = (env.createInstance "Folder")
		local child = assert((env.createInstance("Folder", { Parent = branch })))
		local leaf = assert((env.createInstance("Folder", { Parent = child })))
		local added: { Environment.Instance } = {}
		local rootAdded: { Environment.Instance } = {}
		local ancestry: { { object: Environment.Instance, moved: Environment.Instance, parent: Environment.Instance? } } =
			{}
		destination.DescendantAdded:Connect(function(object: Environment.Instance)
			expect(branch.Parent == destination):toEqual(true)
			expect(object:IsDescendantOf(destination)):toEqual(true)
			table.insert(added, object)
		end)
		env.root.DescendantAdded:Connect(function(object: Environment.Instance)
			table.insert(rootAdded, object)
		end)
		for _, object in { branch, child, leaf } do
			object.AncestryChanged:Connect(function(moved: Environment.Instance, parent: Environment.Instance?)
				expect(branch.Parent == parent):toEqual(true)
				table.insert(ancestry, { object = object, moved = moved, parent = parent })
			end)
		end
		branch.Parent = destination
		expect(#added):toEqual(3)
		expect(#rootAdded):toEqual(3)
		expect(#ancestry):toEqual(3)
		for _, object in { branch, child, leaf } do
			expect(table.find(added, object) ~= nil):toEqual(true)
			expect(table.find(rootAdded, object) ~= nil):toEqual(true)
		end
		for _, record in ancestry do
			expect(record.moved == branch and record.parent == destination):toEqual(true)
		end
		branch.Parent = destination
		expect(#ancestry):toEqual(3)
		expect(#env.errors):toEqual(0)
	end)

	it("reparenting removes the subtree before mutation and notifies only lost or gained ancestors", function()
		local env = environment()
		local previous = (env.createInstance("Folder", { Parent = env.root }))
		local destination = (env.createInstance("Folder", { Parent = env.root }))
		local branch = (env.createInstance("Folder", { Parent = previous }))
		local child = (env.createInstance("Folder", { Parent = branch }))
		local removals: { Environment.Instance } = {}
		local additions: { Environment.Instance } = {}
		local events: { string } = {}
		local shared = 0
		previous.DescendantRemoving:Connect(function(object: Environment.Instance)
			expect(branch.Parent == previous):toEqual(true)
			expect(child.Parent == branch):toEqual(true)
			expect(object:IsDescendantOf(previous)):toEqual(true)
			table.insert(removals, object)
			table.insert(events, "removing")
			expect(thrown(function()
				object.Parent = env.root
			end)):toContain "locked"
		end)
		previous.ChildRemoved:Connect(function(object: Environment.Instance)
			expect(object == branch and object.Parent == destination):toEqual(true)
			expect(previous:FindFirstChild(tostring(branch.Name))):toEqual(nil)
			table.insert(events, "removed")
		end)
		destination.ChildAdded:Connect(function(object: Environment.Instance)
			expect(object == branch and object.Parent == destination):toEqual(true)
		end)
		destination.DescendantAdded:Connect(function(object: Environment.Instance)
			table.insert(additions, object)
		end)
		env.root.DescendantRemoving:Connect(function()
			shared += 1
		end)
		env.root.DescendantAdded:Connect(function()
			shared += 1
		end)
		branch.Parent = destination
		expect(removals[1] == branch and removals[2] == child):toEqual(true)
		expect(#removals):toEqual(2)
		expect(#additions):toEqual(2)
		expect(events):toEqual { "removing", "removing", "removed" }
		expect(shared):toEqual(0)
		expect(#env.errors):toEqual(0)
	end)

	it("a removal handler cannot redirect the move and its failure does not stop notification", function()
		local env = environment()
		local previous = (env.createInstance "Folder")
		local destination = (env.createInstance "Folder")
		local branch = (env.createInstance("Folder", { Parent = previous }))
		local reached = 0
		previous.DescendantRemoving:Connect(function(object: Environment.Instance)
			object.Parent = env.root
		end)
		previous.DescendantRemoving:Connect(function(object: Environment.Instance)
			expect(object == branch and object.Parent == previous):toEqual(true)
			reached += 1
		end)
		branch.Parent = destination
		expect(branch.Parent == destination):toEqual(true)
		expect(reached):toEqual(1)
		expect(#env.errors):toEqual(1)
		expect(env.errors[1]):toContain "locked"
	end)

	it("unparenting preserves descendants and reports the moved ancestor with a nil parent", function()
		local env = environment()
		local branch = (env.createInstance("Folder", { Parent = env.root }))
		local child = (env.createInstance("Folder", { Parent = branch }))
		local count = 0
		child.AncestryChanged:Connect(function(moved: Environment.Instance, parent: Environment.Instance?)
			expect(moved == branch and parent == nil and branch.Parent == nil):toEqual(true)
			expect(child.Parent == branch):toEqual(true)
			count += 1
		end)
		branch.Parent = nil
		branch.Parent = nil
		expect(count):toEqual(1)
		expect(env.isAlive(child)):toEqual(true)
		expect(#env.errors):toEqual(0)
	end)

	it("destroy removes a subtree once before child removal and disconnects its live connections", function()
		local env = environment()
		local branch = (env.createInstance("Folder", { Parent = env.root }))
		local child = (env.createInstance("Folder", { Parent = branch }))
		local leaf = (env.createInstance("Folder", { Parent = child }))
		local removed: { Environment.Instance } = {}
		local destroying = 0
		local connection = branch.Destroying:Connect(function()
			expect(branch.Parent == env.root):toEqual(true)
			destroying += 1
			branch:Destroy()
		end)
		local childConnection = child.AncestryChanged:Connect(function() end)
		local rootConnection = env.root.DescendantRemoving:Connect(function(object: Environment.Instance)
			expect(branch.Parent == env.root):toEqual(true)
			expect(object:IsDescendantOf(env.root)):toEqual(true)
			table.insert(removed, object)
		end)
		local removedConnection = env.root.ChildRemoved:Connect(function(object: Environment.Instance)
			expect(object == branch and object.Parent == nil):toEqual(true)
			expect(#removed):toEqual(3)
		end)
		branch:Destroy()
		branch:Destroy()
		expect(#removed):toEqual(3)
		expect(removed[1] == branch):toEqual(true)
		expect(table.find(removed, child) ~= nil and table.find(removed, leaf) ~= nil):toEqual(true)
		expect(destroying):toEqual(1)
		expect(connection.Connected or childConnection.Connected):toEqual(false)
		connection:Disconnect()
		childConnection:Disconnect()
		expect(env.liveObjects()):toEqual(0)
		expect(env.liveConnections()):toEqual(2)
		rootConnection:Disconnect()
		removedConnection:Disconnect()
		expect(env.liveConnections()):toEqual(0)
		expect(#env.errors):toEqual(0)
	end)

	it("ClearAllChildren destroys each subtree and retains only the parent's subscriptions", function()
		local env = environment()
		local parent = (env.createInstance "Folder")
		local first = (env.createInstance("Folder", { Parent = parent }))
		local leaf = (env.createInstance("Folder", { Parent = first }))
		local second = (env.createInstance("Folder", { Parent = parent }))
		local removed: { Environment.Instance } = {}
		local connection = leaf.Destroying:Connect(function() end)
		parent.DescendantRemoving:Connect(function(object: Environment.Instance)
			expect(object:IsDescendantOf(parent)):toEqual(true)
			table.insert(removed, object)
		end)
		parent:ClearAllChildren()
		parent:ClearAllChildren()
		expect(#removed):toEqual(3)
		expect(table.find(removed, first) < table.find(removed, leaf)):toEqual(true)
		expect(env.isAlive(first) or env.isAlive(second) or env.isAlive(leaf)):toEqual(false)
		expect(connection.Connected):toEqual(false)
		expect(env.liveObjects()):toEqual(1)
		expect(env.liveConnections()):toEqual(1)
		expect(#parent:GetChildren()):toEqual(0)
		expect(#env.errors):toEqual(0)
	end)

	it("DisconnectAll updates handles and remains idempotent", function()
		local env = environment()
		local signal = env.newSignal()
		local fired = 0
		local connection = signal:Connect(function()
			fired += 1
		end)
		signal:DisconnectAll()
		signal:DisconnectAll()
		connection:Disconnect()
		signal:Fire()
		expect(connection.Connected):toEqual(false)
		expect(env.liveConnections()):toEqual(0)
		expect(fired):toEqual(0)
	end)

	it("tracks live objects and connections so a disposal test can assert nothing leaked", function()
		local env = environment()
		local before = env.liveObjects()
		local widget = (env.createInstance("Widget", { Parent = env.root })) :: Fixture
		(widget.Pinged):Connect(function() end)
		widget:GetPropertyChangedSignal("Label"):Connect(function() end)
		expect(env.liveObjects()):toEqual(before + 1)
		expect(env.liveConnections()):toEqual(2)
		widget:Destroy()
		expect(env.liveObjects()):toEqual(before)
		expect(env.liveConnections()):toEqual(0)
	end)

	it("property changes fire only on change and Changed names the property", function()
		local env = environment()
		local widget = (env.createInstance "Widget")
		local fired: { string } = {}
		widget:GetPropertyChangedSignal("Count"):Connect(function()
			table.insert(fired, "count")
		end)
		widget.Changed:Connect(function(property: string)
			table.insert(fired, property)
		end)
		widget.Count = 1
		widget.Count = 1
		widget.Count = 2
		expect(fired):toEqual { "count", "Count", "count", "Count" }
	end)

	it("attributes validate names and types and honor explicit limits", function()
		local env = Roblox.testEnvironment { limits = { attributeNameLength = 8, attributeStringLength = 50 } }
		local folder = (env.createInstance "Folder")
		folder:SetAttribute("Short", "ok")
		expect(folder:GetAttribute "Short"):toEqual "ok"
		expect(thrown(function()
			folder:SetAttribute("ThisNameIsTooLong", 1)
		end)):toContain "longer than 8 characters"
		expect(thrown(function()
			folder:SetAttribute("Long", string.rep("x", 51))
		end)):toContain "longer than 50 characters"
		expect(thrown(function()
			folder:SetAttribute("Bad", {})
		end)):toContain "cannot hold a table"
		expect(thrown(function()
			folder:SetAttribute("bad name", 1)
		end)):toContain "alphanumeric"
		local changes: { string } = {}
		folder:GetAttributeChangedSignal("Short"):Connect(function()
			table.insert(changes, tostring(folder:GetAttribute "Short"))
		end)
		folder:SetAttribute("Short", "two")
		folder:SetAttribute("Short", "two")
		expect(changes):toEqual { "two" }
	end)

	it("attributes accept the value types the engine accepts and refuse the rest by name", function()
		local env = Roblox.testEnvironment()
		local folder = (env.createInstance "Folder")
		folder:SetAttribute("Position", Datatypes.Vector3.new(1, 2, 3))
		folder:SetAttribute("Range", Datatypes.NumberRange.new(1, 2))
		folder:SetAttribute("Frame", Datatypes.CFrame.new(0, 1, 2))
		folder:SetAttribute("Size", Datatypes.UDim2.new(0, 1, 0, 2))
		folder:SetAttribute("Info", Datatypes.TweenInfo.new(1))
		folder:SetAttribute("Item", Datatypes.Enum.Material.Plastic)
		folder:SetAttribute("Other", env.createInstance "Folder")
		folder:SetAttribute("Cleared", nil)
		expect(folder:GetAttribute "Position"):toEqual(Datatypes.Vector3.new(1, 2, 3))
		expect(Datatypes.typeName(folder:GetAttribute "Info")):toBe "TweenInfo"
		expect(Datatypes.typeName(folder:GetAttribute "Range")):toBe "NumberRange"
		expect(thrown(function()
			folder:SetAttribute("Bad", {})
		end)):toContain "cannot hold a table"
		expect(thrown(function()
			folder:SetAttribute("Bad", function() end)
		end)):toContain "cannot hold a function"
		expect(thrown(function()
			folder:SetAttribute("Bad", buffer.create(1))
		end)):toContain "cannot hold a buffer"
		expect(folder:GetAttribute "Bad"):toBe(nil)
	end)

	it("a signal handle fires an event and counts its connections and fires", function()
		local env = environment()
		local widget = (env.createInstance "Widget") :: Fixture
		local handle = env.signalOf(widget, "Pinged")
		expect(handle.connections()):toBe(0)
		local calls = 0
		local connection = widget.Pinged:Connect(function()
			calls += 1
		end)
		handle.fire()
		handle.fire()
		expect(calls):toBe(2)
		expect(handle.connections()):toBe(1)
		expect(handle.fires()):toBe(2)
		connection:Disconnect()
		expect(handle.connections()):toBe(0)
		expect(thrown(function()
			env.signalOf(widget, "Missing")
		end)):toContain "not a valid member"
	end)

	it("a create hook sees every new instance until disconnected", function()
		local env = environment()
		local seen: { string } = {}
		local connection = env.onCreate(function(object)
			table.insert(seen, object.ClassName)
		end)
		local widget = env.createInstance("Widget", { env.createInstance "Folder" })
		widget:Clone()
		connection:Disconnect()
		env.createInstance "Folder"
		expect(seen):toEqual { "Folder", "Widget", "Widget", "Folder" }
	end)

	it("virtual time orders spawn, defer, delay and wait deterministically", function()
		local env = environment()
		local order: { string } = {}
		env.task.delay(2, function()
			table.insert(order, "delay2")
		end)
		env.task.delay(1, function()
			table.insert(order, "delay1")
		end)
		env.task.defer(function()
			table.insert(order, "defer")
		end)
		env.task.spawn(function()
			table.insert(order, "spawn")
			env.task.wait(1.5)
			table.insert(order, "waited")
		end)
		table.insert(order, "sync")
		env.step(0)
		env.step(1)
		env.step(1)
		expect(order):toEqual { "spawn", "sync", "defer", "delay1", "waited", "delay2" }
		expect(env.now()):toEqual(2)
	end)

	it("cancel stops a pending delay and a scheduler failure is reported not hidden", function()
		local env = environment()
		local ran = false
		local pending = env.task.delay(1, function()
			ran = true
		end)
		env.task.cancel(pending)
		env.step(2)
		expect(ran):toEqual(false)
		env.task.defer(function()
			error "deferred broke"
		end)
		env.step(0)
		expect(#env.scheduler.failures):toEqual(1)
		expect(env.scheduler.failures[1]):toContain "deferred broke"
	end)

	it("a chain of nested defers stops at the engine re-entrancy depth of 80", function()
		local env = environment()
		local reached = 0
		local function chain(level: number)
			reached = level
			env.task.defer(chain, level + 1)
		end
		env.task.defer(chain, 1)
		env.step(0)
		expect(reached):toEqual(80)
		expect(#env.scheduler.failures):toEqual(1)
		expect(env.scheduler.failures[1]):toContain "Maximum re-entrancy depth (80) exceeded calling task.defer"
		local later = false
		env.task.defer(function()
			later = true
		end)
		env.step(0)
		expect(later):toEqual(true)
	end)

	it("heartbeat fires once per step with the step length", function()
		local env = environment()
		local deltas: { number } = {}
		env.heartbeat:Connect(function(delta: number)
			table.insert(deltas, delta)
		end)
		env.step(0.5)
		env.step(0.25)
		expect(deltas):toEqual { 0.5, 0.25 }
	end)

	it("injects one named failure and recovers", function()
		local env = environment()
		env.failNext "setParent"
		expect(thrown(function()
			env.createInstance("Folder", { Parent = env.root })
		end)):toContain "injected failure in setParent"
		local folder = (env.createInstance("Folder", { Parent = env.root }))
		expect(folder.Parent):toEqual(env.root)
		env.failNext("create", 2)
		env.clearFailures()
		env.createInstance "Folder"
	end)

	it("finds, names and relates instances", function()
		local env = environment()
		local a = (env.createInstance("Folder", { Name = "a", Parent = env.root }))
		local b = (env.createInstance("Part", { Name = "b", Parent = a }))
		expect(a:FindFirstChild "b"):toEqual(b)
		expect(env.root:FindFirstChild("b", true)):toEqual(b)
		expect(b:GetFullName()):toEqual "a.b"
		expect(b:IsDescendantOf(env.root)):toEqual(true)
		expect(b:FindFirstAncestor "a"):toEqual(a)
		expect(a:FindFirstChildWhichIsA "BasePart"):toEqual(b)
		expect(a:FindFirstChildOfClass "BasePart"):toEqual(nil)
		expect(#env.root:GetDescendants()):toEqual(2)
		expect(thrown(function()
			a.Parent = b
		end)):toContain "own ancestor"
	end)

	it("datatypes compare by value and report their type name and CFrame components", function()
		local types = Roblox.datatypes
		expect(types.Vector2.new(1, 2) == types.Vector2.new(1, 2)):toEqual(true)
		expect(types.Vector3.new(1, 2, 3) == types.Vector3.new(1, 2, 4)):toEqual(false)
		expect(types.Color3.new(0.5, 0, 1) == types.Color3.new(0.5, 0, 1)):toEqual(true)
		expect(types.UDim.new(1, 2) == types.UDim.new(1, 2)):toEqual(true)
		expect(types.UDim2.fromOffset(3, 4) == types.UDim2.new(0, 3, 0, 4)):toEqual(true)
		expect(types.UDim2.fromScale(1, 1) == types.UDim2.fromOffset(1, 1)):toEqual(false)
		local frame = types.CFrame.new(1, 2, 3) * types.CFrame.Angles(0, math.pi / 2, 0)
		expect(frame == types.CFrame.new(1, 2, 3) * types.CFrame.Angles(0, math.pi / 2, 0)):toEqual(true)
		expect(types.typeName(types.UDim2.new())):toEqual "UDim2"
		local size = types.UDim2.new(0.5, 3, 1, 4)
		expect(size.X == types.UDim.new(0.5, 3)):toEqual(true)
		expect(size.Y.Offset):toEqual(4)
		expect(size.Width == size.X and size.Height == size.Y):toEqual(true)
		expect(types.UDim2.new(types.UDim.new(0.5, 3), types.UDim.new(1, 4)) == size):toEqual(true)
		local turned = types.CFrame.new(1, 2, 3, 0, 0, 1, 0, 1, 0, -1, 0, 0)
		local _, _, _, turnedRotation = types.readCFrame(turned)
		expect(turnedRotation[3]):toEqual(1)
		expect(turnedRotation[7]):toEqual(-1)
		expect(types.typeName(frame)):toEqual "CFrame"
		expect(types.typeName(5)):toEqual(nil)
		local x, y, z, rotation = types.readCFrame(frame)
		expect({ x, y, z }):toEqual { 1, 2, 3 }
		expect(#rotation):toEqual(9)
		expect(select("#", frame:GetComponents())):toEqual(12)
		expect(Roblox.typeName(types.Vector3.new())):toEqual "Vector3"
	end)

	it("builtin gui classes declare layout and appearance members", function()
		local env = Roblox.testEnvironment()
		local frame = (env.createInstance "Frame")
		frame.Size = Roblox.datatypes.UDim2.fromOffset(10, 20)
		frame.BackgroundColor3 = Roblox.datatypes.Color3.new(1, 0, 0)
		expect((frame.Position :: Datatypes.UDim2Value) == Roblox.datatypes.UDim2.new()):toEqual(true)
		for _, name in { "UIListLayout", "ScrollingFrame", "TextBox", "CanvasGroup" } do
			expect(env.createInstance(name).ClassName):toEqual(name)
		end
		expect(
			(env.createInstance("ScrollingFrame").CanvasPosition :: Datatypes.Vector2Value)
				== Roblox.datatypes.Vector2.new()
		):toEqual(true)
	end)

	it("an engine-side poke fires property changes only when the value changes", function()
		local env = Roblox.testEnvironment()
		local frame = (env.createInstance "Frame")
		local fired = 0
		frame:GetPropertyChangedSignal("Visible"):Connect(function()
			fired += 1
		end)
		env.poke(frame, "Visible", false)
		env.poke(frame, "Visible", false)
		env.poke(frame, "Visible", true)
		expect(fired):toEqual(2)
	end)

	it("createInstance takes children in the array part and parents them", function()
		local env = Roblox.testEnvironment()
		local a = (env.createInstance("Part", { Name = "a" }))
		local b = assert((env.createInstance("Part", { Name = "b" })))
		local model = (env.createInstance("Model", { Name = "m", a, b, Parent = env.root }))
		expect(#model:GetChildren()):toEqual(2)
		expect(a.Parent):toEqual(model)
		expect(model.Parent):toEqual(env.root)
		expect(Roblox.isInstance(model)):toEqual(true)
		expect(Roblox.isInstance {}):toEqual(false)
	end)

	it("Animator loads a track that plays, stops and reports Stopped and Ended", function()
		local env = Roblox.testEnvironment()
		local animator = (env.createInstance "Animator")
		local animation = (env.createInstance("Animation", { AnimationId = "rbxassetid://1" }))
		local track = (animator.LoadAnimation :: (Environment.Instance, Environment.Instance) -> Fixture)(
			animator,
			animation
		)
		local seen: { string } = {}
		track.Stopped:Connect(function()
			table.insert(seen, "stopped")
		end)
		track.Ended:Connect(function()
			table.insert(seen, "ended")
		end)
		local play: (Environment.Instance) -> () = track.Play
		play(track)
		local speed: (Environment.Instance, number) -> () = track.AdjustSpeed
		speed(track, 2)
		expect(track.IsPlaying):toEqual(true)
		expect(track.Speed):toEqual(2)
		local stop: (Environment.Instance) -> () = track.Stop
		stop(track)
		stop(track)
		expect(track.IsPlaying):toEqual(false)
		expect(seen):toEqual { "stopped", "ended" }
	end)

	it("a snapshot lists the set properties, attributes and children of a tree", function()
		local env = Roblox.testEnvironment()
		local part = (env.createInstance("Part", { Name = "p", Anchored = true }))
		local model = (env.createInstance("Model", { Name = "m", part }))
		model:SetAttribute("Tag", "x")
		local view = env.snapshot(model)
		expect(view.className):toEqual "Model"
		expect(view.attributes):toEqual { Tag = "x" }
		expect(view.children[1].name):toEqual "p"
		expect(view.children[1].properties.Anchored):toEqual(true)
	end)

	it("method tables written as plain function literals type-check without casts", function()
		local env = Roblox.testEnvironment {
			classes = {
				Gadget = {
					super = "Instance",
					methods = {
						Twice = function(_self: Fixture, value: number): number
							return value * 2
						end,
						Missing = true,
					},
				},
			},
		}
		local gadget = env.createInstance "Gadget"
		expect((gadget.Twice :: (Environment.Instance, number) -> number)(gadget, 4)):toEqual(8)
	end)
end)

it("descendant registration order survives moves within an ancestor and advances after reentry", function()
	local env = Environment.create()
	local root = env.createInstance "Folder"
	local first = env.createInstance("Folder", { Parent = root })
	local second = env.createInstance("Folder", { Parent = root })
	local child = env.createInstance("Folder", { Parent = first })
	local peer = env.createInstance("Folder", { Parent = second })
	local registered = assert(env.descendantOrderOf(root, child))
	expect(registered < assert(env.descendantOrderOf(root, peer))):toBe(true)
	child.Parent = second
	expect(env.descendantOrderOf(root, child)):toBe(registered)
	expect(env.descendantOrderOf(first, child)):toBe(nil)
	expect(assert(env.descendantOrderOf(second, child)) > assert(env.descendantOrderOf(second, peer))):toBe(true)
	env.failNext "setParent"
	expect(function()
		child.Parent = first
	end):toThrow()
	expect(env.descendantOrderOf(root, child)):toBe(registered)
	second.Parent = nil
	expect(env.descendantOrderOf(root, child)):toBe(nil)
	second.Parent = root
	expect(assert(env.descendantOrderOf(root, child)) > registered):toBe(true)
	child:Destroy()
	expect(env.descendantOrderOf(root, child)):toBe(nil)
	root:Destroy()
end)

return nil
