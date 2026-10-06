--!strict

local fs = require "@std/fs"
local process = require "@std/process"

local forbiddenRoots = { "vendor", "packages", "node_modules" }
for _, root in forbiddenRoots do
	if fs.exists(root) then
		print("provenance: forbidden dependency root exists: " .. root)
		process.exit(1)
	end
end

for _, file in { "COPYING", "NOTICE", "package.json", "pesde.toml", "wally.toml" } do
	if fs.exists(file) then
		print("provenance: forbidden manifest exists: " .. file)
		process.exit(1)
	end
end

local provenance = fs.readFileToString "PROVENANCE.md"
local license = fs.readFileToString "LICENSE"
local requiredLicenseFragments = {
	"MIT License",
	"Copyright (c) 2026 voidmeld",
	"Permission is hereby granted, free of charge, to any person obtaining a copy",
	'THE SOFTWARE IS PROVIDED "AS IS"',
}
for _, fragment in requiredLicenseFragments do
	if string.find(license, fragment, 1, true) == nil then
		print("provenance: LICENSE is not the authorized MIT grant: missing " .. fragment)
		process.exit(1)
	end
end
if string.find(provenance, "licensed under the MIT License", 1, true) == nil then
	print "provenance: PROVENANCE.md does not identify the MIT license"
	process.exit(1)
end
print "provenance: first-party source and MIT grant intact"
