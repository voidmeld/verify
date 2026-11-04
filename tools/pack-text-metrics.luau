--!strict

local fs = require "@std/fs"
local json = require "@std/json"
local process = require "@std/process"
local Archive = require "../src/lute/text-metrics-archive"
local Metrics = require "../src/lute/text-metrics"

local output, directory = process.args[2], process.args[3]
assert(
	output and directory and #process.args == 3,
	"usage: lute run tools/pack-text-metrics.luau <out.json> <capture-directory>"
)
assert(not fs.exists(output), "text metric archive output exists")
local faces: { [string]: json.Object } = {}
for _, entry in fs.listDirectory(directory) do
	local name = entry.name:match "^(.+)%.json$"
	if entry.type == "file" and name and not name:match "%.report$" then
		local source = fs.readFileToString(`{directory}/{entry.name}`)
		Metrics.decode(source)
		faces[name] = assert(json.asObject(json.deserialize(source)))
	end
end
assert(next(faces) ~= nil, "text metric capture directory is empty")
fs.writeStringToFile(output, Archive.pack(faces))
print("wrote text metric archive to " .. output)
