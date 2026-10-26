--!strict
return [====[
local Parts = require(root.src.roblox["capture-attachments"])
local function sha256(text)
 local bytes = game:GetService("EncodingService"):ComputeStringHash(text, Enum.HashAlgorithm.Sha256)
 return (bytes:gsub(".", function(byte) return string.format("%02x", string.byte(byte)) end))
end
local function captureAttachments(check)
 return Parts.writer(function(name, mediaType, content) check:attach(name, mediaType, content) end,
  sha256, function(value) return game:GetService("HttpService"):JSONEncode(value) end)
end
]====]
