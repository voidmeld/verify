--!strict

return [==[
local virtual=... or assert(game.UserInputService:CreateVirtualInput())
local screen=Instance.new("ScreenGui")
screen.Parent=game.Players.LocalPlayer.PlayerGui
local box=Instance.new("TextBox")
box.Size,box.ClearTextOnFocus,box.Parent=UDim2.fromOffset(300,40),false,screen
box:CaptureFocus()
task.wait(.05)
for _,range in {{1,11},{11,1},{3,7},{7,3},{5,-1}} do
 for _,mode in {"text","backspace"} do
  box.Text="Alpha beta"
  box.CursorPosition,box.SelectionStart=range[1],range[2]
  if mode=="text" then virtual:SendTextInput("X")
  else virtual:SendKey(true,Enum.KeyCode.Backspace,false) end
  task.wait(.05)
  if mode=="backspace" then virtual:SendKey(false,Enum.KeyCode.Backspace,false) end
  task.wait(.05)
  local start=if range[2]>0 then math.min(range[1],range[2]) else range[1]
  local finish=if range[2]>0 then math.max(range[1],range[2]) else range[1]
  if mode=="backspace" and start==finish then start-=1 end
  local replacement=if mode=="text" then "X" else ""
  assert(box.Text==("Alpha beta"):sub(1,start-1)..replacement..("Alpha beta"):sub(finish),"selection replacement")
  assert(box.CursorPosition==start+#replacement and box.SelectionStart==-1,"selection collapses to a byte cursor")
 end
end
box:ReleaseFocus()
box.Text="aéz"
box:CaptureFocus()
task.wait(.05)
assert(box.CursorPosition==5,"capture uses byte offsets")
box.CursorPosition=4
virtual:SendTextInput("ñ")
task.wait(.05)
assert(box.Text=="aéñz" and box.CursorPosition==6,"insertion advances by bytes")
virtual:SendKey(true,Enum.KeyCode.Backspace,false)
task.wait(.05)
virtual:SendKey(false,Enum.KeyCode.Backspace,false)
task.wait(.05)
assert(box.Text=="aéz" and box.CursorPosition==4,"backspace removes a complete codepoint")
virtual:SendKey(true,Enum.KeyCode.Backspace,false)
task.wait(.05)
virtual:SendKey(false,Enum.KeyCode.Backspace,false)
task.wait(.05)
assert(box.Text=="az" and box.CursorPosition==2,"backspace preserves the next byte")
box:ReleaseFocus()
screen:Destroy()
return true
]==]
