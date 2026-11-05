--!strict

return [==[
local virtual=... or assert(game.UserInputService:CreateVirtualInput())
local input=game.UserInputService
local screen=Instance.new("ScreenGui")
screen.IgnoreGuiInset,screen.Parent=true,game.Players.LocalPlayer.PlayerGui
local box=Instance.new("TextBox")
box.Text,box.ClearTextOnFocus,box.Position,box.Size,box.Parent="",false,UDim2.fromOffset(100,150),UDim2.fromOffset(240,40),screen
local function click(x)
 local point=Vector2.new(x,170)
 virtual:SendMousePosition(point)
 virtual:SendMouseButton(point,Enum.UserInputType.MouseButton1,true,0)
 task.wait(.05)
 assert(input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1),"pressed pointer state")
 virtual:SendMouseButton(point,Enum.UserInputType.MouseButton1,false,0)
 task.wait(.05)
 assert(not input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1),"released pointer state")
end
for _,class in {"Frame","TextLabel","TextButton","ImageButton","TextBox"} do
 for _,active in {false,true} do
  local overlay=Instance.new(class)
  if class=="TextBox" then overlay.TextEditable=false end
  overlay.Position,overlay.Size,overlay.Active,overlay.Parent=box.Position,box.Size,active,screen
  task.wait(.05)
  click(110)
  local expected=if class=="TextBox" then overlay elseif class=="Frame" or class=="TextLabel" then box else nil
  assert(input:GetFocusedTextBox()==expected,class.." pointer focus barrier")
  if expected then expected:ReleaseFocus() end
  overlay:Destroy()
 end
end
box.Text,box.ClearTextOnFocus="Racer",true
click(150)
assert(box:IsFocused() and box.Text=="" and box.CursorPosition==1,"clearing focus places an empty cursor")
box.Text,box.ClearTextOnFocus="Ada",false
click(310)
assert(box.CursorPosition==4,"trailing click without padding")
box:ReleaseFocus()
box.Text,box.TextXAlignment="Ada",Enum.TextXAlignment.Left
local padding=Instance.new("UIPadding")
padding.PaddingLeft,padding.PaddingRight,padding.Parent=UDim.new(0,8),UDim.new(0,12),box
task.wait(.05)
click(310)
assert(box:IsFocused() and box.CursorPosition==4 and box.SelectionStart==-1,"pointer places a trailing byte cursor")
click(102)
assert(box.CursorPosition==1 and box.SelectionStart==-1,"an existing edit places its leading cursor")
box:ReleaseFocus()
for _,alignment in {Enum.TextXAlignment.Center,Enum.TextXAlignment.Right} do
 box.TextXAlignment=alignment
 task.wait(.05)
 click(339)
 assert(box:IsFocused() and box.CursorPosition==4 and box.SelectionStart==-1,"aligned trailing cursor")
 box:ReleaseFocus()
end
screen:Destroy()
return true
]==]
