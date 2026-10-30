--!strict
return [==[
local screen=Instance.new("ScreenGui")
screen.Parent=game.Players.LocalPlayer.PlayerGui
local function label(parent,width)
 local text=Instance.new("TextLabel")
 text.Size=UDim2.fromOffset(width,0)
 text.AutomaticSize=Enum.AutomaticSize.Y
 text.TextWrapped=true
 text.Text=string.rep("Wrapped text in a flexible line. ",4)
 text.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json")
 text.TextSize=16
 text.Parent=parent
 return text
end
for _,scale in {0.5,1,2} do
 local row=Instance.new("Frame")
 row.AutomaticSize=Enum.AutomaticSize.Y
 row.Parent=screen
 local scaler=Instance.new("UIScale")
 scaler.Scale,scaler.Parent=scale,row
 local list=Instance.new("UIListLayout")
 list.FillDirection=Enum.FillDirection.Horizontal
 list.SortOrder=Enum.SortOrder.LayoutOrder
 list.Padding=UDim.new(0,8)
 list.Wraps=true
 list.Parent=row
 for index,width in {40,80} do
  local child=Instance.new("Frame")
  child.Size=UDim2.fromOffset(width,20)
  child.LayoutOrder=index
  child.Parent=row
 end
 local text=label(row,180)
 text.LayoutOrder=3
 local flex=Instance.new("UIFlexItem")
 flex.FlexMode=Enum.UIFlexMode.Fill
 flex.Parent=text
 local reference=label(screen,180)
 local referenceScale=Instance.new("UIScale")
 referenceScale.Scale,referenceScale.Parent=scale,reference
 for _,entry in {{120,120,56},{280,280,28},{400,264,0},{280,280,28}} do
  row.Size=UDim2.fromOffset(entry[1],0)
  reference.Size=UDim2.fromOffset(entry[2],0)
  task.wait(0.1)
  local context=scale.."/"..entry[1]
  assert(text.AbsoluteSize==reference.AbsoluteSize,"wrapped flex size "..context..": "..tostring(text.AbsoluteSize).." vs "..tostring(reference.AbsoluteSize))
  assert(text.TextBounds==reference.TextBounds,"wrapped flex text bounds "..context)
  assert(text.TextFits==reference.TextFits,"wrapped flex text fits "..context)
  assert(text.AbsolutePosition.Y-row.AbsolutePosition.Y==entry[3]*scale,"wrapped flex line position "..context..": "..tostring(text.AbsolutePosition-row.AbsolutePosition))
  assert(row.AbsoluteSize.Y==entry[3]*scale+text.AbsoluteSize.Y,"wrapped flex automatic row height "..context..": "..tostring(row.AbsoluteSize))
 end
 reference:Destroy()
 row:Destroy()
end
screen:Destroy()
return true
]==]
