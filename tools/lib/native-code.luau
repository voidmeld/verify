--!strict

return function(rootName: string, code: string): string
	return "local mounted = game:GetService('ReplicatedStorage'):WaitForChild("
		.. string.format("%q", rootName)
		.. ")\n"
		.. [[
local capabilities = SecurityCapabilities.fromCurrent():Remove(Enum.SecurityCapability.Unassigned)
for _, module in mounted:GetDescendants() do
 if module:IsA('ModuleScript') and not module.Sandboxed then
  module.Capabilities = capabilities
  module.Sandboxed = true
 end
end
]]
		.. code
end
