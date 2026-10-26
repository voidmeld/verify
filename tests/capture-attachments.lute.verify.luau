--!strict

local Test = require "./harness"
local it, expect = Test.it, Test.expect
local fs = require "@std/fs"
local Core = require "../src/core"
local Parts = require "../src/roblox/capture-attachments"
local Disk = require "../src/lute/capture-attachments"
local Wire = require "../src/lute/wire"
local sha256 = require "../src/lute/hash"
local Files = require "../src/lute/files"

local function temporary(own: (() -> ()) -> (), name: string): string
	local directory = Files.claimDirectory(".lute/tmp/" .. name)
	own(function()
		fs.removeDirectory(directory, { recursive = true })
	end)
	return directory
end

local function capture(content: string): { Parts.Artifact }
	local artifacts: { Parts.Artifact } = {}
	local writer = Parts.writer(function(name, _mediaType, text)
		table.insert(artifacts, { name = name, content = text })
	end, sha256, Wire.encode)
	writer.attach("sizes-1.json", "application/json", content)
	writer.finish()
	return artifacts
end

it("capture attachments split a sixteen MiB native result within harness limits and verify it on disk", function(own)
	local content = string.rep("x", 1048571) .. utf8.char(0x1F642) .. string.rep("y", 16 * 1024 * 1024)
	local harness = Core.createHarness { now = os.clock }
	harness:case("native-sized attachment", function(check)
		local writer = Parts.writer(function(name, mediaType, text)
			check:attach(name, mediaType, text)
		end, sha256, Wire.encode)
		writer.attach("sizes-1.json", "application/json", content)
		writer.attach("metrics.json", "application/json", "{}")
		writer.finish()
	end)
	local report =
		Core.decode(Wire.parse(Wire.encode(harness:run { executor = "capture-test", attachments = Parts.limits })))
	expect(report.passed):toBe(1)
	for _, artifact in report.results[1].artifacts do
		local text = assert(artifact.content)
		expect(#text < 1048576):toBe(true)
		expect(utf8.len(text) ~= nil):toBe(true)
	end
	local directory = temporary(own, "capture-attachments") .. "/restored"
	local paths = Disk.write(report.results[1].artifacts, directory)
	local saved = fs.readFileToString(assert(paths["sizes-1.json"]))
	expect(#saved):toBe(#content)
	expect(sha256(saved)):toBe(sha256(content))
	expect(fs.readFileToString(assert(paths["metrics.json"]))):toBe "{}"
	expect(pcall(Disk.write, report.results[1].artifacts, directory)):toBe(false)
end)

it("capture reassembly refuses missing duplicate extra and altered parts", function()
	local original = capture(string.rep("a", 1048576))
	local missing = table.clone(original)
	table.remove(missing, 1)
	expect(pcall(Parts.reassemble, missing, Wire.parse, sha256)):toBe(false)
	local duplicate = table.clone(original)
	table.insert(duplicate, original[1])
	expect(pcall(Parts.reassemble, duplicate, Wire.parse, sha256)):toBe(false)
	local extra = table.clone(original)
	table.insert(extra, { name = "extra", content = "unexpected" })
	expect(pcall(Parts.reassemble, extra, Wire.parse, sha256)):toBe(false)
	local changed = table.clone(original)
	changed[1] = { name = original[1].name, content = string.rep("b", #assert(original[1].content)) }
	expect(pcall(Parts.reassemble, changed, Wire.parse, sha256)):toBe(false)
	changed[1] = { name = original[1].name, content = assert(original[1].content) .. "x" }
	expect(pcall(Parts.reassemble, changed, Wire.parse, sha256)):toBe(false)
end)

it("capture reassembly refuses malformed manifests before writing files", function(own)
	for _, mutate in
		{
			function(manifest: Parts.Manifest)
				manifest.files[1].bytes += 1
			end,
			function(manifest: Parts.Manifest)
				manifest.files[1].sha256 = string.rep("0", 64)
			end,
			function(manifest: Parts.Manifest)
				manifest.files[1].parts[1].bytes += 1
			end,
			function(manifest: Parts.Manifest)
				table.insert(manifest.files[1].parts, manifest.files[1].parts[1])
			end,
			function(manifest: Parts.Manifest)
				table.insert(manifest.files, manifest.files[1])
			end,
			function(manifest: Parts.Manifest)
				manifest.files[1].name = "../escape.json"
			end,
			function(manifest: Parts.Manifest)
				manifest.schemaVersion = 2
			end,
		}
	do
		local artifacts = capture "{}"
		local entry = artifacts[#artifacts]
		local manifest = Wire.parse(assert(entry.content)) :: Parts.Manifest
		mutate(manifest)
		entry.content = Wire.encode(manifest)
		local directory = temporary(own, "refused-capture") .. "/restored"
		expect(pcall(Disk.write, artifacts, directory)):toBe(false)
		expect(fs.exists(directory)):toBe(false)
	end
end)

it("capture writer rejects duplicate files and completion misuse and both native sources compile", function()
	local writer = Parts.writer(function() end, sha256, Wire.encode)
	writer.attach("metrics.json", "application/json", "{}")
	expect(pcall(writer.attach, "metrics.json", "application/json", "{}")):toBe(false)
	writer.finish()
	expect(pcall(writer.finish)):toBe(false)
	expect(pcall(writer.attach, "more.json", "application/json", "{}")):toBe(false)
	local luau = require "@lute/luau"
	expect(pcall(luau.compile, require "../tools/lib/capture-text-metrics")):toBe(true)
	expect(pcall(luau.compile, require "../tools/lib/capture-native-content")):toBe(true)
end)

return nil
