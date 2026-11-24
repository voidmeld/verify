--!strict
local process = require "@std/process"
return function(name: string, findings: { string })
	for _, finding in findings do
		print(finding)
	end
	if #findings > 0 then
		process.exit(1)
	end
	print(name .. ": ok")
end
