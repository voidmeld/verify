--!strict

local fs = require "@std/fs"

local Gate = require "../src/gate"
local Verify = require "../src/core"
local Lute = require "../src/lute"

local root = ".lute/tmp/verify-test-bootstrap"
local fixtures: { { name: string, source: string?, passes: boolean, output: string } } = {
	{
		name = "passing",
		source = 'return function(harness) harness:case("bootstrap pass", function(context) context:expect(1):toEqual(1) end) end',
		passes = true,
		output = "::bootstrap pass",
	},
	{
		name = "failing",
		source = 'return function(harness) harness:case("bootstrap mismatch", function(context) print("bootstrap case executed") context:expect(1):toEqual(2) end) end',
		passes = false,
		output = "::bootstrap mismatch",
	},
	{
		name = "registration",
		source = 'return function() error("bootstrap registration failed", 0) end',
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
		fs.writeStringToFile(directory .. "/bootstrap.spec.luau", fixture.source)
	end
	local locators: { string } = {}
	if fixture.source ~= nil then
		table.insert(locators, directory .. "/bootstrap.spec.luau")
	end
	local ran, outcome: unknown = pcall(function()
		local gate = Gate.define {
			id = "bootstrap-" .. fixture.name,
			producers = { { id = "specs", kind = "tests", worker = "examples/worker.luau", locators = locators } },
		}
		return Lute.gate.run(gate, { directory = directory .. "/gate" })
	end)
	local output = if ran then Verify.format((outcome :: Gate.Outcome).execution.report) else tostring(outcome)
	if ran then
		for _, result in (outcome :: Gate.Outcome).execution.report.results do
			for _, failure in result.failures do
				output ..= "\n" .. failure.message
			end
		end
	end
	local passed = ran and (outcome :: Gate.Outcome).acceptance.verdict == "release"
	assert(passed == fixture.passes, fixture.name .. ": unexpected gate verdict\n" .. output)
	assert(string.find(output, fixture.output, 1, true) ~= nil, fixture.name .. ": missing result\n" .. output)
end
print "test bootstrap: success, matcher failure, registration failure and empty discovery verified through the gate"
