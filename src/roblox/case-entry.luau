--!strict

local Core = require "../core"

export type Host = "simulator" | "studio" | "player" | "open-cloud"
export type Entry = {
	cases: { Core.NamedCase },
	options: Core.RunOptions,
	now: () -> number,
}
export type Factory = (Host) -> Entry

local function run(factory: Factory, host: Host, ids: { string }?, progress: Core.RunProgress?): Core.Report
	local entry = factory(host)
	local options = entry.options
	if progress ~= nil then
		options = table.clone(options)
		options.progress = progress
	end
	return Core.runCases(entry.cases, options, entry.now, ids)
end

return { run = run }
