--!strict

local crypto = require "@lute/crypto"
local fs = require "@std/fs"
local process = require "@std/process"
local Core = require "../core"
local Evidence = require "../evidence"
local Files = require "./files"

export type SealOptions = {
	from: Core.EvidenceSubject?,
	runId: string?,
	build: Core.EvidenceBuild?,
	device: string,
	sink: Core.EvidenceSink?,
	directory: string?,
	now: (() -> number)?,
}

export type ValidateOptions = {
	from: Core.EvidenceSubject?,
	runId: string?,
	build: Evidence.ExpectedBuild?,
	requireClean: boolean?,
	required: { Evidence.Requirement },
	store: Core.EvidenceSink?,
	directory: string?,
	now: (() -> number)?,
	maxAgeSeconds: number?,
	maxSkewSeconds: number?,
	hosts: { string }?,
	capabilities: { string }?,
	attest: { [string]: Evidence.Attestation }?,
}

local DEFAULT_DIRECTORY = ".verify/evidence"

local function sha256(bytes: string): string
	local value = crypto.digest(crypto.hash.sha256, bytes)
	local out: { string } = {}
	for index = 0, buffer.len(value) - 1 do
		table.insert(out, string.format("%02x", buffer.readu8(value, index)))
	end
	return table.concat(out)
end

local function absolute(value: string): string
	return if string.sub(value, 1, 1) == "/" then value else tostring(process.cwd()) .. "/" .. value
end

local function readFile(reference: string): (string?, string?)
	if reference == "" or string.match(reference, "^%a[%w+.-]*:") ~= nil then
		return nil, "reference is not a local file"
	end
	local ok, bytes: unknown = pcall(function(): string
		local path = absolute(reference)
		local metadata = fs.metadata(path)
		assert(metadata.type == "file" and metadata.size > 0, "local reference must be a nonempty regular file")
		return fs.readFileToString(path)
	end)
	if not ok then
		return nil, tostring(bytes)
	end
	return bytes :: string, nil
end

local function localDirectory(directory: string): Core.EvidenceSink
	assert(directory ~= "", "evidence store directory must not be empty")
	local root = absolute(directory)
	Files.ensureDirectory(root)
	local function owned(reference: string): string?
		local name = string.match(reference, "^" .. string.gsub(root, "%p", "%%%0") .. "/([^/]+)$")
		if name == nil or name == "." or name == ".." then
			return nil
		end
		return reference
	end
	local function put(content: Core.EvidenceContent, meta: Core.EvidenceMeta): (string?, string?)
		local bytes: string
		if content.kind == "bytes" then
			bytes = content.bytes
		else
			local read, reason = readFile(content.path)
			if read == nil then
				return nil, reason
			end
			bytes = read
		end
		if #bytes ~= meta.size or sha256(bytes) ~= meta.sha256 then
			return nil, "content does not match its declared identity"
		end
		local suffix = string.match(meta.name, "(%.[%w]+)$") or ""
		local reference = ("%s/%s%s"):format(root, meta.sha256, suffix)
		local ok, failure: unknown = pcall(function()
			if fs.exists(reference) then
				assert(fs.readFileToString(reference) == bytes, "a different artifact already holds this identity")
				return
			end
			fs.writeStringToFile(reference, bytes)
			assert(fs.metadata(reference).size == #bytes, "stored artifact is incomplete")
		end)
		if not ok then
			return nil, tostring(failure)
		end
		return reference, nil
	end
	local function get(reference: string): (string?, string?)
		if owned(reference) == nil then
			return nil, "reference is outside the store"
		end
		local ok, bytes: unknown = pcall(fs.readFileToString, reference)
		if not ok then
			return nil, tostring(bytes)
		end
		return bytes :: string, nil
	end
	local function stat(reference: string): (Core.EvidenceStat?, string?)
		if owned(reference) == nil then
			return nil, "reference is outside the store"
		end
		local ok, size: unknown = pcall(function(): number
			local metadata = fs.metadata(reference)
			assert(metadata.type == "file", "stored artifact is not a regular file")
			return metadata.size
		end)
		if not ok then
			return nil, tostring(size)
		end
		return { size = size :: number }, nil
	end
	return { put = put, get = get, stat = stat }
end

local function seal(report: Core.Report, options: SealOptions): Evidence.Sealed
	return Evidence.seal(report, {
		from = options.from,
		runId = options.runId,
		build = options.build,
		device = options.device,
		now = options.now or os.time,
		hash = sha256,
		read = readFile,
		sink = options.sink or localDirectory(options.directory or DEFAULT_DIRECTORY),
	})
end

local function validate(report: Core.Report, options: ValidateOptions): Evidence.Result
	return Evidence.validate(report, {
		from = options.from,
		runId = options.runId,
		build = options.build,
		requireClean = options.requireClean,
		required = options.required,
		now = options.now or os.time,
		maxAgeSeconds = options.maxAgeSeconds,
		maxSkewSeconds = options.maxSkewSeconds,
		hosts = options.hosts,
		capabilities = options.capabilities,
		attest = options.attest,
		store = options.store or localDirectory(options.directory or DEFAULT_DIRECTORY),
		hash = sha256,
	})
end

return {
	DEFAULT_DIRECTORY = DEFAULT_DIRECTORY,
	sha256 = sha256,
	readFile = readFile,
	localDirectory = localDirectory,
	seal = seal,
	validate = validate,
}
