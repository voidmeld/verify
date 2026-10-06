--!strict

local fs = require "@std/fs"
local process = require "@std/process"
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
			local encoded = directory .. "/" .. stem .. ".base64"
			local output = directory .. "/" .. stem .. (if mediaType == "image/png" then ".png" else ".jpg")
			fs.writeStringToFile(encoded, image.data :: string)
			local decoded = process.run { "/usr/bin/base64", "--decode", "-i", encoded, "-o", output }
			fs.remove(encoded)
			assert(decoded.ok, decoded.stderr)
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

return { texts = texts, report = report, saveCapture = saveCapture }
