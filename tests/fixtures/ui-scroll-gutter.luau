--!strict
return [==[
local screen=Instance.new("ScreenGui")
screen.Parent=game.Players.LocalPlayer.PlayerGui
for _,scale in {0.5,1,2} do
 for _,border in {0,1,3} do
  for _,thickness in {0,4,12} do
   for _,mode in {Enum.BorderMode.Outline,Enum.BorderMode.Middle,Enum.BorderMode.Inset} do
    local frame=Instance.new("ScrollingFrame")
    frame.Size=UDim2.fromOffset(240,200)
    frame.CanvasSize=UDim2.fromOffset(600,600)
    frame.BorderSizePixel=border
    frame.BorderMode=mode
    frame.ScrollBarThickness=thickness
    frame.VerticalScrollBarInset=Enum.ScrollBarInset.Always
    frame.HorizontalScrollBarInset=Enum.ScrollBarInset.Always
    local scaler=Instance.new("UIScale")
    scaler.Scale,scaler.Parent=scale,frame
    frame.Parent=screen
    game.RunService.RenderStepped:Wait()
    game.RunService.RenderStepped:Wait()
    local gutter=(border+thickness)*scale
    local wanted=Vector2.new(240*scale-gutter,200*scale-gutter)
    assert(frame.AbsoluteWindowSize==wanted,"scroll gutter "..scale.."/"..border.."/"..thickness.."/"..mode.Name..": "..tostring(frame.AbsoluteWindowSize))
    frame:Destroy()
   end
  end
 end
end
screen:Destroy()
return true
]==]
