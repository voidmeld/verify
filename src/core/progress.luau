--!strict

export type Phase = "started" | "finished"
export type Event = {
	runId: string,
	sequence: number,
	actor: string,
	caseId: string,
	step: string,
	phase: Phase,
	status: string?,
}
export type Progress = {
	runId: string,
	publish: (caseId: string, actor: string, step: string, phase: Phase, status: string?) -> (),
}

local function create(runId: string, emit: (Event) -> ()): Progress
	assert(type(runId) == "string" and runId ~= "", "progress needs a run identity")
	assert(type(emit) == "function", "progress needs an emit function")
	local sequence = 0
	return {
		runId = runId,
		publish = function(caseId: string, actor: string, step: string, phase: Phase, status: string?)
			sequence += 1
			local ok = pcall(emit, {
				runId = runId,
				sequence = sequence,
				actor = actor,
				caseId = caseId,
				step = step,
				phase = phase,
				status = status,
			})
			if not ok then
				return
			end
		end,
	}
end

local function valid(value: unknown, runId: string): Event
	assert(type(value) == "table", "progress event must be a record")
	local fields = value :: { [string]: unknown }
	assert(fields.runId == runId, "progress run identity mismatch")
	assert(type(fields.sequence) == "number" and fields.sequence >= 1 and fields.sequence % 1 == 0, "progress sequence")
	assert(
		type(fields.actor) == "string" and type(fields.caseId) == "string" and type(fields.step) == "string",
		"progress names"
	)
	assert(fields.phase == "started" or fields.phase == "finished", "progress phase")
	assert(fields.status == nil or type(fields.status) == "string", "progress status")
	return {
		runId = runId,
		sequence = fields.sequence :: number,
		actor = fields.actor :: string,
		caseId = fields.caseId :: string,
		step = fields.step :: string,
		phase = fields.phase :: Phase,
		status = fields.status :: string?,
	}
end

local function pending(events: { Event }): { Event }
	local open: { Event } = {}
	for _, event in events do
		if event.phase == "started" then
			table.insert(open, event)
		else
			for index = #open, 1, -1 do
				local candidate = open[index]
				if
					candidate.actor == event.actor
					and candidate.caseId == event.caseId
					and candidate.step == event.step
				then
					table.remove(open, index)
					break
				end
			end
		end
	end
	return open
end

return { create = create, valid = valid, pending = pending }
