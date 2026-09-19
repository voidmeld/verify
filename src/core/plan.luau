--!strict

local Types = require "./types"

type Plan = Types.Plan
type PlanDraft = Types.PlanDraft
type PlanPolicy = Types.PlanPolicy
type PlanPolicyDraft = Types.PlanPolicyDraft
type PlanSelection = Types.PlanSelection
type PlanUnit = Types.PlanUnit
type PlanBatch = Types.PlanBatch
type RetryPolicy = Types.RetryPolicy

local SCHEMA_VERSION = 1

local DEFAULT_RETRY: RetryPolicy = {
	maxAttempts = 1,
	on = { "faulted" },
}

local RETRYABLE: { [string]: boolean } = {
	faulted = true,
	timed_out = true,
}

local function copySortedUnique(values: { string }?, label: string): { string }
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

local function positiveInteger(value: number?, fallback: number, label: string): number
	local chosen = if value ~= nil then value else fallback
	if chosen < 1 or chosen % 1 ~= 0 then
		error(label .. " must be a positive integer", 3)
	end
	return chosen
end

local function positiveSeconds(value: number?, label: string): number?
	if value == nil then
		return nil
	end
	if value <= 0 then
		error(label .. " must be a positive number of seconds", 3)
	end
	return value
end

local function normalizeRetry(retry: RetryPolicy?, label: string): RetryPolicy
	if retry == nil then
		return { maxAttempts = DEFAULT_RETRY.maxAttempts, on = table.clone(DEFAULT_RETRY.on) }
	end
	local outcomes = copySortedUnique(retry.on, label .. ".on")
	for _, outcome in outcomes do
		if not RETRYABLE[outcome] then
			error(
				("%s.on names %q, which is not an infrastructure outcome; only faulted and timed_out may be retried"):format(
					label,
					outcome
				),
				3
			)
		end
	end
	local maxAttempts = positiveInteger(retry.maxAttempts, DEFAULT_RETRY.maxAttempts, label .. ".maxAttempts")
	if maxAttempts > 1 and #outcomes == 0 then
		error(label .. " allows more than one attempt but names no retryable outcome", 3)
	end
	return { maxAttempts = maxAttempts, on = outcomes }
end

local function normalizePolicy(policy: PlanPolicyDraft?, label: string): PlanPolicy
	local source: PlanPolicyDraft = if policy ~= nil then policy else {}
	local style: "unit-prefixed" | "bare" = "unit-prefixed"
	local declaredStyle = source.caseIdStyle
	if declaredStyle == "bare" then
		style = "bare"
	elseif declaredStyle ~= nil and declaredStyle ~= "unit-prefixed" then
		error(label .. ".caseIdStyle must be unit-prefixed or bare", 3)
	end
	return {
		failFast = source.failFast == true,
		maxParallelBatches = positiveInteger(source.maxParallelBatches, 1, label .. ".maxParallelBatches"),
		batchCount = if source.batchCount ~= nil
			then positiveInteger(source.batchCount, 1, label .. ".batchCount")
			else nil,
		deadlineSeconds = positiveSeconds(source.deadlineSeconds, label .. ".deadlineSeconds"),
		runDeadlineSeconds = positiveSeconds(source.runDeadlineSeconds, label .. ".runDeadlineSeconds"),
		retry = normalizeRetry(source.retry, label .. ".retry"),
		caseIdStyle = style,
	}
end

