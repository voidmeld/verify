--!strict

local fs = require "@std/fs"
local Core = require "../core"
local Channel = require "../roblox/report-channel"
local Mcp = require "./studio-mcp"
local Wire = require "./wire"

export type Image = { reference: string, mediaType: string }

local function texts(result: unknown): string
	local content = Mcp.record(result).content
	assert(type(content) == "table", "Studio MCP response has no content")
	local chunks: { string } = {}
	for _, value in content :: { unknown } do
		local block = Mcp.record(value)
		if block.type == "text" and type(block.text) == "string" then
			table.insert(chunks, block.text)
		end
	end
	return table.concat(chunks, "\n")
end

local function find(value: unknown, runId: string): Core.Report?
	if type(value) == "string" then
		local parsed, object = pcall(Wire.parse, value)
		if parsed then
			return find(object, runId)
		end
	elseif type(value) == "table" then
		local object = value :: { [unknown]: unknown }
		if object.runId ~= nil then
			return Channel.receive(value, runId)
		end
		for _, child in object do
			local report = find(child, runId)
			if report ~= nil then
				return report
			end
		end
	end
	return nil
end

local function report(payload: string, runId: string): Core.Report?
	return find(Wire.parse(payload), runId)
end

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local SEXTETS: { [number]: number } = {}
for index = 1, #ALPHABET do
	SEXTETS[string.byte(ALPHABET, index)] = index - 1
end

local function decodeBase64(text: string): string
	local compact = string.gsub(text, "%s", "")
	assert(#compact % 4 == 0, "capture image data is not base64")
	local padding = if string.sub(compact, -2) == "==" then 2 elseif string.sub(compact, -1) == "=" then 1 else 0
	local size = #compact // 4 * 3 - padding
	local output = buffer.create(size)
	local written = 0
	for offset = 1, #compact, 4 do
		local group = 0
		for position = 0, 3 do
			local byte = string.byte(compact, offset + position)
			local value = SEXTETS[byte]
			if value == nil then
				assert(byte == 61 and offset + position > #compact - padding, "capture image data is not base64")
				value = 0
			end
			group = group * 64 + value
		end
		for shift = 16, 0, -8 do
			if written < size then
				buffer.writeu8(output, written, bit32.band(bit32.rshift(group, shift), 255))
				written += 1
			end
		end
	end
	return buffer.tostring(output)
end

local function saveCapture(result: unknown, directory: string, stem: string): Image
	local content = Mcp.record(result).content
	assert(type(content) == "table", "capture returned no image content")
	for _, item in content :: { unknown } do
		local image = Mcp.record(item)
		if image.type == "image" then
			assert(
				type(image.data) == "string" and (image.mimeType == "image/png" or image.mimeType == "image/jpeg"),
				"capture returned unsupported image data"
			)
			local mediaType = image.mimeType :: string
			local output = directory .. "/" .. stem .. (if mediaType == "image/png" then ".png" else ".jpg")
			fs.writeStringToFile(output, decodeBase64(image.data :: string))
			local bytes = fs.readFileToString(output)
			assert(
				(mediaType == "image/png" and bytes:sub(1, 8) == "\137PNG\r\n\26\n")
					or (mediaType == "image/jpeg" and bytes:sub(1, 3) == "\255\216\255"),
				"capture bytes do not match image type"
			)
			return { reference = output, mediaType = mediaType }
		end
	end
	error("Studio capture returned no image", 0)
end

return { texts = texts, report = report, saveCapture = saveCapture, decodeBase64 = decodeBase64 }
