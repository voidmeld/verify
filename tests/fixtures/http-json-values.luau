--!strict
return [==[
local http=game:GetService("HttpService")
local object=Instance.new("Folder")
local values={
 Color3.new(1,0.5,0),Vector2.new(1,2),Vector3.new(1,2,3),CFrame.new(1,2,3),
 UDim.new(0.5,4),UDim2.fromOffset(2,3),Enum.Font.BuilderSans,Enum.Font,Enum,
 ColorSequence.new(Color3.new(1,0,0),Color3.new(0,0,1)),NumberSequence.new(0.1,0.3),
 NumberRange.new(1,4),BrickColor.new("Bright red"),Rect.new(1,2,3,4),
 Ray.new(Vector3.zero,Vector3.one),object,function() end,coroutine.create(function() end)
}
for _,value in values do
 assert(http:JSONEncode(value)=="null","direct "..typeof(value))
 assert(http:JSONEncode({value,7})=="[null,7]","array "..typeof(value))
 local encoded=http:JSONEncode({value=value,other=7})
 assert(encoded:find('"value":null',1,true),"object "..typeof(value)..": "..encoded)
 assert(http:JSONDecode(encoded).other==7)
end
object:Destroy()
assert(http:JSONEncode(nil)=="null")
assert(http:JSONEncode({})=="[]")
assert(http:JSONEncode({[1]="a",[3]="c"})=='["a"]')
assert(http:JSONEncode({nil,7})=='[null,7]')
assert(http:JSONEncode({"a",nil,"c"})=='["a",null,"c"]')
assert(http:JSONEncode({[1]="a",name="ignored"})=='["a"]')
assert(http:JSONEncode({[2]="b"})=='{"2":"b"}')
assert(http:JSONEncode({[0]="zero"})=='{"0":"zero"}')
assert(http:JSONEncode({[-1]="minus"})=='{"-1":"minus"}')
assert(http:JSONEncode({[1.5]="half"})=='{"1":"half"}')
local shared={1,2}
assert(http:JSONEncode({shared,shared})=="[[1,2],[1,2]]")
local cyclic={};cyclic.self=cyclic
assert(not pcall(http.JSONEncode,http,cyclic))
assert(not pcall(http.JSONEncode,http,{[true]="yes"}))
assert(http:JSONEncode(setmetatable({a=1},{__index={b=2}}))=='{"a":1}')
local function rejectMeta() error("JSON encoding called a table metamethod") end
assert(http:JSONEncode(setmetatable({1,nil,3},{__len=rejectMeta,__index=rejectMeta,__iter=rejectMeta}))=='[1,null,3]')
local escaped='quote" backslash\\ newline\n'
assert(http:JSONDecode(http:JSONEncode({escaped}))[1]==escaped)
return true
]==]
