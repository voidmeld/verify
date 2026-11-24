--!strict
return [==[
local gui=game.Players.LocalPlayer.PlayerGui
for _,mode in {Enum.ZIndexBehavior.Sibling,Enum.ZIndexBehavior.Global} do
 for _,reverse in {false,true} do
  local screens,frames={},{}
  for i=1,3 do
   local screen=Instance.new("ScreenGui")
   screen.ZIndexBehavior=mode
   screens[i]=screen
   local frame=Instance.new("Frame")
   frame.Name=tostring(i)
   frame.Position=UDim2.fromOffset(200,150)
   frame.Size=UDim2.fromOffset(80,80)
   frame.ZIndex=4-i
   frame.Parent=screen
   frames[i]=frame
  end
  local function sample(expected)
   game.RunService.RenderStepped:Wait()
   game.RunService.RenderStepped:Wait()
   local point=frames[1].AbsolutePosition+frames[1].AbsoluteSize/2
   local order={}
   for _,hit in gui:GetGuiObjectsAtPosition(point.X,point.Y) do
    if table.find(frames,hit) then table.insert(order,hit.Name) end
   end
   assert(table.concat(order,",")==expected,"screen order: "..table.concat(order,",").." expected "..expected)
  end
  for i=1,3 do screens[if reverse then 4-i else i].Parent=gui end
  sample(if reverse then "1,2,3" else "3,2,1")
  screens[1].Parent=nil;screens[1].Parent=gui
  local tied=if reverse then "1,2,3" else "1,3,2"
  sample(tied)
  screens[2].Enabled=false;sample("1,3")
  screens[2].Enabled=true;sample(tied)
  screens[3].DisplayOrder=1;sample("3,1,2")
  screens[3].DisplayOrder=0;sample(tied)
  screens[2].Name="AAA";sample(tied)
  local a,b=Instance.new("Folder"),Instance.new("Folder")
  a.Parent=gui;b.Parent=gui
  for _,screen in screens do screen.Parent=nil end
  screens[2].Parent=b;screens[1].Parent=a;sample("1,2")
  screens[3].Parent=a;sample("3,1,2")
  b.Parent=nil;b.Parent=gui;sample("2,3,1")
  screens[1].Parent=nil;screens[1].Parent=a;sample("1,2,3")
  screens[3].Parent=b;sample("1,2,3")
  screens[2].Parent=a;sample("1,2,3")
  a:Destroy();b:Destroy()
 end
end
return true
]==]
