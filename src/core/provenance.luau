--!strict

local Shape = require "./shape"

export type ReviewKind = "visual" | "audio"
export type Hasher = (bytes: string) -> string

export type Build = {
	commit: string,
	tree: string,
	clean: boolean,
	digest: string,
}

export type Subject = {
	runId: string,
	build: Build?,
}

export type Provenance = {
	runId: string,
	caseId: string,
	actor: string?,
	checkpoint: string?,
	build: Build,
	host: string,
	capabilities: { string },
	device: string,
	capturedAt: number,
}

export type Identity = {
	sha256: string?,
	size: number?,
	provenance: Provenance?,
}

export type ReviewBinding = {
	kind: ReviewKind?,
	judged: { string }?,
}

export type Content = { kind: "bytes", bytes: string } | { kind: "path", path: string }
export type Meta = { name: string, mediaType: string?, sha256: string, size: number }
export type Stat = { size: number }

export type Sink = {
	put: (content: Content, meta: Meta) -> (string?, string?),
	get: (reference: string) -> (string?, string?),
	stat: (reference: string) -> (Stat?, string?),
}

export type MemorySink = Sink & {
	blobs: { [string]: string },
	available: boolean,
}

local function sha256(value: unknown): boolean
	return type(value) == "string" and #(value :: string) == 64 and string.match(value :: string, "^[0-9a-f]+$") ~= nil
end

local function optionalSha(value: unknown, label: string): string?
	if value == nil then
		return nil
	end
	if not sha256(value) then
		error(label .. " must be a lowercase hex sha-256", 3)
	end
	return value :: string
end

local function text(value: unknown, label: string): string
	if type(value) ~= "string" or value == "" then
		error(label .. " must be a non-empty string", 3)
	end
	return value
end

local function copyBuild(value: unknown, label: string): Build
	if type(value) ~= "table" then
		error(label .. " must be a table", 3)
	end
	local raw = value :: { [string]: unknown }
	if type(raw.clean) ~= "boolean" then
		error(label .. ".clean must be a boolean", 3)
	end
	return {
		commit = text(raw.commit, label .. ".commit"),
		tree = text(raw.tree, label .. ".tree"),
		clean = raw.clean,
		digest = text(raw.digest, label .. ".digest"),
	}
end

local function copyProvenance(value: unknown, label: string): Provenance
	if type(value) ~= "table" then
		error(label .. " must be a table", 3)
	end
	local raw = value :: { [string]: unknown }
	local actor = if raw.actor == nil then nil else text(raw.actor, label .. ".actor")
	local checkpoint = if raw.checkpoint == nil then nil else text(raw.checkpoint, label .. ".checkpoint")
	if checkpoint ~= nil and actor == nil then
		error(label .. ".checkpoint requires an actor", 3)
	end
	if not Shape.finiteNonnegative(raw.capturedAt) then
		error(label .. ".capturedAt must be a finite non-negative number", 3)
	end
	return {
		runId = text(raw.runId, label .. ".runId"),
		caseId = text(raw.caseId, label .. ".caseId"),
		actor = actor,
		checkpoint = checkpoint,
		build = copyBuild(raw.build, label .. ".build"),
		host = text(raw.host, label .. ".host"),
		capabilities = Shape.copyStrings(raw.capabilities, label .. ".capabilities"),
		device = text(raw.device, label .. ".device"),
		capturedAt = raw.capturedAt :: number,
	}
end

local function copyIdentity(raw: { [string]: unknown }, label: string): Identity
	local digest = optionalSha(raw.sha256, label .. ".sha256")
	local size: number? = nil
	if raw.size ~= nil then
		if not Shape.nonnegativeInteger(raw.size) then
			error(label .. ".size must be a non-negative integer", 3)
		end
		size = raw.size :: number
	end
	local provenance = if raw.provenance ~= nil then copyProvenance(raw.provenance, label .. ".provenance") else nil
	if (digest == nil) ~= (size == nil) then
		error(label .. " must carry sha256 and size together", 3)
	end
	if provenance ~= nil and digest == nil then
		error(label .. ".provenance requires a content identity", 3)
	end
	return { sha256 = digest, size = size, provenance = provenance }
end

local function copyReviewBinding(raw: { [string]: unknown }, label: string): ReviewBinding
	if raw.kind ~= nil and raw.kind ~= "visual" and raw.kind ~= "audio" then
		error(label .. ".kind must be visual or audio", 3)
	end
	local judged: { string }? = nil
	if raw.judged ~= nil then
		judged = {}
		for _, item in Shape.copyStrings(raw.judged, label .. ".judged") do
			if not sha256(item) then
				error(label .. ".judged must contain lowercase hex sha-256 values", 3)
			end
			table.insert(judged :: { string }, item)
		end
	end
	return { kind = raw.kind :: ReviewKind?, judged = judged }
end

local function memorySink(hash: Hasher): MemorySink
	local sink: MemorySink
	local count = 0
	sink = {
		blobs = {},
		available = true,
		put = function(content: Content, meta: Meta): (string?, string?)
			if not sink.available then
				return nil, "sink unavailable"
			end
			if content.kind ~= "bytes" then
				return nil, "memory sink stores bytes only"
			end
			if #content.bytes ~= meta.size or hash(content.bytes) ~= meta.sha256 then
				return nil, "content does not match its declared identity"
			end
			count += 1
			local reference = ("memory:%d:%s"):format(count, meta.sha256)
			sink.blobs[reference] = content.bytes
			return reference, nil
		end,
		get = function(reference: string): (string?, string?)
			if not sink.available then
				return nil, "sink unavailable"
			end
			local bytes = sink.blobs[reference]
			if bytes == nil then
				return nil, "no such artifact"
			end
			return bytes, nil
		end,
		stat = function(reference: string): (Stat?, string?)
			if not sink.available then
				return nil, "sink unavailable"
			end
			local bytes = sink.blobs[reference]
			if bytes == nil then
				return nil, "no such artifact"
			end
			return { size = #bytes }, nil
		end,
	}
	return sink
end

return {
	sha256 = sha256,
	copyBuild = copyBuild,
	copy = copyProvenance,
	identity = copyIdentity,
	reviewBinding = copyReviewBinding,
	memorySink = memorySink,
}
