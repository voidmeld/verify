--!strict

local Test = require "./harness"
local it, expect = Test.it, Test.expect
local Roblox = require "../src/roblox"
local Lute = require "../src/lute"
local Transition = require "../src/roblox/ui-style-transition"

local function fixture(own: (() -> ()) -> (), shared: boolean?)
	local roots: { Roblox.Instance } = {}
	local reads: { [Roblox.Instance]: number } = {}
	local layoutReads: { [Roblox.Instance]: number } = {}
	local styleVisits: { [Roblox.Object]: number } = {}
	local readStyled: (Roblox.Instance, string) -> unknown = function()
		error "style reader unavailable"
	end
	local bridge = Lute.fixture.bridge(nil, {
		ui = { measureBounds = false, measureText = false },
		layout = {
			read = function(object, property)
				layoutReads[object] = (layoutReads[object] or 0) + 1
				if property == "Size" then
					reads[object] = (reads[object] or 0) + 1
				end
				return readStyled(object, property)
			end,
			roots = function()
				return roots
			end,
			viewport = function()
				return { X = 800, Y = 600 }
			end,
		},
	})
	own(function()
		bridge.close()
	end)
	local env, ui, layout = bridge.environment, assert(bridge.ui), assert(bridge.layout)
	local types = bridge.placeEngine().datatypes
	readStyled = ui.styled
	local selectors: { [Roblox.Object]: number } = {}
	local isAlive = env.isAlive
	env.isAlive = function(object)
		styleVisits[object] = (styleVisits[object] or 0) + 1
		return isAlive(object)
	end
	local propertyOf = env.propertyOf
	env.propertyOf = function(object, property)
		if property == "Selector" then
			selectors[object] = (selectors[object] or 0) + 1
		end
		return propertyOf(object, property)
	end
	local function set(object: Roblox.Instance, name: string, value: unknown)
		env.method(object, "SetProperty")(object, name, value)
	end
	local container = if shared then env.createInstance "Folder" else nil
	if container then
		table.insert(roots, container)
	end
	local function mount()
		local root = env.createInstance("ScreenGui", { Parent = container })
		local frame = env.createInstance("Frame", { Parent = root })
		local sheet = env.createInstance "StyleSheet"
		local rule = env.createInstance("StyleRule", { Parent = sheet, Selector = "Frame" })
		set(rule, "Size", types.UDim2.fromOffset(200, 100))
		local link = env.createInstance("StyleLink", { Parent = root, StyleSheet = sheet })
		if container == nil then
			table.insert(roots, root)
		end
		return { root = root, frame = frame, sheet = sheet, rule = rule, link = link }
	end
	local function settle()
		layout.step()
		layout.step()
		table.clear(reads)
		table.clear(selectors)
		table.clear(layoutReads)
		table.clear(styleVisits)
	end
	return {
		env = env,
		ui = ui,
		layout = layout,
		types = types,
		mount = mount,
		set = set,
		settle = settle,
		reads = reads,
		layoutReads = layoutReads,
		styleVisits = styleVisits,
		selectors = selectors,
		roots = roots,
		close = bridge.close,
	}
end

it("sheet edits update linked geometry and values without measuring independent trees", function(own)
	local f = fixture(own)
	local a, b = f.mount(), f.mount()
	f.set(b.rule, "BackgroundTransparency", 0.25)
	f.ui.styled(b.frame, "BackgroundTransparency")
	f.settle()
	local epoch = f.env.layoutEpoch()
	f.set(a.rule, "Size", f.types.UDim2.fromOffset(240, 120))
	f.set(a.rule, "BackgroundTransparency", 0.5)
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(240, 120))
	expect(f.ui.styled(a.frame, "BackgroundTransparency")):toBe(0.5)
	expect(f.ui.styled(b.frame, "BackgroundTransparency")):toBe(0.25)
	expect(f.selectors[b.rule] or 0):toBe(0)
	expect((f.reads[a.frame] or 0) > 0):toBe(true)
	expect(f.reads[b.frame] or 0):toBe(0)
	expect(f.env.layoutEpoch()):toBe(epoch)
	f.settle()
	a.rule.Selector = ".selected"
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(0, 0))
	expect(f.reads[b.frame] or 0):toBe(0)
	a.frame:AddTag "selected"
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(240, 120))
	local higher = f.env.createInstance("StyleRule", { Parent = a.sheet, Selector = "Frame", Priority = 1 })
	f.set(higher, "Size", f.types.UDim2.fromOffset(300, 80))
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(300, 80))
	a.rule.Priority = 2
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(240, 120))
	expect(f.reads[b.frame] or 0):toBe(0)
