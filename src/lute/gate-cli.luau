--!strict

local Gate = require "../gate"

export type Command = {
	only: { string },
	tiers: { string },
	cases: { string },
	files: { string },
	name: string?,
	rerun: boolean,
	list: boolean,
	explain: string?,
	shard: Shard?,
	weights: string?,
	recordWeights: string?,
}

export type Shard = { index: number, count: number }
export type Weights = { producers: { [string]: number }, files: { [string]: number } }
export type Share = { files: { string }, only: { string }, load: number }

local VALUED: { [string]: boolean } = {
	["--only"] = true,
	["--tier"] = true,
	["--case"] = true,
	["--file"] = true,
	["--name"] = true,
	["--explain"] = true,
	["--shard"] = true,
	["--weights"] = true,
	["--record-weights"] = true,
}

local USAGE =
	"usage: <gate script> [--only producer]... [--tier name]... [--case id]... [--file spec]... [--name text] [--rerun] [--explain id] [--list] [--shard index/count] [--weights path] [--record-weights path]"

local function parse(args: { string }): (Command?, string?)
	local command: Command = {
		only = {},
		tiers = {},
		cases = {},
		files = {},
		rerun = false,
		list = false,
	}
	local index = 1
	while index <= #args do
		local flag = args[index]
		if flag == "--rerun" then
			command.rerun = true
		elseif flag == "--list" then
			command.list = true
		elseif VALUED[flag] and args[index + 1] ~= nil then
			index += 1
			local value = args[index]
			if flag == "--only" then
				table.insert(command.only, value)
			elseif flag == "--tier" then
				table.insert(command.tiers, value)
			elseif flag == "--case" then
				table.insert(command.cases, value)
			elseif flag == "--file" then
				table.insert(command.files, value)
			elseif flag == "--shard" then
				local position, total = string.match(value, "^(%d+)/(%d+)$")
				local slot, count = tonumber(position), tonumber(total)
				if slot == nil or count == nil or count < 1 or slot < 1 or slot > count then
					return nil, "--shard needs index/count with 1 <= index <= count"
				end
				command.shard = { index = slot, count = count }
			elseif flag == "--weights" then
				command.weights = value
			elseif flag == "--record-weights" then
				command.recordWeights = value
			elseif flag == "--name" then
				if value == "" then
					return nil, "--name needs a nonempty text"
				end
				command.name = value
			else
				command.explain = value
			end
		else
			return nil, "unknown or incomplete argument " .. flag
		end
		index += 1
	end
	return command, nil
end

