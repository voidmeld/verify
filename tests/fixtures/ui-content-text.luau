--!strict

return [==[
local cases = {
 { "", "" },
 { "Hello", "Hello" },
 { "<b>Bold</b>", "Bold" },
 { "&lt;&amp;&gt;&quot;&apos;", "<&>\"'" },
 { "<uppercase>Hi</uppercase><br/>End", "Hi\nEnd" },
 { "<bad>Hi</bad>", "Hi" },
}
for _, class in { "TextLabel", "TextButton", "TextBox" } do
 local object = Instance.new(class)
 assert(object.ContentText == object.Text, class .. " default content")
 for _, rich in { false, true } do
  object.RichText = rich
  for _, row in cases do
   object.Text = row[1]
   local expected = if rich then row[2] else row[1]
   assert(object.ContentText == expected, class .. " immediate content: " .. object.ContentText)
   task.wait()
   assert(object.ContentText == expected, class .. " deferred content")
   local copy = object:Clone()
   assert(copy.ContentText == expected, class .. " cloned content")
   copy:Destroy()
  end
 end
 object.RichText = false
 assert(object.ContentText == object.Text, class .. " rich text disabled")
 object:Destroy()
end
return true
]==]
