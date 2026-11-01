--!strict

local fs = require "@std/fs"
local Path = require "@std/path"
local Metrics = require "../roblox/text-metrics"
local Datatypes = require "../roblox/datatypes"
local json = require "@std/json"
local Values = require "../roblox/ui-values"

local function numbers(value: json.Value): { number }
	local result: { number } = {}
	for _, entry in assert(json.asArray(value)) do
		table.insert(result, Values.number(entry))
	end
	return result
end

local function decode(source: string): (Metrics.Face, string)
	local root = assert(json.asObject(json.deserialize(source)))
	local tokens: { string } = {}
	for _, entry in assert(json.asArray(root.tokens)) do
		table.insert(tokens, Values.string(entry))
	end
	local pairs: { { number } } = {}
	for _, entry in assert(json.asArray(root.pairs)) do
		local pair = numbers(entry)
		assert(#pair == 2)
		for _, index in pair do
			assert(index % 1 == 0 and index >= 1 and index <= #tokens)
		end
		table.insert(pairs, pair)
	end
	local sizes: { Metrics.Row } = {}
	for _, entry in assert(json.asArray(root.sizes)) do
		local row = assert(json.asObject(entry))
		local advances, adjustments = numbers(row.advances), numbers(row.adjustments)
		local declaredStarts, declaredEnds = row.starts, row.ends
		local starts = if declaredStarts == nil then nil else numbers(declaredStarts)
		local ends = if declaredEnds == nil then nil else numbers(declaredEnds)
		assert(#advances == #tokens and #adjustments == #pairs)
		if starts ~= nil then
			local values: { number } = starts
			assert(#values == #tokens)
		end
		if ends ~= nil then
			local values: { number } = ends
			assert(#values == #tokens)
		end
		table.insert(sizes, {
			advances = advances,
			adjustments = adjustments,
			starts = starts,
			ends = ends,
			height = if row.height == nil then nil else Values.number(row.height),
		})
	end
	assert(#sizes == 100)
	local key = Values.string(root.family) .. "/" .. Values.string(root.weight) .. "/" .. Values.string(root.style)
	return {
		tokens = tokens,
		pairs = pairs,
		sizes = sizes,
		pixelScale = if root.pixelScale == nil then nil else Values.number(root.pixelScale),
	},
		key
end

local DIRECTORY = Path.format(Path.join(Path.dirname(Path.resolve(debug.info(1, "s"))), "fixtures/text"))
local models: { [string]: Metrics.Model } = {}
local richModels: { [string]: Metrics.Model } = {}
local faces: { [string]: Metrics.Face } = {}

local function richFace(face: Metrics.Face): Metrics.Face
	local scalar = buffer.create(4)
	local function rounded(value: number): number
		buffer.writef32(scalar, 0, value)
		return buffer.readf32(scalar, 0)
	end
	local originalScale = face.pixelScale or 1
	local scale = 1 / rounded(1 / originalScale)
	local result = table.clone(face)
	result.pixelScale = scale
	result.sizes = {}
	for _, row in face.sizes do
		local converted = table.clone(row)
		if row.height then
			converted.height = rounded(math.round(row.height / originalScale) * scale)
		end
		table.insert(result.sizes, converted)
	end
	return result
end

local sources: { [string]: string }? = nil

local function preload()
	if sources then
		return
	end
	local read: { [string]: string } = {}
	for _, entry in fs.listDirectory(DIRECTORY) do
		local name = entry.name:match "^(.+)%.json$"
		if entry.type == "file" and name then
			read[name] = fs.readFileToString(`{DIRECTORY}/{entry.name}`)
		end
	end
	sources = read
end

local function load(key: string): Metrics.Model?
	local loaded = models[key]
	if loaded then
		return loaded
	end
	local family, weight, style = key:match "^rbxasset://fonts/families/(%w+)%.json/(%w+)/(%w+)$"
	local source = if family and sources then sources[`{family}-{weight}-{style}`] else nil
	if source == nil then
		return nil
	end
	local face, declared = decode(source)
	assert(declared == key, "text metrics face does not match its key: " .. key)
	faces[key] = face
	local model = Metrics.create(face)
	models[key] = model
	return model
end

local ENTITIES: { [string]: string } = { lt = "<", gt = ">", amp = "&", quot = '"', apos = "'" }
local NEUTRAL_TAGS: { [string]: boolean } = { u = true, s = true, stroke = true, mark = true }
local NEUTRAL_FONT: { [string]: boolean } = { color = true, transparency = true }

local function unescape(text: string): string
	return (string.gsub(text, "&(%a+);", function(name: string): string
		return ENTITIES[name] or `&{name};`
	end))
end

local function plain(text: string): string
	local source = string.gsub(text, "<!%-%-.-%-%->", "")
	local out: { string } = {}
	local upper = 0
	local cursor = 1
	while true do
		local first, last, closing, name, attributes = string.find(source, "<(/?)(%a+)(.-)>", cursor)
		local chunk = unescape(string.sub(source, cursor, if first then first - 1 else #source))
		table.insert(out, if upper > 0 then string.upper(chunk) else chunk)
		if first == nil or last == nil then
			break
		end
		local tag = string.lower(name or "")
		if tag == "br" then
			table.insert(out, "\n")
		elseif tag == "uc" or tag == "uppercase" then
			upper = math.max(0, upper + (if closing == "/" then -1 else 1))
		elseif tag == "font" then
			for attribute in string.gmatch(attributes or "", "([%w_]+)%s*=") do
				if not NEUTRAL_FONT[string.lower(attribute)] then
					error("unsupported_text_metrics: RichText <font " .. attribute .. ">", 0)
				end
			end
		elseif not NEUTRAL_TAGS[tag] then
			error("unsupported_text_metrics: RichText <" .. tag .. ">", 0)
		end
		cursor = last + 1
	end
	return table.concat(out)
end

local function modelFor(parameters: Values.TextParameters): (Metrics.Model, number)
	local font = parameters.Font
	local key = font.Family
		.. "/"
		.. Values.enumName(font.Weight, "FontWeight")
		.. "/"
		.. Values.enumName(font.Style, "FontStyle")
	local model = load(key)
	if model ~= nil and parameters.RichText then
		model = richModels[key] or Metrics.create(richFace(faces[key]))
		richModels[key] = model
	end
	if model == nil then
		error("unsupported_text_metrics: font " .. key, 0)
	end
	return model, math.clamp(math.floor(parameters.Size), 1, 100)
end

local function create(): (Values.TextParameters, number?) -> unknown
	preload()
	return function(parameters: Values.TextParameters, unwrappedWidth: number?): unknown
		local model, size = modelFor(parameters)
		local text = if parameters.RichText then plain(parameters.Text) else parameters.Text
		local width, lines
		if unwrappedWidth ~= nil and not parameters.RichText then
			width, lines = model.fit(text, size, unwrappedWidth)
		else
			width, lines = model.wrap(text, size, parameters.Width, parameters.RichText)
		end
		return Datatypes.Vector2.new(width, model.height(size, lines))
	end
end

local function truncator(): (Values.TextParameters, string, number, boolean) -> number?
	preload()
	return function(parameters: Values.TextParameters, mode: string, lines: number, wrapped: boolean): number?
		local model, size = modelFor(parameters)
		local text = if parameters.RichText then plain(parameters.Text) else parameters.Text
		return model.truncate(text, size, parameters.Width, lines, mode, wrapped)
	end
end

local function heights(): (Values.TextParameters, number, number) -> number
	preload()
	return function(parameters: Values.TextParameters, lines: number, spacing: number): number
		local model, size = modelFor(parameters)
		return model.height(size, lines, spacing)
	end
end

return { create = create, truncator = truncator, heights = heights, decode = decode }
