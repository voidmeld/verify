--!strict

local fs = require "@std/fs"

local Gate = require "../src/gate"
local Verify = require "../src/core"
local Lute = require "../src/lute"

local root = ".lute/tmp/verify-test-bootstrap"
local fixtures: { { name: string, source: string?, passes: boolean, output: string } } = {
	{
		name = "passing",
		source = 'local Test = require "../../../../tests/harness" Test.it("bootstrap pass", function() Test.expect(1):toEqual(1) end) return nil',
		passes = true,
		output = "::bootstrap pass",
	},
	{
		name = "failing",
		source = 'local Test = require "../../../../tests/harness" Test.it("bootstrap mismatch", function() print("bootstrap case executed") Test.expect(1):toEqual(2) end) return nil',
		passes = false,
		output = "::bootstrap mismatch",
	},
	{
		name = "registration",
		source = 'error("bootstrap registration failed", 0) return nil',
		passes = false,
		output = "bootstrap registration failed",
	},
	{
		name = "empty",
		passes = false,
		output = "lists no test module",
	},
}

for _, fixture in fixtures do
	local directory = root .. "/" .. fixture.name
	if not fs.exists(directory) then
		fs.createDirectory(directory, { makeParents = true })
	end
	if fixture.source ~= nil then
		fs.writeStringToFile(directory .. "/bootstrap.verify.luau", fixture.source)
	end
	local locators: { string } = {}
	if fixture.source ~= nil then
		table.insert(locators, directory .. "/bootstrap.verify.luau")
	end
	local ran, outcome = pcall(function()
		local gate = Gate.define {
			id = "bootstrap-" .. fixture.name,
			producers = { { id = "specs", kind = "tests", worker = "tests/worker.luau", locators = locators } },
		}
		return Lute.gate.run(gate, { directory = directory .. "/gate" })
	end)
	local output = if ran then Verify.format(outcome.execution.report) else tostring(outcome)
	if ran then
		for _, result in outcome.execution.report.results do
			for _, failure in result.failures do
				output ..= "\n" .. failure.message
			end
		end
	end
	local passed = ran and outcome.acceptance.verdict == "release"
	assert(passed == fixture.passes, fixture.name .. ": unexpected gate verdict\n" .. output)
	assert(string.find(output, fixture.output, 1, true) ~= nil, fixture.name .. ": missing result\n" .. output)
end
print "test bootstrap: success, matcher failure, registration failure and empty discovery verified through the gate"
