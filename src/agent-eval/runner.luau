--!strict

local Paths = require "../core/path"
local Result = require "./result"
local Schema = require "./schema"
local Services = require "./services"

local function load(evidence: string, files: Services.Files, decode: (text: string) -> unknown): { Result.RunResult }
	local indexPath = Paths.join(evidence, "index.json")
	if not files.exists(indexPath) then
		error(("no run index at %s"):format(indexPath), 0)
	end
	local raw = Schema.record(decode(files.read(indexPath)), "index")
	local results: { Result.RunResult } = {}
	for position, item in Schema.list(raw.runs, "index.runs") do
		local entry = Schema.record(item, ("index.runs[%d]"):format(position))
		local path = Paths.join(evidence, Schema.text(entry.path, "index.runs.path") .. "/result.json")
		table.insert(results, Result.decode(decode(files.read(path))))
	end
	return results
end

return {
	load = load,
}
