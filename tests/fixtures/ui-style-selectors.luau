--!strict

return [==[
local screen=Instance.new("ScreenGui")
screen.IgnoreGuiInset,screen.Parent=true,game.Players.LocalPlayer.PlayerGui
local sheet=Instance.new("StyleSheet")
sheet.Parent=screen
local link=Instance.new("StyleLink")
link.StyleSheet,link.Parent=sheet,screen
local container=Instance.new("Frame")
container:AddTag("Container")
container.Parent=screen
local child=Instance.new("Frame")
child.Name,child.Parent="Kid",container
child:AddTag("Card")
local grand=Instance.new("Frame")
grand.Parent=child
grand:AddTag("Hot")
local outside=Instance.new("Frame")
outside:AddTag("Card")
outside.Parent=screen
local rule=Instance.new("StyleRule")
rule:SetProperties({BackgroundTransparency=0.7})
rule.Parent=sheet
local records={}
for _,selector in {"Frame", "GuiObject", ".Card", "#Kid", "Frame#Kid.Card", ".Container > .Card", ".Container >> .Hot", ".Container > Frame#Kid > .Hot", "#Kid, .Hot"} do
 rule.Selector=selector
 task.wait(0.05)
 table.insert(records,{selector=selector,error=rule.SelectorError,values={container:GetStyled("BackgroundTransparency"),child:GetStyled("BackgroundTransparency"),grand:GetStyled("BackgroundTransparency"),outside:GetStyled("BackgroundTransparency")}})
end
rule:Destroy()
local expected = {
 {0.7,0.7,0.7,0.7}, {0.7,0.7,0.7,0.7}, {0,0.7,0,0.7}, {0,0.7,0,0}, {0,0.7,0,0},
 {0,0.7,0,0}, {0,0,0.7,0}, {0,0,0.7,0}, {0,0.7,0.7,0},
}
for index, record in records do
 for valueIndex, value in record.values do
  assert(math.abs(value - expected[index][valueIndex]) < 0.00001, record.selector)
 end
end

local parents={}
for _,physical in {false,true} do
 local parent=Instance.new("Frame")
 parent.Size,parent.Parent=UDim2.fromOffset(200,100),screen
 parent:AddTag("Padded")
 local marker=Instance.new("Frame")
 marker.Size,marker.Parent=UDim2.fromOffset(20,20),parent
 local padding
 if physical then padding=Instance.new("UIPadding");padding.Parent=parent end
 table.insert(parents,{parent=parent,marker=marker,padding=padding,physical=physical})
end
local observations={}
for _,selector in {".Padded::UIPadding", ".Padded > UIPadding", ".Padded::UIPadding, .Padded > UIPadding"} do
 local rule=Instance.new("StyleRule")
 rule.Selector=selector
 rule:SetProperties({PaddingLeft=UDim.new(0,12),PaddingTop=UDim.new(0,7)})
 rule.Parent=sheet
 task.wait(0.05)
 local row={selector=selector,error=rule.SelectorError,values={}}
 for _,entry in parents do
  local parent,marker=entry.parent,entry.marker
  local at=marker.AbsolutePosition-parent.AbsolutePosition
  local ok,value=pcall(function() return parent:GetStyled("PaddingLeft","::UIPadding").Offset end)
  table.insert(row.values,{physical=entry.physical,children=#parent:GetChildren(),find=parent:FindFirstChildWhichIsA("UIPadding")~=nil,position={at.X,at.Y},actual=if entry.padding then entry.padding:GetStyled("PaddingLeft").Offset else nil,queryOk=ok,query=tostring(value)})
 end
 table.insert(observations,row)
 rule:Destroy()
 task.wait(0.05)
end
for index, row in observations do
 for _, entry in row.values do
  local padded = index == 3 or (index == 1 and not entry.physical) or (index == 2 and entry.physical)
  assert(entry.position[1] == (if padded then 12 else 0), row.selector .. " x")
  assert(entry.position[2] == (if padded then 7 else 0), row.selector .. " y")
  assert(entry.children == (if entry.physical then 2 else 1), "physical child count")
  assert(entry.find == entry.physical, "physical lookup")
  assert(entry.queryOk == (index ~= 2), "phantom query availability")
  if entry.queryOk then assert(entry.query == "12", "phantom query value") end
  if entry.physical then assert(entry.actual == (if index == 1 then 0 else 12), "physical padding") end
 end
end

local parent, marker = parents[1].parent, parents[1].marker
local added, removed = 0, 0
parent.ChildAdded:Connect(function() added += 1 end)
parent.ChildRemoved:Connect(function() removed += 1 end)

local pad = Instance.new("StyleRule")
pad.Selector = ".Padded::UIPadding, .Padded > UIPadding"
pad:SetProperties({PaddingLeft = "$Inset"})
pad.Parent = sheet
sheet:SetAttribute("Inset", UDim.new(0, 12))
local function offset(expected)
 task.wait(0.05)
 assert(math.abs(marker.AbsolutePosition.X - parent.AbsolutePosition.X - expected) < 0.001, "mutated padding " .. expected)
 assert(#parent:GetChildren() == 1, "phantom creates physical children")
end
offset(12)
assert(added == 0 and removed == 0, "phantom hierarchy events")
assert(parent:GetStyled("PaddingRight", "::UIPadding") == UDim.new(0, 0), "phantom default")
sheet:SetAttribute("Inset", UDim.new(0, 18))
offset(18)
parent:RemoveTag("Padded")
offset(0)
assert(not pcall(function() parent:GetStyled("PaddingLeft", "::UIPadding") end), "missing phantom query")
parent:AddTag("Padded")
offset(18)
local physical = Instance.new("UIPadding")
physical.Parent = parent
task.wait(0.05)
assert(marker.AbsolutePosition.X - parent.AbsolutePosition.X == 18, "physical selector padding")
physical.PaddingLeft = UDim.new(0, 5)
task.wait(0.05)
assert(marker.AbsolutePosition.X - parent.AbsolutePosition.X == 5, "physical override padding")
physical:Destroy()
offset(18)
assert(added == 1 and removed == 1, "physical hierarchy events")
pad:SetProperties({PaddingLeft = UDim.new(0, 9)})
offset(9)
pad:Destroy()
offset(0)
local rule = Instance.new("StyleRule")
rule.Selector = ".Container > #Kid.Card"
rule:SetProperties({BackgroundTransparency = 0.4})
rule.Parent = sheet
local function styled(expected)
 task.wait(0.05)
 assert(math.abs(child:GetStyled("BackgroundTransparency") - expected) < 0.00001, "mutated hierarchy selector")
end
styled(0.4)
child.Name = "Other"
styled(0)
child.Name = "Kid"
styled(0.4)
child.Parent = screen
styled(0)
child.Parent = container
styled(0.4)
container:RemoveTag("Container")
styled(0)
container:AddTag("Container")
styled(0.4)
for _, entry in {{"UICorner", "CornerRadius", UDim.new(0, 11)}, {"UIStroke", "Thickness", 3}, {"UIGradient", "Rotation", 25}} do
 local modifier = Instance.new("StyleRule")
 modifier.Selector = ".Padded::" .. entry[1]
 modifier:SetProperties({[entry[2]] = entry[3]})
 modifier.Parent = sheet
 task.wait(0.05)
 assert(parent:GetStyled(entry[2], "::" .. entry[1]) == entry[3], "phantom modifier query")
 assert(#parent:GetChildren() == 1, "phantom modifier hierarchy")
 modifier:Destroy()
 task.wait(0.05)
 assert(not pcall(function() parent:GetStyled(entry[2], "::" .. entry[1]) end), "removed phantom modifier")
end
assert(added == 1 and removed == 1, "modifier queries create no physical events")
screen:Destroy()
assert(#records == 9)
return true
]==]
