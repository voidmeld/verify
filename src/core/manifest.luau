--!strict

local Types = require "./types"

type Manifest = Types.Manifest
type ManifestEntry = Types.ManifestEntry

local SCHEMA_VERSION = 1

local function copySortedUnique(values: { string }?, label: string): { string }
	local seen: { [string]: boolean } = {}
	local result: { string } = {}
	local source: { string } = if values ~= nil then values else {}
	for _, value in source do
		if value == "" then
			error(label .. " must not contain an empty value", 3)
		end
		if not seen[value] then
			seen[value] = true
			table.insert(result, value)
		end
	end
	table.sort(result)
	return result
end

local function validate(manifest: Manifest): Manifest
	if manifest.schemaVersion ~= SCHEMA_VERSION then
		error(
			("unsupported manifest schema major %s; expected %d"):format(
				tostring(manifest.schemaVersion),
				SCHEMA_VERSION
			),
			2
		)
	end
	local ids: { [string]: boolean } = {}
	local sources: { [string]: boolean } = {}
	local entries: { ManifestEntry } = {}
	for index, entry in manifest.entries do
		if entry.id == "" then
			error(("manifest entry %d has an empty id"):format(index), 2)
		end
		if entry.source == "" then
			error(("manifest entry %q has an empty source"):format(entry.id), 2)
		end
		if string.match(entry.source, "%.verify%.luau$") == nil then
			error(("manifest entry %q source must end in .verify.luau"):format(entry.id), 2)
		end
		if entry.group == "" then
			error(("manifest entry %q has an empty group"):format(entry.id), 2)
		end
		if ids[entry.id] then
			error("duplicate manifest id: " .. entry.id, 2)
		end
		if sources[entry.source] then
			error("duplicate manifest source: " .. entry.source, 2)
		end
		ids[entry.id] = true
		sources[entry.source] = true
		table.insert(entries, {
			id = entry.id,
			source = entry.source,
			group = entry.group,
			tags = copySortedUnique(entry.tags, "manifest tags"),
			requires = copySortedUnique(entry.requires, "manifest requirements"),
		})
	end
	return { schemaVersion = SCHEMA_VERSION, entries = entries }
end

return { SCHEMA_VERSION = SCHEMA_VERSION, validate = validate }
