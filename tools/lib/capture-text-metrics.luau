--!strict
local attachments = require "./capture-attachments"
return [====[
local root = game.ReplicatedStorage.TextMetrics
]====] .. attachments .. [====[
local Core, Roblox = require(root.src.core), require(root.src.roblox)
local harness = Core.createHarness {now = os.clock}
harness:case("native font metrics", function(check)
 local captured = captureAttachments(check)
 local params = Instance.new("GetTextBoundsParams")
 params.Font = Font.new(descriptor.family, Enum.FontWeight[descriptor.weight], Enum.FontStyle[descriptor.style])
 params.Width = 1000000
 local count = 0
 local function boundsWidth(text, size)
  params.Text, params.Size = text, size
  local value = game:GetService("TextService"):GetTextBoundsAsync(params).X
  count += 1
  if count % 1000 == 0 then task.wait() end
  return value
 end
 local spaces = {}
 local function width(text, size)
  local space = spaces[size]
  if space == nil then
   space = (boundsWidth(string.rep(" ", 128), size) - boundsWidth(string.rep(" ", 64), size)) / 64
   spaces[size] = space
  end
  local word = text .. " "
  return (boundsWidth(string.rep(word, 128), size) - boundsWidth(string.rep(word, 64), size)) / 64 - space
 end
 local tokens = {}
 for codepoint = 32, 126 do
  local value = utf8.char(codepoint)
  table.insert(tokens, value)
 end
 for _, value in {"…", "•", "—", "–", "×", "·", "’", "“", "”", "°", "→", "−", "★", "é", "á", "í", "ó", "ú", "ñ", "ü", "ö", "ä", "ç", "è", "à", "ê", "ô", "ë", "ß", "É", "ð", "ĝ", "ş", "Ş", "ţ"} do table.insert(tokens, value) end
 for _, value in {"ff", "fi", "fl", "ffi", "ffl"} do table.insert(tokens, value) end
 local sizes, seen = {}, {}
 for size = 1, 100 do
  local advances, adjustments, starts, ends = {}, {}, {}, {}
  for index, value in tokens do
   advances[index] = width(value, size)
   starts[index] = boundsWidth(value .. " ", size) - width(value .. " ", size)
   ends[index] = boundsWidth(" " .. value, size) - width(" " .. value, size)
  end
  for leftIndex, left in tokens do
   for rightIndex, right in tokens do
    local delta = width(left .. right, size) - advances[leftIndex] - advances[rightIndex]
    if delta ~= 0 then
     local key = (leftIndex - 1) * #tokens + rightIndex
     adjustments[key], seen[key] = delta, true
    end
   end
  end
  params.Text, params.Size = "", size
  local height = game.TextService:GetTextBoundsAsync(params).Y
  count += 1
  sizes[size] = {height = height, advances = advances, adjustments = adjustments, starts = starts, ends = ends}
 end
 local pairs = {}
 for leftIndex in tokens do
  for rightIndex in tokens do
   if seen[(leftIndex - 1) * #tokens + rightIndex] then table.insert(pairs, {leftIndex, rightIndex}) end
  end
 end
 for _, row in sizes do
  local adjustments = {}
  for index, pair in pairs do adjustments[index] = row.adjustments[(pair[1] - 1) * #tokens + pair[2]] or 0 end
  row.adjustments = adjustments
 end
 captured.attach("metrics.json", "application/json", game.HttpService:JSONEncode({
  engineVersion = version(), family = params.Font.Family, weight = params.Font.Weight.Name,
  style = params.Font.Style.Name, tokens = tokens, pairs = pairs, calls = count,
 }))
 captured.attach("sizes-1.json", "application/json", game.HttpService:JSONEncode(table.move(sizes, 1, 50, 1, {})))
 captured.attach("sizes-2.json", "application/json", game.HttpService:JSONEncode(table.move(sizes, 51, 100, 1, {})))
 local model = require(root.src.roblox["text-metrics"]).create({tokens = tokens, pairs = pairs, sizes = sizes})
 local random = Random.new(527)
 local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
 local strings = {"Hello world", "Office staff affiliation", "affluent waffle", "A very fine office staff", "The quick brown fox jumps over the lazy dog", "Never store expected test geometry as a font measurement", "Score: 1,250 (+15%) — ready…", "“Quoted” • 3×4 · 90°"}
 for index = 1, 200 do
  local characters = {}
  for cursor = 1, random:NextInteger(1, 80) do
   local at = random:NextInteger(1, #alphabet + 10)
   characters[cursor] = if at <= #alphabet then alphabet:sub(at, at) else tokens[#tokens - (at - #alphabet) + 1]
  end
  table.insert(strings, table.concat(characters))
 end
 local differences = {}
 for size = 1, 100 do
  for _, text in strings do
   local modeled, actual = pcall(model.width, text, size)
   local expected = if modeled then boundsWidth(text, size) else actual
   if modeled and actual ~= expected then table.insert(differences, {size = size, text = text, native = expected, actual = actual}) end
  end
 end
 captured.attach("differences.json", "application/json", game.HttpService:JSONEncode(differences))
 check:expect(#differences):toBe(0)

 captured.finish()
 params:Destroy()
 check:expect(#sizes):toBe(100)
end)
return game.HttpService:JSONEncode(Roblox.reportChannel.envelope(runId, harness:run {executor = "native-font-metrics", environment = {engineVersion = version()}, attachments = Parts.limits}))
]====]