end)

it("nested independent links retain their measurements when the outer sheet changes", function(own)
	local f = fixture(own)
	local a, b = f.mount(), f.mount()
	b.link.Parent = b.frame
	b.frame.Parent = a.root
	local child = f.env.createInstance("Frame", { Parent = b.frame })
	f.settle()
	f.set(a.rule, "Size", f.types.UDim2.fromOffset(240, 120))
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(240, 120))
	expect(b.frame.AbsoluteSize):toEqual(f.types.Vector2.new(200, 100))
	expect(child.AbsoluteSize):toEqual(f.types.Vector2.new(200, 100))
	expect(f.reads[b.frame] or 0):toBe(0)
	expect(f.reads[child] or 0):toBe(0)
end)

it("detached rules and tokens stay inert until attachment or linking", function(own)
	local f = fixture(own)
	local a, b = f.mount(), f.mount()
	f.settle()
	local epoch = f.env.layoutEpoch()
	local sheet = f.env.createInstance "StyleSheet"
	local rule = f.env.createInstance("StyleRule", { Selector = "Frame", Parent = sheet })
	f.env.method(rule, "SetProperties")(rule, { Size = "$Extent", BackgroundTransparency = 0.5 })
	sheet:SetAttribute("Extent", f.types.UDim2.fromOffset(320, 90))
	f.layout.step()
	expect(f.reads[a.frame] or 0):toBe(0)
	expect(f.reads[b.frame] or 0):toBe(0)
	expect(f.env.layoutEpoch()):toBe(epoch)
	a.link.StyleSheet = sheet
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(320, 90))
	expect(f.ui.styled(a.frame, "BackgroundTransparency")):toBe(0.5)
	f.settle()
	sheet:SetAttribute("Extent", f.types.UDim2.fromOffset(360, 110))
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(360, 110))
	expect(f.reads[b.frame] or 0):toBe(0)
	b.sheet:SetAttribute("Extent", f.types.UDim2.fromOffset(420, 140))
	rule.Priority = 1
	rule.Parent = b.sheet
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(0, 0))
	f.layout.step()
	expect(b.frame.AbsoluteSize):toEqual(f.types.Vector2.new(420, 140))
	f.settle()
	rule.Parent = nil
	f.layout.step()
	expect(b.frame.AbsoluteSize):toEqual(f.types.Vector2.new(200, 100))
	expect(f.reads[a.frame] or 0):toBe(0)
	f.set(rule, "Size", f.types.UDim2.fromOffset(180, 70))
	rule.Parent = sheet
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(180, 70))
end)

it("links and scope reparenting invalidate their old and new trees", function(own)
	local f = fixture(own)
	local a, b = f.mount(), f.mount()
	f.set(b.rule, "Size", f.types.UDim2.fromOffset(300, 150))
	f.settle()
	a.link.StyleSheet = nil
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(0, 0))
	expect(f.reads[b.frame] or 0):toBe(0)
	a.link.StyleSheet = a.sheet
	a.link.Parent = a.frame
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(200, 100))
	a.link.Parent = nil
	a.frame.Parent = b.root
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(300, 150))
	a.frame.Parent = a.root
	a.link.Parent = a.root
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(200, 100))
	a.link:Destroy()
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(0, 0))
end)

it("ancestor selectors and tags refresh descendant geometry within their scope", function(own)
	local f = fixture(own)
	local a, b = f.mount(), f.mount()
	a.rule.Selector = ".active >> Frame"
	local child = f.env.createInstance("Frame", { Parent = a.frame })
	f.settle()
	a.frame:AddTag "active"
	f.layout.step()
	expect(child.AbsoluteSize):toEqual(f.types.Vector2.new(200, 100))
	expect(f.reads[b.frame] or 0):toBe(0)
	a.frame:RemoveTag "active"
	f.layout.step()
	expect(child.AbsoluteSize):toEqual(f.types.Vector2.new(0, 0))
	a.rule.Selector = "#Named >> Frame"
	a.frame.Name = "Named"
	f.layout.step()
	expect(child.AbsoluteSize):toEqual(f.types.Vector2.new(200, 100))
	a.frame.Name = "Other"
	f.layout.step()
	expect(child.AbsoluteSize):toEqual(f.types.Vector2.new(0, 0))
	expect(f.reads[b.frame] or 0):toBe(0)
end)

