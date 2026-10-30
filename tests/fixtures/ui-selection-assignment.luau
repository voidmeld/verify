--!strict

return [==[
local screen=Instance.new("ScreenGui")
screen.Parent=game.Players.LocalPlayer.PlayerGui
local first=Instance.new("TextButton")
first.Name,first.Text,first.Parent="First","",screen
local target=Instance.new("TextButton")
target.Name,target.Text,target.Parent="Target","",screen
for _,mode in {"normal","unselectable","hidden","inactive","unparented","disabledScreen"} do
 target.Selectable,target.Visible,target.Active=true,true,true
 target.Parent,screen.Enabled=screen,true
 game.GuiService.SelectedObject=first
 if mode=="unselectable" then target.Selectable=false end
 if mode=="hidden" then target.Visible=false end
 if mode=="inactive" then target.Active=false end
 if mode=="unparented" then target.Parent=nil end
 if mode=="disabledScreen" then screen.Enabled=false end
 task.wait(0.1)
 local ok=pcall(function() game.GuiService.SelectedObject=target end)
 assert(ok==(mode~="unparented"),"selection assignment acceptance: "..mode)
 local expected=if mode=="unparented" then first else target
 assert(game.GuiService.SelectedObject==expected,"immediate selected object: "..mode)
 task.wait(0.1)
 assert(game.GuiService.SelectedObject==expected,"settled selected object: "..mode)
end
game.GuiService.SelectedObject=nil
target:Destroy()
screen:Destroy()
return true
]==]
