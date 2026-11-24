--!strict

local process = require "@std/process"

local ATTEMPTS = 3

local arguments = { "lute", "lint" }
for index = 2, #process.args do
	table.insert(arguments, process.args[index])
end

local function reports(text: string): boolean
	return string.find(text, "%.luau:%d") ~= nil
end

for attempt = 1, ATTEMPTS do
	local result = process.run(arguments)
	if result.ok then
		print(result.stdout)
		process.exit(0)
	end
	if reports(result.stdout) or reports(result.stderr) then
		print(result.stdout)
		print(result.stderr)
		process.exit(1)
	end
	print(("lint: lute lint exited without any report on attempt %d of %d"):format(attempt, ATTEMPTS))
	print(result.stderr)
end
process.exit(1)