it("transition edits preserve motion and watches without measuring other sheets", function(own)
	local f = fixture(own)
	local a, b = f.mount(), f.mount()
	local fires = 0
	f.env.connect(f.env.method(a.frame, "GetStyledPropertyChangedSignal")(a.frame, "Size"), function()
		fires += 1
	end)
	f.env.method(a.rule, "SetPropertyTransitions")(a.rule, {
		Size = f.types.TweenInfo.new(1, f.types.Enum.EasingStyle.Linear),
	})
	f.settle()
	f.set(a.rule, "Size", f.types.UDim2.fromOffset(400, 200))
	f.env.step(0.5)
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(300, 150))
	expect(fires > 0):toBe(true)
	expect(f.reads[b.frame] or 0):toBe(0)
	f.set(a.rule, "Size", f.types.UDim2.fromOffset(500, 250))
	f.env.step(0.5)
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(400, 200))
	f.env.step(0.5)
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(500, 250))
	f.env.method(a.rule, "SetPropertyTransition")(a.rule, "Size", nil)
	f.env.method(a.rule, "SetDefaultPropertyTransition")(a.rule, f.types.TweenInfo.new(0))
	f.set(a.rule, "Size", f.types.UDim2.fromOffset(220, 110))
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(220, 110))
	expect(f.reads[b.frame] or 0):toBe(0)
end)

it("derive dependencies propagate transitively with cycle protection and retain resolution limits", function(own)
	local f = fixture(own)
	local a, b = f.mount(), f.mount()
	local base = f.env.createInstance "StyleSheet"
	local middle = f.env.createInstance "StyleSheet"
	local edge = f.env.createInstance("StyleDerive", { Parent = a.sheet, StyleSheet = middle })
	f.env.method(middle, "SetDerives")(middle, { base })
	f.settle()
	local before = f.env.layoutStamp(a.frame)
	base:SetAttribute("Token", 10)
	expect(f.env.layoutStamp(a.frame) > before):toBe(true)
	f.layout.step()
	expect(f.reads[b.frame] or 0):toBe(0)
	f.env.method(base, "SetDerives")(base, { a.sheet })
	local detached = f.env.createInstance "StyleSheet"
	detached:SetAttribute("Unrelated", 1)
	f.settle()
	before = f.env.layoutStamp(a.frame)
	base:SetAttribute("Token", 20)
	expect(f.env.layoutStamp(a.frame) > before):toBe(true)
	f.env.method(base, "SetDerives")(base, {})
	edge.StyleSheet = nil
	f.settle()
	before = f.env.layoutStamp(a.frame)
	base:SetAttribute("Token", 30)
	expect(f.env.layoutStamp(a.frame)):toBe(before)
	edge.StyleSheet = middle
	f.env.method(a.sheet, "SetDerives")(a.sheet, { base })
	expect((pcall(f.ui.styled, a.frame, "Size"))):toBe(false)
	f.env.method(a.sheet, "SetDerives")(a.sheet, {})
	expect(f.ui.styled(a.frame, "Size")):toEqual(f.types.UDim2.fromOffset(200, 100))
	edge.Parent = b.sheet
	f.settle()
	local otherBefore = f.env.layoutStamp(b.frame)
	before = f.env.layoutStamp(a.frame)
	base:SetAttribute("Token", 35)
	expect(f.env.layoutStamp(a.frame)):toBe(before)
	expect(f.env.layoutStamp(b.frame) > otherBefore):toBe(true)
	edge:Destroy()
	f.settle()
	before = f.env.layoutStamp(a.frame)
	base:SetAttribute("Token", 40)
	expect(f.env.layoutStamp(a.frame)):toBe(before)
	expect(f.reads[b.frame] or 0):toBe(0)
end)

it("rule and sheet disposal releases indexes and preserves independent scopes", function(own)
	local f = fixture(own)
	local a, b = f.mount(), f.mount()
	f.settle()
	a.rule:Destroy()
	f.layout.step()
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(0, 0))
	expect(f.reads[b.frame] or 0):toBe(0)
	b.sheet:Destroy()
	f.layout.step()
	expect(b.frame.AbsoluteSize):toEqual(f.types.Vector2.new(0, 0))
	a.root:Destroy()
	table.remove(f.roots, 1)
	f.settle()
	f.close()
	expect(f.env.liveConnections()):toBe(0)
end)

