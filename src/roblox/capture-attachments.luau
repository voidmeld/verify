--!strict

export type Part = { name: string, bytes: number, sha256: string }
export type File = { name: string, mediaType: string, bytes: number, sha256: string, parts: { Part } }
export type Manifest = { schemaVersion: number, files: { File } }
export type Artifact = { name: string, content: string? }
export type Writer = { attach: (string, string, string) -> (), finish: () -> () }

local MANIFEST = "capture-attachments.json"
local PART_BYTES = 1048572
local LIMITS = { maxBytes = 1048576, maxCount = 4097, maxTotalBytes = 268435456 }

local function name(value: string)
	assert(
		value ~= "" and value ~= "." and value ~= ".." and #value <= 160 and string.match(value, "^[%w_.%-]+$"),
		"invalid capture attachment name"
	)
end

local function digest(value: string): string
	assert(#value == 64 and string.match(value, "^[0-9a-f]+$"), "capture requires a SHA-256 hex digest")
	return value
end

local function writer(
	emit: (string, string, string) -> (),
	sha256: (string) -> string,
	encode: (unknown) -> string
): Writer
	local files: { File } = {}
	local seen: { [string]: boolean } = {}
	local count, total, finished = 0, 0, false
	return {
		attach = function(filename, mediaType, content)
			assert(not finished, "capture attachments are finished")
			name(filename)
			assert(not seen[filename], "duplicate capture attachment")
			assert(
				mediaType ~= "" and content ~= "" and utf8.len(content) ~= nil,
				"capture attachments require nonempty UTF-8 text and a media type"
			)
			assert(
				total + #content < LIMITS.maxTotalBytes - LIMITS.maxBytes,
				"capture attachments exceed the total byte limit"
			)
			seen[filename], total = true, total + #content
			local file: File = {
				name = filename,
				mediaType = mediaType,
				bytes = #content,
				sha256 = digest(sha256(content)),
				parts = {},
			}
			local first = 1
			while first <= #content do
				local last = math.min(first + PART_BYTES - 1, #content)
				while
					last < #content
					and string.byte(content, last + 1) >= 128
					and string.byte(content, last + 1) <= 191
				do
					last -= 1
				end
				count += 1
				assert(count < LIMITS.maxCount, "capture attachments exceed the part count limit")
				local part = content:sub(first, last)
				local partName = string.format("capture-part-%06d.txt", count)
				table.insert(file.parts, { name = partName, bytes = #part, sha256 = digest(sha256(part)) })
				emit(partName, "text/plain", part)
				first = last + 1
			end
			table.insert(files, file)
		end,
		finish = function()
			assert(not finished and #files > 0, "capture attachments are finished or empty")
			finished = true
			local encoded = encode { schemaVersion = 1, files = files }
			assert(#encoded < LIMITS.maxBytes, "capture manifest exceeds the byte limit")
			emit(MANIFEST, "application/json", encoded)
		end,
	}
end

local function reassemble<A>(
	artifacts: { A },
	decode: (string) -> unknown,
	sha256: (string) -> string
): { [string]: string }
	local parts: { [string]: string } = {}
	for _, entry in artifacts do
		local artifact = (entry :: unknown) :: Artifact
		assert(parts[artifact.name] == nil, "duplicate capture part")
		local content = assert(artifact.content, "capture part has no content")
		assert(
			#content > 0 and #content < LIMITS.maxBytes and utf8.len(content) ~= nil,
			"invalid capture part size or UTF-8"
		)
		parts[artifact.name] = content
	end
	local manifest = decode((assert(parts[MANIFEST], "missing capture manifest"))) :: Manifest
	assert(
		type(manifest) == "table"
			and manifest.schemaVersion == 1
			and type(manifest.files) == "table"
			and #manifest.files > 0,
		"invalid capture manifest"
	)
	local used: { [string]: boolean } = { [MANIFEST] = true }
	local output: { [string]: string } = {}
	local total = 0
	for _, file in manifest.files do
		name(file.name)
		assert(output[file.name] == nil, "duplicate captured file")
		assert(type(file.mediaType) == "string" and file.mediaType ~= "", "invalid capture media type")
		assert(
			type(file.bytes) == "number"
				and file.bytes > 0
				and file.bytes % 1 == 0
				and file.bytes < LIMITS.maxTotalBytes,
			"invalid capture byte count"
		)
		assert(type(file.parts) == "table" and #file.parts > 0, "capture has no parts")
		local chunks: { string } = {}
		for _, part in file.parts do
			assert(not used[part.name], "duplicate capture manifest part")
			used[part.name] = true
			local content = assert(parts[part.name], "missing capture part: " .. part.name)
			assert(
				#content == part.bytes and sha256(content) == digest(part.sha256),
				"capture part byte count or SHA-256 differs"
			)
			table.insert(chunks, content)
		end
		local content = table.concat(chunks)
		assert(
			#content == file.bytes and sha256(content) == digest(file.sha256),
			"capture file byte count or SHA-256 differs"
		)
		total += #content
		assert(total < LIMITS.maxTotalBytes, "capture exceeds the total byte limit")
		output[file.name] = content
	end
	for part in parts do
		assert(used[part], "unexpected capture part")
	end
	return output
end

return { writer = writer, reassemble = reassemble, limits = LIMITS }
