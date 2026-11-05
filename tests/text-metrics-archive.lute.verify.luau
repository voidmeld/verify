--!strict

local Test = require "./harness"
local it, expect = Test.it, Test.expect
local fs = require "@std/fs"
local json = require "@std/json"
local Archive = require "../src/lute/text-metrics-archive"
local NativeMetrics = require "../src/lute/text-metrics"
local Metrics = require "../src/roblox/text-metrics"
local hash = require "../src/lute/hash"
local Wire = require "../src/lute/wire"

local function fingerprint(face: Metrics.Face): string
	local values = { face.pixelScale or 1, #face.tokens, #face.pairs, #face.sizes }
	for _, pair in face.pairs do
		table.insert(values, pair[1])
		table.insert(values, pair[2])
	end
	local function append(array: { number }?)
		table.insert(values, if array then #array else -1)
		if array then
			for _, value in array do
				table.insert(values, value)
			end
		end
	end
	for _, row in face.sizes do
		table.insert(values, row.height or -1)
		append(row.advances)
		append(row.adjustments)
		append(row.starts)
		append(row.ends)
	end
	local bytes = buffer.create(#values * 8)
	for index, value in values do
		buffer.writef64(bytes, (index - 1) * 8, value)
	end
	local tokens: json.Array = {}
	for _, token in face.tokens do
		table.insert(tokens, token)
	end
	return hash(json.serialize(tokens) .. buffer.tostring(bytes))
end

local EXPECTED = {
	["BuilderSans-Bold-Normal"] = "546a47cb29f4a33d0781613e62cd07db6f899ccca39da769a46d43e93a8531a8",
	["BuilderSans-Medium-Normal"] = "2ab35964b2d722d547f250ae6b6d94146e966752d7fd686d33c6a5621339d60b",
	["BuilderSans-Regular-Normal"] = "7b03df6a68c46b5bcb52a627c4e185b2c251e8d0d31df607848b85ab7f74c24b",
	["BuilderSans-SemiBold-Normal"] = "631664dc9b93fa7107aab8beacc78e67ecd9df9b66b6cac07b74710b6ff3ce07",
	["Fondamento-Bold-Normal"] = "18dec20af64ae0f6505cbd9354c2825f130b5d72c5c7484fe281e3149b48c92b",
	["Fondamento-Medium-Normal"] = "18dec20af64ae0f6505cbd9354c2825f130b5d72c5c7484fe281e3149b48c92b",
	["Fondamento-Regular-Normal"] = "18dec20af64ae0f6505cbd9354c2825f130b5d72c5c7484fe281e3149b48c92b",
	["Fondamento-SemiBold-Normal"] = "18dec20af64ae0f6505cbd9354c2825f130b5d72c5c7484fe281e3149b48c92b",
	["GothamSSm-Bold-Normal"] = "c7fca7509892241e24aa57bb85fae9a607cce09c9f9a2af6ded16fbf5a9a7907",
	["GothamSSm-Medium-Normal"] = "53d1eedc8dc2ed167e37ffe6df4438a34e7351367bcfecf2ea5cd0c8386391e4",
	["Guru-Regular-Normal"] = "e98eb66151a7fad36f0f99df22f4f05dd1e67aa40224486fa1cfcce467231a63",
	["LegacyArial-Regular-Normal"] = "69c3d5fb265438c667106273f8c11d4d8a54db3c61d05f3fffc94c84533e0774",
	["Michroma-Bold-Normal"] = "c841f444efc3ed88da974f0da8069d8e8342dfa1245815d33d00fef56ec18cb4",
	["Michroma-Medium-Normal"] = "c841f444efc3ed88da974f0da8069d8e8342dfa1245815d33d00fef56ec18cb4",
	["Michroma-Regular-Normal"] = "c841f444efc3ed88da974f0da8069d8e8342dfa1245815d33d00fef56ec18cb4",
	["Michroma-SemiBold-Normal"] = "c841f444efc3ed88da974f0da8069d8e8342dfa1245815d33d00fef56ec18cb4",
	["Nunito-Bold-Normal"] = "53c4f6b46c894e8a1834635d2ab0e6edd0aed0136ff1b632eefd4a373c97c489",
	["Nunito-Medium-Normal"] = "066a628f28a6939288f8a01194d2a7485a0bbf4d397f0016f53725eaf1cfb3d5",
	["Nunito-Regular-Normal"] = "066a628f28a6939288f8a01194d2a7485a0bbf4d397f0016f53725eaf1cfb3d5",
	["Nunito-SemiBold-Normal"] = "a0f09a73e8bc405fed08c47b4055c31f879dc2954373f7e3fc32394bd9846a41",
	["RobotoMono-Regular-Normal"] = "0d82f3b375a705e7d95423de7d05fc4a15d2e6db376699dedc56995be7912b87",
	["SourceSansPro-Bold-Normal"] = "f62618495fd5a39736315e7bcab1ce9d99b41286e11a5c122b7f5880f532e862",
	["SourceSansPro-Regular-Normal"] = "cd36e8c2dbb0da1ef11e7a80b6059ad2d182e24b1f800983824fdf4144309537",
	["SourceSansPro-SemiBold-Normal"] = "4179899e84e147635bb7ea1b503999f06cc52168ed862302a631c52d1a20d02c",
}

it("preserves every captured token and float64 metric across all 24 faces", function()
	local faces = Archive.open(fs.readFileToString "src/lute/fixtures/text/metrics.json")
	local count = 0
	for name, read in faces do
		local face, key = NativeMetrics.decode(read())
		local family, weight, style = name:match "^(%w+)%-(%w+)%-(%w+)$"
		expect(key):toBe(`rbxasset://fonts/families/{family}.json/{weight}/{style}`)
		expect(fingerprint(face)):toBe(EXPECTED[name])
		count += 1
	end
	expect(count):toBe(24)
end)

local function capture(): json.Object
	return assert(json.asObject(json.deserialize [=[{
		"family":"rbxasset://fonts/families/Test.json","weight":"Regular","style":"Normal",
		"engineVersion":"captured","calls":123,"pixelScale":0.6666666865348816,
		"tokens":["A","é"],"pairs":[[1,2],[2,1]],
		"sizes":[
			{"height":1.25,"advances":[1.5,1.5],"adjustments":[-0.015625,0],"starts":[0,0]},
			{"height":2.5,"advances":[3,3],"adjustments":[-0.03125,0],"ends":[0,0]}
		]
	}]=]))
end

it("shares identical columns and faces while preserving metadata and optional boundaries", function()
	local original = capture()
	local packed = Archive.pack { first = original, second = original }
	local root = assert(json.asObject(json.deserialize(packed)))
	local single = assert(json.asObject(json.deserialize(Archive.pack { first = original })))
	expect(#assert(json.asArray(root.vectors))):toBe(#assert(json.asArray(single.vectors)))
	local faces = Archive.open(packed)
	for _, name in { "first", "second" } do
		expect(Wire.parse(json.serialize(faces[name]()))):toEqual(Wire.parse(json.serialize(original)))
	end
end)

it("decodes raw capture JSON and archived rows into the same face and key", function()
	local original = capture()
	local rows = assert(json.asArray(original.sizes))
	local sizes: json.Array = {}
	for index = 1, 100 do
		table.insert(sizes, rows[(index - 1) % #rows + 1])
	end
	original.sizes = sizes
	local before, beforeKey = NativeMetrics.decode(json.serialize(original))
	local after, afterKey = NativeMetrics.decode(Archive.open(Archive.pack { captured = original }).captured())
	expect(after):toEqual(before)
	expect(afterKey):toBe(beforeKey)
end)

it("rejects missing fractional and out-of-range vector references and truncated columns", function()
	local packed = Archive.pack { first = capture() }
	for _, reference in { 0, 0.5, 10000 } do
		local root = assert(json.asObject(json.deserialize(packed)))
		local faces = assert(json.asObject(root.faces))
		assert(json.asObject(faces.first)).tokens = reference
		expect(pcall(function()
			Archive.open(json.serialize(root)).first()
		end)):toBe(false)
	end
	local root = assert(json.asObject(json.deserialize(packed)))
	local vectors = assert(json.asArray(root.vectors))
	local truncated: json.Array = { 1 }
	vectors[1] = truncated
	expect(pcall(function()
		Archive.open(json.serialize(root)).first()
	end)):toBe(false)
end)

return nil