it("repeated independent mounts and edits require bounded measurements", function(own)
	local f = fixture(own)
	local total = 0
	for _ = 1, 9 do
		local mounted = f.mount()
		f.layout.step()
		f.layout.step()
		local measured = 0
		for _, count in f.reads do
			measured += count
		end
		expect(measured):toBe(1)
		total += measured
		table.clear(f.reads)
		f.set(mounted.rule, "Size", f.types.UDim2.fromOffset(240, 120))
		f.layout.step()
		measured = 0
		for _, count in f.reads do
			measured += count
		end
		expect(measured):toBe(1)
		expect(mounted.frame.AbsoluteSize):toEqual(f.types.Vector2.new(240, 120))
		table.clear(f.reads)
	end
	expect(total):toBe(9)
	local epoch = f.env.layoutEpoch()
	f.env.invalidateLayout()
	f.layout.step()
	local measured = 0
	for _, count in f.reads do
		measured += count
	end
	expect(measured):toBe(9)
	expect(f.env.layoutEpoch() > epoch):toBe(true)
end)

it("live mount validation and style notifications visit only changed trees", function(own)
	local f = fixture(own, true)
	local mounts = {}
	local expectedReads: number? = nil
	for _ = 1, 24 do
		f.settle()
		local mounted = f.mount()
		local styledFires, propertyFires = 0, 0
		mounted.frame.StyledPropertiesChanged:Connect(function()
			styledFires += 1
		end)
		f.env.connect(f.env.method(mounted.frame, "GetStyledPropertyChangedSignal")(mounted.frame, "Size"), function()
			propertyFires += 1
		end)
		f.ui.styled(mounted.frame, "Size")
		f.layout.step()
		local count = f.layoutReads[mounted.frame] or 0
		expect(count > 0):toBe(true)
		expectedReads = expectedReads or count
		expect(count):toBe(expectedReads)
		for _, previous in mounts do
			assert((f.layoutReads[previous.frame] or 0) == 0, `old layout reads {f.layoutReads[previous.frame]}`)
			assert((f.styleVisits[previous.frame] or 0) == 0, `old style visits {f.styleVisits[previous.frame]}`)
		end
		f.settle()
		f.set(mounted.rule, "Size", f.types.UDim2.fromOffset(250, 125))
		table.clear(f.styleVisits)
		f.layout.step()
		expect(mounted.frame.AbsoluteSize):toEqual(f.types.Vector2.new(250, 125))
		expect(styledFires):toBe(1)
		expect(propertyFires):toBe(1)
		for _, previous in mounts do
			assert((f.layoutReads[previous.frame] or 0) == 0, `old layout reads {f.layoutReads[previous.frame]}`)
			assert((f.styleVisits[previous.frame] or 0) == 0, `old style visits {f.styleVisits[previous.frame]}`)
		end
		table.insert(mounts, mounted)
	end
end)

it("geometry reads flush their own roots and leave independent dirty roots pending", function(own)
	local f = fixture(own)
	local a, b = f.mount(), f.mount()
	f.settle()
	f.set(a.rule, "Size", f.types.UDim2.fromOffset(240, 120))
	f.set(b.rule, "Size", f.types.UDim2.fromOffset(360, 180))
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(240, 120))
	expect(f.layoutReads[b.frame] or 0):toBe(0)
	expect(f.env.propertyOf(b.frame, "AbsoluteSize")):toEqual(f.types.Vector2.new(200, 100))
	expect(b.frame.AbsoluteSize):toEqual(f.types.Vector2.new(360, 180))
	f.settle()
	local invalid = f.env.createInstance("UITableLayout", { Parent = b.frame })
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(240, 120))
	expect((pcall(f.layout.step))):toBe(false)
	invalid:Destroy()
	f.set(b.rule, "Size", f.types.UDim2.fromOffset(400, 200))
	expect(b.frame.AbsoluteSize):toEqual(f.types.Vector2.new(400, 200))
end)

it("failed style observations stay dirty until their rules are repaired", function(own)
	local f = fixture(own)
	local mounted = f.mount()
	f.env.method(mounted.frame, "GetStyledPropertyChangedSignal")(mounted.frame, "Size")
	f.settle()
	mounted.rule.Selector = "Frame:hover"
	expect((pcall(f.ui.step))):toBe(false)
	expect((pcall(f.ui.step))):toBe(false)
	mounted.rule.Selector = "Frame"
	f.set(mounted.rule, "Size", f.types.UDim2.fromOffset(300, 150))
	f.ui.step()
	expect(mounted.frame.AbsoluteSize):toEqual(f.types.Vector2.new(300, 150))
end)