local function censusOf(declared: { string }?, locators: { string }, kept: { string }): { string }?
	if declared == nil then
		return nil
	end
	local census: { string } = {}
	for _, id in declared do
		local owner: string? = nil
		for _, locator in locators do
			if string.sub(id, 1, #locator + 2) == locator .. "::" then
				owner = locator
				break
			end
		end
		if owner == nil then
			return nil
		end
		if table.find(kept, owner) ~= nil then
			table.insert(census, id)
		end
	end
	return census
end

local function narrow(draft: Gate.Draft, files: { string }, only: { string }): (Gate.Draft?, string?)
	if #files == 0 then
		return draft, nil
	end
	local producers: { Gate.ProducerDraft } = {}
	local known: { [string]: boolean } = {}
	for _, producer in draft.producers do
		if producer.kind == "tests" and producer.locators ~= nil then
			local kept: { string } = {}
			for _, locator in producer.locators do
				known[locator] = true
				if table.find(files, locator) ~= nil then
					table.insert(kept, locator)
				end
			end
			if #kept > 0 then
				local narrowed = table.clone(producer)
				narrowed.locators = kept
				if producer.silent ~= nil then
					local silent: { string } = {}
					for _, locator in producer.silent do
						if table.find(kept, locator) ~= nil then
							table.insert(silent, locator)
						end
					end
					narrowed.silent = silent
				end
				narrowed.cases = censusOf(producer.cases, producer.locators, kept)
				table.insert(producers, narrowed)
				table.insert(only, producer.id)
			end
		else
			table.insert(producers, producer)
		end
	end
	for _, file in files do
		if not known[file] then
			return nil, "no spec file named " .. file
		end
	end
	local narrowed = table.clone(draft)
	narrowed.producers = producers
	return narrowed, nil
end

type Item = { files: { string }, producers: { string }, weight: number }

local function median(values: { [string]: number }, fallback: number): number
	local sorted: { number } = {}
	for _, value in values do
		table.insert(sorted, value)
	end
	if #sorted == 0 then
		return fallback
	end
	table.sort(sorted)
	return sorted[(#sorted + 1) // 2]
end

local function shard(draft: Gate.Draft, slot: Shard, weights: Weights, tiers: { string }): Share
	local items: { Item } = {}
	local producerDefault = median(weights.producers, 1)
	local fileDefault = median(weights.files, 1)
	local group: { [string]: string } = {}
	local function root(id: string): string
		local parent = group[id] or id
		if parent == id then
			return id
		end
		local top = root(parent)
		group[id] = top
		return top
	end
	local selected: { Gate.ProducerDraft } = {}
	for _, producer in draft.producers do
		local inTier = #tiers == 0 or producer.tier == nil or table.find(tiers, producer.tier) ~= nil
		if inTier then
			table.insert(selected, producer)
			if producer.kind ~= "tests" or producer.locators == nil then
				group[producer.id] = group[producer.id] or producer.id
			end
		end
	end
	for _, producer in selected do
		local dependencies: { string } = producer.after or {}
		if group[producer.id] ~= nil then
			for _, dependency in dependencies do
				if group[dependency] ~= nil then
					group[root(producer.id)] = root(dependency)
				end
			end
		end
	end
	local suite: { [string]: string } = {}
	local function suiteOf(id: string): string
		local parent = suite[id] or id
		if parent == id then
			return id
		end
		local found = suiteOf(parent)
		suite[id] = found
		return found
	end
	for _, producer in selected do
		if producer.kind == "tests" and producer.locators ~= nil then
			suite[producer.id] = suite[producer.id] or producer.id
		end
	end
	local linked: { [string]: boolean } = {}
	for _, producer in selected do
		local dependencies: { string } = producer.after or {}
		if suite[producer.id] ~= nil then
			for _, dependency in dependencies do
				if suite[dependency] ~= nil then
					suite[suiteOf(producer.id)] = suiteOf(dependency)
					linked[producer.id], linked[dependency] = true, true
				end
			end
		end
	end
	local byRoot: { [string]: Item } = {}
	local bySuite: { [string]: Item } = {}
	for _, producer in selected do
		if producer.kind == "tests" and producer.locators ~= nil and linked[producer.id] then
			local key = suiteOf(producer.id)
			local item = bySuite[key]
			if item == nil then
				item = { files = {}, producers = {}, weight = 0 }
				bySuite[key] = item
				table.insert(items, item)
			end
			for _, locator in producer.locators do
				table.insert(item.files, locator)
				item.weight += weights.files[locator] or fileDefault
			end
		elseif producer.kind == "tests" and producer.locators ~= nil then
			for _, locator in producer.locators do
				table.insert(
					items,
					{ files = { locator }, producers = {}, weight = weights.files[locator] or fileDefault }
				)
			end
		else
			local top = root(producer.id)
			local item = byRoot[top]
			if item == nil then
				item = { files = {}, producers = {}, weight = 0 }
				byRoot[top] = item
				table.insert(items, item)
			end
			table.insert(item.producers, producer.id)
			item.weight += weights.producers[producer.id] or producerDefault
		end
	end
	table.sort(items, function(left: Item, right: Item): boolean
		if left.weight ~= right.weight then
			return left.weight > right.weight
		end
		return (left.files[1] or left.producers[1] or "") < (right.files[1] or right.producers[1] or "")
	end)
	local loads: { number } = table.create(slot.count, 0)
	local share: Share = { files = {}, only = {}, load = 0 }
	for _, item in items do
		local lightest = 1
		for index = 2, slot.count do
			if loads[index] < loads[lightest] then
				lightest = index
			end
		end
		loads[lightest] += item.weight
		if lightest == slot.index then
			share.load += item.weight
			for _, file in item.files do
				table.insert(share.files, file)
			end
			for _, id in item.producers do
				table.insert(share.only, id)
			end
		end
	end
	return share
end

export type ProducerTime = { id: string, timed: boolean, durationMicros: number? }
export type ResultTime = { source: string?, durationMicros: number }

local function measured(previous: Weights, producerTimes: { ProducerTime }, resultTimes: { ResultTime }): Weights
	local producers = table.clone(previous.producers)
	local files = table.clone(previous.files)
	for _, record in producerTimes do
		local micros = record.durationMicros
		if record.timed and micros ~= nil then
			producers[record.id] = math.floor(micros / 1e5 + 0.5) / 10
		end
	end
	local totals: { [string]: number } = {}
	for _, result in resultTimes do
		local source = result.source
		if source ~= nil and string.find(source, "/", 1, true) ~= nil then
			totals[source] = (totals[source] or 0) + result.durationMicros
		end
	end
	for source, micros in totals do
		files[source] = math.floor(micros / 1e5 + 0.5) / 10
	end
	return { producers = producers, files = files }
end

return { USAGE = USAGE, parse = parse, narrow = narrow, shard = shard, measured = measured }
