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
  local strings = {"", "  ", "Hello world", "Office staff affiliation", "affluent waffle", "The quick brown fox jumps over the lazy dog", "W.n", "W.m", "W.N", ".n", " .n", "W..n", "W.nW", "W.n W.n ", "W.LL W.RR W.ll W.rr"}
  for index = 1, 100 do
   local text = ""
   for cursor = 1, random:NextInteger(1, 80) do
    local at = random:NextInteger(1, #alphabet)
    text ..= alphabet:sub(at, at)
   end
   table.insert(strings, text)
  end
  local differences, compared, violations = {}, 0, {}
  local widths = {}
  local lastHeight = 0
  local function violate(rule, text, size)
   if #violations < 20 then table.insert(violations, {rule = rule, text = text, size = size}) end
  end
  for size = 1, 100 do
   params.Size = size
   local lineHeight = model.height(size)
   local line = nil
   for _, text in strings do
    params.Text, params.Width = text, 0
    local native = game.TextService:GetTextBoundsAsync(params)
    local width = model.width(text, size)
    compared += 1
    if width ~= native.X or native.Y ~= lineHeight then
     table.insert(differences, {text = text, size = size, actual = {width, lineHeight}, native = {native.X, native.Y}})
    end
    if text:match "%S" then
     line = line or native.Y
     if native.Y ~= line then violate("every non-empty line has one height", text, size) end
     if native.X <= 0 then violate("visible text has width", text, size) end
    elseif text == "" and native.X ~= 0 then
     violate("empty text has zero width", text, size)
    end
    local previous = widths[text]
    if previous and native.X < previous - 0.001 then violate("width grows with size", text, size) end
    widths[text] = native.X
   end
   if line then
    if line < lastHeight then violate("line height grows with size", "", size) end
    lastHeight = line
   end
   for _, text in {"Hello world ", "  Office staff affiliation  ", "affluent\nwaffle\n", "The quick brown fox jumps over the lazy dog"} do
    local minimum = 1
    for word in text:gmatch("[^ \n]+") do minimum = math.max(minimum, model.width(word, size)) end
    params.Text, params.Width = text, minimum + random:NextInteger(0, 150)
    local native = game.TextService:GetTextBoundsAsync(params)
    local width, lines = model.wrap(text, size, params.Width)
    local height = model.height(size, lines)
    compared += 1
    if width ~= native.X or height ~= native.Y then
     table.insert(differences, {text = text, size = size, width = params.Width, actual = {width, height}, native = {native.X, native.Y}})
    end
    if line then
     local count = native.Y / line
     if math.abs(count - math.floor(count + 0.5)) > 0.05 then violate("wrapped height is whole lines", text, size) end
     if native.X > params.Width + 0.5 then violate("wrapped width stays within the constraint", text, size) end
     params.Width = params.Width + 40
     local wider = game.TextService:GetTextBoundsAsync(params)
     if wider.Y > native.Y + 0.001 then violate("wider constraint never adds lines", text, size) end
    end
   end
  end
  local samples = {}
  for index = 1, math.min(20, #differences) do samples[index] = differences[index] end
  check:attach("drift.json", "application/json", game.HttpService:JSONEncode({compared = compared, differing = #differences, engineVersion = version(), samples = samples}))
  check:expect(violations):toEqual({})
 end)
end
return game.HttpService:JSONEncode(Roblox.reportChannel.envelope(runId, harness:run {executor = "native-text-metrics", environment = {engineVersion = version()}}))
]==],
	}
	assert(result.status == "returned", result.detail)
	local report = Core.decode(result.report)
	print(Core.format(report))
	for _, case in report.results do
		for _, artifact in case.artifacts do
			if artifact.name == "drift.json" and artifact.content ~= nil then
				local differing = string.match(artifact.content, '"differing":(%d+)')
				local compared = string.match(artifact.content, '"compared":(%d+)')
				if differing ~= nil and compared ~= nil then
					print(
						string.format(
							"drift %s: %s of %s recorded measurements differ from the live engine",
							case.name,
							differing,
							compared
						)
					)
				end
			end
		end
	end
	assert(report.total > 0 and report.passed == report.total, "native text metrics conformance failed")
end
