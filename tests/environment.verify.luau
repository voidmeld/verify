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
			local widget = (env.createInstance("Widget", { Label = "go" })) :: Fixture
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
			local parent = (env.createInstance("Widget", { Parent = env.root })) :: Fixture
			local first = (env.createInstance("Folder", { Name = "Slot", Parent = parent })) :: Fixture
			env.createInstance("Folder", { Name = "Slot", Parent = parent })
			local other = (env.createInstance("Folder", { Name = "Other", Parent = parent })) :: Fixture
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
			check
				:expect(thrown(function()
					return (parent.WaitForChild :: (Environment.Instance, string) -> Environment.Instance)(
						parent,
						"Slot"
					)
				end))
				:toContain 'WaitForChild is not a valid member of Widget "Widget"'
		end)

		suite:case("a property, event or method wins over a child of the same name", function(check)
			local env = environment()
			local parent = (env.createInstance("Widget", { Label = "own", Parent = env.root })) :: Fixture
			env.createInstance("Folder", { Name = "Label", Parent = parent })
			env.createInstance("Folder", { Name = "Pinged", Parent = parent })
			env.createInstance("Folder", { Name = "Double", Parent = parent })
			env.createInstance("Folder", { Name = "Destroy", Parent = parent })
			check:expect(parent.Label):toEqual "own"
			check:expect((parent.Pinged :: Environment.Signal<()>).Connect ~= nil):toEqual(true)
			check:expect((parent.Double :: (Environment.Instance, number) -> number)(parent, 1)):toEqual(2)
			check:expect(type(parent.Destroy)):toEqual "function"
			check:expect(parent.ClassName):toEqual "Widget"
		end)

		suite:case(
			"a renamed, destroyed or reparented child is found only while it holds that name and parent",
			function(check)
				local env = environment()
				local parent = (env.createInstance("Widget", { Parent = env.root })) :: Fixture
				local elsewhere = (env.createInstance("Widget", { Parent = env.root })) :: Fixture
				local child = (env.createInstance("Folder", { Name = "Before", Parent = parent })) :: Fixture
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
			local parent = (env.createInstance("Widget", { Parent = env.root })) :: Fixture
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
			local frame = (env.createInstance "Frame") :: Fixture
			check:expect(frame.Extra):toEqual(1)
			check:expect(frame.Visible):toEqual(true)
			env.defineClass("Fresh", { super = "Instance" }, { replace = true })
			check:expect(env.createInstance("Fresh").ClassName):toEqual "Fresh"
		end)

		suite:case(
			"a declared method needs a simulation or a configured fake and never invents a result",
			function(check)
				local env = environment()
				local widget = (env.createInstance "Widget") :: Fixture
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
				local record = (env.createInstance "Record") :: Fixture
				local changed = 0
				record.Changed:Connect(function()
					changed += 1
				end)
				check
					:expect(thrown(function()
						(record :: Environment.Instance).Count = "wrong"
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
			local previous = (env.createInstance "Folder") :: Fixture
			forbidden = env.createInstance "Folder"
			local branch = (env.createInstance("Folder", { Parent = previous })) :: Fixture
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
			local service = (env.createInstance "TextService") :: Fixture
			check
				:expect(
					(service.GetTextSize :: (Environment.Instance, string, number) -> Datatypes.Vector2Value)(
						service,
						"abc",
						2
					) == Roblox.datatypes.Vector2.new(6, 2)
				)
				:toEqual(true)
			local control = (env.createInstance("FixtureControl", { Label = "source", CanFocus = false })) :: Fixture
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
			local parent = (env.createInstance("Folder", { Parent = env.root })) :: Fixture
			local seen: { string } = {}
			parent.ChildAdded:Connect(function(child: Environment.Instance)
				table.insert(seen, "added " .. tostring(child.Name))
			end)
			parent.ChildRemoved:Connect(function(child: Environment.Instance)
				table.insert(seen, "removed " .. tostring(child.Name))
			end)
			local child = (env.createInstance("Widget", { Name = "w", Parent = parent })) :: Fixture
			local grandchild = (env.createInstance("Folder", { Name = "g", Parent = child })) :: Fixture
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
			local destination = (env.createInstance("Folder", { Parent = env.root })) :: Fixture
			local branch = (env.createInstance "Folder") :: Fixture
			local child = (env.createInstance("Folder", { Parent = branch })) :: Fixture
			local leaf = (env.createInstance("Folder", { Parent = child })) :: Fixture
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
				local previous = (env.createInstance("Folder", { Parent = env.root })) :: Fixture
				local destination = (env.createInstance("Folder", { Parent = env.root })) :: Fixture
				local branch = (env.createInstance("Folder", { Parent = previous })) :: Fixture
				local child = (env.createInstance("Folder", { Parent = branch })) :: Fixture
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
				local previous = (env.createInstance "Folder") :: Fixture
				local destination = (env.createInstance "Folder") :: Fixture
				local branch = (env.createInstance("Folder", { Parent = previous })) :: Fixture
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
			local branch = (env.createInstance("Folder", { Parent = env.root })) :: Fixture
			local child = (env.createInstance("Folder", { Parent = branch })) :: Fixture
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
				local branch = (env.createInstance("Folder", { Parent = env.root })) :: Fixture
				local child = (env.createInstance("Folder", { Parent = branch })) :: Fixture
				local leaf = (env.createInstance("Folder", { Parent = child })) :: Fixture
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
			local parent = (env.createInstance "Folder") :: Fixture
			local first = (env.createInstance("Folder", { Parent = parent })) :: Fixture
			local leaf = (env.createInstance("Folder", { Parent = first })) :: Fixture
			local second = (env.createInstance("Folder", { Parent = parent })) :: Fixture
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
			(widget.Pinged :: Environment.Signal<()>):Connect(function() end)
			widget:GetPropertyChangedSignal("Label"):Connect(function() end)
			check:expect(env.liveObjects()):toEqual(before + 1)
			check:expect(env.liveConnections()):toEqual(2)
			widget:Destroy()
			check:expect(env.liveObjects()):toEqual(before)
			check:expect(env.liveConnections()):toEqual(0)
		end)

		suite:case("property changes fire only on change and Changed names the property", function(check)
			local env = environment()
			local widget = (env.createInstance "Widget") :: Fixture
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
			local folder = (env.createInstance "Folder") :: Fixture
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
			local folder = (env.createInstance "Folder") :: Fixture
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
			local folder = (env.createInstance("Folder", { Parent = env.root })) :: Fixture
			check:expect(folder.Parent):toEqual(env.root)
			env.failNext("create", 2)
			env.clearFailures()
			env.createInstance "Folder"
		end)

		suite:case("finds, names and relates instances", function(check)
			local env = environment()
			local a = (env.createInstance("Folder", { Name = "a", Parent = env.root })) :: Fixture
			local b = (env.createInstance("Part", { Name = "b", Parent = a })) :: Fixture
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
			local frame = (env.createInstance "Frame") :: Fixture
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
			local frame = (env.createInstance "Frame") :: Fixture
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
			local a = (env.createInstance("Part", { Name = "a" })) :: Fixture
			local b = (env.createInstance("Part", { Name = "b" })) :: Fixture
			local model = (env.createInstance("Model", { Name = "m", a, b, Parent = env.root })) :: Fixture
			check:expect(#model:GetChildren()):toEqual(2)
			check:expect(a.Parent):toEqual(model)
			check:expect(model.Parent):toEqual(env.root)
			check:expect(Roblox.isInstance(model)):toEqual(true)
			check:expect(Roblox.isInstance {}):toEqual(false)
		end)

		suite:case("Animator loads a track that plays, stops and reports Stopped and Ended", function(check)
			local env = Roblox.testEnvironment()
			local animator = (env.createInstance "Animator") :: Fixture
			local animation = (env.createInstance("Animation", { AnimationId = "rbxassetid://1" })) :: Fixture
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
			local play = track.Play :: (Environment.Instance) -> ()
			play(track)
			local speed = track.AdjustSpeed :: (Environment.Instance, number) -> ()
			speed(track, 2)
			check:expect(track.IsPlaying):toEqual(true)
			check:expect(track.Speed):toEqual(2)
			local stop = track.Stop :: (Environment.Instance) -> ()
			stop(track)
			stop(track)
			check:expect(track.IsPlaying):toEqual(false)
			check:expect(seen):toEqual { "stopped", "ended" }
		end)

		suite:case("a snapshot lists the set properties, attributes and children of a tree", function(check)
			local env = Roblox.testEnvironment()
			local part = (env.createInstance("Part", { Name = "p", Anchored = true })) :: Fixture
			local model = (env.createInstance("Model", { Name = "m", part })) :: Fixture
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