it("geometry readers share a flush within each root while other roots stay pending", function(own)
	local f = fixture(own)
	local a, b = f.mount(), f.mount()
	local child = f.env.createInstance("Frame", { Parent = a.root })
	local flushes = 0
	local flush = f.layout.flush
	f.layout.flush = function(object)
		flushes += 1
		flush(object)
	end
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(200, 100))
	expect(child.AbsoluteSize):toEqual(f.types.Vector2.new(200, 100))
	expect(flushes):toBe(1)
	expect(b.frame.AbsoluteSize):toEqual(f.types.Vector2.new(200, 100))
	expect(flushes):toBe(2)
	f.set(a.rule, "Size", f.types.UDim2.fromOffset(300, 150))
	expect(child.AbsoluteSize):toEqual(f.types.Vector2.new(300, 150))
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(300, 150))
	expect(flushes):toBe(3)
	f.env.method(a.rule, "SetPropertyTransition")(
		a.rule,
		"Size",
		f.types.TweenInfo.new(1, f.types.Enum.EasingStyle.Linear)
	)
	f.ui.styled(a.frame, "Size")
	f.ui.styled(child, "Size")
	f.set(a.rule, "Size", f.types.UDim2.fromOffset(400, 200))
	f.env.step(0.5)
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(350, 175))
	expect(child.AbsoluteSize):toEqual(f.types.Vector2.new(350, 175))
	expect(flushes):toBe(4)
end)

it("settled transition definitions require no per-step motion checks across live mounts", function(own)
	local f = fixture(own, true)
	local last = f.mount()
	for index = 1, 24 do
		local mounted = if index == 1 then last else f.mount()
		f.env.method(mounted.rule, "SetPropertyTransition")(
			mounted.rule,
			"BackgroundTransparency",
			f.types.TweenInfo.new(1, f.types.Enum.EasingStyle.Linear)
		)
		f.ui.styled(mounted.frame, "BackgroundTransparency")
		last = mounted
	end
	f.settle()
	local checks = 0
	local running = Transition.running
	Transition.running = function(motion, now)
		checks += 1
		return running(motion, now)
	end
	own(function()
		Transition.running = running
	end)
	f.layout.step()
	expect(f.ui.animating()):toBe(false)
	expect(f.ui.animating(true)):toBe(false)
	expect(checks):toBe(0)
	f.set(last.rule, "BackgroundTransparency", 1)
	f.env.step(0.5)
	f.ui.step()
	expect(f.ui.styled(last.frame, "BackgroundTransparency")):toBe(0.5)
	expect(f.ui.animating()):toBe(true)
	f.env.step(0.5)
	f.ui.step()
	expect(f.ui.styled(last.frame, "BackgroundTransparency")):toBe(1)
	f.settle()
	checks = 0
	f.layout.step()
	expect(f.ui.animating()):toBe(false)
	expect(checks):toBe(0)
	f.set(last.rule, "BackgroundTransparency", 0)
	f.env.step(0.5)
	f.ui.step()
	expect(f.ui.styled(last.frame, "BackgroundTransparency")):toBe(0.5)
end)

it("unread sheet edits coalesce scope work and reads reopen invalidation", function(own)
	local f = fixture(own)
	local a, b = f.mount(), f.mount()
	f.settle()
	local stamps = 0
	local stamp = f.env.stampLayout
	f.env.stampLayout = function(object)
		stamps += 1
		stamp(object)
	end
	f.set(a.rule, "Size", f.types.UDim2.fromOffset(201, 101))
	local first = stamps
	expect(first > 0):toBe(true)
	for index = 2, 100 do
		f.set(a.rule, "Size", f.types.UDim2.fromOffset(200 + index, 100 + index))
	end
	expect(stamps):toBe(first)
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(300, 200))
	expect(f.layoutReads[b.frame] or 0):toBe(0)
	f.set(a.rule, "Size", f.types.UDim2.fromOffset(400, 250))
	expect(stamps > first):toBe(true)
	expect(f.ui.styled(a.frame, "Size")):toEqual(f.types.UDim2.fromOffset(400, 250))
	local afterRead = stamps
	f.set(a.rule, "Size", f.types.UDim2.fromOffset(500, 300))
	expect(stamps > afterRead):toBe(true)
	expect(a.frame.AbsoluteSize):toEqual(f.types.Vector2.new(500, 300))
end)

return nil
