--!strict

local PNG_SIGNATURE = "\137PNG\r\n\26\n"

local function mediaType(bytes: string): string?
	if string.sub(bytes, 1, 8) == PNG_SIGNATURE then
		return "image/png"
	end
	if string.sub(bytes, 1, 3) == "\255\216\255" then
		return "image/jpeg"
	end
	if string.sub(bytes, 1, 6) == "GIF87a" or string.sub(bytes, 1, 6) == "GIF89a" then
		return "image/gif"
	end
	if string.sub(bytes, 1, 4) == "RIFF" and string.sub(bytes, 9, 12) == "WEBP" then
		return "image/webp"
	end
	return nil
end

local function pngSize(bytes: string): (number?, number?)
	if #bytes < 24 or string.sub(bytes, 1, 8) ~= PNG_SIGNATURE or string.sub(bytes, 13, 16) ~= "IHDR" then
		return nil, nil
	end
	local width, height = string.unpack(">I4I4", bytes, 17)
	return width, height
end

return {
	mediaType = mediaType,
	pngSize = pngSize,
}
