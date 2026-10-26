--!strict

local Environment = require "./environment"

type Instance = Environment.Instance
type Segment = { className: string?, name: string?, tags: { string }, state: string? }
export type Branch = { segments: { Segment }, relations: { string }, phantom: string? }
export type Selector = { Branch }

local function unsupported(selector: string): never
	error("unsupported_ui_style: selector " .. selector, 0)
end

local function parse(selector: string): Selector
	local branches: Selector = {}
	for _, text in string.split(selector, ",") do
		local source = string.match(text, "^%s*(.-)%s*$") or ""
		local branch: Branch = { segments = {}, relations = {} }
		local position = 1
		while position <= #source do
			local segment: Segment = { tags = {} }
			local className = string.match(source:sub(position), "^([%a_][%w_]*)")
			if className then
				segment.className = className
				position += #className
			end
			while position <= #source do
				local prefix = source:sub(position, position)
				if prefix == ":" and source:sub(position + 1, position + 1) ~= ":" then
					local state = source:sub(position + 1):match "^([%a]+)"
					if state ~= "Idle" and state ~= "Hover" and state ~= "Press" and state ~= "NonInteractable" then
						unsupported(selector)
					end
					if segment.state ~= nil then
						unsupported(selector)
					end
					segment.state = state
					position += #assert(state) + 1
					continue
				end
				if prefix ~= "." and prefix ~= "#" then
					break
				end
				local name = source:sub(position + 1):match "^([%a_][%w_%-]*)"
				if name == nil then
					unsupported(selector)
				end
				assert(name ~= nil)
				if prefix == "." then
					table.insert(segment.tags, name)
				elseif segment.name == nil then
					segment.name = name
				else
					unsupported(selector)
				end
				position += #name + 1
			end
			if segment.className == nil and segment.name == nil and #segment.tags == 0 then
				unsupported(selector)
			end
			table.insert(branch.segments, segment)
			local whitespace = source:sub(position):match "^%s*" or ""
			position += #whitespace
			if position > #source then
				break
			end
			if source:sub(position, position + 1) == "::" then
				local phantom = source:sub(position + 2):match "^([%a_][%w_]*)$"
				if phantom == nil then
					unsupported(selector)
				end
				branch.phantom = phantom
				position = #source + 1
			elseif source:sub(position, position) == ">" then
				local descendant = source:sub(position, position + 1) == ">>"
				table.insert(branch.relations, if descendant then "descendant" else "child")
				position += if descendant then 2 else 1
				position += #(source:sub(position):match "^%s*" or "")
				if position > #source then
					unsupported(selector)
				end
			else
				unsupported(selector)
			end
		end
		if #branch.segments == 0 then
			unsupported(selector)
		end
		table.insert(branches, branch)
	end
	return branches
end

local function matches(branch: Branch, object: Instance, hasTag: ((Instance, string) -> boolean)?): boolean
	local function at(index: number, candidate: Instance): boolean
		local segment = branch.segments[index]
		if segment.className and not candidate:IsA(segment.className) then
			return false
		end
		if segment.name and candidate.Name ~= segment.name then
			return false
		end
		for _, tag in segment.tags do
			local tagged = if hasTag then hasTag(candidate, tag) else candidate:HasTag(tag)
			if not tagged then
				return false
			end
		end
		if segment.state then
			if not candidate:IsA "GuiObject" then
				return false
			end
			if tostring(candidate.GuiState) ~= "Enum.GuiState." .. segment.state then
				return false
			end
		end
		if index == 1 then
			return true
		end
		local parent = candidate.Parent
		while parent do
			if at(index - 1, parent) then
				return true
			end
			if branch.relations[index - 1] == "child" then
				return false
			end
			parent = parent.Parent
		end
		return false
	end
	return at(#branch.segments, object)
end

return { parse = parse, matches = matches }
