--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local Core = require "../core"
local Attachment = require "../core/attachment"
local EvidenceStore = require "./evidence-store"
local Files = require "./files"

export type Meta = { mediaType: string, sha256: string, size: number }
export type Sink = (caseId: string, name: string, text: string, meta: Meta) -> (string?, string?)

export type Options = {
	directory: string,
	sink: Sink?,
	limits: Attachment.Limits?,
	supported: boolean?,
	host: string?,
}

local function absolute(value: string): string
	return if string.sub(value, 1, 1) == "/" then value else tostring(process.cwd()) .. "/" .. value
end

local function safeSegment(value: string): string
	return string.sub(string.gsub(value, "[^%w._-]", "_"), 1, 80)
end

local function directorySink(directory: string): Sink
	local root = absolute(directory) .. "/attachments"
	return function(caseId: string, name: string, text: string, meta: Meta): (string?, string?)
		local path = root .. "/" .. safeSegment(caseId) .. "/" .. name
		local ok, failure: unknown = pcall(function()
			local parent = string.match(path, "^(.*)/[^/]+$") :: string
			Files.ensureDirectory(parent)
			fs.writeStringToFile(path, text)
			assert(fs.metadata(path).size == meta.size, "attachment copy is incomplete")
		end)
		if not ok then
			return nil, tostring(failure)
		end
		return path, nil
	end
end

local function materialize(report: Core.Report, options: Options): (Core.Report, { string })
	local limits = Attachment.resolve(options.limits)
	local sink = options.sink or directorySink(options.directory)
	local copy = Core.decode(report)
	local issues: { string } = {}
	local total = 0
	for _, result in copy.results do
		local kept: { Core.Artifact } = {}
		local names: { [string]: boolean } = {}
		local count = 0
		for _, artifact in result.artifacts do
			local text = artifact.content
			if text == nil then
				table.insert(kept, artifact)
				continue
			end
			local function refuse(reason: string)
				table.insert(issues, ("%s: %s"):format(result.id, reason))
			end
			if options.supported == false then
				refuse(
					("attachment %q is unsupported on host %s and was not delivered"):format(
						artifact.name,
						options.host or "unknown"
					)
				)
				continue
			end
			local mediaType = artifact.mediaType or ""
			local problem = Attachment.check(artifact.name, mediaType, text, limits)
			if problem == nil and names[artifact.name] then
				problem = ("attachment %q is already attached to this case"):format(artifact.name)
			end
			if problem == nil and count >= limits.maxCount then
				problem = ("attachment %q exceeds the per-case count limit of %d"):format(
					artifact.name,
					limits.maxCount
				)
			end
			if problem == nil and total + #text > limits.maxTotalBytes then
				problem = ("attachment %q exceeds the per-report limit of %d bytes"):format(
					artifact.name,
					limits.maxTotalBytes
				)
			end
			if problem ~= nil then
				refuse(problem)
				continue
			end
			local meta: Meta = { mediaType = mediaType, sha256 = EvidenceStore.sha256(text), size = #text }
			local ok, reference, reason = pcall(sink, result.id, artifact.name, text, meta)
			if not ok or reference == nil then
				refuse(
					("attachment %q was not stored: %s"):format(
						artifact.name,
						tostring(if ok then reason else reference)
					)
				)
				continue
			end
			names[artifact.name] = true
			count += 1
			total += #text
			table.insert(kept, {
				name = artifact.name,
				reference = reference,
				mediaType = mediaType,
				sha256 = meta.sha256,
				size = meta.size,
			})
		end
		result.artifacts = kept
	end
	return copy, issues
end

return { materialize = materialize, directorySink = directorySink }
