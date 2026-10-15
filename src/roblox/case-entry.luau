--!strict

local Core = require "../core"
local Logs = require "./engine-logs"

export type Host = "simulator" | "studio" | "player" | "open-cloud"
export type Entry = {
	cases: { Core.NamedCase },
	options: Core.RunOptions,
	now: () -> number,
	expectedErrors: { [string]: { string } }?,
}
export type Factory = (Host, string?) -> Entry

local function run(
	factory: Factory,
	host: Host,
	ids: { string }?,
	progress: Core.RunProgress?,
	runId: string?,
	logs: Logs.Drain?
): Core.Report
	local entry = factory(host, runId)
	local options = entry.options
	if logs ~= nil then
		options = table.clone(options)
		local bind = options.bind
		options.bind = function(context)
			context:defer(function()
				Logs.finish(
					context,
					logs :: Logs.Drain,
					if entry.expectedErrors then entry.expectedErrors[context.id] else nil
				)
			end)
			return if bind
				then bind(context)
				else {
					name = "studio-logs",
					capabilities = {},
					environment = {},
					now = entry.now,
					invoke = function()
						error("no operation host is bound", 0)
					end,
				}
		end
	end
	if progress ~= nil then
		options = table.clone(options)
		options.progress = progress
	end
	return Core.runCases(entry.cases, options, entry.now, ids)
end

return { run = run }
