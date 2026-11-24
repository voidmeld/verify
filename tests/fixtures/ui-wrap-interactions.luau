--!strict

return [==[
local screen=Instance.new("ScreenGui")
screen.IgnoreGuiInset,screen.Parent=true,game.Players.LocalPlayer.PlayerGui
local function near(actual,expected,label) assert(math.abs(actual-expected)<0.001,label .. ': ' .. actual .. ' expected ' .. expected) end
local observations=game.HttpService:JSONDecode([=[[{"direction":"Horizontal","scenario":"scaled","scale":0.5,"cells":[[1,0,0,30,5],[2,38.5,0,40,15],[3,0,22.5,20,10],[4,28.5,22.5,50,7.5],[5,0,40,15,12.5]],"content":[78.5,52.5],"size":[90,70]},{"direction":"Horizontal","scenario":"scaled","scale":1,"cells":[[1,0,0,60,10],[2,77,0,80,30],[3,0,45,40,20],[4,57,45,100,15],[5,0,80,30,25]],"content":[157,105],"size":[180,140]},{"direction":"Horizontal","scenario":"scaled","scale":2,"cells":[[1,0,0,120,20],[2,154,0,160,60],[3,0,90,80,40],[4,114,90,200,30],[5,0,160,60,50]],"content":[314,210],"size":[360,280]},{"direction":"Horizontal","scenario":"padded","scale":0.5,"cells":[[1,2.5,1.5,30,5],[2,36.5,1.5,40,15],[3,2.5,20.5,20,10],[4,26.5,20.5,50,7.5],[5,2.5,34.5,15,12.5]],"content":[74,45.5],"size":[90,70]},{"direction":"Horizontal","scenario":"padded","scale":1,"cells":[[1,5,3,60,10],[2,73,3,80,30],[3,5,41,40,20],[4,53,41,100,15],[5,5,69,30,25]],"content":[148,91],"size":[180,140]},{"direction":"Horizontal","scenario":"padded","scale":2,"cells":[[1,10,6,120,20],[2,146,6,160,60],[3,10,82,80,40],[4,106,82,200,30],[5,10,138,60,50]],"content":[296,182],"size":[360,280]},{"direction":"Horizontal","scenario":"overflow","scale":0.5,"cells":[[1,0,0,110,5],[2,0,9,40,15],[3,44,9,20,10],[4,0,28,50,7.5],[5,54,28,15,12.5]],"content":[110,40.5],"size":[90,70]},{"direction":"Horizontal","scenario":"overflow","scale":1,"cells":[[1,0,0,220,10],[2,0,18,80,30],[3,88,18,40,20],[4,0,56,100,15],[5,108,56,30,25]],"content":[220,81],"size":[180,140]},{"direction":"Horizontal","scenario":"overflow","scale":2,"cells":[[1,0,0,440,20],[2,0,36,160,60],[3,176,36,80,40],[4,0,112,200,30],[5,216,112,60,50]],"content":[440,162],"size":[360,280]},{"direction":"Horizontal","scenario":"empty","scale":0.5,"cells":[],"content":[0,0],"size":[90,70]},{"direction":"Horizontal","scenario":"empty","scale":1,"cells":[],"content":[0,0],"size":[180,140]},{"direction":"Horizontal","scenario":"empty","scale":2,"cells":[],"content":[0,0],"size":[360,280]},{"direction":"Horizontal","scenario":"hidden","scale":0.5,"cells":[[1,0,0,30,5],[3,34,0,20,10],[4,0,14,50,7.5],[5,54,14,15,12.5]],"content":[69,26.5],"size":[90,70]},{"direction":"Horizontal","scenario":"hidden","scale":1,"cells":[[1,0,0,60,10],[3,68,0,40,20],[4,0,28,100,15],[5,108,28,30,25]],"content":[138,53],"size":[180,140]},{"direction":"Horizontal","scenario":"hidden","scale":2,"cells":[[1,0,0,120,20],[3,136,0,80,40],[4,0,56,200,30],[5,216,56,60,50]],"content":[276,106],"size":[360,280]},{"direction":"Horizontal","scenario":"flex","scale":0.5,"cells":[[1,0,18.166667938232423,30,5],[2,34,0,56,23.166667938232423],[3,0,27.16666603088379,20,18.166667938232423],[4,24,27.16666603088379,66,18.166667938232423],[5,0,49.333335876464847,15,20.666667938232423]],"content":[90,70],"size":[90,70]},{"direction":"Horizontal","scenario":"flex","scale":1,"cells":[[1,0,36.333335876464847,60,10],[2,68,0,112,46.333335876464847],[3,0,54.33333206176758,40,36.333335876464847],[4,48,54.33333206176758,132,36.333335876464847],[5,0,98.66667175292969,30,41.333335876464847]],"content":[180,140],"size":[180,140]},{"direction":"Horizontal","scenario":"flex","scale":2,"cells":[[1,0,72.66667175292969,120,20],[2,136,0,224,92.66667175292969],[3,0,108.66666412353516,80,72.66667175292969],[4,96,108.66666412353516,264,72.66667175292969],[5,0,197.33334350585938,60,82.66667175292969]],"content":[360,280],"size":[360,280]},{"direction":"Horizontal","scenario":"limits","scale":0.5,"cells":[[1,0,0,42.5,10],[2,46.5,0,42.5,10],[3,0,37,22.25,10],[4,26.25,37,42.5,10],[5,72.75,37,17.25,10]],"content":[90,70],"size":[90,70]},{"direction":"Horizontal","scenario":"limits","scale":1,"cells":[[1,0,0,85,20],[2,93,0,85,20],[3,0,74,44.5,20],[4,52.5,74,85,20],[5,145.5,74,34.5,20]],"content":[180,140],"size":[180,140]},{"direction":"Horizontal","scenario":"limits","scale":2,"cells":[[1,0,0,170,40],[2,186,0,170,40],[3,0,148,89,40],[4,105,148,170,40],[5,291,148,69,40]],"content":[360,280],"size":[360,280]},{"direction":"Horizontal","scenario":"automatic","scale":0.5,"cells":[[1,0,0,30,5],[2,34,0,40,15],[3,0,19,20,10],[4,24,19,50,7.5],[5,0,33,15,12.5]],"content":[74,45.5],"size":[90,45.5]},{"direction":"Horizontal","scenario":"automatic","scale":1,"cells":[[1,0,0,60,10],[2,68,0,80,30],[3,0,38,40,20],[4,48,38,100,15],[5,0,66,30,25]],"content":[148,91],"size":[180,91]},{"direction":"Horizontal","scenario":"automatic","scale":2,"cells":[[1,0,0,120,20],[2,136,0,160,60],[3,0,76,80,40],[4,96,76,200,30],[5,0,132,60,50]],"content":[296,182],"size":[360,182]},{"direction":"Horizontal","scenario":"automatic-main","scale":0.5,"cells":[[1,0,0,30,5],[2,34,0,40,15],[3,78,0,20,10],[4,102,0,50,7.5],[5,156,0,15,12.5]],"content":[171,15],"size":[171,70]},{"direction":"Horizontal","scenario":"automatic-main","scale":1,"cells":[[1,0,0,60,10],[2,68,0,80,30],[3,156,0,40,20],[4,204,0,100,15],[5,312,0,30,25]],"content":[342,30],"size":[342,140]},{"direction":"Horizontal","scenario":"automatic-main","scale":2,"cells":[[1,0,0,120,20],[2,136,0,160,60],[3,312,0,80,40],[4,408,0,200,30],[5,624,0,60,50]],"content":[684,60],"size":[684,280]},{"direction":"Vertical","scenario":"scaled","scale":0.5,"cells":[[1,0,0,5,30],[2,0,38.5,15,40],[3,22.5,0,10,20],[4,22.5,28.5,7.5,50],[5,40,0,12.5,15]],"content":[52.5,78.5],"size":[70,90]},{"direction":"Vertical","scenario":"scaled","scale":1,"cells":[[1,0,0,10,60],[2,0,77,30,80],[3,45,0,20,40],[4,45,57,15,100],[5,80,0,25,30]],"content":[105,157],"size":[140,180]},{"direction":"Vertical","scenario":"scaled","scale":2,"cells":[[1,0,0,20,120],[2,0,154,60,160],[3,90,0,40,80],[4,90,114,30,200],[5,160,0,50,60]],"content":[210,314],"size":[280,360]},{"direction":"Vertical","scenario":"padded","scale":0.5,"cells":[[1,2.5,1.5,5,30],[2,2.5,35.5,15,40],[3,21.5,1.5,10,20],[4,21.5,25.5,7.5,50],[5,35.5,1.5,12.5,15]],"content":[45.5,74],"size":[70,90]},{"direction":"Vertical","scenario":"padded","scale":1,"cells":[[1,5,3,10,60],[2,5,71,30,80],[3,43,3,20,40],[4,43,51,15,100],[5,71,3,25,30]],"content":[91,148],"size":[140,180]},{"direction":"Vertical","scenario":"padded","scale":2,"cells":[[1,10,6,20,120],[2,10,142,60,160],[3,86,6,40,80],[4,86,102,30,200],[5,142,6,50,60]],"content":[182,296],"size":[280,360]},{"direction":"Vertical","scenario":"overflow","scale":0.5,"cells":[[1,0,0,5,110],[2,9,0,15,40],[3,9,44,10,20],[4,28,0,7.5,50],[5,28,54,12.5,15]],"content":[40.5,110],"size":[70,90]},{"direction":"Vertical","scenario":"overflow","scale":1,"cells":[[1,0,0,10,220],[2,18,0,30,80],[3,18,88,20,40],[4,56,0,15,100],[5,56,108,25,30]],"content":[81,220],"size":[140,180]},{"direction":"Vertical","scenario":"overflow","scale":2,"cells":[[1,0,0,20,440],[2,36,0,60,160],[3,36,176,40,80],[4,112,0,30,200],[5,112,216,50,60]],"content":[162,440],"size":[280,360]},{"direction":"Vertical","scenario":"empty","scale":0.5,"cells":[],"content":[0,0],"size":[70,90]},{"direction":"Vertical","scenario":"empty","scale":1,"cells":[],"content":[0,0],"size":[140,180]},{"direction":"Vertical","scenario":"empty","scale":2,"cells":[],"content":[0,0],"size":[280,360]},{"direction":"Vertical","scenario":"hidden","scale":0.5,"cells":[[1,0,0,5,30],[3,0,34,10,20],[4,14,0,7.5,50],[5,14,54,12.5,15]],"content":[26.5,69],"size":[70,90]},{"direction":"Vertical","scenario":"hidden","scale":1,"cells":[[1,0,0,10,60],[3,0,68,20,40],[4,28,0,15,100],[5,28,108,25,30]],"content":[53,138],"size":[140,180]},{"direction":"Vertical","scenario":"hidden","scale":2,"cells":[[1,0,0,20,120],[3,0,136,40,80],[4,56,0,30,200],[5,56,216,50,60]],"content":[106,276],"size":[280,360]},{"direction":"Vertical","scenario":"flex","scale":0.5,"cells":[[1,18.166667938232423,0,5,30],[2,0,34,23.166667938232423,56],[3,27.16666603088379,0,18.166667938232423,20],[4,27.16666603088379,24,18.166667938232423,66],[5,49.333335876464847,0,20.666667938232423,15]],"content":[70,90],"size":[70,90]},{"direction":"Vertical","scenario":"flex","scale":1,"cells":[[1,36.333335876464847,0,10,60],[2,0,68,46.333335876464847,112],[3,54.33333206176758,0,36.333335876464847,40],[4,54.33333206176758,48,36.333335876464847,132],[5,98.66667175292969,0,41.333335876464847,30]],"content":[140,180],"size":[140,180]},{"direction":"Vertical","scenario":"flex","scale":2,"cells":[[1,72.66667175292969,0,20,120],[2,0,136,92.66667175292969,224],[3,108.66666412353516,0,72.66667175292969,80],[4,108.66666412353516,96,72.66667175292969,264],[5,197.33334350585938,0,82.66667175292969,60]],"content":[280,360],"size":[280,360]},{"direction":"Vertical","scenario":"limits","scale":0.5,"cells":[[1,0,0,10,42.5],[2,0,46.5,10,42.5],[3,37,0,10,22.25],[4,37,26.25,10,42.5],[5,37,72.75,10,17.25]],"content":[70,90],"size":[70,90]},{"direction":"Vertical","scenario":"limits","scale":1,"cells":[[1,0,0,20,85],[2,0,93,20,85],[3,74,0,20,44.5],[4,74,52.5,20,85],[5,74,145.5,20,34.5]],"content":[140,180],"size":[140,180]},{"direction":"Vertical","scenario":"limits","scale":2,"cells":[[1,0,0,40,170],[2,0,186,40,170],[3,148,0,40,89],[4,148,105,40,170],[5,148,291,40,69]],"content":[280,360],"size":[280,360]},{"direction":"Vertical","scenario":"automatic","scale":0.5,"cells":[[1,0,0,5,30],[2,0,34,15,40],[3,19,0,10,20],[4,19,24,7.5,50],[5,33,0,12.5,15]],"content":[45.5,74],"size":[45.5,90]},{"direction":"Vertical","scenario":"automatic","scale":1,"cells":[[1,0,0,10,60],[2,0,68,30,80],[3,38,0,20,40],[4,38,48,15,100],[5,66,0,25,30]],"content":[91,148],"size":[91,180]},{"direction":"Vertical","scenario":"automatic","scale":2,"cells":[[1,0,0,20,120],[2,0,136,60,160],[3,76,0,40,80],[4,76,96,30,200],[5,132,0,50,60]],"content":[182,296],"size":[182,360]},{"direction":"Vertical","scenario":"automatic-main","scale":0.5,"cells":[[1,0,0,5,30],[2,0,34,15,40],[3,0,78,10,20],[4,0,102,7.5,50],[5,0,156,12.5,15]],"content":[15,171],"size":[70,171]},{"direction":"Vertical","scenario":"automatic-main","scale":1,"cells":[[1,0,0,10,60],[2,0,68,30,80],[3,0,156,20,40],[4,0,204,15,100],[5,0,312,25,30]],"content":[30,342],"size":[140,342]},{"direction":"Vertical","scenario":"automatic-main","scale":2,"cells":[[1,0,0,20,120],[2,0,136,60,160],[3,0,312,40,80],[4,0,408,30,200],[5,0,624,50,60]],"content":[60,684],"size":[280,684]}]]=])
local observationIndex=0
for _,direction in {"Horizontal","Vertical"} do
 for _,scenario in {"scaled","padded","overflow","empty","hidden","flex","limits","automatic","automatic-main"} do
  for _,scale in {0.5,1,2} do
   local horizontal=direction=="Horizontal"
   local parent=Instance.new("Frame")
   parent.Size,parent.Parent=UDim2.fromOffset(if horizontal then 180 else 140,if horizontal then 140 else 180),screen
   if scenario=="automatic" then
    parent.Size=UDim2.fromOffset(if horizontal then 180 else 0,if horizontal then 0 else 180)
    parent.AutomaticSize=if horizontal then Enum.AutomaticSize.Y else Enum.AutomaticSize.X
   elseif scenario=="automatic-main" then
    parent.Size=UDim2.fromOffset(if horizontal then 0 else 140,if horizontal then 140 else 0)
    parent.AutomaticSize=if horizontal then Enum.AutomaticSize.X else Enum.AutomaticSize.Y
   end
   local scaler=Instance.new("UIScale")
   scaler.Scale,scaler.Parent=scale,parent
   if scenario=="padded" then
    local pad=Instance.new("UIPadding")
    pad.PaddingLeft,pad.PaddingRight,pad.PaddingTop,pad.PaddingBottom=UDim.new(0,5),UDim.new(0,7),UDim.new(0,3),UDim.new(0,9)
    pad.Parent=parent
   end
   local list=Instance.new("UIListLayout")
   list.FillDirection,list.Wraps,list.Padding,list.SortOrder=Enum.FillDirection[direction],true,UDim.new(if scenario=="scaled" then 0.05 else 0,8),Enum.SortOrder.LayoutOrder
   if scenario=="flex" or scenario=="limits" then list.HorizontalFlex,list.VerticalFlex=Enum.UIFlexAlignment.Fill,Enum.UIFlexAlignment.Fill end
   list.Parent=parent
   local cells={}
   if scenario~="empty" then
    for index,shape in {{60,10},{80,30},{40,20},{100,15},{30,25}} do
     local cell=Instance.new("Frame")
     local main=if scenario=="overflow" and index==1 then 220 else shape[1]
     cell.Size=UDim2.fromOffset(if horizontal then main else shape[2],if horizontal then shape[2] else main)
     cell.LayoutOrder,cell.Parent=index,parent
     if scenario=="hidden" and index==2 then cell.Visible=false end
     if scenario=="flex" then
      local flex=Instance.new("UIFlexItem")
      flex.FlexMode=Enum.UIFlexMode[if index%2==0 then "Grow" else "None"]
      flex.ItemLineAlignment=Enum.ItemLineAlignment[if index==1 then "End" else "Automatic"]
      flex.Parent=cell
     elseif scenario=="limits" then
      local bound=Instance.new("UISizeConstraint")
      bound.MaxSize=Vector2.new(if horizontal then 85 else 20,if horizontal then 20 else 85)
      bound.Parent=cell
     end
     table.insert(cells,cell)
    end
   end
   task.wait(0.02)
   local bounds={}
   for index,cell in cells do
    if cell.Visible then local at=cell.AbsolutePosition-parent.AbsolutePosition;table.insert(bounds,{index,at.X,at.Y,cell.AbsoluteSize.X,cell.AbsoluteSize.Y}) end
   end
   observationIndex += 1
local expected=observations[observationIndex]
for cellIndex,actual in bounds do for axis=1,5 do near(actual[axis],expected.cells[cellIndex][axis],"wrap interaction " .. observationIndex .. "/" .. cellIndex .. "/" .. axis) end end
near(parent.AbsoluteSize.X,expected.size[1],"wrap parent width " .. observationIndex)
near(parent.AbsoluteSize.Y,expected.size[2],"wrap parent height " .. observationIndex)
near(list.AbsoluteContentSize.X,expected.content[1],"wrap content width " .. observationIndex)
near(list.AbsoluteContentSize.Y,expected.content[2],"wrap content height " .. observationIndex)
   parent:Destroy()
  end
 end
end

screen:Destroy()
return true
]==]
