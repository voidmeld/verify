--!strict

local attachments = require "./capture-attachments"
return [====[
local root = game.ReplicatedStorage.TextMetrics
]====] .. attachments .. [====[
local Core, Roblox = require(root.src.core), require(root.src.roblox)
local harness = Core.createHarness {now = os.clock}
harness:case("native symbol metrics", function(check)
 local captured = captureAttachments(check)
 local params = Instance.new("GetTextBoundsParams")
 check:defer(function() params:Destroy() end)
 params.Font = Font.new(descriptor.family, Enum.FontWeight[descriptor.weight], Enum.FontStyle[descriptor.style])
 params.Width = 0
 local measurements, heights = {}, {}
 for _, text in descriptor.texts do
  local widths = {}
  for size = 1, 100 do
   params.Text, params.Size = text, size
   local bounds = game.TextService:GetTextBoundsAsync(params)
   widths[size] = bounds.X
   if heights[size] then check:expect(bounds.Y):toBe(heights[size]) else heights[size] = bounds.Y end
  end
  measurements[text] = widths
 end
 captured.attach("symbols.json", "application/json", game.HttpService:JSONEncode({engineVersion = version(), measurements = measurements, heights = heights}))
 captured.finish()
 check:expect(#heights):toBe(100)
end)
return game.HttpService:JSONEncode(Roblox.reportChannel.envelope(runId, harness:run {executor = "native-symbol-metrics", environment = {engineVersion = version()}, attachments = Parts.limits}))
]====]
