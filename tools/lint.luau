--!strict

local process = require "@std/process"

local ATTEMPTS = 3

local arguments = { "lute", "lint" }
for index = 2, #process.args do
	table.insert(arguments, process.args[index])
end

local function isBlank(text: string): boolean
	return string.match(text, "%S") == nil
end

for attempt = 1, ATTEMPTS do
	local result = process.run(arguments)
	if result.ok then
		print(result.stdout)
		process.exit(0)
	end
	if not (isBlank(result.stdout) and isBlank(result.stderr)) then
		print(result.stdout)
		print(result.stderr)
		process.exit(1)
	end
	print(("lint: lute lint exited without any report on attempt %d of %d"):format(attempt, ATTEMPTS))
end
process.exit(1)
