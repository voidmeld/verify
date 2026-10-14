--!strict

local fs = require "@std/fs"
local process = require "@std/process"

local path = assert(process.args[2], "missing module path")
local name = assert(process.args[3], "missing function name")
local scores = assert(process.args[4], "missing scores path")

if not fs.exists(path) then
	print("no module at " .. path)
	process.exit(1)
end
local source = fs.readFileToString(path)
local lines = 0
for _ in string.gmatch(source, "[^\n]+") do
	lines += 1
end
fs.writeStringToFile(scores, ('{"lines": %d}'):format(lines))
if string.find(source, name, 1, true) == nil then
	print(("the module defines no %s"):format(name))
	process.exit(1)
end
print(("the module defines %s"):format(name))
