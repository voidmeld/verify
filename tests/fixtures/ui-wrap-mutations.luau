--!strict

return [==[
local screen=Instance.new("ScreenGui")
screen.IgnoreGuiInset,screen.Parent=true,game.Players.LocalPlayer.PlayerGui
local parent=Instance.new("Frame")
parent.Size,parent.AutomaticSize,parent.Parent=UDim2.fromOffset(180,0),Enum.AutomaticSize.Y,screen
local list=Instance.new("UIListLayout")
list.Wraps,list.FillDirection,list.SortOrder,list.Padding,list.Parent=true,Enum.FillDirection.Horizontal,Enum.SortOrder.LayoutOrder,UDim.new(0,8),parent
local cells={}
for index,shape in {{60,10},{80,30},{40,20}} do
 local cell=Instance.new("Frame")
 cell.Size,cell.LayoutOrder,cell.Parent=UDim2.fromOffset(unpack(shape)),index,parent
 cells[index]=cell
end
local function expect(width,height,positions)
 task.wait(0.05)
 assert(parent.AbsoluteSize==Vector2.new(width,height),"automatic wrapped parent: " .. tostring(parent.AbsoluteSize))
 for index,position in positions do
  local actual=cells[index].AbsolutePosition-parent.AbsolutePosition
  assert(actual==Vector2.new(unpack(position)),"wrapped mutation position " .. index .. ": " .. tostring(actual))
 end
end
expect(180,58,{{0,0},{68,0},{0,38}})
parent.Size=UDim2.fromOffset(200,0)
expect(200,30,{{0,0},{68,0},{156,0}})
cells[2].Visible=false
expect(200,20,{[1]={0,0},[3]={68,0}})
cells[2].Visible=true
cells[3].LayoutOrder=-1
expect(200,30,{{48,0},{116,0},{0,0}})
parent.Size=UDim2.fromOffset(100,0)
expect(100,76,{{0,28},{0,46},{0,0}})
cells[3]:Destroy()
expect(100,48,{{0,0},{0,18}})
list.Wraps=false
expect(100,30,{{0,0},{68,0}})
screen:Destroy()
return true
]==]
