--!strict

export type Deps = {
	start: () -> (boolean, string?),
	list: () -> ({ string }?, string?),
	read: (reference: string) -> string?,
	now: () -> number,
	wait: () -> boolean,
}

export type Predicates = {
	candidate: (bytes: string) -> boolean,
	complete: (bytes: string) -> boolean,
	bound: (bytes: string) -> boolean,
	observed: (bytes: string) -> boolean,
	halt: (bytes: string) -> string?,
	defect: (bytes: string) -> string?,
	latch: ((bytes: string) -> boolean)?,
}

export type Reasons = {
	startFailed: string,
	listFailed: string,
	clockFailed: string,
	waitFailed: string,
	readFailed: string,
	ambiguous: string,
	halted: string,
	truncated: string,
	unobserved: string,
	missing: string,
}

export type Options = {
	deadlineSeconds: number,
	exclusive: boolean,
	reasons: Reasons?,
}

export type Selection = {
	reference: string,
	mode: string,
	offset: number,
	bytes: string?,
	whole: string?,
	baseline: { string },
	appeared: { string },
	latched: boolean,
	halt: string?,
	defect: string?,
	reason: string?,
}

local DEFAULT_REASONS: Reasons = table.freeze {
	startFailed = "scenario_start_failed",
	listFailed = "scenario_source_list_failed",
	clockFailed = "scenario_clock_failed",
	waitFailed = "scenario_wait_failed",
	readFailed = "scenario_source_read_failed",
	ambiguous = "scenario_ambiguous_source",
	halted = "scenario_run_halted",
	truncated = "scenario_receipt_truncated",
	unobserved = "scenario_boot_unobserved",
	missing = "scenario_receipt_missing",
}

type Window = {
	reference: string,
	mode: string,
	offset: number,
	bytes: string,
}

local function empty(reference: string, mode: string, offset: number, reason: string?): Selection
	return {
		reference = reference,
		mode = mode,
		offset = offset,
		bytes = nil,
		whole = nil,
		baseline = {},
		appeared = {},
		latched = false,
		halt = nil,
		defect = nil,
		reason = reason,
	}
end

local function callList(list: () -> ({ string }?, string?)): ({ string }?, string?)
	local ok, values, problem = pcall(list)
	if not ok or type(values) ~= "table" then
		return nil, if type(problem) == "string" then problem else "unavailable"
	end
	for _, reference in values :: { any } do
		if type(reference) ~= "string" or reference == "" then
			return nil, "malformed"
		end
	end
	return values :: { string }, nil
end

local function callStart(start: () -> (boolean, string?)): (boolean, string?)
	local ok, outcome, detail = pcall(start)
	if not ok then
		return false, tostring(outcome)
	end
	if outcome == false then
		return false, if type(detail) == "string" then detail :: string else nil
	end
	return true, nil
end

local function callWait(wait: () -> boolean): boolean
	local ok, outcome = pcall(wait)
	return ok and outcome ~= false
end

local function callClock(now: () -> number): number?
	local ok, value = pcall(now)
	if not ok or type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function windows(
	deps: Deps,
	references: { string },
	baseline: { [string]: boolean },
	sizes: { [string]: number }
): ({ Window }, { string })
	local rows: { Window } = {}
	local appeared: { string } = {}
	for _, reference in references do
		local ok, bytes = pcall(deps.read, reference)
		local text = if ok and type(bytes) == "string" then bytes :: string else nil
		if not baseline[reference] then
			table.insert(appeared, reference)
			if text ~= nil then
				table.insert(rows, { reference = reference, mode = "new", offset = 0, bytes = text })
			end
		elseif text ~= nil then
			local offset = sizes[reference] or 0
			if #text > offset then
				table.insert(
					rows,
					{ reference = reference, mode = "reused", offset = offset, bytes = string.sub(text, offset + 1) }
				)
			end
		end
	end
	return rows, appeared
end

local function partition(rows: { Window }, accept: (string) -> boolean): ({ Window }, { Window })
	local fresh: { Window } = {}
	local reused: { Window } = {}
	for _, row in rows do
		if accept(row.bytes) then
			if row.mode == "new" then
				table.insert(fresh, row)
			else
				table.insert(reused, row)
			end
		end
	end
	return fresh, reused
end

local function ambiguous(fresh: { Window }, reused: { Window }, exclusive: boolean): boolean
	return #fresh > 1 or (#fresh == 0 and #reused > 1) or (exclusive and #fresh + #reused > 1)
