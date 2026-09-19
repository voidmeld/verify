--!strict

local fs = require "@std/fs"
local process = require "@std/process"

local Verify = require "../src/core"
local Lute = require "../src/lute"

local root = process.args[2] or "tests"
local paths = Lute.corpus.discover {
	listDir = function(path: string): { { name: string, type: string } }
		local entries: { { name: string, type: string } } = {}
		for _, entry in fs.listDirectory(path) do
			table.insert(entries, { name = entry.name, type = entry.type :: string })
		end
		return entries
	end,
	rules = { { root = root, pattern = "%.spec%.luau$" } },
}
assert(#paths > 0, "test corpus is empty: " .. root)

local units: { Verify.PlanUnit } = {}
for _, path in paths do
	table.insert(units, {
		id = path,
		locator = path,
		group = nil,
		tags = {},
		requires = {},
		deadlineSeconds = nil,
		weight = 1,
	})
end

local report = Lute.runWorkerBatch({ id = "self-host", index = 1, units = units }, {
	load = function(locator: string): unknown
		local loaded, value: any = pcall(require, "../" .. string.sub(locator, 1, -6))
		if not loaded then
			error(value, 0)
		end
		return value
	end,
}, { executor = "verify-self-host" })
print(Verify.format(report))
if report.total == 0 or report.passed ~= report.total then
	process.exit(1)
end
