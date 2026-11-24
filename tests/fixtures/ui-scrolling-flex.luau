--!strict

return [==[
local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local g = Instance.new("ScreenGui"); g.Parent = pg
local out = {}
local function case(name, class, pad, flex, kids)
	local root = Instance.new("Frame"); root.Size = UDim2.fromOffset(400, 300); root.Parent = g
	local s = Instance.new(class); s.Size = UDim2.fromOffset(0, 50); s.AutomaticSize = Enum.AutomaticSize.X
	if class == "ScrollingFrame" then s.CanvasSize = UDim2.new() end
	local u = Instance.new("UIPadding"); u.PaddingLeft = UDim.new(0, pad); u.PaddingRight = UDim.new(0, pad); u.PaddingTop = UDim.new(0, pad); u.Parent = s
	local l = Instance.new("UIListLayout"); l.FillDirection = Enum.FillDirection.Horizontal; l.Padding = UDim.new(0, 4); l.HorizontalFlex = Enum.UIFlexAlignment[flex]; l.Parent = s
	local made = {}
	for i, k in kids do
		local f = Instance.new("Frame"); f.Size = UDim2.fromOffset(k, 20); f.LayoutOrder = i
		local fi = Instance.new("UIFlexItem"); fi.FlexMode = Enum.UIFlexMode.Grow; fi.Parent = f
		f.Parent = s; made[i] = f
	end
	s.Parent = root
	task.wait(); task.wait()
	local got = {}
	for _, f in made do table.insert(got, `{f.AbsoluteSize.X}@{f.AbsolutePosition.X - s.AbsolutePosition.X}`) end
	table.insert(out, `{name}: abs={s.AbsoluteSize.X} kids=` .. table.concat(got, " "))
	root:Destroy()
end
case("SF pad3 fill", "ScrollingFrame", 3, "Fill", {69, 74})
case("SF pad3 none", "ScrollingFrame", 3, "None", {69, 74})
case("Frame pad3 fill", "Frame", 3, "Fill", {69, 74})
case("SF pad0 fill", "ScrollingFrame", 0, "Fill", {69, 74})
case("SF pad10 fill", "ScrollingFrame", 10, "Fill", {69, 74})
g:Destroy()
local want = [[
SF pad3 fill: abs=153 kids=72@3 77@79
SF pad3 none: abs=153 kids=72@3 77@79
Frame pad3 fill: abs=153 kids=69@3 74@76
SF pad0 fill: abs=147 kids=69@0 74@73
SF pad10 fill: abs=167 kids=79@10 84@93
]]
local got = table.concat(out, "\n") .. "\n"
assert(got == want, got)
local screen=Instance.new("ScreenGui")
screen.Parent=game.Players.LocalPlayer.PlayerGui
for _,horizontal in {true,false} do
 for _,canvas in {0,200,600} do
  for _,thickness in {0,12} do
   local frame=Instance.new("ScrollingFrame")
   frame.Size,frame.CanvasSize=UDim2.fromOffset(400,400),UDim2.fromOffset(canvas,canvas)
   frame.BorderSizePixel,frame.ScrollBarThickness=0,thickness
   frame.VerticalScrollBarInset,frame.HorizontalScrollBarInset=Enum.ScrollBarInset.Always,Enum.ScrollBarInset.Always
   frame.Parent=screen
   local padding=Instance.new("UIPadding")
   padding.PaddingLeft,padding.PaddingRight,padding.PaddingTop,padding.PaddingBottom,padding.Parent=UDim.new(0,3),UDim.new(0,7),UDim.new(0,5),UDim.new(0,9),frame
   local list=Instance.new("UIListLayout")
   list.FillDirection=if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
   list[if horizontal then "HorizontalFlex" else "VerticalFlex"]=Enum.UIFlexAlignment.Fill
   list.Parent=frame
   local children={}
   for index=1,3 do
    local child=Instance.new("Frame")
    child.Size,child.LayoutOrder,child.Parent=UDim2.fromOffset(20,20),index,frame
    local item=Instance.new("UIFlexItem")
    item.FlexMode,item.Parent=Enum.UIFlexMode.Grow,child
    table.insert(children,child)
   end
   task.wait(.05)
   local extent=math.max(canvas,400-thickness)-(if horizontal then 10 else 14)
   local first=if horizontal then 3 else 5
   for index,child in children do
    local position=child.AbsolutePosition-frame.AbsolutePosition
    local size=child.AbsoluteSize
    assert(math.abs((if horizontal then position.X else position.Y)-(first+(index-1)*extent/3))<.001,"padded scrolling flex position")
    assert(math.abs((if horizontal then size.X else size.Y)-extent/3)<.001,"padded scrolling flex size")
   end
   assert(math.abs((if horizontal then list.AbsoluteContentSize.X else list.AbsoluteContentSize.Y)-extent)<.001,"padded scrolling content")
   local window=if canvas==600 then 400-thickness else 400
   assert(frame.AbsoluteWindowSize==Vector2.new(window,window),"scrolling window follows its gutters")
   frame:Destroy()
  end
 end
end
screen:Destroy()
return true
]==]
