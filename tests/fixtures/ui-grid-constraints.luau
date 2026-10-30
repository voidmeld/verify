--!strict
return [==[
local out={}
local screen=Instance.new("ScreenGui")
screen.IgnoreGuiInset=true
screen.Parent=game.Players.LocalPlayer.PlayerGui
for _,variant in {"plain","min-wide","min-tall","min-both","min-wide-165","max","half","double","aspect"} do
 local parent=Instance.new("Frame")
 parent.Size=UDim2.fromOffset(300,200)
 parent.Parent=screen
 local grid=Instance.new("UIGridLayout")
 grid.CellSize=UDim2.fromOffset(80,40)
 grid.CellPadding=UDim2.fromOffset(10,5)
 grid.SortOrder=Enum.SortOrder.LayoutOrder
 grid.Parent=parent
 local items={}
 for i=1,5 do
  local item=Instance.new("Frame")
  item.Name,item.LayoutOrder,item.Parent="Item"..i,i,parent
  items[i]=item
 end
 if variant:sub(1,3)=="min" or variant=="max" then
  local c=Instance.new("UISizeConstraint")
  if variant=="max" then c.MaxSize=Vector2.new(30,20)
  elseif variant=="min-wide" then c.MinSize=Vector2.new(120,0)
  elseif variant=="min-wide-165" then c.MinSize=Vector2.new(165,0)
  elseif variant=="min-tall" then c.MinSize=Vector2.new(0,60)
  else c.MinSize=Vector2.new(120,60) end
  c.Parent=items[2]
 elseif variant=="half" or variant=="double" then
  local c=Instance.new("UIScale")
  c.Scale=if variant=="half" then 0.5 else 2
  c.Parent=items[2]
 elseif variant=="aspect" then
  local c=Instance.new("UIAspectRatioConstraint")
  c.AspectRatio=1
  c.Parent=items[2]
 end
 task.wait(0.1)
 local row={variant=variant,cell=tostring(grid.AbsoluteCellSize),count=tostring(grid.AbsoluteCellCount),content=tostring(grid.AbsoluteContentSize),items={}}
 for _,item in items do table.insert(row.items,{size=tostring(item.AbsoluteSize),position=tostring(item.AbsolutePosition-parent.AbsolutePosition)}) end
 table.insert(out,row)
 parent:Destroy()
end
screen:Destroy()
local expected=game.HttpService:JSONDecode([====[[{"items":[{"position":"0, 0","size":"80, 40"},{"position":"90, 0","size":"80, 40"},{"position":"180, 0","size":"80, 40"},{"position":"0, 45","size":"80, 40"},{"position":"90, 45","size":"80, 40"}],"count":"3, 2","variant":"plain","cell":"80, 40","content":"260, 85"},{"items":[{"position":"0, 0","size":"80, 40"},{"position":"115, 20","size":"120, 0"},{"position":"0, 45","size":"80, 40"},{"position":"90, 45","size":"80, 40"},{"position":"180, 45","size":"80, 40"}],"count":"3, 2","variant":"min-wide","cell":"80, 40","content":"260, 85"},{"items":[{"position":"0, 0","size":"80, 40"},{"position":"130, 12.5","size":"0, 60"},{"position":"180, 0","size":"80, 40"},{"position":"0, 45","size":"80, 40"},{"position":"180, 45","size":"80, 40"}],"count":"3, 2","variant":"min-tall","cell":"80, 40","content":"260, 85"},{"items":[{"position":"0, 0","size":"80, 40"},{"position":"115, 12.5","size":"120, 60"},{"position":"0, 45","size":"80, 40"},{"position":"0, 90","size":"80, 40"},{"position":"90, 90","size":"80, 40"}],"count":"3, 3","variant":"min-both","cell":"80, 40","content":"260, 130"},{"items":[{"position":"0, 0","size":"80, 40"},{"position":"92.5, 20","size":"165, 0"},{"position":"0, 45","size":"80, 40"},{"position":"90, 45","size":"80, 40"},{"position":"180, 45","size":"80, 40"}],"count":"3, 2","variant":"min-wide-165","cell":"80, 40","content":"260, 85"},{"items":[{"position":"0, 0","size":"80, 40"},{"position":"115, 10","size":"30, 20"},{"position":"180, 0","size":"80, 40"},{"position":"0, 45","size":"80, 40"},{"position":"90, 45","size":"80, 40"}],"count":"3, 2","variant":"max","cell":"80, 40","content":"260, 85"},{"items":[{"position":"0, 0","size":"80, 40"},{"position":"110, 10","size":"40, 20"},{"position":"180, 0","size":"80, 40"},{"position":"0, 45","size":"80, 40"},{"position":"90, 45","size":"80, 40"}],"count":"3, 2","variant":"half","cell":"80, 40","content":"260, 85"},{"items":[{"position":"0, 0","size":"80, 40"},{"position":"50, -20","size":"160, 80"},{"position":"180, 0","size":"80, 40"},{"position":"0, 45","size":"80, 40"},{"position":"90, 45","size":"80, 40"}],"count":"3, 2","variant":"double","cell":"80, 40","content":"260, 85"},{"items":[{"position":"0, 0","size":"80, 40"},{"position":"110, 0","size":"40, 40"},{"position":"180, 0","size":"80, 40"},{"position":"0, 45","size":"80, 40"},{"position":"90, 45","size":"80, 40"}],"count":"3, 2","variant":"aspect","cell":"80, 40","content":"260, 85"}]]====])
for index,row in out do local want=expected[index]; assert(row.cell==want.cell and row.count==want.count and row.content==want.content,row.variant.." grid geometry"); for i,item in row.items do assert(item.size==want.items[i].size and item.position==want.items[i].position,row.variant.." item "..i..": "..item.size.." at "..item.position) end end
return true
]==]
