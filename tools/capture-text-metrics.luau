--!strict

local fs = require "@std/fs"
local json = require "@std/json"
local process = require "@std/process"
local Core = require "../src/core"
local Lute = require "../src/lute"
local Files = require "../src/lute/files"
local source = require "./lib/capture-text-metrics"
local Attachments = require "../src/lute/capture-attachments"

local USAGE = "usage: lute run tools/capture-text-metrics.luau <out.json> <font-family> [weight] [style]"
local output, family = process.args[2], process.args[3]
assert(output and family and #process.args <= 5, USAGE)
assert(
	not fs.exists(output) and not fs.exists(output .. ".report.json") and not fs.exists(output .. ".attachments"),
	"capture output exists; preserve and reconcile it"
)
local descriptor = { family = family, weight = process.args[4] or "Regular", style = process.args[5] or "Normal" }
local place = Files.temporary "Verify-Text-Metrics.rbxlx"
Lute.place.build { output = place, roots = { "src/core", "src/roblox" }, rootName = "TextMetrics" }
local result = Lute.studio.run {
	place = place,
	worker = "tools/studio-worker.luau",
	context = "Client",
	deadlineSeconds = 600,
	code = 'local descriptor = game:GetService("HttpService"):JSONDecode(' .. string.format(
		"%q",
		Lute.encode(descriptor)
	) .. ")\n" .. source,
}
assert(result.status == "returned", result.detail)
local report = Core.decode(result.report)
fs.writeStringToFile(output .. ".report.json", Lute.encode(report))
print(Core.format(report))
local parts = Attachments.write(report.results[1].artifacts, output .. ".attachments")
assert(report.total == 1 and report.passed == 1, "font model did not match native measurements")
local metrics = assert(
	json.asObject(
		json.deserialize(fs.readFileToString((assert(parts["metrics.json"], "native capture returned no font facts"))))
	)
)
local sizes: { json.Value } = {}
for _, name in { "sizes-1.json", "sizes-2.json" } do
	for _, row in
		assert(
			json.asArray(
				json.deserialize(fs.readFileToString((assert(parts[name], "native capture returned no " .. name))))
			)
		)
	do
		table.insert(sizes, row)
	end
end
metrics.sizes = sizes
fs.writeStringToFile(output, json.serialize(metrics))
print("wrote native font facts to " .. output)
