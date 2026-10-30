--!strict
return [==[
local p = Instance.new("GetTextBoundsParams")
p.Font,p.Size,p.Width = Font.new("rbxasset://fonts/families/BuilderSans.json"),14,100000
p.Text="M"
local single=game.TextService:GetTextBoundsAsync(p)
local cases={
 {"MMMMM",{6,5,5,3,3,2}},
 {"M MMMMM",{7,6,6,4,4,3}},
 {"MMMMM M",{7,6,6,4,4,3}},
 {"MM MMM",{6,5,5,3,3,2}},
 {"MMMMM\nM",{8,6,6,4,4,3}},
}
local ratios={0.5,1,1.9,2,2.1,3}
for _,case in cases do
 for index,ratio in ratios do
  p.Text,p.Width=case[1],single.X*ratio
  local measured=game.TextService:GetTextBoundsAsync(p)
  assert(measured.Y==single.Y*case[2][index], case[1] .. " at " .. ratio .. ": " .. tostring(measured))
  if ratio>=1 then
   assert(measured.X<=p.Width, "wrapped glyphs stay within a fitting width")
  end
 end
end
p:Destroy()
return true
]==]
