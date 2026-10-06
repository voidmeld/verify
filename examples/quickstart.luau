--!strict

local process = require "@std/process"

local Verify = require "../src/core"

local harness = Verify.createHarness { now = os.clock }

harness:case("adds numbers", function(context)
	context:expect(2 + 2):toBe(4)
end)

local report = harness:run {
	executor = "quickstart",
	capabilities = {},
	environment = { revision = "working-tree" },
}
print(Verify.format(report))
if report.passed ~= report.total then
	process.exit(1)
end
