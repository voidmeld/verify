--!strict

local Verify = require "../src/core"
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

return function(suite: Verify.Harness)
	suite:suite("roblox test environment", function()
		suite:case("class defaults require declared properties and allocate no instances", function(check)
			local env = environment()
			local before = env.liveObjects()
			check:expect(env.defaultClassProperty("Widget", "Count")):toBe(0)
			check:expect(env.defaultClassProperty("Widget", "Archivable")):toBe(true)
			check:expect(env.liveObjects()):toBe(before)
			check:expect((pcall(env.defaultClassProperty, "Missing", "Count"))):toBe(false)
			check:expect((pcall(env.defaultClassProperty, "Widget", "Missing"))):toBe(false)
		end)
		suite:case("checked instance lookup preserves identity and rejects unregistered values", function(check)
			local env = environment()
			local widget = env.createInstance "Widget"
			local value: unknown = widget
			local instance = Roblox.assertInstance(value)
			check:expect(instance):toBe(widget)
			env.poke(instance, "Count", 7)
			check:expect(widget.Count):toBe(7)
			widget:Destroy()
			check:expect(Roblox.assertInstance(value)):toBe(widget)
			local invalidValues: { unknown } =
				{ false, 1, "Instance", {}, { ClassName = "Widget" }, Datatypes.Vector2.zero }
			for _, invalid in invalidValues do
				check
					:expect(thrown(function()
						Roblox.assertInstance(invalid)
					end))
					:toContain "expected a simulated Instance"
			end
			check
				:expect(thrown(function()
					Roblox.assertInstance(nil)
				end))
				:toContain "expected a simulated Instance"
		end)
		suite:case("native signal and connection type identity belongs only to authoritative signals", function(check)
			local env = environment()
			local signal = env.newSignal()
			local connection = signal:Connect(function() end)
			check:expect(Environment.typeName(signal)):toBe "RBXScriptSignal"
			check:expect(Environment.typeName(connection)):toBe "RBXScriptConnection"
			check:expect(Environment.typeName(env.heartbeat)):toBe "RBXScriptSignal"
			local widget = env.createInstance "Widget"
			check:expect(Environment.typeName(widget.Pinged)):toBe "RBXScriptSignal"
			check:expect(Environment.typeName { Connect = function() end, Wait = function() end }):toBe "table"
			check:expect(Environment.typeName { Connect = signal.Connect, Wait = signal.Wait }):toBe "table"
			check:expect(Environment.typeName { Connected = true, Disconnect = connection.Disconnect }):toBe "table"
			connection:Disconnect()
			check:expect(Environment.typeName(connection)):toBe "RBXScriptConnection"
			check:expect(env.liveConnections()):toBe(0)
			widget:Destroy()
			check:expect(Environment.typeName(widget)):toBe "Instance"
			check:expect(Environment.isInstance(widget)):toBe(true)
		end)
		suite:case("Studio 0.744 Objects inherit only Object members and use environment-owned cleanup", function(check)
			local options: Environment.Options = {
				classes = { VirtualInput = { super = "Object", creatable = false } },
			}
			local env = Environment.create(options)
			local object = env.createEngineObject "VirtualInput"
			check:expect(object.ClassName):toBe "VirtualInput"
			check:expect(object:IsA "VirtualInput"):toBe(true)
			check:expect(object:IsA "Object"):toBe(true)
			check:expect(object:IsA "Instance"):toBe(false)
			check:expect(Environment.isInstance(object)):toBe(false)
			check
				:expect(thrown(function()
					Roblox.assertInstance(object)
				end))
				:toContain "expected a simulated Instance"
			local members = (object :: unknown) :: { [string]: unknown }
			for _, name in { "Name", "Archivable", "Parent", "Destroy", "GetChildren", "ChildAdded", "Destroying" } do
				check
					:expect(thrown(function(): unknown
						return members[name]
					end))
					:toContain "not a valid member"
			end
			check
				:expect(thrown(function()
					members.Parent = env.root
				end))
				:toContain "not a valid member"
			check
				:expect(thrown(function()
					env.createInstance "VirtualInput"
				end))
				:toContain "Unable to create"
			check
				:expect(thrown(function()
					env.createEngineInstance "VirtualInput"
				end))
				:toContain "requires an Instance class"
			check
				:expect(thrown(function()
					env.createEngineObject "Missing"
				end))
				:toContain "Unable to create"
			check:expect(Environment.typeName(object)):toBe "Object"
			local changed = object.Changed:Connect(function() end)
			local signal = object:GetPropertyChangedSignal "ClassName"
			check:expect(signal):toBe(object:GetPropertyChangedSignal "ClassName")
			check:expect(env.liveConnections()):toBe(1)
			check:expect(env.liveObjects()):toBe(1)
			local other = Environment.create()
			check
				:expect(thrown(function()
					other.releaseObject(object)
				end))
				:toContain "must belong to this environment"
			env.releaseObject(object)
			env.releaseObject(object)
			check:expect(Environment.typeName(object)):toBe "Object"
			check:expect(Environment.isInstance(object)):toBe(false)
			check:expect(changed.Connected):toBe(false)
			check:expect(env.liveConnections()):toBe(0)
			check:expect(env.liveObjects()):toBe(0)
		end)
		suite:case(
			"scoped method doubles restore active predecessors without resurrecting disposed layers",
			function(check)
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
				check:expect(read()):toEqual(3)
				first()
				check:expect(read()):toEqual(3)
				second()
				check:expect(read()):toEqual(1)
				second()
				first()
				check:expect(read()):toEqual(1)
				baseline()
				check:expect((pcall(read))):toEqual(false)
			end
		)
		suite:case("scoped method cleanup preserves a later explicit method assignment", function(check)
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
			check:expect((object.Read :: Environment.Method)(object)):toEqual(11)
		end)
		suite:case("yielding signal listeners do not suspend the emitter or other listeners", function(check)
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
			check:expect(observed):toBe(7)
			check:expect(completed):toBe(0)
			signal:DisconnectAll()
			env.scheduler.resume(assert(waiting))
			env.scheduler.drain(20)
			check:expect(completed):toBe(7)
			check:expect(env.scheduler.failures):toHaveLength(0)
		end)
		suite:case("Signal.Wait returns the next argument tuple once including nil values", function(check)
			local env = environment()
			local signal: Environment.Signal = env.newSignal()
			signal:Fire "past"
			local result: { [number]: unknown, n: number }? = nil
			local waiter = env.task.spawn(function()
				result = table.pack(signal:Wait())
			end)
			env.scheduler.drain(20)
			check:expect(result):toEqual(nil)
			check:expect(env.liveConnections()):toEqual(1)
			signal:Fire("next", nil, 3, nil)
			signal:Fire "later"
			check:expect(env.liveConnections()):toEqual(0)
			env.scheduler.drain(20)
			local values = assert(result)
			check:expect(values.n):toEqual(4)
			check:expect(values[1]):toEqual "next"
			check:expect(values[2]):toEqual(nil)
			check:expect(values[3]):toEqual(3)
			check:expect(values[4]):toEqual(nil)
			check:expect(coroutine.status(waiter)):toEqual "dead"
			check:expect(env.scheduler.failures):toHaveLength(0)
		end)
		suite:case("canceling Signal.Wait releases its listener before any future event", function(check)
			local env = environment()
			local signal: Environment.Signal = env.newSignal()
			local resumed = false
			local waiter = env.task.spawn(function()
				signal:Wait()
				resumed = true
			end)
			env.scheduler.drain(20)
			check:expect(env.liveConnections()):toEqual(1)
			env.task.cancel(waiter)
			check:expect(env.liveConnections()):toEqual(0)
			signal:Fire(1)
			env.scheduler.drain(20)
			check:expect(resumed):toEqual(false)
			check:expect(env.scheduler.failures):toHaveLength(0)
			check:expect(env.scheduler.pending()):toEqual(0)
		end)
		suite:case("Signal.Wait resumes all current waiters with their own scheduler context", function(check)
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
			check:expect(results):toEqual { "first:7", "second:7" }
			check:expect(env.liveConnections()):toEqual(0)
		end)
		suite:case("scheduler block cleanup runs once on resume and cancel", function(check)
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
			check:expect(cleanups):toBe(1)
			env.step(0)
			check:expect(completed):toBe(true)
			env.task.cancel(waiter)
			check:expect(cleanups):toBe(1)
			local canceled = env.task.spawn(function()
				env.scheduler.block(function()
					return function()
						cleanups += 1
					end
				end)
			end)
			env.task.cancel(canceled)
			env.task.cancel(canceled)
			check:expect(cleanups):toBe(2)
			check:expect(#env.scheduler.failures):toBe(0)
		end)

		suite:case("scheduler block releases cleanup when registration synchronously queues its waiter", function(check)
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
			check:expect(completed):toBe(true)
			check:expect(cleanups):toBe(1)
		end)

		suite:case("scheduler cancellation still closes a waiter when its cleanup fails", function(check)
			local env = environment()
			local waiter = env.task.spawn(function()
				env.scheduler.block(function()
					return function()
						error "cleanup fixture failure"
					end
				end)
			end)
			env.task.cancel(waiter)
			check:expect(coroutine.status(waiter)):toBe "dead"
			check:expect(#env.scheduler.failures):toBe(1)
			check:expect(env.scheduler.failures[1]):toContain "cleanup fixture failure"
		end)
		suite:case("propertyOf inspects declared callbacks while instance reads remain forbidden", function(check)
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
			check:expect(env.propertyOf(object, "OnInvoke") == callback):toBe(true)
			check
				:expect(thrown(function()
					return object.OnInvoke
				end))
				:toContain "you can only set the callback value"
			env.fakeOn(object, "Handler", callback)
			check:expect(env.propertyOf(object, "Handler")):toBe(nil)
		end)
		suite:case("computed lookup honors an empty table with a dynamic getter", function(check)
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
			check:expect(env.createInstance("Folder").Count):toEqual(7)
		end)

		suite:case("a frozen computed table caches lookups until a class changes inheritance", function(check)
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
			check:expect(probe.Count):toEqual(1)
			check:expect(probe.Count):toEqual(1)
			env.defineClass("Probe", { super = "Basis", properties = { Count = 0 } }, { replace = true })
			check:expect(env.createInstance("Probe").Count):toEqual(2)
		end)

		suite:case("computed lookup sees replacement, removal and changed inheritance", function(check)
			local computed: { [string]: Environment.Computed } = {}
			local env = Environment.create { computed = computed }
			env.defineClass("Probe", { super = "Folder", properties = { Count = 0 } })
			local probe = env.createInstance "Probe"
			check:expect(probe.Count):toEqual(0)
			computed["Folder.Count"] = function(): unknown
				return 1
			end
			check:expect(probe.Count):toEqual(1)
			check
				:expect(thrown(function()
					probe.Count = 2
				end))
				:toContain "read-only"
			local entry = {
				get = function(): unknown
					return nil
				end,
				writable = true,
			}
			computed["Folder.Count"] = entry
			probe.Count = 2
			check:expect(probe.Count):toEqual(2)
			entry.writable = false
			check:expect(probe.Count):toEqual(nil)
			computed["Folder.Count"] = nil
			probe.Count = 3
			check:expect(probe.Count):toEqual(3)
			computed["Basis.Count"] = function(): unknown
				return 4
			end
			env.defineClass("Probe", { super = "Basis", properties = { Count = 0 } }, { replace = true })
			check:expect(probe.Count):toEqual(4)
		end)

		suite:case("retains unobserved fires when signals are first read and connected", function(check)
			local env = environment()
			local widget = env.createInstance "Widget"
			widget.Count = 1
			widget.Count = 2
			widget:SetAttribute("Probe", 1)
			env.fire(widget, "Pinged", "before")
			local changed = widget:GetPropertyChangedSignal "Count"
			local attribute = widget:GetAttributeChangedSignal "Probe"
			local pinged = widget.Pinged :: Environment.Signal
			check:expect(env.firesOf(changed)):toEqual(2)
			check:expect(env.firesOf(attribute)):toEqual(1)
			check:expect(env.signalOf(widget, "Pinged").fires()):toEqual(1)
			check:expect(env.liveConnections()):toEqual(0)
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
			check:expect(calls):toEqual {}
			widget.Count = 3
			widget:SetAttribute("Probe", 2)
			env.fire(widget, "Pinged", "after")
			check:expect(calls):toEqual { "property", "attribute", "after" }
			check:expect(env.firesOf(changed)):toEqual(3)
			widget:Destroy()
			check:expect(connection.Connected):toEqual(false)
			check:expect(env.liveConnections()):toEqual(0)
			check:expect(env.signalOf(widget, "Destroying").fires()):toEqual(1)
		end)

		suite:case("materializes a later signal during an earlier notification", function(check)
			local env = environment()
			local widget = env.createInstance "Widget"
			widget.Count = 1
			local changes: { string } = {}
			widget:GetPropertyChangedSignal("Count"):Connect(function()
				check:expect(env.signalOf(widget, "Changed").fires()):toEqual(1)
				widget.Changed:Connect(function(property: string)
					table.insert(changes, property)
				end)
			end)
			widget.Count = 2
			check:expect(changes):toEqual { "Count" }
			check:expect(env.signalOf(widget, "Changed").fires()):toEqual(2)
		end)

		suite:case("retains unobserved hierarchy fires through removal and destruction", function(check)
			local env = environment()
			local parent = env.createInstance "Folder"
			local child = env.createInstance("Folder", { Parent = parent })
			child.Parent = nil
			check:expect(env.signalOf(parent, "ChildAdded").fires()):toEqual(1)
			check:expect(env.signalOf(parent, "ChildRemoved").fires()):toEqual(1)
			check:expect(env.signalOf(parent, "DescendantAdded").fires()):toEqual(1)
			check:expect(env.signalOf(parent, "DescendantRemoving").fires()):toEqual(1)
			check:expect(env.signalOf(child, "AncestryChanged").fires()):toEqual(2)
			check:expect(env.firesOf(child:GetPropertyChangedSignal "Parent")):toEqual(2)
			child:Destroy()
			check:expect(env.signalOf(child, "Destroying").fires()):toEqual(1)
		end)

		suite:case("lets a class override a builtin with its own method", function(check)
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
			check:expect(((probe.Clone :: unknown) :: (Environment.Instance) -> number)(probe)):toEqual(1)
			check:expect(calls):toEqual(1)
			check:expect(env.createInstance("Folder"):Clone() ~= nil):toEqual(true)
		end)

		suite:case("clones archivable trees and remaps only internal instance references", function(check)
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
			check:expect(#children):toEqual(2)
			check:expect(clone.Parent == nil and clone.PrimaryPart == children[1]):toEqual(true)
			check:expect(children[1].Target == children[2]):toEqual(true)
			check:expect(children[2].Target == external):toEqual(true)
			check:expect(children[1]:GetAttribute "Count"):toEqual(3)
			check:expect(children[1]:HasTag "selected"):toEqual(true)
			children[1]:RemoveTag "selected"
			check:expect(child:HasTag "selected"):toEqual(true)
			check:expect(excluded:Clone()):toEqual(nil)
			clone:Destroy()
			check:expect(env.isAlive(child)):toEqual(true)
		end)

		suite:case("recursive class lookup and ancestor lookup distinguish inheritance", function(check)
			local env = environment()
			env.defineClass("Special", { super = "Widget" })
			local parent = env.createInstance("Special", { Parent = env.root })
			local folder = env.createInstance("Folder", { Parent = parent })
			local child = env.createInstance("Special", { Parent = folder })
			check:expect(parent:FindFirstChildWhichIsA "Widget"):toEqual(nil)
			check:expect(parent:FindFirstChildWhichIsA("Widget", true) == child):toEqual(true)
			check:expect(child:FindFirstAncestorWhichIsA "Widget" == parent):toEqual(true)
			check:expect(child:FindFirstAncestorOfClass "Widget"):toEqual(nil)
			check:expect(child:FindFirstAncestorOfClass "Special" == parent):toEqual(true)
		end)

		suite:case("creates declared classes with inherited defaults and refuses undeclared members", function(check)
			local env = environment()
			local widget = (env.createInstance("Widget", { Label = "go" }))
			check:expect(widget.ClassName):toEqual "Widget"
			check:expect(widget.Name):toEqual "Widget"
			check:expect(widget.Label):toEqual "go"
			check:expect(widget.Count):toEqual(0)
			check:expect(widget:IsA "Instance"):toEqual(true)
			check
				:expect(thrown(function()
					return env.createInstance "Missing"
				end))
				:toContain 'Unable to create an Instance of type "Missing"'
			check
				:expect(thrown(function()
					return env.createInstance "Instance"
				end))
				:toContain 'Unable to create an Instance of type "Instance"'
			check
				:expect(thrown(function()
					widget.Lable = "x"
				end))
				:toContain 'Lable is not a valid member of Widget "Widget"'
		end)

		suite:case("reading an unknown name returns the first child with that name, as the engine does", function(check)
			local env = environment()
			local parent = (env.createInstance("Widget", { Parent = env.root }))
			local first = (env.createInstance("Folder", { Name = "Slot", Parent = parent }))
			env.createInstance("Folder", { Name = "Slot", Parent = parent })
			local other = (env.createInstance("Folder", { Name = "Other", Parent = parent }))
			check:expect(parent.Slot == first):toEqual(true)
			local key = "Other"
			check:expect(parent[key] == other):toEqual(true)
			check:expect(parent:FindFirstChild "Slot" == first):toEqual(true)
			check:expect(parent:FindFirstChild "Absent"):toEqual(nil)
			check
				:expect(thrown(function()
					return parent.Absent
				end))
				:toContain 'Absent is not a valid member of Widget "Widget"'
			check:expect(parent:WaitForChild "Slot" == first):toBe(true)
		end)

		suite:case("WaitForChild returns an existing direct child without yielding or scheduling", function(check)
			local env = environment()
			local parent = env.createInstance "Folder"
			local child = env.createInstance("Folder", { Name = "Ready", Parent = parent })
			check:expect(parent:WaitForChild("Ready", 1) == child):toBe(true)
			check:expect(env.scheduler.pending()):toBe(0)
			check:expect(env.liveConnections()):toBe(0)
		end)

		suite:case("matches Studio 0.744 rejection of nonpositive WaitForChild timeouts", function(check)
			local env = environment()
			local parent = env.createInstance "Folder"
			for _, timeout in { 0, -1 } do
				check
					:expect(thrown(function()
						parent:WaitForChild("Ready", timeout)
					end))
					:toContain "illegal argument #2 (timeOut must be greater than 0)"
			end
			env.createInstance("Folder", { Name = "Ready", Parent = parent })
			check
				:expect(thrown(function()
					parent:WaitForChild("Ready", 0)
				end))
				:toContain "illegal argument #2 (timeOut must be greater than 0)"
			check:expect(env.liveConnections()):toBe(0)
		end)

		suite:case("matches Studio 0.744 WaitForChild waking when an existing child is renamed", function(check)
			local env = environment()
			local parent = env.createInstance "Folder"
			local child = env.createInstance("Folder", { Name = "Other", Parent = parent })
			local result: Environment.Instance?
			env.task.spawn(function()
				result = parent:WaitForChild("Ready", 2)
			end)
			child.Name = "Ready"
			env.step(0)
			check:expect(result == child):toBe(true)
			check:expect(env.liveConnections()):toBe(0)
			check:expect(env.scheduler.pending()):toBe(0)
		end)

		suite:case("WaitForChild observes newly added child renames and detaches removed children", function(check)
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
			check:expect(result):toBe(nil)
			local child = env.createInstance("Folder", { Name = "Other", Parent = parent })
			child.Name = "Ready"
			env.step(0)
			check:expect(result == child):toBe(true)
			check:expect(env.liveConnections()):toBe(0)
		end)

		suite:case("WaitForChild yields for its named direct child and cancels its timeout", function(check)
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
			check:expect(completed):toBe(false)
			local child = env.createInstance("Folder", { Name = "Ready", Parent = parent })
			env.step(0)
			check:expect(result == child):toBe(true)
			check:expect(completed):toBe(true)
			check:expect(env.scheduler.pending()):toBe(0)
			check:expect(env.liveConnections()):toBe(0)
		end)

		suite:case("WaitForChild timeout returns nil once and disconnects its listener", function(check)
			local env = environment()
			local parent = env.createInstance "Folder"
			local result: Environment.Instance? = parent
			local completions = 0
			env.task.spawn(function()
				result = parent:WaitForChild("Ready", 2)
				completions += 1
			end)
			env.step(1)
			check:expect(completions):toBe(0)
			env.step(1)
			check:expect(result):toBe(nil)
			check:expect(completions):toBe(1)
			env.createInstance("Folder", { Name = "Ready", Parent = parent })
			env.step(10)
			check:expect(completions):toBe(1)
			check:expect(env.liveConnections()):toBe(0)
		end)

		suite:case("WaitForChild with nil timeout stays suspended until the named child arrives", function(check)
			local env = environment()
			local parent = env.createInstance "Folder"
			local result: Environment.Instance?
			env.task.spawn(function()
				result = parent:WaitForChild("Ready", nil)
			end)
			env.step(20)
			check:expect(result):toBe(nil)
			local child = env.createInstance("Folder", { Name = "Ready", Parent = parent })
			env.step(0)
			check:expect(result == child):toBe(true)
			check:expect(env.liveConnections()):toBe(0)
		end)

		suite:case("a canceled WaitForChild is not resumed when its child arrives", function(check)
			local env = environment()
			local parent = env.createInstance "Folder"
			local resumed = false
			local waiter = env.task.spawn(function()
				parent:WaitForChild "Ready"
				resumed = true
			end)
			env.task.cancel(waiter)
			check:expect(env.liveConnections()):toBe(0)
			env.createInstance("Folder", { Name = "Ready", Parent = parent })
			env.step(0)
			check:expect(resumed):toBe(false)
			check:expect(#env.scheduler.failures):toBe(0)
			check:expect(env.liveConnections()):toBe(0)
			check:expect(env.scheduler.pending()):toBe(0)
		end)

		suite:case("a canceled WaitForChild timeout releases its listeners without resuming the thread", function(check)
			local env = environment()
			local parent = env.createInstance "Folder"
			local resumed = false
			local waiter = env.task.spawn(function()
				parent:WaitForChild("Ready", 1)
				resumed = true
			end)
			env.task.cancel(waiter)
			check:expect(env.liveConnections()):toBe(0)
			check:expect(env.scheduler.pending()):toBe(0)
			env.step(1)
			check:expect(resumed):toBe(false)
			check:expect(#env.scheduler.failures):toBe(0)
			check:expect(env.liveConnections()):toBe(0)
			check:expect(env.scheduler.pending()):toBe(0)
		end)

		suite:case("a property, event or method wins over a child of the same name", function(check)
			local env = environment()
			local parent = (env.createInstance("Widget", { Label = "own", Parent = env.root })) :: Fixture
			env.createInstance("Folder", { Name = "Label", Parent = parent })
			env.createInstance("Folder", { Name = "Pinged", Parent = parent })
			env.createInstance("Folder", { Name = "Double", Parent = parent })
			env.createInstance("Folder", { Name = "Destroy", Parent = parent })
			check:expect(parent.Label):toEqual "own"
			check:expect((parent.Pinged).Connect ~= nil):toEqual(true)
			check:expect((parent.Double :: (Environment.Instance, number) -> number)(parent, 1)):toEqual(2)
			check:expect(type(parent.Destroy)):toEqual "function"
			check:expect(parent.ClassName):toEqual "Widget"
		end)

		suite:case(
			"a renamed, destroyed or reparented child is found only while it holds that name and parent",
			function(check)
				local env = environment()
				local parent = (env.createInstance("Widget", { Parent = env.root }))
				local elsewhere = (env.createInstance("Widget", { Parent = env.root }))
				local child = (env.createInstance("Folder", { Name = "Before", Parent = parent }))
				check:expect(parent.Before == child):toEqual(true)
				child.Name = "After"
				check:expect(parent.After == child):toEqual(true)
				check
					:expect(thrown(function()
						return parent.Before
					end))
					:toContain "Before is not a valid member"
				child.Parent = elsewhere
				check
					:expect(thrown(function()
						return parent.After
					end))
					:toContain "After is not a valid member"
				check:expect(elsewhere.After == child):toEqual(true)
				child:Destroy()
				check
					:expect(thrown(function()
						return elsewhere.After
					end))
					:toContain "After is not a valid member"
			end
		)

		suite:case("writing an unknown name stays an error even when a child has that name", function(check)
			local env = environment()
			local parent = (env.createInstance("Widget", { Parent = env.root }))
			env.createInstance("Folder", { Name = "Slot", Parent = parent })
			check
				:expect(thrown(function()
					parent.Slot = env.createInstance "Folder"
				end))
				:toContain 'Slot is not a valid member of Widget "Widget"'
		end)

		suite:case("a builtin class is redefined only on explicit request", function(check)
			local env = environment()
			check
				:expect(thrown(function()
					env.defineClass("Frame", { super = "GuiObject", properties = { Extra = 1 } })
				end))
				:toContain 'class "Frame" is already defined'
			env.defineClass("Frame", { super = "GuiObject", properties = { Extra = 1 } }, { replace = true })
			local frame = (env.createInstance "Frame")
			check:expect(frame.Extra):toEqual(1)
			check:expect(frame.Visible):toEqual(true)
			env.defineClass("Fresh", { super = "Instance" }, { replace = true })
			check:expect(env.createInstance("Fresh").ClassName):toEqual "Fresh"
		end)

		suite:case(
			"a declared method needs a simulation or a configured fake and never invents a result",
			function(check)
				local env = environment()
				local widget = (env.createInstance "Widget")
				check:expect((widget.Double :: (Environment.Instance, number) -> number)(widget, 4)):toEqual(8)
				check
					:expect(thrown(function()
						return (widget.Ping :: (Environment.Instance) -> unknown)(widget)
					end))
					:toContain "unsupported_method: Widget.Ping is declared but has no simulation or configured fake"
				env.fake("Widget.Ping", function(): string
					return "pong"
				end)
				check:expect((widget.Ping :: (Environment.Instance) -> unknown)(widget)):toEqual "pong"
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
				check:expect((configuredWidget.Ping :: (Environment.Instance) -> unknown)(configuredWidget)):toEqual(7)
			end
		)

		suite:case("opt-in defaults preserve false and allocate fresh property values per instance", function(check)
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
			check:expect(env.createInstance("Frame").Visible):toEqual(false)
			local first = (env.createInstance "Record") :: Fixture
			local second = (env.createInstance "Record") :: Fixture
			first.Data.Key = "first"
			check:expect(second.Data.Key):toEqual(nil)
			check:expect(first.Name):toEqual "Record"
		end)

		suite:case(
			"opt-in validation rejects writes before mutation and distinguishes engine-side poke",
			function(check)
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
				check
					:expect(thrown(function()
						(assert(record)).Count = "wrong"
					end))
					:toContain "Count requires a number"
				check
					:expect(thrown(function()
						record.Label = "wrong"
					end))
					:toContain "Label is read-only"
				check:expect(record.Count):toEqual(0)
				check:expect(record.Label):toEqual ""
				check:expect(changed):toEqual(0)
				env.poke(record, "Label", "engine")
				check
					:expect(thrown(function()
						env.poke(record, "Label", false)
					end))
					:toContain "Label requires a string"
				check:expect(record.Label):toEqual "engine"
				check:expect(changed):toEqual(1)
			end
		)

		suite:case("Parent validation preserves ancestry safety and rejects a move before its events", function(check)
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
			check
				:expect(thrown(function()
					branch.Parent = forbidden
				end))
				:toContain "destination refused"
			check
				:expect(thrown(function()
					branch.Parent = branch
				end))
				:toContain "own ancestor"
			check:expect(branch.Parent == previous):toEqual(true)
			check:expect(events):toEqual(0)
		end)

		suite:case("explicit fixture methods supply measurement, focus and style behavior", function(check)
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
			check
				:expect(
					(service.GetTextSize :: (Environment.Instance, string, number) -> Datatypes.Vector2Value)(
						service,
						"abc",
						2
					) == Roblox.datatypes.Vector2.new(6, 2)
				)
				:toEqual(true)
			local control = (env.createInstance("FixtureControl", { Label = "source", CanFocus = false }))
			check
				:expect(thrown(function()
					(control.CaptureFocus :: (Environment.Instance) -> ())(control)
				end))
				:toContain "focus is disabled"
			control.CanFocus = true
			local focus = control.CaptureFocus :: (Environment.Instance) -> ()
			local apply = control.ApplyStyle :: (Environment.Instance, string) -> ()
			focus(control)
			apply(control, "accent")
			local copy = (control.Clone :: (Environment.Instance) -> Fixture)(control)
			check:expect(control.HasFocus):toEqual(true)
			check:expect(copy ~= control and copy.Parent == nil):toEqual(true)
			check:expect(copy.Label):toEqual "source"
			check:expect(copy.Style):toEqual "accent"
			copy.Label = "copy"
			check:expect(control.Label):toEqual "source"
		end)

		suite:case("fires signals in connect order and honors a disconnect made during the fire", function(check)
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
			check:expect(order):toEqual { "first", "third" }
			check:expect(second.Connected):toEqual(false)
			check:expect(env.liveConnections()):toEqual(2)
		end)

		suite:case("a failing handler does not stop later handlers and is recorded", function(check)
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
			check:expect(reached):toEqual(true)
			check:expect(env.errors[1]):toContain "handler broke"
		end)

		suite:case("reparenting reports child events and Destroy locks, disconnects and cascades", function(check)
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
			check:expect(env.liveObjects()).never:toEqual(0)
			child:Destroy()
			check:expect(seen):toEqual { "added w", "removed w" }
			check:expect(destroyed):toEqual(1)
			check:expect(env.isAlive(child)):toEqual(false)
			check:expect(env.isAlive(grandchild)):toEqual(false)
			check:expect(child.Parent):toEqual(nil)
			check
				:expect(thrown(function()
					child.Parent = parent
				end))
				:toContain "locked"
			child:Destroy()
			check:expect(#parent:GetChildren()):toEqual(0)
		end)

		suite:case("subtree parenting notifies every gained ancestor after the final parent is visible", function(check)
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
				check:expect(branch.Parent == destination):toEqual(true)
				check:expect(object:IsDescendantOf(destination)):toEqual(true)
				table.insert(added, object)
			end)
			env.root.DescendantAdded:Connect(function(object: Environment.Instance)
				table.insert(rootAdded, object)
			end)
			for _, object in { branch, child, leaf } do
				object.AncestryChanged:Connect(function(moved: Environment.Instance, parent: Environment.Instance?)
					check:expect(branch.Parent == parent):toEqual(true)
					table.insert(ancestry, { object = object, moved = moved, parent = parent })
				end)
			end
			branch.Parent = destination
			check:expect(#added):toEqual(3)
			check:expect(#rootAdded):toEqual(3)
			check:expect(#ancestry):toEqual(3)
			for _, object in { branch, child, leaf } do
				check:expect(table.find(added, object) ~= nil):toEqual(true)
				check:expect(table.find(rootAdded, object) ~= nil):toEqual(true)
			end
			for _, record in ancestry do
				check:expect(record.moved == branch and record.parent == destination):toEqual(true)
			end
			branch.Parent = destination
			check:expect(#ancestry):toEqual(3)
			check:expect(#env.errors):toEqual(0)
		end)

		suite:case(
			"reparenting removes the subtree before mutation and notifies only lost or gained ancestors",
			function(check)
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
					check:expect(branch.Parent == previous):toEqual(true)
					check:expect(child.Parent == branch):toEqual(true)
					check:expect(object:IsDescendantOf(previous)):toEqual(true)
					table.insert(removals, object)
					table.insert(events, "removing")
					check
						:expect(thrown(function()
							object.Parent = env.root
						end))
						:toContain "locked"
				end)
				previous.ChildRemoved:Connect(function(object: Environment.Instance)
					check:expect(object == branch and object.Parent == destination):toEqual(true)
					check:expect(previous:FindFirstChild(tostring(branch.Name))):toEqual(nil)
					table.insert(events, "removed")
				end)
				destination.ChildAdded:Connect(function(object: Environment.Instance)
					check:expect(object == branch and object.Parent == destination):toEqual(true)
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
				check:expect(removals[1] == branch and removals[2] == child):toEqual(true)
				check:expect(#removals):toEqual(2)
				check:expect(#additions):toEqual(2)
				check:expect(events):toEqual { "removing", "removing", "removed" }
				check:expect(shared):toEqual(0)
				check:expect(#env.errors):toEqual(0)
			end
		)

		suite:case(
			"a removal handler cannot redirect the move and its failure does not stop notification",
			function(check)
				local env = environment()
				local previous = (env.createInstance "Folder")
				local destination = (env.createInstance "Folder")
				local branch = (env.createInstance("Folder", { Parent = previous }))
				local reached = 0
				previous.DescendantRemoving:Connect(function(object: Environment.Instance)
					object.Parent = env.root
				end)
				previous.DescendantRemoving:Connect(function(object: Environment.Instance)
					check:expect(object == branch and object.Parent == previous):toEqual(true)
					reached += 1
				end)
				branch.Parent = destination
				check:expect(branch.Parent == destination):toEqual(true)
				check:expect(reached):toEqual(1)
				check:expect(#env.errors):toEqual(1)
				check:expect(env.errors[1]):toContain "locked"
			end
		)

		suite:case("unparenting preserves descendants and reports the moved ancestor with a nil parent", function(check)
			local env = environment()
			local branch = (env.createInstance("Folder", { Parent = env.root }))
			local child = (env.createInstance("Folder", { Parent = branch }))
			local count = 0
			child.AncestryChanged:Connect(function(moved: Environment.Instance, parent: Environment.Instance?)
				check:expect(moved == branch and parent == nil and branch.Parent == nil):toEqual(true)
				check:expect(child.Parent == branch):toEqual(true)
				count += 1
			end)
			branch.Parent = nil
			branch.Parent = nil
			check:expect(count):toEqual(1)
			check:expect(env.isAlive(child)):toEqual(true)
			check:expect(#env.errors):toEqual(0)
		end)

		suite:case(
			"destroy removes a subtree once before child removal and disconnects its live connections",
			function(check)
				local env = environment()
				local branch = (env.createInstance("Folder", { Parent = env.root }))
				local child = (env.createInstance("Folder", { Parent = branch }))
				local leaf = (env.createInstance("Folder", { Parent = child }))
				local removed: { Environment.Instance } = {}
				local destroying = 0
				local connection = branch.Destroying:Connect(function()
					check:expect(branch.Parent == env.root):toEqual(true)
					destroying += 1
					branch:Destroy()
				end)
				local childConnection = child.AncestryChanged:Connect(function() end)
				local rootConnection = env.root.DescendantRemoving:Connect(function(object: Environment.Instance)
					check:expect(branch.Parent == env.root):toEqual(true)
					check:expect(object:IsDescendantOf(env.root)):toEqual(true)
					table.insert(removed, object)
				end)
				local removedConnection = env.root.ChildRemoved:Connect(function(object: Environment.Instance)
					check:expect(object == branch and object.Parent == nil):toEqual(true)
					check:expect(#removed):toEqual(3)
				end)
				branch:Destroy()
				branch:Destroy()
				check:expect(#removed):toEqual(3)
				check:expect(removed[1] == branch):toEqual(true)
				check:expect(table.find(removed, child) ~= nil and table.find(removed, leaf) ~= nil):toEqual(true)
				check:expect(destroying):toEqual(1)
				check:expect(connection.Connected or childConnection.Connected):toEqual(false)
				connection:Disconnect()
				childConnection:Disconnect()
				check:expect(env.liveObjects()):toEqual(0)
				check:expect(env.liveConnections()):toEqual(2)
				rootConnection:Disconnect()
				removedConnection:Disconnect()
				check:expect(env.liveConnections()):toEqual(0)
				check:expect(#env.errors):toEqual(0)
			end
		)

		suite:case("ClearAllChildren destroys each subtree and retains only the parent's subscriptions", function(check)
			local env = environment()
			local parent = (env.createInstance "Folder")
			local first = (env.createInstance("Folder", { Parent = parent }))
			local leaf = (env.createInstance("Folder", { Parent = first }))
			local second = (env.createInstance("Folder", { Parent = parent }))
			local removed: { Environment.Instance } = {}
			local connection = leaf.Destroying:Connect(function() end)
			parent.DescendantRemoving:Connect(function(object: Environment.Instance)
				check:expect(object:IsDescendantOf(parent)):toEqual(true)
				table.insert(removed, object)
			end)
			parent:ClearAllChildren()
			parent:ClearAllChildren()
			check:expect(#removed):toEqual(3)
			check:expect(table.find(removed, first) < table.find(removed, leaf)):toEqual(true)
			check:expect(env.isAlive(first) or env.isAlive(second) or env.isAlive(leaf)):toEqual(false)
			check:expect(connection.Connected):toEqual(false)
			check:expect(env.liveObjects()):toEqual(1)
			check:expect(env.liveConnections()):toEqual(1)
			check:expect(#parent:GetChildren()):toEqual(0)
			check:expect(#env.errors):toEqual(0)
		end)

		suite:case("DisconnectAll updates handles and remains idempotent", function(check)
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
			check:expect(connection.Connected):toEqual(false)
			check:expect(env.liveConnections()):toEqual(0)
			check:expect(fired):toEqual(0)
		end)

		suite:case("tracks live objects and connections so a disposal test can assert nothing leaked", function(check)
			local env = environment()
			local before = env.liveObjects()
			local widget = (env.createInstance("Widget", { Parent = env.root })) :: Fixture
			(widget.Pinged):Connect(function() end)
			widget:GetPropertyChangedSignal("Label"):Connect(function() end)
			check:expect(env.liveObjects()):toEqual(before + 1)
			check:expect(env.liveConnections()):toEqual(2)
			widget:Destroy()
			check:expect(env.liveObjects()):toEqual(before)
			check:expect(env.liveConnections()):toEqual(0)
		end)

		suite:case("property changes fire only on change and Changed names the property", function(check)
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
			check:expect(fired):toEqual { "count", "Count", "count", "Count" }
		end)

		suite:case("attributes validate names and types and honor explicit limits", function(check)
			local env = Roblox.testEnvironment { limits = { attributeNameLength = 8, attributeStringLength = 50 } }
			local folder = (env.createInstance "Folder")
			folder:SetAttribute("Short", "ok")
			check:expect(folder:GetAttribute "Short"):toEqual "ok"
			check
				:expect(thrown(function()
					folder:SetAttribute("ThisNameIsTooLong", 1)
				end))
				:toContain "longer than 8 characters"
			check
				:expect(thrown(function()
					folder:SetAttribute("Long", string.rep("x", 51))
				end))
				:toContain "longer than 50 characters"
			check
				:expect(thrown(function()
					folder:SetAttribute("Bad", {})
				end))
				:toContain "cannot hold a table"
			check
				:expect(thrown(function()
					folder:SetAttribute("bad name", 1)
				end))
				:toContain "alphanumeric"
			local changes: { string } = {}
			folder:GetAttributeChangedSignal("Short"):Connect(function()
				table.insert(changes, tostring(folder:GetAttribute "Short"))
			end)
			folder:SetAttribute("Short", "two")
			folder:SetAttribute("Short", "two")
			check:expect(changes):toEqual { "two" }
		end)

		suite:case("attributes accept the value types the engine accepts and refuse the rest by name", function(check)
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
			check:expect(folder:GetAttribute "Position"):toEqual(Datatypes.Vector3.new(1, 2, 3))
			check:expect(Datatypes.typeName(folder:GetAttribute "Info")):toBe "TweenInfo"
			check:expect(Datatypes.typeName(folder:GetAttribute "Range")):toBe "NumberRange"
			check
				:expect(thrown(function()
					folder:SetAttribute("Bad", {})
				end))
				:toContain "cannot hold a table"
			check
				:expect(thrown(function()
					folder:SetAttribute("Bad", function() end)
				end))
				:toContain "cannot hold a function"
			check
				:expect(thrown(function()
					folder:SetAttribute("Bad", buffer.create(1))
				end))
				:toContain "cannot hold a buffer"
			check:expect(folder:GetAttribute "Bad"):toBe(nil)
		end)

		suite:case("a signal handle fires an event and counts its connections and fires", function(check)
			local env = environment()
			local widget = (env.createInstance "Widget") :: Fixture
			local handle = env.signalOf(widget, "Pinged")
			check:expect(handle.connections()):toBe(0)
			local calls = 0
			local connection = widget.Pinged:Connect(function()
				calls += 1
			end)
			handle.fire()
			handle.fire()
			check:expect(calls):toBe(2)
			check:expect(handle.connections()):toBe(1)
			check:expect(handle.fires()):toBe(2)
			connection:Disconnect()
			check:expect(handle.connections()):toBe(0)
			check
				:expect(thrown(function()
					env.signalOf(widget, "Missing")
				end))
				:toContain "not a valid member"
		end)

		suite:case("a create hook sees every new instance until disconnected", function(check)
			local env = environment()
			local seen: { string } = {}
			local connection = env.onCreate(function(object)
				table.insert(seen, object.ClassName)
			end)
			local widget = env.createInstance("Widget", { env.createInstance "Folder" })
			widget:Clone()
			connection:Disconnect()
			env.createInstance "Folder"
			check:expect(seen):toEqual { "Folder", "Widget", "Widget", "Folder" }
		end)

		suite:case("virtual time orders spawn, defer, delay and wait deterministically", function(check)
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
			check:expect(order):toEqual { "spawn", "sync", "defer", "delay1", "waited", "delay2" }
			check:expect(env.now()):toEqual(2)
		end)

		suite:case("cancel stops a pending delay and a scheduler failure is reported not hidden", function(check)
			local env = environment()
			local ran = false
			local pending = env.task.delay(1, function()
				ran = true
			end)
			env.task.cancel(pending)
			env.step(2)
			check:expect(ran):toEqual(false)
			env.task.defer(function()
				error "deferred broke"
			end)
			env.step(0)
			check:expect(#env.scheduler.failures):toEqual(1)
			check:expect(env.scheduler.failures[1]):toContain "deferred broke"
		end)

		suite:case("heartbeat fires once per step with the step length", function(check)
			local env = environment()
			local deltas: { number } = {}
			env.heartbeat:Connect(function(delta: number)
				table.insert(deltas, delta)
			end)
			env.step(0.5)
			env.step(0.25)
			check:expect(deltas):toEqual { 0.5, 0.25 }
		end)

		suite:case("injects one named failure and recovers", function(check)
			local env = environment()
			env.failNext "setParent"
			check
				:expect(thrown(function()
					env.createInstance("Folder", { Parent = env.root })
				end))
				:toContain "injected failure in setParent"
			local folder = (env.createInstance("Folder", { Parent = env.root }))
			check:expect(folder.Parent):toEqual(env.root)
			env.failNext("create", 2)
			env.clearFailures()
			env.createInstance "Folder"
		end)

		suite:case("finds, names and relates instances", function(check)
			local env = environment()
			local a = (env.createInstance("Folder", { Name = "a", Parent = env.root }))
			local b = (env.createInstance("Part", { Name = "b", Parent = a }))
			check:expect(a:FindFirstChild "b"):toEqual(b)
			check:expect(env.root:FindFirstChild("b", true)):toEqual(b)
			check:expect(b:GetFullName()):toEqual "a.b"
			check:expect(b:IsDescendantOf(env.root)):toEqual(true)
			check:expect(b:FindFirstAncestor "a"):toEqual(a)
			check:expect(a:FindFirstChildWhichIsA "BasePart"):toEqual(b)
			check:expect(a:FindFirstChildOfClass "BasePart"):toEqual(nil)
			check:expect(#env.root:GetDescendants()):toEqual(2)
			check
				:expect(thrown(function()
					a.Parent = b
				end))
				:toContain "own ancestor"
		end)

		suite:case("datatypes compare by value and report their type name and CFrame components", function(check)
			local types = Roblox.datatypes
			check:expect(types.Vector2.new(1, 2) == types.Vector2.new(1, 2)):toEqual(true)
			check:expect(types.Vector3.new(1, 2, 3) == types.Vector3.new(1, 2, 4)):toEqual(false)
			check:expect(types.Color3.new(0.5, 0, 1) == types.Color3.new(0.5, 0, 1)):toEqual(true)
			check:expect(types.UDim.new(1, 2) == types.UDim.new(1, 2)):toEqual(true)
			check:expect(types.UDim2.fromOffset(3, 4) == types.UDim2.new(0, 3, 0, 4)):toEqual(true)
			check:expect(types.UDim2.fromScale(1, 1) == types.UDim2.fromOffset(1, 1)):toEqual(false)
			local frame = types.CFrame.new(1, 2, 3) * types.CFrame.Angles(0, math.pi / 2, 0)
			check:expect(frame == types.CFrame.new(1, 2, 3) * types.CFrame.Angles(0, math.pi / 2, 0)):toEqual(true)
			check:expect(types.typeName(types.UDim2.new())):toEqual "UDim2"
			local size = types.UDim2.new(0.5, 3, 1, 4)
			check:expect(size.X == types.UDim.new(0.5, 3)):toEqual(true)
			check:expect(size.Y.Offset):toEqual(4)
			check:expect(size.Width == size.X and size.Height == size.Y):toEqual(true)
			check:expect(types.UDim2.new(types.UDim.new(0.5, 3), types.UDim.new(1, 4)) == size):toEqual(true)
			local turned = types.CFrame.new(1, 2, 3, 0, 0, 1, 0, 1, 0, -1, 0, 0)
			local _, _, _, turnedRotation = types.readCFrame(turned)
			check:expect(turnedRotation[3]):toEqual(1)
			check:expect(turnedRotation[7]):toEqual(-1)
			check:expect(types.typeName(frame)):toEqual "CFrame"
			check:expect(types.typeName(5)):toEqual(nil)
			local x, y, z, rotation = types.readCFrame(frame)
			check:expect({ x, y, z }):toEqual { 1, 2, 3 }
			check:expect(#rotation):toEqual(9)
			check:expect(select("#", frame:GetComponents())):toEqual(12)
			check:expect(Roblox.typeName(types.Vector3.new())):toEqual "Vector3"
		end)

		suite:case("builtin gui classes declare layout and appearance members", function(check)
			local env = Roblox.testEnvironment()
			local frame = (env.createInstance "Frame")
			frame.Size = Roblox.datatypes.UDim2.fromOffset(10, 20)
			frame.BackgroundColor3 = Roblox.datatypes.Color3.new(1, 0, 0)
			check:expect((frame.Position :: Datatypes.UDim2Value) == Roblox.datatypes.UDim2.new()):toEqual(true)
			for _, name in { "UIListLayout", "ScrollingFrame", "TextBox", "CanvasGroup" } do
				check:expect(env.createInstance(name).ClassName):toEqual(name)
			end
			check
				:expect(
					(env.createInstance("ScrollingFrame").CanvasPosition :: Datatypes.Vector2Value)
						== Roblox.datatypes.Vector2.new()
				)
				:toEqual(true)
		end)

		suite:case("an engine-side poke fires property changes only when the value changes", function(check)
			local env = Roblox.testEnvironment()
			local frame = (env.createInstance "Frame")
			local fired = 0
			frame:GetPropertyChangedSignal("Visible"):Connect(function()
				fired += 1
			end)
			env.poke(frame, "Visible", false)
			env.poke(frame, "Visible", false)
			env.poke(frame, "Visible", true)
			check:expect(fired):toEqual(2)
		end)

		suite:case("createInstance takes children in the array part and parents them", function(check)
			local env = Roblox.testEnvironment()
			local a = (env.createInstance("Part", { Name = "a" }))
			local b = assert((env.createInstance("Part", { Name = "b" })))
			local model = (env.createInstance("Model", { Name = "m", a, b, Parent = env.root }))
			check:expect(#model:GetChildren()):toEqual(2)
			check:expect(a.Parent):toEqual(model)
			check:expect(model.Parent):toEqual(env.root)
			check:expect(Roblox.isInstance(model)):toEqual(true)
			check:expect(Roblox.isInstance {}):toEqual(false)
		end)

		suite:case("Animator loads a track that plays, stops and reports Stopped and Ended", function(check)
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
			check:expect(track.IsPlaying):toEqual(true)
			check:expect(track.Speed):toEqual(2)
			local stop: (Environment.Instance) -> () = track.Stop
			stop(track)
			stop(track)
			check:expect(track.IsPlaying):toEqual(false)
			check:expect(seen):toEqual { "stopped", "ended" }
		end)

		suite:case("a snapshot lists the set properties, attributes and children of a tree", function(check)
			local env = Roblox.testEnvironment()
			local part = (env.createInstance("Part", { Name = "p", Anchored = true }))
			local model = (env.createInstance("Model", { Name = "m", part }))
			model:SetAttribute("Tag", "x")
			local view = env.snapshot(model)
			check:expect(view.className):toEqual "Model"
			check:expect(view.attributes):toEqual { Tag = "x" }
			check:expect(view.children[1].name):toEqual "p"
			check:expect(view.children[1].properties.Anchored):toEqual(true)
		end)

		suite:case("method tables written as plain function literals type-check without casts", function(check)
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
			check:expect((gadget.Twice :: (Environment.Instance, number) -> number)(gadget, 4)):toEqual(8)
		end)
	end)
end
