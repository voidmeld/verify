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
 local pixelScale = 1
 local function boundsWidth(text, size)
  params.Text, params.Size = text, size
  local value = game:GetService("TextService"):GetTextBoundsAsync(params).X
  count += 1
  if count % 1000 == 0 then task.wait() end
  return value
 end
 local function pixelsWidth(text, size)
  return math.round(boundsWidth(text, size) / pixelScale)
 end
 local spaces = {}
 local function width(text, size)
  local space = spaces[size]
  if space == nil then
   space = (pixelsWidth(string.rep(" ", 128), size) - pixelsWidth(string.rep(" ", 64), size)) / 64
   spaces[size] = space
  end
  local word = text .. " "
  return (pixelsWidth(string.rep(word, 128), size) - pixelsWidth(string.rep(word, 64), size)) / 64 - space
 end
 local tokens = {}
 for codepoint = 32, 126 do
  local value = utf8.char(codepoint)
  table.insert(tokens, value)
 end
 if params.Font.Family == "rbxasset://fonts/families/Guru.json" then
  for _, value in {".D", ".H", ".L", ".M", ".N", ".R", ".S", ".T", ".d", ".h", ".l", ".m", ".n", ".r", ".s", ".t", ".LL", ".RR", ".ll", ".rr"} do table.insert(tokens, value) end
 end
 for _, value in {"…", "•", "—", "–", "×", "·", "’", "“", "”", "°", "→", "−", "★", "é", "á", "í", "ó", "ú", "ñ", "ü", "ö", "ä", "ç", "è", "à", "ê", "ô", "ë", "ß", "É", "ð", "ĝ", "ş", "Ş", "ţ"} do table.insert(tokens, value) end
 for _, value in {"›", "↑", "↓", "▸", "▾", "▶", "▼", "◀", "▲", "◆", "◇", "○", "●", "☆", "♡", "♥", "♦", "✓"} do table.insert(tokens, value) end
 for _, value in {"þ", "ṽ", "ĥ", "東", "京", "速", "度", "制", "限", "標", "識", "と", "設", "定", "画", "面"} do table.insert(tokens, value) end
 for _, value in {"⇧", "⌘", "⌫", "〜", "◎", "⚡", "⛓", "▣", "□", "▢", "☰", "◉", "◩", "≡", "⬡", "■"} do table.insert(tokens, value) end
 if params.Font.Family == "rbxasset://fonts/families/BuilderSans.json" then
  for _, value in {"->", "-^", "–>", "–^", "—>", "—^", "<-", "<–", "<—", "^-", "^–", "^—"} do table.insert(tokens, value) end
 end
 for _, value in {"ff", "fi", "fl", "ffi", "ffl"} do table.insert(tokens, value) end
 local minimum = math.huge
 for _, value in tokens do
  params.Text, params.Size = value, 1
  local measured = game.TextService:GetTextBoundsAsync(params).X
  count += 1
  if measured > 0 then minimum = math.min(minimum, measured) end
 end
 assert(minimum < math.huge, "font has no measurable pixel scale")
 pixelScale = minimum
 local sizes, seen = {}, {}
 for size = 1, 100 do
  local advances, adjustments, starts, ends = {}, {}, {}, {}
  for index, value in tokens do
   advances[index] = width(value, size)
   starts[index] = pixelsWidth(value .. " ", size) - width(value .. " ", size)
   ends[index] = pixelsWidth(" " .. value, size) - width(" " .. value, size)
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
  style = params.Font.Style.Name, tokens = tokens, pairs = pairs, calls = count, pixelScale = pixelScale,
 }))
 captured.attach("sizes-1.json", "application/json", game.HttpService:JSONEncode(table.move(sizes, 1, 50, 1, {})))
 captured.attach("sizes-2.json", "application/json", game.HttpService:JSONEncode(table.move(sizes, 51, 100, 1, {})))
 local model = require(root.src.roblox["text-metrics"]).create({tokens = tokens, pairs = pairs, sizes = sizes, pixelScale = pixelScale})
 local random = Random.new(527)
 local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
 local randomTokens = {"ffl", "ffi", "fl", "fi", "ff", "✓", "♦", "♥", "♡", "☆"}
 local strings = {"Hello world", "Office staff affiliation", "affluent waffle", "A very fine office staff", "The quick brown fox jumps over the lazy dog", "Never store expected test geometry as a font measurement", "Score: 1,250 (+15%) — ready…", "“Quoted” • 3×4 · 90°"}
 for _, symbol in {"›", "↑", "↓", "▸", "▾", "▶", "▼", "◀", "▲", "◆", "◇", "○", "●", "☆", "♡", "♥", "♦", "✓"} do
  table.insert(strings, symbol)
  table.insert(strings, "Layering " .. symbol .. " Makeup")
  table.insert(strings, "A" .. symbol .. "V" .. symbol .. "To")
 end
 for index = 1, 200 do
  local characters = {}
  for cursor = 1, random:NextInteger(1, 80) do
   local at = random:NextInteger(1, #alphabet + #randomTokens)
   characters[cursor] = if at <= #alphabet then alphabet:sub(at, at) else randomTokens[at - #alphabet]
  end
  table.insert(strings, table.concat(characters))
 end
 for _, text in {",<-", "->7", "-^/", "->>", "—.R-"} do
  table.insert(strings, text)
  table.insert(strings, "A" .. text .. "V")
 end
 for _, sequence in {"->", "-^", "–>", "–^", "—>", "—^", "<-", "<–", "<—", "^-", "^–", "^—"} do
  for _, prefix in {"", "A", ",", "☆"} do
   for _, suffix in {"", "V", "/7>", "♥"} do
    table.insert(strings, prefix .. sequence .. suffix)
   end
  end
 end
 local differences = {}
 for _, symbol in {"⇧", "⌘", "⌫", "〜", "◎", "⚡", "⛓", "▣", "□", "▢", "☰", "◉", "◩", "≡", "⬡", "■"} do
  table.insert(strings, symbol)
  table.insert(strings, "Layering " .. symbol .. " Makeup")
  table.insert(strings, "A" .. symbol .. "V" .. symbol .. "To")
 end
 for _, text in {"þ", "ṽ", "ĥ", "ṽþĥ", "東京", "速度制限", "標識と設定画面", "東京速度制限標識と設定画面"} do
  table.insert(strings, text)
  table.insert(strings, "A" .. text .. "V")
  table.insert(strings, text .. " A " .. text)
 end
 for size = 1, 100 do
  for _, text in strings do
   local modeled, actual = pcall(model.width, text, size)
   local expected = boundsWidth(text, size)
   if not modeled or actual ~= expected then table.insert(differences, {size = size, text = text, native = expected, actual = actual}) end
  end
 end
 captured.attach("differences.json", "application/json", game.HttpService:JSONEncode(differences))
 captured.finish()
 check:expect(#differences):toBe(0)
 params:Destroy()
 check:expect(#sizes):toBe(100)
end)
return game.HttpService:JSONEncode(Roblox.reportChannel.envelope(runId, harness:run {executor = "native-font-metrics", environment = {engineVersion = version()}, attachments = Parts.limits}))
]====]
