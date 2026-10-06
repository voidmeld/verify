--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local Walk = require "./lib/walk"

local FORBIDDEN_ROOTS = { "integration", "integrations", "src/integration", "src/integrations" }

local failures: { string } = {}
local requires = 0

local function requiresIn(source: string): { string }
	local found: { string } = {}
	for request in string.gmatch(source, 'require%s*"([^"]+)"') do
		table.insert(found, request)
	end
	for request in string.gmatch(source, 'require%s*%(%s*"([^"]+)"') do
		table.insert(found, request)
	end
	return found
end

for _, file in Walk.files("src/core", { ".luau" }) do
	for _, request in requiresIn(file.contents) do
		requires += 1
		if string.sub(request, 1, 6) ~= "@self/" and string.sub(request, 1, 2) ~= "./" then
			table.insert(
				failures,
				("%s names %q; core may require only @self/ or ./ siblings"):format(file.path, request)
			)
		end
	end
end

for _, root in FORBIDDEN_ROOTS do
	if fs.exists(root) then
		table.insert(failures, ("%s exists; consumer integration does not belong in Verify"):format(root))
	end
end

for _, failure in failures do
	print("dependencies: " .. failure)
end
if #failures > 0 then
	process.exit(1)
end
print(("dependencies: %d core requires stay framework-neutral; no integration package exists"):format(requires))
