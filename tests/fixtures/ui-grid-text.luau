--!strict
return [==[
local screen=Instance.new("ScreenGui")
screen.IgnoreGuiInset=true
screen.Parent=game.Players.LocalPlayer.PlayerGui
for _,automatic in {Enum.AutomaticSize.X,Enum.AutomaticSize.Y,Enum.AutomaticSize.XY} do
 local parent=Instance.new("Frame")
 parent.Size=UDim2.fromOffset(300,200)
 parent.Parent=screen
 local grid=Instance.new("UIGridLayout")
 grid.Parent=parent
 local label=Instance.new("TextLabel")
 label.Size=UDim2.fromOffset(250,0)
 label.AutomaticSize=automatic
 label.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json")
 label.TextSize=14
 label.TextWrapped=true
 label.Text="M M M M M M M M M M M M M M M M"
 label.Parent=parent
 local reference=label:Clone()
 reference.AutomaticSize=Enum.AutomaticSize.None
 reference.Parent=screen
 for _,cell in {Vector2.new(80,40),Vector2.new(120,20),Vector2.new(40,100)} do
  grid.CellSize=UDim2.fromOffset(cell.X,cell.Y)
  reference.Size=grid.CellSize
  task.wait(0.1)
  assert(label.AbsoluteSize==cell,tostring(automatic).." grid size: "..tostring(label.AbsoluteSize))
  assert(label.TextBounds==reference.TextBounds,tostring(automatic).." grid text: "..tostring(label.TextBounds).." vs "..tostring(reference.TextBounds))
  assert(label.TextFits==reference.TextFits,tostring(automatic).." grid text fit")
 end
 reference:Destroy()
 parent:Destroy()
end
screen:Destroy()
return true
]==]
