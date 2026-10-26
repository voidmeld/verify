--!strict

local fs = require "@std/fs"
local Corpus = require "../lute/corpus"

export type Config = {
	path: string,
	rules: { Corpus.Rule },
	entries: { string }?,
	write: boolean?,
	format: ((string) -> ())?,
}

local function check(config: Config): { string }
	local found = Corpus.discover { listDir = fs.listDirectory, rules = config.rules, order = "walk" }
	if config.write then
		local lines = { "--!strict", "", "return table.freeze {" }
		for _, source in found do
			table.insert(lines, ("\t%q,"):format(source))
		end
		table.insert(lines, "}")
		table.insert(lines, "")
		fs.writeStringToFile(config.path, table.concat(lines, "\n"))
		if config.format ~= nil then
			config.format(config.path)
		end
		return {}
	end
	assert(config.entries ~= nil, "manifest check needs loaded entries")
	local entries = config.entries :: { string }
	local findings: { string } = {}
	for index = 1, math.max(#found, #entries) do
		if found[index] ~= entries[index] then
			table.insert(
				findings,
				("%s: entry %d is %s; discovery requires %s"):format(
					config.path,
					index,
					tostring(entries[index]),
					tostring(found[index])
				)
			)
		end
	end
	return findings
end

return check
