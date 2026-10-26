--!strict

local fs = require "@std/fs"
local Base64 = require "../codec/base64"
local Media = require "../codec/image"
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

local function decodeBase64(text: string): string
	local decoded = Base64.decode((string.gsub(text, "%s", "")))
	assert(decoded ~= nil, "capture image data is not base64")
	return decoded
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
			local mediaType = image.mimeType
			local output = directory .. "/" .. stem .. (if mediaType == "image/png" then ".png" else ".jpg")
			fs.writeStringToFile(output, decodeBase64(image.data))
			assert(Media.mediaType(fs.readFileToString(output)) == mediaType, "capture bytes do not match image type")
			return { reference = output, mediaType = mediaType }
		end
	end
	error("Studio capture returned no image", 0)
end

return { texts = texts, report = report, saveCapture = saveCapture, decodeBase64 = decodeBase64 }
