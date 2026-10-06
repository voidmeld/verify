--!strict

local fs = require "@std/fs"
local process = require "@std/process"

local Consumer = require "../src/consumer"

local USAGE = "usage: lute run tools/verify-check.luau --ruleset generic|roblox <file-or-root> [...]"
local rulesets: { [string]: Consumer.Ruleset } = { generic = Consumer.generic, roblox = Consumer.roblox }
local roots: { string } = {}
local ruleset: Consumer.Ruleset? = nil
local index = 2
while index <= #process.args do
	if process.args[index] == "--ruleset" then
		ruleset = rulesets[process.args[index + 1] or ""]
		index += 2
	else
		table.insert(roots, process.args[index])
		index += 1
	end
end
if #roots == 0 or ruleset == nil then
	error(USAGE, 0)
end
local selected: Consumer.Ruleset = ruleset

local function listDir(path: string): { Consumer.DirEntry }
	local entries = fs.listDirectory(path)
	local result: { Consumer.DirEntry } = table.create(#entries)
	for _, entry in entries do
		table.insert(result, { name = entry.name, type = entry.type :: string })
	end
	return result
end

local function readFile(path: string): string
	return fs.readFileToString(path)
end

local failures = 0

for _, root in roots do
	local metadata = fs.metadata(root)

	local scanRoot = root
	local trueListDir = listDir
	if metadata.type == "file" then
		local slash = string.find(root, "/[^/]*$")
		local parent = if slash ~= nil then string.sub(root, 1, slash - 1) else "."
		local name = if slash ~= nil then string.sub(root, slash + 1) else root
		scanRoot = parent
		trueListDir = function(path: string): { Consumer.DirEntry }
			if path == parent then
				return { { name = name, type = "file" } }
			end
			return listDir(path)
		end
	end

	local result = Consumer.scanTree(scanRoot, { ruleset = selected, listDir = trueListDir, readFile = readFile })
	for _, finding in result.findings do
		failures += 1
		print(("%s:%d %s %s; %s"):format(finding.path, finding.offset, finding.code, finding.why, finding.fix))
	end
end

if failures > 0 then
	print(("verify-check: FAILED (%d findings)"):format(failures))
	process.exit(1)
end
print "verify-check: clean"
