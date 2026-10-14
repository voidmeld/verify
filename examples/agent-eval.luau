--!strict

local process = require "@std/process"

local AgentEval = require "../src/agent-eval"

local binding = AgentEval.lute
local root = binding.absolute ".lute/tmp/agent-eval-example"
local services = binding.services { workspaces = root .. "/workspaces" }
local loader = binding.loader()
local suitePath = binding.absolute "examples/agent-eval/eval.json"
local suite = AgentEval.decodeSuite(binding.decode(loader.files.read(suitePath)), suitePath, loader)

local summary = AgentEval.run {
	suite = suite,
	loader = loader,
	services = services,
	adapters = { fixture = AgentEval.adapters.fixture(binding.decode) },
	evidence = root .. "/evidence",
	encode = binding.encode,
	decode = binding.decode,
	resume = false,
}

local thresholds = AgentEval.report.decodeThresholds(
	binding.decode(loader.files.read(binding.absolute "examples/agent-eval/thresholds.json"))
)
local report = AgentEval.report.build(suite.id, summary.results, {}, thresholds, nil)
print(AgentEval.report.markdown(report))

local passed = 0
for _, result in summary.results do
	if result.passed then
		passed += 1
	end
end
assert(#summary.results == 8, ("expected 8 runs, got %d"):format(#summary.results))
assert(passed == 6, ("expected 6 passing runs, got %d"):format(passed))
if report.verdict ~= "PASS" then
	process.exit(1)
end
