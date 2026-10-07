--!strict

local process = require "@std/process"

local Lute = require "../src/lute"
local Gate = require "../src/gate"

local checksum = 0

local gate = Gate.define {
	id = "example-gate",
	producers = {
		{
			id = "prepare",
			kind = "build",
			argv = { "/bin/echo", "prepared" },
			tier = "fast",
			why = "stages the inputs",
		},
		{
			id = "specs",
			kind = "tests",
			worker = "examples/worker.luau",
			locators = { "tests/wait.verify.luau" },
			after = { "prepare" },
			tier = "fast",
			why = "the module corpus",
		},
		{
			id = "speed",
			kind = "benchmark",
			after = { "prepare" },
			tier = "slow",
			benchmark = {
				name = "checksum",
				unit = "microseconds",
				warmup = 2,
				samples = 8,
				iterations = 100,
				workload = function()
					for value = 1, 100 do
						checksum += value % 3
					end
				end,
				budget = { maximum = 100000 },
				environment = { observed = "example-machine" },
			},
		},
		{
			id = "interactive",
			kind = "native",
			argv = { "/bin/echo", "would drive an interactive editor" },
			requires = { "native-studio" },
			tier = "slow",
		},
	},
	policy = {
		concurrency = 2,
		deadlineSeconds = 120,
		deferrals = { interactive = "no interactive editor in this run" },
	},
}

local ids: { string } = {}
for index = 2, #process.args do
	table.insert(ids, process.args[index])
end
local outcome = Lute.gate.run(gate, {
	selection = if #ids > 0 then { ids = ids } else nil,
	capabilities = {},
})
print(Gate.format(outcome))
print(
	("%d case(s); the report is outcome.execution.report; logs are under %s"):format(
		outcome.execution.report.total,
		Lute.gate.DEFAULT_DIRECTORY
	)
)
local verdict = outcome.acceptance.verdict
if verdict == "failed" then
	process.exit(1)
end