end

local function chosen(fresh: { Window }, reused: { Window }): Window?
	if #fresh == 1 then
		return fresh[1]
	end
	if #fresh == 0 and #reused == 1 then
		return reused[1]
	end
	return nil
end

local function observe(deps: Deps, predicates: Predicates, options: Options): Selection
	local named = if options.reasons ~= nil then options.reasons else DEFAULT_REASONS
	local baselineRows, baselineProblem = callList(deps.list)
	if baselineRows == nil then
		local refusal = empty("", "", 0, named.listFailed)
		refusal.defect = baselineProblem
		return refusal
	end
	local baseline: { [string]: boolean } = {}
	local sizes: { [string]: number } = {}
	for _, reference in baselineRows :: { string } do
		baseline[reference] = true
		local ok, bytes = pcall(deps.read, reference)
		if not ok or type(bytes) ~= "string" then
			local refusal = empty(reference, "baseline", 0, named.readFailed)
			refusal.baseline = baselineRows :: { string }
			return refusal
		end
		sizes[reference] = #(bytes :: string)
	end

	local started, startProblem = callStart(deps.start)
	if not started then
		local refusal = empty("", "", 0, named.startFailed)
		refusal.baseline = baselineRows :: { string }
		refusal.defect = startProblem
		return refusal
	end

	local startedAt = callClock(deps.now)
	if startedAt == nil then
		local refusal = empty("", "", 0, named.clockFailed)
		refusal.baseline = baselineRows :: { string }
		return refusal
	end

	local selection: Selection = {
		reference = "",
		mode = "",
		offset = 0,
		bytes = nil,
		whole = nil,
		baseline = baselineRows :: { string },
		appeared = {},
		latched = false,
		halt = nil,
		defect = nil,
		reason = nil,
	}

	local function bind(row: Window)
		selection.reference = row.reference
		selection.mode = row.mode
		selection.offset = row.offset
	end

	while true do
		local references, listProblem = callList(deps.list)
		if references == nil then
			selection.reason = named.listFailed
			selection.defect = listProblem
			break
		end
		local rows, appeared = windows(deps, references :: { string }, baseline, sizes)
		selection.appeared = appeared

		for _, row in rows do
			if not selection.latched and predicates.latch ~= nil and (predicates.latch :: any)(row.bytes) then
				selection.latched = true
			end
			if selection.halt == nil then
				selection.halt = predicates.halt(row.bytes)
			end
		end
		if selection.halt ~= nil then
			selection.reason = named.halted
			break
		end

		local fresh, reused = partition(rows, predicates.candidate)
		if ambiguous(fresh, reused, options.exclusive) then
			selection.reason = named.ambiguous
			break
		end
		local candidate = chosen(fresh, reused)
		if candidate ~= nil and predicates.complete((candidate :: Window).bytes) then
			bind(candidate :: Window)
			break
		end

		local current = callClock(deps.now)
		if current == nil then
			selection.reason = named.clockFailed
			break
		end
		if (current :: number) - (startedAt :: number) >= options.deadlineSeconds then
			local boundFresh, boundReused = partition(rows, function(bytes: string): boolean
				return predicates.candidate(bytes) or predicates.bound(bytes)
			end)
			if ambiguous(boundFresh, boundReused, false) then
				selection.reason = named.ambiguous
				break
			end
			local fallback = chosen(boundFresh, boundReused)
			if fallback == nil then
				selection.reason = named.unobserved
				break
			end
			local row = fallback :: Window
			bind(row)
			local defect = predicates.defect(row.bytes)
			if defect ~= nil then
				selection.defect = defect
				selection.reason = named.truncated
			elseif not predicates.observed(row.bytes) then
				selection.reason = named.unobserved
			else
				selection.reason = named.missing
			end
			break
		end

		if not callWait(deps.wait) then
			selection.reason = named.waitFailed
			break
		end
	end

	if selection.reference == "" then
		return selection
	end
	local ok, bytes = pcall(deps.read, selection.reference)
	if not ok or type(bytes) ~= "string" then
		selection.reason = named.readFailed
		return selection
	end
	selection.whole = bytes :: string
	selection.bytes = if selection.mode == "reused"
		then string.sub(bytes :: string, selection.offset + 1)
		else bytes :: string
	return selection
end

return {
	DEFAULT_REASONS = DEFAULT_REASONS,
	observe = observe,
}
