--!strict

local fs = require "@std/fs"
local luau = require "@std/luau"
local process = require "@std/process"

local Core = require "../../../../../src/core"
local Lute = require "../../../../../src/lute"

local path = assert(process.args[2], "missing module path")
local reportPath = assert(process.args[3], "missing report path")
local runId = assert(process.args[4], "missing run id")

type Counter = { increment: () -> (), value: () -> number }

local function load(): Counter
	local chunk = luau.load(luau.compile(fs.readFileToString(path)), "counter")
	local value: Counter = chunk()
	assert(type(value) == "table", "the module must return a table")
	return value
end

local harness = Core.createHarness { now = os.clock }
harness:case("starts at zero", function(context)
	context:expect(load().value()):toBe(0)
end)
harness:case("increments by one", function(context)
	local counter = load()
	counter.increment()
	counter.increment()
	context:expect(counter.value()):toBe(2)
end)
local report = harness:run { executor = "counter-cases", environment = { module = path } }
Lute.gate.writeReport(reportPath, runId, report)
print(Core.format(report))
