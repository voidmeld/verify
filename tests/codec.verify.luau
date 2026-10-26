--!strict

local Base64 = require "../src/codec/base64"
local Image = require "../src/codec/image"
local Verify = require "../src/core"

local PNG_HEADER = "\137PNG\r\n\26\n\0\0\0\13IHDR\0\0\1\44\0\0\0\200\8\6\0\0\0"

return function(suite: Verify.Harness)
	suite:suite("base64", function()
		suite:case("encodes every padding length", function(check)
			check:expect(Base64.encode ""):toBe ""
			check:expect(Base64.encode "M"):toBe "TQ=="
			check:expect(Base64.encode "Ma"):toBe "TWE="
			check:expect(Base64.encode "Man"):toBe "TWFu"
			check:expect(Base64.encode "\0\255\128"):toBe "AP+A"
		end)

		suite:case("decodes what it encodes and refuses malformed text", function(check)
			local all = buffer.create(256)
			for value = 0, 255 do
				buffer.writeu8(all, value, value)
			end
			check:expect(Base64.decode(Base64.encode(buffer.tostring(all)))):toBe(buffer.tostring(all))
			check:expect(Base64.decode "TQ=="):toBe "M"
			check:expect(Base64.decode "TWF"):toBe(nil)
			check:expect(Base64.decode "T*Fu"):toBe(nil)
			check:expect(Base64.decode "T=Fu"):toBe(nil)
		end)
	end)

	suite:suite("image", function()
		suite:case("names the media type from the file signature", function(check)
			check:expect(Image.mediaType(PNG_HEADER)):toBe "image/png"
			check:expect(Image.mediaType "\255\216\255\224"):toBe "image/jpeg"
			check:expect(Image.mediaType "GIF89a...."):toBe "image/gif"
			check:expect(Image.mediaType "RIFF\0\0\0\0WEBPVP8 "):toBe "image/webp"
			check:expect(Image.mediaType "<svg/>"):toBe(nil)
		end)

		suite:case("reads the PNG size from IHDR and refuses other bytes", function(check)
			local width, height = Image.pngSize(PNG_HEADER)
			check:expect({ width, height }):toEqual { 300, 200 }
			check:expect((Image.pngSize(string.sub(PNG_HEADER, 1, 20)))):toBe(nil)
			check:expect((Image.pngSize((string.gsub(PNG_HEADER, "IHDR", "IDAT", 1))))):toBe(nil)
		end)
	end)
end
