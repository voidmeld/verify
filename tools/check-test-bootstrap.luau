--!strict

local fs = require "@std/fs"
local process = require "@std/process"

local root = ".lute/tmp/verify-test-bootstrap"
local fixtures: { { name: string, source: string?, passes: boolean, output: string } } = {
	{
		name = "passing",
		source = 'return function(harness) harness:case("bootstrap pass", function(context) context:expect(1):toEqual(1) end) end',
		passes = true,
		output = "1 passed, 0 failed",
	},
	{
		name = "failing",
		source = 'return function(harness) harness:case("bootstrap mismatch", function(context) print("bootstrap case executed") context:expect(1):toEqual(2) end) end',
		passes = false,
		output = "0 passed, 1 failed",
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
		output = "test corpus is empty",
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
	local result = process.run { "lute", "run", "tools/test.luau", directory }
	local output = result.stdout .. result.stderr
	assert(result.ok == fixture.passes, fixture.name .. ": unexpected runner exit\n" .. output)
	assert(string.find(output, fixture.output, 1, true) ~= nil, fixture.name .. ": missing result\n" .. output)
	if fixture.name == "failing" then
		assert(string.find(output, "bootstrap case executed", 1, true) ~= nil, "failed case was not executed")
	end
end
print "test bootstrap: success, matcher failure, registration failure and empty discovery verified independently"
