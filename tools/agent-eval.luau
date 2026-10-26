--!strict

local process = require "@std/process"

local AgentEval = require "../src/agent-eval"
local Lute = require "../src/lute"

local args: { string } = {}
for index = 2, #process.args do
	table.insert(args, process.args[index])
end

local binding = AgentEval.lute
local code = AgentEval.cli(args, {
	services = binding.services(),
	loader = binding.loader(),
	encode = binding.encode,
	decode = binding.decode,
	absolute = binding.absolute,
	writeVerifyReport = Lute.gate.writeReport,
})
if code ~= 0 then
	process.exit(code)
end
