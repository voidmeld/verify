--!strict

local fs = require "@std/fs"
local Core = require "../src/core"
local Lute = require "../src/lute"
local Files = require "../src/lute/files"

return function()
	local directory = ".lute/tmp/text-metrics-native"
	fs.createDirectory(directory, { makeParents = true })
	for _, entry in fs.listDirectory(directory) do
		fs.remove(directory .. "/" .. entry.name)
	end
	for _, entry in fs.listDirectory "src/lute/fixtures/text" do
		if entry.name:match "%.json$" then
			local raw = fs.readFileToString("src/lute/fixtures/text/" .. entry.name)
			fs.writeStringToFile(
				directory .. "/" .. entry.name:gsub("%.json$", ".luau"),
				"return " .. string.format("%q", raw)
			)
		end
	end
	local place = Files.temporary "Verify-Text-Metrics-Conformance.rbxlx"
	Lute.place.build {
		output = place,
		roots = { "src/core", "src/roblox", directory },
		rootName = "TextMetricsConformance",
	}
	local result = Lute.studio.run {
		place = place,
		worker = "tools/studio-worker.luau",
		context = "Client",
		deadlineSeconds = 180,
		code = [==[
local root = game.ReplicatedStorage.TextMetricsConformance
local Core, Roblox = require(root.src.core), require(root.src.roblox)
local metrics = require(root.src.roblox["text-metrics"])
local harness = Core.createHarness {now = os.clock}
for _, module in root[".lute"].tmp["text-metrics-native"]:GetChildren() do
 harness:case(module.Name, function(check)
  local data = game.HttpService:JSONDecode(require(module))
  local model = metrics.create(data)
  local params = Instance.new("GetTextBoundsParams")
  check:defer(function() params:Destroy() end)
  params.Font = Font.new(data.family, Enum.FontWeight[data.weight], Enum.FontStyle[data.style])
  local random = Random.new(527)
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 "
  local strings = {"", "  ", "Hello world", "Office staff affiliation", "affluent waffle", "The quick brown fox jumps over the lazy dog"}
  for index = 1, 100 do
   local text = ""
   for cursor = 1, random:NextInteger(1, 80) do
    local at = random:NextInteger(1, #alphabet)
    text ..= alphabet:sub(at, at)
   end
   table.insert(strings, text)
  end
  local differences = {}
  for size = 1, 100 do
   params.Size = size
   local lineHeight = model.height(size)
   for _, text in strings do
    params.Text, params.Width = text, 0
    local native = game.TextService:GetTextBoundsAsync(params)
    local width = model.width(text, size)
    if width ~= native.X or native.Y ~= lineHeight then
     table.insert(differences, {text = text, size = size, actual = {width, lineHeight}, native = {native.X, native.Y}})
    end
   end
   for _, text in {"Hello world ", "  Office staff affiliation  ", "affluent\nwaffle\n", "The quick brown fox jumps over the lazy dog"} do
    local minimum = 1
    for word in text:gmatch("[^ \n]+") do minimum = math.max(minimum, model.width(word, size)) end
    params.Text, params.Width = text, minimum + random:NextInteger(0, 150)
    local native = game.TextService:GetTextBoundsAsync(params)
    local width, lines = model.wrap(text, size, params.Width)
    if width ~= native.X or lines * lineHeight ~= native.Y then
     table.insert(differences, {text = text, size = size, width = params.Width, actual = {width, lines * lineHeight}, native = {native.X, native.Y}})
    end
   end
  end
  local samples = {}
  for index = 1, math.min(100, #differences) do samples[index] = differences[index] end
  check:attach("differences.json", "application/json", game.HttpService:JSONEncode(samples))
  check:expect(#differences):toBe(0)
 end)
end
return game.HttpService:JSONEncode(Roblox.reportChannel.envelope(runId, harness:run {executor = "native-text-metrics", environment = {engineVersion = version()}}))
]==],
	}
	assert(result.status == "returned", result.detail)
	local report = Core.decode(result.report)
	print(Core.format(report))
	assert(report.total > 0 and report.passed == report.total, "native text metrics conformance failed")
end
