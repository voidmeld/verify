--!strict

local Verify = require "../src/core"

local tick = 0
local harness = Verify.createHarness {
	now = function()
		tick += 0.001
		return tick
	end,
}

harness:suite("example", function()
	harness:case("produces a receipt", {
		requires = { "example" },
		limitations = { "synthetic clock" },
		run = function(context)
			context:step("observe", function()
				context:expect(2 + 2):toBe(4)
			end)
			context:artifact("trace", "build/example-trace.json", "application/json")
		end,
	})
end)

local report = harness:run {
	executor = "example",
	capabilities = { "example" },
	environment = { revision = "working-tree" },
}

print(Verify.format(report))

local session = Verify.compose({
	{ id = "worker-1", report = report },
	{ id = "worker-2", error = "worker exited before writing a report" },
	{ id = "worker-3", report = "truncated" },
}, "example-session", { revision = "working-tree" })

print(Verify.format(session))
