--!strict

return [==[
 local params = Instance.new("GetTextBoundsParams")
 params.Font, params.Size = Font.new("rbxasset://fonts/families/BuilderSans.json"), 14
 params.Text = "A"
 game.TextService:GetTextBoundsAsync(params)
 local screen = Instance.new("ScreenGui")
 screen.IgnoreGuiInset, screen.Parent = true, game.Players.LocalPlayer.PlayerGui
 local expected = game.HttpService:JSONDecode([=[[{"bounds":[0,6.6666669845581055],"lineHeight":1,"api":[0,14],"scale":0.5,"text":"","size":[50,6.6666669845581055]},{"bounds":[28.666667938232422,6.6666669845581055],"lineHeight":1,"api":[59.333335876464844,14],"scale":0.5,"text":"Hello world","size":[50,6.6666669845581055]},{"bounds":[36,40],"lineHeight":1,"api":[73.33333587646484,84],"scale":0.5,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[50,40]},{"bounds":[14,13.333333969116211],"lineHeight":1,"api":[29.33333396911621,28],"scale":0.5,"text":"Hello\nworld","size":[50,13.333333969116211]},{"bounds":[0,6.6666669845581055],"lineHeight":1.2,"api":[0,14],"scale":0.5,"text":"","size":[50,6.6666669845581055]},{"bounds":[28.666667938232422,6.6666669845581055],"lineHeight":1.2,"api":[59.333335876464844,14],"scale":0.5,"text":"Hello world","size":[50,6.6666669845581055]},{"bounds":[36,46.66666793823242],"lineHeight":1.2,"api":[73.33333587646484,84],"scale":0.5,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[50,46.66666793823242]},{"bounds":[14,14.666666984558105],"lineHeight":1.2,"api":[29.33333396911621,28],"scale":0.5,"text":"Hello\nworld","size":[50,14.666666984558105]},{"bounds":[0,6.6666669845581055],"lineHeight":2,"api":[0,14],"scale":0.5,"text":"","size":[50,6.6666669845581055]},{"bounds":[28.666667938232422,6.6666669845581055],"lineHeight":2,"api":[59.333335876464844,14],"scale":0.5,"text":"Hello world","size":[50,6.6666669845581055]},{"bounds":[36,73.33333587646484],"lineHeight":2,"api":[73.33333587646484,84],"scale":0.5,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[50,73.33333587646484]},{"bounds":[14,20],"lineHeight":2,"api":[29.33333396911621,28],"scale":0.5,"text":"Hello\nworld","size":[50,20]},{"bounds":[0,14],"lineHeight":1,"api":[0,14],"scale":1,"text":"","size":[100,14]},{"bounds":[59.333335876464844,14],"lineHeight":1,"api":[59.333335876464844,14],"scale":1,"text":"Hello world","size":[100,14]},{"bounds":[73.33333587646484,84],"lineHeight":1,"api":[73.33333587646484,84],"scale":1,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[100,84]},{"bounds":[29.33333396911621,28],"lineHeight":1,"api":[29.33333396911621,28],"scale":1,"text":"Hello\nworld","size":[100,28]},{"bounds":[0,14],"lineHeight":1.2,"api":[0,14],"scale":1,"text":"","size":[100,14]},{"bounds":[59.333335876464844,14],"lineHeight":1.2,"api":[59.333335876464844,14],"scale":1,"text":"Hello world","size":[100,14]},{"bounds":[73.33333587646484,98],"lineHeight":1.2,"api":[73.33333587646484,84],"scale":1,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[100,98]},{"bounds":[29.33333396911621,30.80000114440918],"lineHeight":1.2,"api":[29.33333396911621,28],"scale":1,"text":"Hello\nworld","size":[100,30.80000114440918]},{"bounds":[0,14],"lineHeight":2,"api":[0,14],"scale":1,"text":"","size":[100,14]},{"bounds":[59.333335876464844,14],"lineHeight":2,"api":[59.333335876464844,14],"scale":1,"text":"Hello world","size":[100,14]},{"bounds":[73.33333587646484,154],"lineHeight":2,"api":[73.33333587646484,84],"scale":1,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[100,154]},{"bounds":[29.33333396911621,42],"lineHeight":2,"api":[29.33333396911621,28],"scale":1,"text":"Hello\nworld","size":[100,42]},{"bounds":[0,28],"lineHeight":1,"api":[0,14],"scale":2,"text":"","size":[200,28]},{"bounds":[115.33333587646484,28],"lineHeight":1,"api":[59.333335876464844,14],"scale":2,"text":"Hello world","size":[200,28]},{"bounds":[144,168],"lineHeight":1,"api":[73.33333587646484,84],"scale":2,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[200,168]},{"bounds":[56.66666793823242,56],"lineHeight":1,"api":[29.33333396911621,28],"scale":2,"text":"Hello\nworld","size":[200,56]},{"bounds":[0,28],"lineHeight":1.2,"api":[0,14],"scale":2,"text":"","size":[200,28]},{"bounds":[115.33333587646484,28],"lineHeight":1.2,"api":[59.333335876464844,14],"scale":2,"text":"Hello world","size":[200,28]},{"bounds":[144,196],"lineHeight":1.2,"api":[73.33333587646484,84],"scale":2,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[200,196]},{"bounds":[56.66666793823242,61.60000228881836],"lineHeight":1.2,"api":[29.33333396911621,28],"scale":2,"text":"Hello\nworld","size":[200,61.60000228881836]},{"bounds":[0,28],"lineHeight":2,"api":[0,14],"scale":2,"text":"","size":[200,28]},{"bounds":[115.33333587646484,28],"lineHeight":2,"api":[59.333335876464844,14],"scale":2,"text":"Hello world","size":[200,28]},{"bounds":[144,308],"lineHeight":2,"api":[73.33333587646484,84],"scale":2,"text":"Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text Wrapped text ","size":[200,308]},{"bounds":[56.66666793823242,84],"lineHeight":2,"api":[29.33333396911621,28],"scale":2,"text":"Hello\nworld","size":[200,84]}]]=])
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
    local legacyApi = game.TextService:GetTextSize(text, 14, Enum.Font.BuilderSans, Vector2.new(100, 0))
    assert(legacyApi == Vector2.new(api.X, 14), "legacy text API height limit")
    for _, height in {13, 14, 20, 28, 100} do
     local legacy = game.TextService:GetTextSize(text, 14, Enum.Font.BuilderSans, Vector2.new(100, height))
     assert(legacy == Vector2.new(api.X, math.min(api.Y, math.max(1, math.floor(height / 14)) * 14)), "legacy text API line limit")
    end
    assert(game.TextService:GetTextSize(text, 14, Enum.Font.BuilderSans, Vector2.new(100, 1000000)) == api, "legacy text API full height")
    index += 1
    local observation = expected[index]
    assert(label.TextBounds == Vector2.new(observation.bounds[1], observation.bounds[2]), "text bounds " .. index .. ": " .. tostring(label.TextBounds))
    assert(label.AbsoluteSize == Vector2.new(observation.size[1], observation.size[2]), "automatic size " .. index .. ": " .. tostring(label.AbsoluteSize))
    assert(api == Vector2.new(observation.api[1], observation.api[2]), "text API " .. index)
    frame:Destroy()
   end
  end
 end
 local automaticExpected = game.HttpService:JSONDecode([=[[{"bounds":[26.666667938232422,14],"padded":false,"automatic":"None","fits":false,"extent":[0,0],"size":[0,0]},{"bounds":[26.666667938232422,14],"padded":true,"automatic":"None","fits":false,"extent":[0,0],"size":[0,0]},{"bounds":[26.666667938232422,14],"padded":false,"automatic":"None","fits":false,"extent":[10,8],"size":[10,8]},{"bounds":[26.666667938232422,14],"padded":true,"automatic":"None","fits":false,"extent":[10,8],"size":[10,8]},{"bounds":[26.666667938232422,14],"padded":false,"automatic":"None","fits":true,"extent":[100,100],"size":[100,100]},{"bounds":[26.666667938232422,14],"padded":true,"automatic":"None","fits":true,"extent":[100,100],"size":[100,100]},{"bounds":[26.666667938232422,14],"padded":false,"automatic":"X","fits":false,"extent":[0,0],"size":[26.666667938232422,0]},{"bounds":[26.666667938232422,14],"padded":true,"automatic":"X","fits":false,"extent":[0,0],"size":[32.66666793823242,0]},{"bounds":[26.666667938232422,14],"padded":false,"automatic":"X","fits":false,"extent":[10,8],"size":[26.666667938232422,8]},{"bounds":[26.666667938232422,14],"padded":true,"automatic":"X","fits":false,"extent":[10,8],"size":[32.66666793823242,8]},{"bounds":[26.666667938232422,14],"padded":false,"automatic":"X","fits":true,"extent":[100,100],"size":[100,100]},{"bounds":[26.666667938232422,14],"padded":true,"automatic":"X","fits":true,"extent":[100,100],"size":[100,100]},{"bounds":[26.666667938232422,14],"padded":false,"automatic":"Y","fits":false,"extent":[0,0],"size":[0,14]},{"bounds":[26.666667938232422,14],"padded":true,"automatic":"Y","fits":false,"extent":[0,0],"size":[0,22]},{"bounds":[26.666667938232422,14],"padded":false,"automatic":"Y","fits":false,"extent":[10,8],"size":[10,14]},{"bounds":[26.666667938232422,14],"padded":true,"automatic":"Y","fits":false,"extent":[10,8],"size":[10,22]},{"bounds":[26.666667938232422,14],"padded":false,"automatic":"Y","fits":true,"extent":[100,100],"size":[100,100]},{"bounds":[26.666667938232422,14],"padded":true,"automatic":"Y","fits":true,"extent":[100,100],"size":[100,100]},{"bounds":[26.666667938232422,14],"padded":false,"automatic":"XY","fits":true,"extent":[0,0],"size":[26.666667938232422,14]},{"bounds":[26.666667938232422,14],"padded":true,"automatic":"XY","fits":true,"extent":[0,0],"size":[32.66666793823242,22]},{"bounds":[26.666667938232422,14],"padded":false,"automatic":"XY","fits":true,"extent":[10,8],"size":[26.666667938232422,14]},{"bounds":[26.666667938232422,14],"padded":true,"automatic":"XY","fits":true,"extent":[10,8],"size":[32.66666793823242,22]},{"bounds":[26.666667938232422,14],"padded":false,"automatic":"XY","fits":true,"extent":[100,100],"size":[100,100]},{"bounds":[26.666667938232422,14],"padded":true,"automatic":"XY","fits":true,"extent":[100,100],"size":[100,100]}]]=])
 local automaticIndex = 0
 for _, automatic in {"None", "X", "Y", "XY"} do
  for _, extent in {{0, 0}, {10, 8}, {100, 100}} do
   for _, padded in {false, true} do
    local label = Instance.new("TextLabel")
    label.FontFace, label.TextSize = params.Font, 14
    label.Text, label.TextWrapped = "Hello", false
    label.Size, label.AutomaticSize = UDim2.fromOffset(extent[1], extent[2]), Enum.AutomaticSize[automatic]
    label.Parent = screen
    if padded then
     local padding = Instance.new("UIPadding")
     padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 2), UDim.new(0, 4)
     padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 3), UDim.new(0, 5)
     padding.Parent = label
    end
    task.wait(0.05)
    automaticIndex += 1
    local observation = automaticExpected[automaticIndex]
    assert(label.TextBounds == Vector2.new(observation.bounds[1], observation.bounds[2]), "automatic text bounds " .. automaticIndex)
    assert(label.AbsoluteSize == Vector2.new(observation.size[1], observation.size[2]), "automatic axes " .. automaticIndex)
    assert(label.TextFits == observation.fits, "automatic text fits " .. automaticIndex)
    label:Destroy()
   end
  end
 end
 for index, mode in { "AtEnd", "SplitWord" } do
  local label = Instance.new("TextLabel")
  label.FontFace, label.TextSize = params.Font, 16
  label.Text = "The quick brown fox jumps over the lazy dog"
  label.Size, label.TextTruncate = UDim2.fromOffset(600, 20), Enum.TextTruncate[mode]
  label.Parent = screen
  task.wait(0.05)
  assert(label.AbsoluteSize == Vector2.new(600, 20), "fitting truncated size " .. index)
  assert(label.TextBounds == Vector2.new(262.66668701171875, 16), "fitting truncated text bounds " .. index .. ": " .. tostring(label.TextBounds))
  assert(label.TextFits == true, "fitting truncated text fits " .. index)
  label:Destroy()
 end
 local automaticTruncated = Instance.new("TextLabel")
 automaticTruncated.FontFace, automaticTruncated.TextSize = params.Font, 16
 automaticTruncated.Text = "The quick brown fox jumps over the lazy dog"
 automaticTruncated.Size, automaticTruncated.AutomaticSize = UDim2.fromOffset(0, 20), Enum.AutomaticSize.X
 automaticTruncated.TextTruncate, automaticTruncated.Parent = Enum.TextTruncate.AtEnd, screen
 task.wait(0.05)
 assert(automaticTruncated.AbsoluteSize == Vector2.new(262.66668701171875, 20), "automatic size ignores truncation")
 assert(automaticTruncated.TextBounds == Vector2.new(262.66668701171875, 16), "automatic truncated text bounds")
 automaticTruncated:Destroy()
 params:Destroy()
 screen:Destroy()

return true
]==]
