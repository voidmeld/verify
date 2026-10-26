--!strict

local fs = require "@std/fs"
local Wire = require "../src/lute/wire"
local process = require "@std/process"
local Core = require "../src/core"
local Lute = require "../src/lute"
local Files = require "../src/lute/files"
local Identity = require "../src/lute/studio-identity"
local Facts = require "../src/roblox/content-facts"
local source = require "./lib/capture-native-content"
local Attachments = require "../src/lute/capture-attachments"

assert(#process.args == 3, "usage: lute run tools/capture-native-content.luau <request.json> <out.json>")
local input = Wire.parse(fs.readFileToString(process.args[2])) :: { [string]: unknown }
local requests = Facts.requests(input.requests)
local output = process.args[3]
assert(not fs.exists(output), "capture output exists; preserve and reconcile it")
assert(not fs.exists(output .. ".report.json"), "capture report exists; preserve and reconcile it")
assert(not fs.exists(output .. ".attachments"), "capture attachment directory exists; preserve and reconcile it")
local place = Files.temporary "Verify-Native-Content.rbxlx"
Lute.place.build { output = place, roots = { "src/core", "src/roblox" }, rootName = "NativeContent" }
local result = Lute.studio.run {
	place = place,
	worker = "tools/studio-worker.luau",
	context = "Server",
	deadlineSeconds = 600,
	identity = if input.identity then Identity.read(input.identity) else nil,
	code = "local requests = game:GetService('HttpService'):JSONDecode("
		.. string.format("%q", Lute.encode(requests))
		.. ")\n"
		.. source,
}
assert(result.status == "returned", result.detail)
local report = Core.decode(result.report)
fs.writeStringToFile(output .. ".report.json", Lute.encode(report))
print(Core.format(report))
assert(report.total == 1 and report.passed == 1, "native content capture failed")
local parts = Attachments.write(report.results[1].artifacts, output .. ".attachments")
local encoded = fs.readFileToString((assert(parts["facts.json"], "native capture returned no content facts")))
local capture = Facts.validate(Wire.parse(encoded))
if input.identity then
	local identity = Identity.read(input.identity)
	assert(
		capture.placeId == identity.placeId and capture.gameId == identity.universeId,
		"native content place identity differs"
	)
end
assert(#capture.rows == #requests, "native content request count differs")
for index, row in capture.rows do
	local expected = requests[index]
	assert(
		row.request.kind == expected.kind
			and row.request.key == expected.key
			and row.request.id == expected.id
			and row.request.version == expected.version,
		"native content request differs"
	)
end
fs.writeStringToFile(output, encoded)
print("wrote native content facts to " .. output)
