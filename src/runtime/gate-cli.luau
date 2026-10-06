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
}

local VALUED: { [string]: boolean } = {
	["--only"] = true,
	["--tier"] = true,
	["--case"] = true,
	["--file"] = true,
	["--name"] = true,
	["--explain"] = true,
}

local USAGE =
	"usage: <gate script> [--only producer]... [--tier name]... [--case id]... [--file spec]... [--name text] [--rerun] [--explain id] [--list]"

local function parse(args: { string }): (Command?, string?)
	local command: Command = {
		only = {},
		tiers = {},
		cases = {},
		files = {},
		name = nil,
		rerun = false,
		list = false,
		explain = nil,
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

return { USAGE = USAGE, parse = parse, narrow = narrow }
