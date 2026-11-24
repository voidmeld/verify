--!strict
return [==[
local gui=game:GetService("GuiService")
local screen=Instance.new("ScreenGui")
screen.Parent=game.Players.LocalPlayer.PlayerGui
local frame=Instance.new("Frame")
frame.Size=UDim2.fromOffset(500,500)
frame.Parent=screen
local function button(name,order,x)
 local b=Instance.new("TextButton")
 b.Name,b.SelectionOrder,b.Position,b.Size,b.Parent=name,order,UDim2.fromOffset(x,0),UDim2.fromOffset(50,50),frame
 return b
end
local first=button("First",3,0)
local second=button("Second",2,60)
local hidden=button("Hidden",-10,120)
hidden.Visible=false
local disabled=button("Disabled",-20,180)
disabled.Selectable=false
local off=button("Offscreen",-30,100000)
local empty=Instance.new("Frame")
empty.Parent=frame
local out={}
local function select(name,parent)
 local ok,err=pcall(function()gui:Select(parent)end)
 out[name]={ok=ok,selected=gui.SelectedObject and gui.SelectedObject.Name or "nil",error=if ok then nil else tostring(err)}
end
task.wait(0.1)
select("ordered",frame)
select("empty",empty)
select("leaf",first)
select("outside",workspace)
gui.SelectedObject=nil
select("none",empty)
local inactive=button("Inactive",-40,240)
inactive.Active=false
task.wait(0.1)
select("inactive",frame)
local noninteractable=button("Noninteractable",-50,300)
noninteractable.Interactable=false
task.wait(0.1)
select("noninteractable",frame)
gui.SelectedObject=nil
screen:Destroy()
assert(out.ordered.selected == "Second")
assert(out.empty.selected == "Second" and out.leaf.selected == "Second")
assert(not out.outside.ok and out.outside.selected == "Second")
assert(out.none.selected == "nil")
assert(out.inactive.selected == "Inactive" and out.noninteractable.selected == "Inactive")
return true
]==]
