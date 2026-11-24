--!strict
return [==[
local p = Instance.new("GetTextBoundsParams")
local function unwrapped(text)
 p.Text,p.Width=text,0
 return game.TextService:GetTextBoundsAsync(p)
end
local function advances(text)
 local widths,previous,prefix={},0,""
 for _,codepoint in utf8.codes(text) do
  prefix ..= utf8.char(codepoint)
  local current=unwrapped(prefix).X
  table.insert(widths,current-previous)
  previous=current
 end
 return widths
end
local function expected(widths,limit)
 local line,maximum,count=0,0,1
 for _,advance in widths do
  if line+advance>limit and (line>0 or count==1) then
   maximum=math.max(maximum,line)
   line,count=0,count+1
  end
  line+=advance
 end
 return math.max(maximum,line),count
end
local function wrapped(text,limit)
 p.Text,p.Width=text,limit
 return game.TextService:GetTextBoundsAsync(p)
end
for _,family in {"BuilderSans","Nunito","SourceSansPro","LegacyArial"} do
 p.Font=Font.new("rbxasset://fonts/families/" .. family .. ".json")
 for _,size in {7,14,18,24,42} do
  p.Size=size
  local single=unwrapped("M")
  for _,text in {"MMMMM","iiiii","WWWWW"} do
   local natural=unwrapped(text)
   local widths=advances(text)
   local maximum=math.max(table.unpack(widths))
   local previousHeight=math.huge
   for _,ratio in {0.5,1,1.01,1.9,2,2.1,3} do
    local limit=single.X*ratio
    local measured=wrapped(text,limit)
    local tag=family .. "/" .. size .. "/" .. text .. "/" .. ratio .. ": " .. tostring(measured)
    if text=="MMMMM" then
     local width,lines=natural.X,1
     if width>limit then width,lines=expected(widths,limit) end
     assert(math.abs(measured.X-width)<0.001,"wrapped width retains rounded run advances " .. tag)
     assert(math.abs(measured.Y-single.Y*lines)<0.001,"wrapped height retains rounded run advances " .. tag)
    end
    assert(measured.X<=math.max(limit,maximum)+0.001,"wrapped glyphs stay within the constraint or one rounded run advance " .. tag)
    local count=measured.Y/single.Y
    assert(math.abs(count-math.round(count))<0.001,"wrapping keeps whole lines " .. tag)
    assert(measured.Y<=previousHeight+0.001,"a wider constraint never adds lines " .. tag)
    previousHeight=measured.Y
   end
  end
 end
end
p.Font,p.Size = Font.new("rbxasset://fonts/families/BuilderSans.json"),14
local single=unwrapped("M")
for _,text in {"MMMMM","M MMMMM","MMMMM M","MM MMM","MMMMM\nM"} do
 local maximum=0
 for _,paragraph in string.split(text,"\n") do
  local prefix,previous="",0
  for character,spaces in paragraph:gmatch("([^ ])( *)") do
   prefix ..= character .. spaces
   local current=unwrapped(prefix).X
   maximum=math.max(maximum,current-previous)
   previous=current
  end
 end
 for _,ratio in {0.5,1,1.9,2,2.1,3} do
  local limit=single.X*ratio
  local measured=wrapped(text,limit)
  assert(measured.X<=math.max(limit,maximum)+0.001,"wrapped fragments keep the constraint or one rounded glyph with its spaces")
  local paragraphs=#string.split(text,"\n")
  local count=measured.Y/single.Y
  assert(math.abs(count-math.round(count))<0.001,"word and paragraph wrapping keeps whole lines")
  assert(count>=paragraphs and count<=(utf8.len(text) or 0)+paragraphs,"wrapping retains whole glyphs and paragraph struts")
  if text:find("\n",1,true) then
   local height,width=0,0
   for _,paragraph in string.split(text,"\n") do
    local bounds=wrapped(paragraph,limit)
    height,width=height+bounds.Y,math.max(width,bounds.X)
   end
   assert(measured.Y==height and measured.X==width,"paragraph breaks preserve independent wrapped bounds")
  end
 end
end
p:Destroy()
return true
]==]
