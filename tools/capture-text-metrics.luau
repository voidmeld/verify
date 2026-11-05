--!strict

local fs = require "@std/fs"
local json = require "@std/json"
local process = require "@std/process"
local Core = require "../src/core"
local Lute = require "../src/lute"
local Files = require "../src/lute/files"
local source = require "./lib/capture-text-metrics"
local Attachments = require "../src/lute/capture-attachments"
local NativeCode = require "./lib/native-code"
local Metrics = require "../src/lute/text-metrics"

local USAGE =
	"usage: lute run tools/capture-text-metrics.luau <out.json> <font-family> [weight] [style] [symbols base.json]"
local output, family = process.args[2], process.args[3]
assert(output and family and (#process.args <= 5 or #process.args == 7 and process.args[6] == "symbols"), USAGE)
assert(
	not fs.exists(output) and not fs.exists(output .. ".report.json") and not fs.exists(output .. ".attachments"),
	"capture output exists; preserve and reconcile it"
)
local symbols = process.args[6] == "symbols"
local descriptor = {
	family = family,
	weight = process.args[4] or "Regular",
	style = process.args[5] or "Normal",
	texts = if symbols then require "./lib/text-metric-symbols" else nil,
}
local base = if symbols then assert(json.asObject(json.deserialize(fs.readFileToString(process.args[7])))) else nil
if base then
	Metrics.decode(base)
	assert(
		base.family == descriptor.family and base.weight == descriptor.weight and base.style == descriptor.style,
		"symbol base face differs"
	)
end
local place = Files.temporary "Verify-Text-Metrics.rbxlx"
Lute.place.build { output = place, roots = { "src/core", "src/roblox" }, rootName = "TextMetrics" }
local result = Lute.studio.run {
	place = place,
	worker = "tools/studio-worker.luau",
	context = "Client",
	deadlineSeconds = 1800,
	code = NativeCode(
		"TextMetrics",
		'local descriptor = game:GetService("HttpService"):JSONDecode('
			.. string.format("%q", Lute.encode(descriptor))
			.. ")\n"
			.. (if symbols then require "./lib/capture-text-symbols" else source)
	),
}
assert(result.status == "returned", result.detail)
local report = Core.decode(result.report)
fs.writeStringToFile(output .. ".report.json", Lute.encode(report))
print(Core.format(report))
local parts = Attachments.write(report.results[1].artifacts, output .. ".attachments")
assert(report.total == 1 and report.passed == 1, "font capture did not pass native checks")
if base then
	local facts = assert(json.asObject(json.deserialize(fs.readFileToString(assert(parts["symbols.json"])))))
	base.measurements, base.measurementHeights, base.measurementEngineVersion =
		facts.measurements, facts.heights, facts.engineVersion
	Metrics.decode(base)
	fs.writeStringToFile(output, json.serialize(base))
	print("wrote native symbol facts to " .. output)
	return
end
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