local function validate(draft: PlanDraft): Plan
	if draft.schemaVersion ~= nil and draft.schemaVersion ~= SCHEMA_VERSION then
		error(
			("unsupported execution plan schema major %s; expected %d"):format(
				tostring(draft.schemaVersion),
				SCHEMA_VERSION
			),
			2
		)
	end
	if type(draft.id) ~= "string" or draft.id == "" then
		error("execution plan id must be a non-empty string", 2)
	end
	local ids: { [string]: boolean } = {}
	local locators: { [string]: boolean } = {}
	local units: { PlanUnit } = {}
	for index, unit in draft.units do
		if type(index) ~= "number" or index ~= #units + 1 then
			error("execution plan units must be a dense array", 2)
		end
		if type(unit.id) ~= "string" or unit.id == "" then
			error(("execution plan unit %d has an empty id"):format(index), 2)
		end
		if type(unit.locator) ~= "string" or unit.locator == "" then
			error(("execution plan unit %q has an empty locator"):format(unit.id), 2)
		end
		if unit.group ~= nil and unit.group == "" then
			error(("execution plan unit %q has an empty group"):format(unit.id), 2)
		end
		if ids[unit.id] then
			error("duplicate execution plan unit id: " .. unit.id, 2)
		end
		if locators[unit.locator] then
			error("duplicate execution plan unit locator: " .. unit.locator, 2)
		end

		if
			unit.weight ~= nil and not (type(unit.weight) == "number" and unit.weight > 0 and unit.weight < math.huge)
		then
			error(("execution plan unit %q weight must be a positive finite number"):format(unit.id), 2)
		end
		ids[unit.id] = true
		locators[unit.locator] = true
		table.insert(units, {
			id = unit.id,
			locator = unit.locator,
			group = unit.group,
			weight = if unit.weight ~= nil then unit.weight else 1,
			tags = copySortedUnique(unit.tags, ("execution plan unit %q tags"):format(unit.id)),
			requires = copySortedUnique(unit.requires, ("execution plan unit %q requirements"):format(unit.id)),
			deadlineSeconds = positiveSeconds(
				unit.deadlineSeconds,
				("execution plan unit %q deadlineSeconds"):format(unit.id)
			),
		})
	end
	return {
		schemaVersion = SCHEMA_VERSION,
		id = draft.id,
		requires = copySortedUnique(draft.requires, "execution plan requirements"),
		policy = normalizePolicy(draft.policy, "execution plan policy"),
		units = units,
	}
end

local function set(values: { string }?): { [string]: boolean }
	local result: { [string]: boolean } = {}
	local source: { string } = if values ~= nil then values else {}
	for _, value in source do
		result[value] = true
	end
	return result
end

local function intersects(values: { string }, wanted: { [string]: boolean }): boolean
	for _, value in values do
		if wanted[value] then
			return true
		end
	end
	return false
end

local function select(plan: PlanDraft, selection: PlanSelection?): Plan
	local checked = validate(plan)
	if selection == nil then
		return checked
	end
	local ids = set(selection.ids)
	local tags = set(selection.tags)
	local capabilities = set(selection.capabilities)
	local groups = set(selection.groups)
	local hasIds = next(ids) ~= nil
	local hasTags = next(tags) ~= nil
	local hasCapabilities = next(capabilities) ~= nil
	local hasGroups = next(groups) ~= nil
	local predicate = selection.predicate
	local units: { PlanUnit } = {}
	for _, unit in checked.units do
		local keep = (not hasIds or ids[unit.id])
			and (not hasTags or intersects(unit.tags, tags))
			and (not hasCapabilities or intersects(unit.requires, capabilities))
			and (not hasGroups or (unit.group ~= nil and groups[unit.group :: string]))
		if keep and predicate ~= nil then
			keep = predicate {
				id = unit.id,
				source = unit.locator,
				path = {},
				name = unit.id,
				tags = unit.tags,
				requires = unit.requires,
			}
		end
		if keep then
			table.insert(units, unit)
		end
	end
	return {
		schemaVersion = SCHEMA_VERSION,
		id = checked.id,
		requires = checked.requires,
		policy = checked.policy,
		units = units,
	}
end

