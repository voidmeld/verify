--!strict

local Plan = require "./plan"
local Types = require "./types"

export type Identity = { name: string, path: string, eligible: boolean }
export type Manifest = { schemaVersion: number, count: number, digest: string }

local function select<T>(sources: { T }, identity: (T) -> Identity, pattern: string): { T }
	local selected: { { source: T, path: string } } = {}
	for _, source in sources do
		local row = identity(source)
		if row.eligible and string.match(row.name, pattern) then
			table.insert(selected, { source = source, path = row.path })
		end
	end
	table.sort(selected, function(left, right)
		return left.path < right.path
	end)
	local found: { T } = {}
	for _, row in selected do
		table.insert(found, row.source)
	end
	return found
end

local function manifest(id: string, paths: { string }): Manifest
	local sorted = table.clone(paths)
	table.sort(sorted)
	local units: { Types.PlanUnitDraft } = {}
	for _, path in sorted do
		table.insert(units, { id = path, locator = path, group = path })
	end
	return {
		schemaVersion = 1,
		count = #units,
		digest = Plan.digest { schemaVersion = 1, id = id, units = units, policy = { caseIdStyle = "bare" } },
	}
end

local function unreported(paths: { string }, report: Types.Report): { string }
	local reported: { [string]: boolean } = {}
	for _, result in report.results do
		if type(result.source) == "string" then
			reported[result.source] = true
		end
	end
	local silent: { string } = {}
	for _, path in paths do
		if not reported[path] then
			table.insert(silent, path)
		end
	end
	return silent
end

return table.freeze { select = select, manifest = manifest, unreported = unreported }
