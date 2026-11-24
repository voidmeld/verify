--!strict

return [==[
local simulator = game:GetService("StudioDeviceSimulatorService")
local gui = game:GetService("GuiService")
for _, row in { {"iphone_14", "Small"}, {"xbox", "Large"}, {"hd_1080", "Medium"}, {"generic_handheld_720", "Small"} } do
 simulator:SetDeviceAsync(row[1])
 for _ = 1, 10 do game:GetService("RunService").RenderStepped:Wait() end
 assert(gui.ViewportDisplaySize == Enum.DisplaySize[row[2]], row[1] .. " display size " .. tostring(gui.ViewportDisplaySize))
end
simulator:SetDeviceAsync("hd_1080")
for _, width in {400, 800, 1920, 2560} do
 simulator:SetResolutionAsync(width, 720)
 for _ = 1, 10 do game:GetService("RunService").RenderStepped:Wait() end
 assert(gui.ViewportDisplaySize == Enum.DisplaySize.Medium, "resolution changed device class")
end
simulator:StopSimulationAsync()
return true
]==]
