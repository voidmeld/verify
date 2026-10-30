--!strict

return [==[
local screen=Instance.new("ScreenGui")
screen.IgnoreGuiInset,screen.Parent=true,game.Players.LocalPlayer.PlayerGui
for _,scale in {0.5,1,2} do
 for _,direction in {"X","Y","XY"} do
  for _,enabled in {false,true} do
   local scroll=Instance.new("ScrollingFrame")
   scroll.BorderSizePixel,scroll.ScrollBarThickness=0,0
   scroll.Position,scroll.Size=UDim2.fromOffset(100,100),UDim2.fromOffset(240,160)
   scroll.CanvasSize,scroll.ScrollingDirection=UDim2.fromOffset(1000,1000),Enum.ScrollingDirection[direction]
   scroll.ScrollingEnabled,scroll.Parent=enabled,screen
   local scaler=Instance.new("UIScale")
   scaler.Scale,scaler.Parent=scale,scroll
   local button=Instance.new("TextButton")
   button.Text,button.Size="",UDim2.fromOffset(80,30)
   button.Position,button.Parent=UDim2.fromOffset(400,500),scroll
   task.wait(0.1)
   local before=button.AbsolutePosition
   game.GuiService.SelectedObject=button
   local expected=if enabled then Vector2.new(240,370)*scale else Vector2.zero
   assert(scroll.CanvasPosition==expected,"immediate selection scroll: "..tostring(scroll.CanvasPosition))
   task.wait(0.1)
   assert((before-button.AbsolutePosition-expected).Magnitude<0.75,"canvas offsets use screen pixels")
   game.GuiService.SelectedObject=nil
   button.Position=UDim2.fromOffset(0,0)
   task.wait(0.1)
   game.GuiService.SelectedObject=button
   assert(scroll.CanvasPosition==Vector2.zero,"return selection to scroll origin")
   game.GuiService.SelectedObject=nil
   scroll:Destroy()
  end
 end
end
local scroll=Instance.new("ScrollingFrame")
scroll.BorderSizePixel,scroll.ScrollBarThickness=0,0
scroll.Size,scroll.CanvasSize=UDim2.fromOffset(240,160),UDim2.fromOffset(2000,2000)
scroll.Parent=screen
local oversized=Instance.new("TextButton")
oversized.Text,oversized.Size="",UDim2.fromOffset(300,300)
oversized.Position,oversized.Parent=UDim2.fromOffset(800,800),scroll
task.wait(0.1)
for _,expected in {Vector2.new(300,300),Vector2.new(600,600),Vector2.new(600,900)} do
 game.GuiService.SelectedObject=oversized
 assert(scroll.CanvasPosition==expected,"oversized selection scrolls by its own extent")
 game.GuiService.SelectedObject=nil
 task.wait(0.1)
end
scroll:Destroy()
for _,outerEnabled in {false,true} do
 for _,innerEnabled in {false,true} do
  local outer=Instance.new("ScrollingFrame")
  outer.BorderSizePixel,outer.ScrollBarThickness=0,0
  outer.Size,outer.CanvasSize=UDim2.fromOffset(200,150),UDim2.fromOffset(800,800)
  outer.ScrollingEnabled,outer.Parent=outerEnabled,screen
  local inner=Instance.new("ScrollingFrame")
  inner.BorderSizePixel,inner.ScrollBarThickness=0,0
  inner.Size,inner.CanvasSize=UDim2.fromOffset(180,120),UDim2.fromOffset(600,600)
  inner.Position=UDim2.fromOffset(400,300)
  inner.ScrollingEnabled,inner.Parent=innerEnabled,outer
  local button=Instance.new("TextButton")
  button.Text,button.Size="",UDim2.fromOffset(40,30)
  button.Position,button.Parent=UDim2.fromOffset(500,400),inner
  task.wait(0.1)
  game.GuiService.SelectedObject=button
  assert(inner.CanvasPosition==(if innerEnabled then Vector2.new(360,310) else Vector2.zero),"inner selection scroll")
  assert(outer.CanvasPosition==(if outerEnabled then Vector2.new(600,580) else Vector2.zero),"outer uses the selection geometry before scrolling")
  game.GuiService.SelectedObject=nil
  outer:Destroy()
 end
end
screen:Destroy()
return true
]==]