local function partition(plan: PlanDraft, batchCount: number, mode: Types.BatchingMode?): { PlanBatch }
	local checked = validate(plan)
	if batchCount < 1 or batchCount % 1 ~= 0 then
		error("execution plan batch count must be a positive integer", 2)
	end
	if mode ~= nil and mode ~= "count" and mode ~= "weighted" then
		error("execution plan batching mode must be count or weighted", 2)
	end
	local weighted = mode == "weighted"
	type Group = { key: string, first: string, order: number, units: { PlanUnit }, size: number }
	local groups: { Group } = {}
	local byKey: { [string]: Group } = {}
	for order, unit in checked.units do
		local key = if unit.group ~= nil then "g:" .. (unit.group :: string) else "u:" .. unit.id
		local group = byKey[key]
		if group == nil then
			group = { key = key, first = unit.id, order = order, units = {}, size = 0 }
			byKey[key] = group
			table.insert(groups, group)
		end
		table.insert(group.units, unit)
		group.size += if weighted then unit.weight else 1
	end

	local order = table.clone(groups)
	table.sort(order, function(left, right)
		if left.size ~= right.size then
			return left.size > right.size
		end
		return left.first < right.first
	end)

	local assignment: { [string]: number } = {}
	local sizes: { number } = table.create(batchCount, 0)
	for _, group in order do
		local target = 1
		for candidate = 2, batchCount do
			if sizes[candidate] < sizes[target] then
				target = candidate
			end
		end
		assignment[group.key] = target
		sizes[target] += group.size
	end

	local batches: { PlanBatch } = table.create(batchCount)
	for index = 1, batchCount do
		table.insert(batches, {
			id = ("batch-%d"):format(index),
			index = index,
			units = {},
			deadlineSeconds = checked.policy.deadlineSeconds,
		})
	end
	for _, unit in checked.units do
		local key = if unit.group ~= nil then "g:" .. (unit.group :: string) else "u:" .. unit.id
		table.insert(batches[assignment[key]].units, unit)
	end
	return batches
end

local function caseId(unitId: string, path: { string }, name: string, style: string?): string
	if unitId == "" or name == "" then
		error("a case id needs a non-empty unit id and case name", 2)
	end
	local pieces = table.clone(path)
	table.insert(pieces, name)
	local tail = table.concat(pieces, " > ")
	if style == nil or style == "unit-prefixed" then
		return unitId .. "::" .. tail
	elseif style == "bare" then
		return tail
	end
	error("unknown case id style: " .. tostring(style), 2)
end

local function digest(plan: PlanDraft): string
	local checked = validate(plan)
	local pieces: { string } = {
		("v%d"):format(checked.schemaVersion),
		checked.id,
		table.concat(checked.requires, ","),
		("failFast=%s"):format(tostring(checked.policy.failFast)),
		("parallel=%d"):format(checked.policy.maxParallelBatches),
		("batches=%s"):format(tostring(checked.policy.batchCount)),
		("deadline=%s"):format(tostring(checked.policy.deadlineSeconds)),
		("runDeadline=%s"):format(tostring(checked.policy.runDeadlineSeconds)),
		("attempts=%d"):format(checked.policy.retry.maxAttempts),
		("retryOn=%s"):format(table.concat(checked.policy.retry.on, ",")),
		("ids=%s"):format(checked.policy.caseIdStyle),
	}
	for _, unit in checked.units do
		table.insert(
			pieces,

			("%s|%s|%s|%s|%s|%s|%s"):format(
				unit.id,
				unit.locator,
				tostring(unit.group),
				table.concat(unit.tags, ","),
				table.concat(unit.requires, ","),
				tostring(unit.deadlineSeconds),
				tostring(unit.weight)
			)
		)
	end
	local text = table.concat(pieces, "\n")
	local hash = 2166136261
	for index = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = bit32.band(hash * 16777619, 0xFFFFFFFF)
	end
	return ("%08x-%d"):format(hash, #text)
end

local function fromManifest(manifest: Types.Manifest, policy: PlanPolicyDraft?): Plan
	local units: { Types.PlanUnitDraft } = {}
	for _, entry in manifest.entries do
		table.insert(units, {
			id = entry.id,
			locator = entry.source,
			group = entry.group,
			tags = entry.tags,
			requires = entry.requires,
		})
	end
	return validate {
		schemaVersion = SCHEMA_VERSION,
		id = ("manifest-v%d"):format(manifest.schemaVersion),
		policy = policy,
		units = units,
	}
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	validate = validate,
	select = select,
	partition = partition,
	caseId = caseId,
	digest = digest,
	fromManifest = fromManifest,
}
