--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local Policy = require "../src/lute/type-policy"

local listed = process.run { "git", "ls-files", "--cached", "--others", "--exclude-standard", "--", "*.luau" }
assert(listed.ok, listed.stderr)
local failures = 0
local seen: { [string]: boolean } = {}
for path in string.gmatch(listed.stdout, "[^\r\n]+") do
	if not seen[path] and fs.exists(path) then
		seen[path] = true
		local source = fs.readFileToString(path)
		if string.match(source, "^%-%-!strict%s") == nil then
			print(path .. ":1: maintained Luau requires --!strict")
			failures += 1
		end
		for _, line in Policy.nonStrict(source) do
			print(("%s:%d: weakening strict checking is forbidden"):format(path, line))
			failures += 1
		end
		for _, line in Policy.explicitAny(source) do
			print(
				("%s:%d: explicit any is forbidden; use a concrete type, generic or validated unknown"):format(
					path,
					line
				)
			)
			failures += 1
		end
	end
end
assert(failures == 0, ("type policy: %d type-policy violations"):format(failures))
print "type policy: no explicit any in maintained Luau"
