--!strict

return [==[
 local function near(actual, expected, label)
  assert(math.abs(actual.X-expected[1]) < 0.001 and math.abs(actual.Y-expected[2]) < 0.001, label .. ": " .. tostring(actual))
 end
 local params = Instance.new("GetTextBoundsParams")
 params.Font, params.Size = Font.new("rbxasset://fonts/families/LegacyArial.json"), 14
 params.Text = "A"
 game.TextService:GetTextBoundsAsync(params)
 local screen = Instance.new("ScreenGui")
 screen.IgnoreGuiInset, screen.Parent = true, game.Players.LocalPlayer.PlayerGui
 local expected = game.HttpService:JSONDecode([=[[{"bounds":[0,10],"lineHeight":1,"api":[0,21],"scale":0.5,"text":"","size":[50,10]},{"bounds":[46,10],"lineHeight":1,"api":[96,21],"scale":0.5,"text":"Hello world","size":[50,10]},{"bounds":[37,120],"lineHeight":1,"api":[80,252],"scale":0.5,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[50,120]},{"bounds":[22,20],"lineHeight":1,"api":[47,42],"scale":0.5,"text":"Hello\nworld","size":[50,20]},{"bounds":[0,10],"lineHeight":1.2,"api":[0,21],"scale":0.5,"text":"","size":[50,10]},{"bounds":[46,10],"lineHeight":1.2,"api":[96,21],"scale":0.5,"text":"Hello world","size":[50,10]},{"bounds":[37,142],"lineHeight":1.2,"api":[80,252],"scale":0.5,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[50,142]},{"bounds":[22,22],"lineHeight":1.2,"api":[47,42],"scale":0.5,"text":"Hello\nworld","size":[50,22]},{"bounds":[0,10],"lineHeight":2,"api":[0,21],"scale":0.5,"text":"","size":[50,10]},{"bounds":[46,10],"lineHeight":2,"api":[96,21],"scale":0.5,"text":"Hello world","size":[50,10]},{"bounds":[37,230],"lineHeight":2,"api":[80,252],"scale":0.5,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[50,230]},{"bounds":[22,30],"lineHeight":2,"api":[47,42],"scale":0.5,"text":"Hello\nworld","size":[50,30]},{"bounds":[0,21],"lineHeight":1,"api":[0,21],"scale":1,"text":"","size":[100,21]},{"bounds":[96,21],"lineHeight":1,"api":[96,21],"scale":1,"text":"Hello world","size":[100,21]},{"bounds":[80,252],"lineHeight":1,"api":[80,252],"scale":1,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[100,252]},{"bounds":[47,42],"lineHeight":1,"api":[47,42],"scale":1,"text":"Hello\nworld","size":[100,42]},{"bounds":[0,21],"lineHeight":1.2,"api":[0,21],"scale":1,"text":"","size":[100,21]},{"bounds":[96,21],"lineHeight":1.2,"api":[96,21],"scale":1,"text":"Hello world","size":[100,21]},{"bounds":[80,298.1999816894531],"lineHeight":1.2,"api":[80,252],"scale":1,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[100,298.1999816894531]},{"bounds":[47,46.20000076293945],"lineHeight":1.2,"api":[47,42],"scale":1,"text":"Hello\nworld","size":[100,46.20000076293945]},{"bounds":[0,21],"lineHeight":2,"api":[0,21],"scale":1,"text":"","size":[100,21]},{"bounds":[96,21],"lineHeight":2,"api":[96,21],"scale":1,"text":"Hello world","size":[100,21]},{"bounds":[80,483],"lineHeight":2,"api":[80,252],"scale":1,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[100,483]},{"bounds":[47,63],"lineHeight":2,"api":[47,42],"scale":1,"text":"Hello\nworld","size":[100,63]},{"bounds":[0,42],"lineHeight":1,"api":[0,21],"scale":2,"text":"","size":[200,42]},{"bounds":[191,42],"lineHeight":1,"api":[96,21],"scale":2,"text":"Hello world","size":[200,42]},{"bounds":[154,504],"lineHeight":1,"api":[80,252],"scale":2,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[200,504]},{"bounds":[92,84],"lineHeight":1,"api":[47,42],"scale":2,"text":"Hello\nworld","size":[200,84]},{"bounds":[0,42],"lineHeight":1.2,"api":[0,21],"scale":2,"text":"","size":[200,42]},{"bounds":[191,42],"lineHeight":1.2,"api":[96,21],"scale":2,"text":"Hello world","size":[200,42]},{"bounds":[154,596.3999633789062],"lineHeight":1.2,"api":[80,252],"scale":2,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[200,596.3999633789062]},{"bounds":[92,92.4000015258789],"lineHeight":1.2,"api":[47,42],"scale":2,"text":"Hello\nworld","size":[200,92.4000015258789]},{"bounds":[0,42],"lineHeight":2,"api":[0,21],"scale":2,"text":"","size":[200,42]},{"bounds":[191,42],"lineHeight":2,"api":[96,21],"scale":2,"text":"Hello world","size":[200,42]},{"bounds":[154,966],"lineHeight":2,"api":[80,252],"scale":2,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[200,966]},{"bounds":[92,126],"lineHeight":2,"api":[47,42],"scale":2,"text":"Hello\nworld","size":[200,126]}]]=])
 local index = 0
 for _, scale in {0.5, 1, 2} do
  for _, lineHeight in {1, 1.2, 2} do
   for _, text in {"", "Hello world", string.rep("Wrapped text ", 6), "Hello\nworld"} do
    local frame = Instance.new("Frame")
    frame.Size, frame.Parent = UDim2.fromOffset(200, 500), screen
    local scaler = Instance.new("UIScale")
    scaler.Scale, scaler.Parent = scale, frame
    local label = Instance.new("TextLabel")
    label.FontFace, label.TextSize, label.LineHeight = params.Font, 14, lineHeight
    label.Text, label.TextWrapped = text, true
    label.Size, label.AutomaticSize = UDim2.fromOffset(100, 0), Enum.AutomaticSize.Y
    label.Parent = frame
    task.wait(0.05)
    params.Text, params.Width = text, 100
    local api = game.TextService:GetTextBoundsAsync(params)
    index += 1
    local observation = expected[index]
    near(label.TextBounds, observation.bounds, "legacy bounds " .. index)
    near(label.AbsoluteSize, observation.size, "legacy automatic size " .. index)
    assert(api == Vector2.new(unpack(observation.api)), "legacy bounds API " .. index)
    for _, height in {20,21,41,42,50,100} do
     assert(game.TextService:GetTextSize(text,14,Enum.Font.Legacy,Vector2.new(100,height)) == Vector2.new(api.X,math.min(api.Y,math.max(1,math.floor(height/21))*21)), "legacy enum line limit " .. index)
    end
    assert(game.TextService:GetTextSize(text,14,Enum.Font.Legacy,Vector2.new(100,0)) == Vector2.new(api.X,21), "legacy enum height limit " .. index)
    assert(game.TextService:GetTextSize(text,14,Enum.Font.Legacy,Vector2.new(100,1000000)) == api, "legacy enum API " .. index)
    frame:Destroy()
   end
  end
 end
 params:Destroy()
 screen:Destroy()

return true
]==]
