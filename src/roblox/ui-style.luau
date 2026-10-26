--!strict

local Environment = require "./environment"
local Selector = require "./ui-style-selector"
local Values = require "./ui-values"
local Names = require "./datatypes/names"

type Instance = Environment.Instance
export type Properties = { [Instance]: { [string]: unknown } }
export type Controller = {
	styled: (Instance, string, string?) -> unknown,
	component: (Instance, string, string) -> unknown,
	signal: (Instance, string) -> Environment.Signal<()>,
	step: () -> (),
	cached: (() -> ()) -> (),
	close: () -> (),
	invalidate: () -> (),
}
type Resolved = { sheet: Instance?, value: unknown, present: boolean }
type Watch = { signal: Environment.Signal<()>, sheet: Instance?, value: unknown }
local PHANTOMS = { UIPadding = true, UICorner = true, UIStroke = true, UIGradient = true }

local function unsupported(detail: string): never
	error("unsupported_ui_style: " .. detail, 0)
end

local function create(
	env: Environment.Environment,
	properties: Properties,
	transitions: Properties,
	defaults: { [Instance]: unknown },
	derives: { [Instance]: { Instance } }
): Controller
	local watches: { [Instance]: { [string]: Watch } } = {}
	setmetatable(watches, { __mode = "k" })
	local parsed: { [string]: Selector.Selector } = {}
	type Index =
		{ rules: { Instance }, byProperty: { [string]: { Instance } }, connections: { Environment.Connection } }
	local indexes: { [Instance]: Index } = {}
	local function forget(sheet: Instance)
		local index = indexes[sheet]
		if index then
			indexes[sheet] = nil
			for _, connection in index.connections do
				connection:Disconnect()
			end
		end
	end
	local function invalidate()
		for sheet in indexes do
			forget(sheet)
		end
	end
	local frameScopes: { [Instance]: { sheet: Instance? } }? = nil
	local frameValues: { [Instance]: { [string]: Resolved } }? = nil
	local function linkedSheet(object: Instance): Instance?
		local current: Instance? = object
		while current do
			local link: Instance? = nil
			for _, child in current:GetChildren() do
				if child:IsA "StyleLink" then
					if link then
						unsupported "multiple StyleLinks"
					end
					link = child
				end
			end
			if link then
				local sheet = env.propertyOf(link, "StyleSheet")
				if sheet ~= nil then
					local instance = Environment.assertInstance(sheet)
					assert(instance:IsA "StyleSheet", "StyleLink requires a StyleSheet")
					return instance
				end
			end
			current = current.Parent
		end
		return nil
	end
	local function scope(object: Instance): Instance?
		local scopes = frameScopes
		if scopes == nil then
			return linkedSheet(object)
		end
		local known = scopes[object]
		if known == nil then
			known = { sheet = linkedSheet(object) }
			scopes[object] = known
		end
		return known.sheet
	end
	local function token(sheet: Instance, value: unknown): unknown
		local seen: { [string]: boolean } = {}
		while type(value) == "string" and value:sub(1, 1) == "$" do
			local name = value:sub(2)
			if seen[name] then
				unsupported("cyclic token " .. name)
			end
			seen[name] = true
			value = sheet:GetAttribute(name)
			if value == nil then
				unsupported("missing token " .. name)
			end
		end
		return value
	end
	local function branches(rule: Instance): Selector.Selector
		local source = Values.string(env.propertyOf(rule, "Selector"))
		local result = parsed[source]
		if result == nil then
			result = Selector.parse(source)
			parsed[source] = result
		end
		return result
	end
	local function indexOf(sheet: Instance): Index
		local known = indexes[sheet]
		if known then
			return known
		end
		local index: Index = { rules = {}, byProperty = {}, connections = {} }
		local function drop()
			forget(sheet)
		end
		table.insert(index.connections, sheet.ChildAdded:Connect(drop))
		table.insert(index.connections, sheet.ChildRemoved:Connect(drop))
		for _, candidate in sheet:GetChildren() do
			if not candidate:IsA "StyleRule" then
				continue
			end
			table.insert(index.rules, candidate)
			table.insert(index.connections, candidate:GetPropertyChangedSignal("Selector"):Connect(drop))
			table.insert(index.connections, candidate:GetPropertyChangedSignal("Priority"):Connect(drop))
			table.insert(index.connections, candidate.DescendantAdded:Connect(drop))
			table.insert(index.connections, candidate.DescendantRemoving:Connect(drop))
			local names: { [string]: boolean } = {}
			local own = properties[candidate]
			if own then
				for name in own do
					names[name] = true
				end
			end
			for _, descendant in candidate:GetDescendants() do
				if descendant:IsA "StyleRule" then
					local nested = properties[descendant]
					if nested then
						for name in nested do
							names[name] = true
						end
					end
				end
			end
			for name in names do
				local list = index.byProperty[name]
				if list == nil then
					list = {}
					index.byProperty[name] = list
				end
				table.insert(list, candidate)
			end
		end
		indexes[sheet] = index
		return index
	end
	local resolveFresh: (Instance, string?, string?) -> (Instance?, unknown, boolean)
	local function resolve(object: Instance, property: string?, phantom: string?): (Instance?, unknown, boolean)
		local values = frameValues
		if values == nil then
			return resolveFresh(object, property, phantom)
		end
		local entries = values[object]
		if entries == nil then
			entries = {}
			values[object] = entries
		end
		local key = (property or "") .. "|" .. (phantom or "")
		local found = entries[key]
		if found == nil then
			local sheet, value, present = resolveFresh(object, property, phantom)
			found = { sheet = sheet, value = value, present = present }
			entries[key] = found
		end
		return found.sheet, found.value, found.present
	end
	function resolveFresh(object: Instance, property: string?, phantom: string?): (Instance?, unknown, boolean)
		local sheet = scope(object)
		local result: unknown = if phantom or property == nil then nil else env.defaultPropertyOf(object, property)
		if sheet == nil then
			return nil, result, false
		end
		if #(derives[sheet] or {}) > 0 then
			unsupported "StyleSheet derives"
		end
		local winning: number? = nil
		local present = false
		local index = indexOf(sheet)
		local candidates: { Instance } = index.rules
		if property then
			candidates = index.byProperty[property] or {}
		end
		for _, candidate in candidates do
			local values = properties[candidate] or {}
			if property == nil and phantom then
				local source = Values.string(env.propertyOf(candidate, "Selector"))
				if not source:find("::" .. phantom, 1, true) then
					continue
				end
			end
			local value = if property then values[property] else nil
			if #candidate:GetChildren() > 0 then
				unsupported "nested StyleRules"
			end
			local matches = false
			for _, branch in branches(candidate) do
				if branch.phantom == phantom and Selector.matches(branch, object) then
					matches = true
				end
			end
			if not matches then
				continue
			end
			present = true
			if value ~= nil and property then
				local priority = Values.number(env.propertyOf(candidate, "Priority"))
				if winning == priority then
					unsupported("equal-priority property " .. property)
				end
				if winning == nil or priority > winning then
					local transition = (transitions[candidate] or {})[property] or defaults[candidate]
					if transition ~= nil then
						transition = token(sheet, transition)
						local duration = if type(transition) == "table"
							then rawget(transition, "Time")
							else Names.fields(transition).Time
						if Values.number(duration) ~= 0 then
							unsupported "nonzero property transition"
						end
					end
					winning, result = priority, token(sheet, value)
				end
			end
		end
		return sheet, result, present
	end
	local function phantomValue(object: Instance, className: string, property: string): unknown
		if not PHANTOMS[className] then
			unsupported("phantom class " .. className)
		end
		local _, _, present = resolve(object, nil, className)
		if not present then
			return nil
		end
		local fallback = env.defaultClassProperty(className, property)
		local _, value = resolve(object, property, className)
		return if value == nil then fallback else value
	end
	local function styled(object: Instance, property: string, selector: string?): unknown
		if selector then
			local className = selector:match "^::([%a_][%w_]*)$"
			if className == nil then
				unsupported "GetStyled selector argument"
			end
			assert(className ~= nil)
			local value = phantomValue(object, className, property)
			if value == nil then
				error("GetStyled: phantom instance does not exist: " .. selector, 0)
			end
			return value
		end
		local _, value = resolve(object, property, nil)
		return if object:IsPropertyModified(property) then env.propertyOf(object, property) else value
	end
	local function close()
		invalidate()
		for _, entries in pairs(watches) do
			for _, watch in entries do
				watch.signal:DisconnectAll()
			end
		end
		for object in pairs(watches) do
			watches[object] = nil
		end
	end
	return {
		styled = styled,
		component = function(object: Instance, className: string, property: string): unknown
			local physical = object:FindFirstChildWhichIsA(className)
			return if physical then styled(physical, property) else phantomValue(object, className, property)
		end,
		signal = function(object: Instance, property: string): Environment.Signal<()>
			local entries = watches[object] or {}
			watches[object] = entries
			if entries[property] == nil then
				local sheet, value = resolve(object, property, nil)
				entries[property] = { signal = env.newSignal(), sheet = sheet, value = value }
			end
			return entries[property].signal
		end,
		step = function()
			for object, entries in pairs(watches) do
				if not env.isAlive(object) then
					for _, watch in entries do
						watch.signal:DisconnectAll()
					end
					watches[object] = nil
				else
					for property, watch in entries do
						local sheet, value = resolve(object, property, nil)
						if sheet ~= watch.sheet or value ~= watch.value then
							watch.sheet, watch.value = sheet, value
							watch.signal:Fire()
						end
					end
				end
			end
		end,
		cached = function(body: () -> ())
			if frameValues ~= nil then
				body()
				return
			end
			frameScopes, frameValues = {}, {}
			local outcome = table.pack(pcall(body))
			frameScopes, frameValues = nil, nil
			if not outcome[1] then
				error(outcome[2], 0)
			end
		end,
		close = close,
		invalidate = invalidate,
	}
end

return { create = create }
