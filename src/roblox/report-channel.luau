--!strict

local Core = require "../core"

export type Envelope = { runId: string, report: Core.Report }

local function envelope(runId: string, report: Core.Report): Envelope
	assert(runId ~= "", "report channel requires a run id")
	return { runId = runId, report = Core.decode(report) }
end

local function receive(value: unknown, runId: string): Core.Report
	assert(runId ~= "" and type(value) == "table", "report channel requires an envelope")
	local fields = value :: { [string]: unknown }
	assert(fields.runId == runId, "report channel run identity mismatch")
	return Core.decode(fields.report)
end

local function publish(runId: string, report: Core.Report, encode: (unknown) -> string, emit: (string) -> ())
	for _, line in Core.frame("VERIFY_REPORT", encode(envelope(runId, report))) do
		emit(line)
	end
end

local function collect(bytes: string, runId: string, decode: (string) -> unknown): Core.Report
	local payload, reason = Core.receipt(bytes, "VERIFY_REPORT")
	assert(payload ~= nil, reason)
	return receive(decode(payload :: string), runId)
end

return { envelope = envelope, receive = receive, publish = publish, collect = collect }
