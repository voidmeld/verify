--!strict

local Lune = require "../src/lune"
local Verify = require "../src/core"

local plan: Verify.PlanDraft = {
	id = "lune-example",
	units = {
		{ id = "passing", locator = "lune-cases/passing", group = "a" },
		{ id = "failing", locator = "lune-cases/failing", group = "b" },
		{ id = "missing", locator = "lune-cases/absent", group = "c" },
	},
}

local host = Lune.host {
	worker = "examples/lune-worker.luau",
	directory = ".verify/lune-example",
	deadlineSeconds = 30,
}
local execution = Verify.execute(plan, host, { batchCount = 3, parallel = 3 })
print(Verify.format(execution.report))
print(
	("lune example: %d passed, %d failed (the failures are intentional)"):format(
		execution.report.passed,
		execution.report.failed
	)
)
