--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Base64 = require "../src/codec/base64"
local Image = require "../src/codec/image"

local PNG_HEADER = "\137PNG\r\n\26\n\0\0\0\13IHDR\0\0\1\44\0\0\0\200\8\6\0\0\0"

describe("base64", function()
	it("encodes every padding length", function()
		expect(Base64.encode ""):toBe ""
		expect(Base64.encode "M"):toBe "TQ=="
		expect(Base64.encode "Ma"):toBe "TWE="
		expect(Base64.encode "Man"):toBe "TWFu"
		expect(Base64.encode "\0\255\128"):toBe "AP+A"
	end)

	it("decodes what it encodes and refuses malformed text", function()
		local all = buffer.create(256)
		for value = 0, 255 do
			buffer.writeu8(all, value, value)
		end
		expect(Base64.decode(Base64.encode(buffer.tostring(all)))):toBe(buffer.tostring(all))
		expect(Base64.decode "TQ=="):toBe "M"
		expect(Base64.decode "TWF"):toBe(nil)
		expect(Base64.decode "T*Fu"):toBe(nil)
		expect(Base64.decode "T=Fu"):toBe(nil)
	end)
end)

describe("image", function()
	it("names the media type from the file signature", function()
		expect(Image.mediaType(PNG_HEADER)):toBe "image/png"
		expect(Image.mediaType "\255\216\255\224"):toBe "image/jpeg"
		expect(Image.mediaType "GIF89a...."):toBe "image/gif"
		expect(Image.mediaType "RIFF\0\0\0\0WEBPVP8 "):toBe "image/webp"
		expect(Image.mediaType "<svg/>"):toBe(nil)
	end)

	it("reads the PNG size from IHDR and refuses other bytes", function()
		local width, height = Image.pngSize(PNG_HEADER)
		expect({ width, height }):toEqual { 300, 200 }
		expect((Image.pngSize(string.sub(PNG_HEADER, 1, 20)))):toBe(nil)
		expect((Image.pngSize((string.gsub(PNG_HEADER, "IHDR", "IDAT", 1))))):toBe(nil)
	end)
end)

return nil
