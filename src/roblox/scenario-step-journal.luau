--!strict

export type Result = { ok: boolean, output: string, detail: string? }
export type Entry = {
	kind: string,
	label: string,
	tool: string,
	path: string,
	request: string?,
	checkpoint: string?,
	viewport: string?,
	evidenceOnly: boolean?,
	status: string?,
	command: { string }?,
}
export type Deps = {
	digest: (string) -> string,
	write: (string, string) -> (),
	log: ((string) -> ())?,
}
export type Journal = {
	steps: { any },
	calls: { any },
	record: (self: Journal, entry: Entry, result: Result) -> (any, any?),
}

local function create(binding: string, deps: Deps): Journal
	assert(type(binding) == "string" and binding ~= "", "journal binding missing")
	local journal: Journal = { steps = {}, calls = {} } :: any
	function journal:record(entry: Entry, result: Result): (any, any?)
		assert(type(entry.path) == "string" and entry.path ~= "", "journal path missing")
		assert(type(result.output) == "string", "journal output missing")
		local ordinal = #self.steps + 1
		local requestDigest = if entry.request ~= nil then deps.digest(entry.request) else nil
		local resultDigest = deps.digest(result.output)
		local status = entry.status or (if result.ok then "returned" else "failed")
		deps.write(entry.path, result.output)
		local step = {
			ordinal = ordinal,
			kind = entry.kind,
			label = entry.label,
			tool = entry.tool,
			checkpoint = entry.checkpoint,
			viewport = entry.viewport,
			requestDigest = requestDigest,
			resultDigest = resultDigest,
			path = entry.path,
			status = status,
			bytes = #result.output,
			command = entry.command,
		}
		table.insert(self.steps, step)
		local call = nil
		if entry.evidenceOnly ~= true and requestDigest ~= nil then
			call = {
				tool = entry.tool,
				binding = binding,
				requestDigest = requestDigest,
				resultDigest = resultDigest,
				status = status,
			}
			table.insert(self.calls, call)
		end
		if deps.log ~= nil then
			(deps.log :: (string) -> ())(
				("%03d %s %s %s bytes=%d -> %s"):format(
					ordinal,
					status,
					entry.kind,
					entry.label,
					#result.output,
					entry.path
				)
			)
		end
		return step, call
	end
	return journal
end

return { create = create }
