--!strict

export type Negotiation = {
	satisfied: boolean,
	declared: { string },
	required: { string },
	missing: { string },
}

local function sortedUnique(values: { string }?, label: string): { string }
	local seen: { [string]: boolean } = {}
	local result: { string } = {}
	local source: { string } = if values ~= nil then values else {}
	for _, value in source do
		if type(value) ~= "string" or value == "" then
			error(label .. " must contain only non-empty strings", 3)
		end
		if not seen[value] then
			seen[value] = true
			table.insert(result, value)
		end
	end
	table.sort(result)
	return result
end

local function setOf(values: { string }): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for _, value in values do
		result[value] = true
	end
	return result
end

local function negotiate(declared: { string }, required: { string }?): Negotiation
	local have = sortedUnique(declared, "declared capabilities")
	local want = sortedUnique(required, "required capabilities")
	local available = setOf(have)
	local missing: { string } = {}
	for _, requirement in want do
		if not available[requirement] then
			table.insert(missing, requirement)
		end
	end
	return {
		satisfied = #missing == 0,
		declared = have,
		required = want,
		missing = missing,
	}
end

local function union(left: { string }, right: { string }): { string }
	local combined: { string } = table.clone(left)
	for _, value in right do
		table.insert(combined, value)
	end
	return sortedUnique(combined, "capabilities")
end

local function explain(negotiation: Negotiation): string
	if negotiation.satisfied then
		return "every declared requirement is available"
	end
	local declared = if #negotiation.declared > 0 then table.concat(negotiation.declared, ", ") else "none"
	return ("missing %s; the host declared %s"):format(table.concat(negotiation.missing, ", "), declared)
end

return {
	negotiate = negotiate,
	union = union,
	explain = explain,
	sorted = sortedUnique,
}
