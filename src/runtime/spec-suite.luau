--!strict

local Core = require "../core"
local Gate = require "../gate"

export type Invocation = {
	serial: boolean,
	verbose: boolean,
	shards: number?,
	verdictPath: string?,
	specs: { [string]: boolean },
	deadlines: { [string]: number },
	gateFlags: { string },
}

export type Defaults = { serial: boolean?, shards: number? }
export type Options = {
	worker: string,
	workers: number,
	batches: number,
	silent: { string }?,
	deadlineSeconds: number?,
}

local VALUED: { [string]: boolean } = {
	["--only"] = true,
	["--tier"] = true,
	["--case"] = true,
	["--name"] = true,
	["--explain"] = true,
}

local function parse(args: { string }, defaults: Defaults?): Invocation
	local settings: Defaults = defaults or {}
	local invocation: Invocation = {
		serial = settings.serial or false,
		verbose = false,
		shards = settings.shards,
		specs = {},
		deadlines = {},
		gateFlags = {},
	}
	local index = 1
	while index <= #args do
		local argument = args[index]
		local shards = string.match(argument, "^%-%-shards=(%d+)$")
		local verdicts = string.match(argument, "^%-%-verdicts=(.+)$")
		if argument == "--serial" then
			invocation.serial = true
		elseif argument == "--verbose" then
			invocation.verbose = true
		elseif shards ~= nil then
			invocation.shards = tonumber(shards)
		elseif verdicts ~= nil then
			invocation.verdictPath = verdicts
		elseif string.sub(argument, 1, 16) == "--spec-deadline=" then
			local locator, seconds = string.match(argument, "^%-%-spec%-deadline=(.+):(%d+)$")
			assert(locator ~= nil and seconds ~= nil, "usage: --spec-deadline=<locator>:<seconds>")
			local limit = tonumber(seconds)
			assert(limit ~= nil and limit > 0, "spec deadline must be positive")
			invocation.deadlines[locator] = limit
		elseif VALUED[argument] and args[index + 1] ~= nil then
			table.insert(invocation.gateFlags, argument)
			table.insert(invocation.gateFlags, args[index + 1])
			index += 1
		elseif string.sub(argument, 1, 2) == "--" then
			table.insert(invocation.gateFlags, argument)
		else
			invocation.specs[argument] = true
		end
		index += 1
	end
	return invocation
end

local function prepare(
	plan: Core.PlanDraft,
	invocation: Invocation,
	options: Options
): (Core.PlanDraft, Gate.Draft, { string })
	local selected = table.clone(plan)
	selected.units = {}
	for _, unit in plan.units do
		local copy = table.clone(unit)
		copy.deadlineSeconds = invocation.deadlines[unit.locator] or unit.deadlineSeconds
		table.insert(selected.units, copy)
	end
	for locator in invocation.deadlines do
		local matched = false
		for _, unit in plan.units do
			if unit.locator == locator then
				matched = true
				break
			end
		end
		assert(matched, "unknown spec deadline locator: " .. locator)
	end
	local flags = table.clone(invocation.gateFlags)
	for spec in invocation.specs do
		table.insert(flags, "--file")
		table.insert(flags, spec)
	end
	return selected,
		{
			id = if next(invocation.specs) ~= nil then selected.id .. "-focused" else selected.id,
			producers = Gate.shard(selected, {
				prefix = "specs",
				worker = options.worker,
				count = options.batches,
				silent = options.silent,
				deadlineSeconds = options.deadlineSeconds,
			}),
			policy = { concurrency = options.workers },
		},
		flags
end

return { parse = parse, prepare = prepare }
