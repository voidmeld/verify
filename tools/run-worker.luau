--!strict

local fs = require "@std/fs"
local pathlib = require "@std/path"
local process = require "@std/process"
local system = require "@std/system"
local Core = require "../src/core"
local Entry = require "../src/roblox/case-entry"
local ProgressFile = require "../src/lute/progress-file"
local Wire = require "../src/lute/wire"

local entry = assert(process.args[2], "missing entry module")
local output = assert(process.args[3], "missing output path")
local ids: { string } = {}
for index = 4, #process.args do
	table.insert(ids, process.args[index])
end
local function parts(value: string): { string }
	local result: { string } = {}
	for part in value:gmatch(if system.win32 then "[^/\\]+" else "[^/]+") do
		if part == ".." then
			table.remove(result)
		elseif part ~= "." then
			table.insert(result, part)
		end
	end
	return result
end
local worker = process.args[1]
if not pathlib.isAbsolute(worker) then
	worker = tostring(process.cwd()) .. "/" .. worker
end
local base = parts(worker)
table.remove(base)
local target = parts((entry:gsub("%.luau$", "")))
local common = 0
local function same(left: string?, right: string?): boolean
	if left == nil or right == nil then
		return false
	end
	return if system.win32 then string.lower(left) == string.lower(right) else left == right
end
while same(base[common + 1], target[common + 1]) do
	common += 1
end
local relative = string.rep("../", #base - common)
if relative == "" then
	relative = "./"
end
relative ..= table.concat(target, "/", common + 1)
local loadFactory: (string) -> Entry.Factory = require
local loadedOk, loaded = pcall(loadFactory, relative)
assert(loadedOk, tostring(loaded))
assert(type(loaded) == "function", "entry module must return a factory")
local progressPath = process.env["VERIFY_PROGRESS_FILE"]
local progressRun = process.env["VERIFY_PROGRESS_RUN"]
local progress: Core.RunProgress? = nil
if progressPath ~= nil and progressPath ~= "" and progressRun ~= nil and progressRun ~= "" then
	progress = Core.progress.create(progressRun, ProgressFile.emitter(progressPath))
end
local report = Entry.run(loaded, "simulator", if #ids > 0 then ids else nil, progress)
fs.writeStringToFile(output, Wire.encode(report))
