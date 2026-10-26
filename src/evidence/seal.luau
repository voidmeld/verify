--!strict

local Provenance = require "../core/provenance"
local Report = require "../core/report"
local Types = require "../core/types"

type Artifact = Types.Artifact

export type Subject = Provenance.Subject

export type Issue = { code: string, subject: string, detail: string }

export type SealOptions = {
	from: Provenance.Subject?,
	runId: string?,
	build: Provenance.Build?,
	device: string,
	now: () -> number,
	hash: Provenance.Hasher,
	read: (reference: string) -> (string?, string?),
	sink: Provenance.Sink,
}

export type Sealed = { report: Types.Report, issues: { Issue } }

export type ReviewBinding = {
	caseId: string,
	actor: string,
	checkpoint: string,
	kind: Provenance.ReviewKind,
	judged: { string },
}

local function seal(report: Types.Report, options: SealOptions): Sealed
	local runId = if options.runId ~= nil then options.runId elseif options.from ~= nil then options.from.runId else ""
	local source = if options.build ~= nil then options.build elseif options.from ~= nil then options.from.build else nil
	assert(runId ~= "" and options.device ~= "", "sealing needs a run id and a device class")
	assert(source ~= nil, "sealing needs the build, directly or from an outcome that carries one")
	local build = Provenance.copyBuild(source, "build")
	local copy = Report.decode(report)
	local issues: { Issue } = {}
	local function one(artifact: Artifact, caseId: string, actor: string?, checkpoint: string?, origin: Types.Origin)
		local subject = caseId
			.. (if actor then " / " .. actor else "")
			.. (if checkpoint then " / " .. checkpoint else "")
			.. " / "
			.. artifact.name
		local function refuse(code: string, detail: string)
			table.insert(issues, { code = code, subject = subject, detail = detail })
		end
		local readOk, bytes, readReason = pcall(options.read, artifact.reference)
		if not readOk or bytes == nil or bytes == "" then
			refuse("unreadable", tostring(if readOk then readReason or "artifact is empty" else bytes))
			return
		end
		local hashOk, digest = pcall(options.hash, bytes)
		if not hashOk or not Provenance.sha256(digest) then
			refuse("hash_failed", "the hash binding did not return a lowercase hex sha-256")
			return
		end
		local meta: Provenance.Meta = {
			name = artifact.name,
			mediaType = artifact.mediaType,
			sha256 = digest,
			size = #bytes,
		}
		local content: Provenance.Content = { kind = "bytes", bytes = bytes }
		local putOk, reference, putReason = pcall(options.sink.put, content, meta)
		if not putOk or reference == nil then
			refuse("sink_unavailable", tostring(if putOk then putReason or "sink refused the artifact" else reference))
			return
		end
		local statOk, stat = pcall(function(): Provenance.Stat?
			local found = options.sink.stat(reference)
			return found
		end)
		if not statOk or stat == nil or stat.size ~= #bytes then
			refuse("sink_unavailable", "the sink could not confirm the stored artifact")
			return
		end
		local at = options.now()
		if not (type(at) == "number" and at == at and at >= 0 and at < math.huge) then
			refuse("clock_invalid", "the injected clock returned a non-finite or negative time")
			return
		end
		artifact.reference = reference
		artifact.sha256 = digest
		artifact.size = #bytes
		artifact.provenance = {
			runId = runId,
			caseId = caseId,
			actor = actor,
			checkpoint = checkpoint,
			build = table.clone(build),
			host = origin.executor,
			capabilities = table.clone(origin.capabilities),
			device = options.device,
			capturedAt = at,
		}
	end
	for _, result in copy.results do
		for _, artifact in result.artifacts do
			one(artifact, result.id, nil, nil, result.origin)
		end
		if result.evidence ~= nil then
			for _, checkpoint in result.evidence.checkpoints do
				for _, artifact in checkpoint.artifacts do
					one(artifact, result.id, checkpoint.actor, checkpoint.name, result.origin)
				end
			end
		end
	end
	return { report = copy, issues = issues }
end

local function bindReview(report: Types.Report, binding: ReviewBinding): Types.Report
	assert(#binding.judged > 0, "a review must name the artifacts it judged")
	for _, digest in binding.judged do
		assert(Provenance.sha256(digest), "judged artifacts are named by lowercase hex sha-256")
	end
	local copy = Report.decode(report)
	local bound = 0
	for _, result in copy.results do
		if result.id == binding.caseId and result.evidence ~= nil then
			for _, review in result.evidence.reviews do
				if review.actor == binding.actor and review.checkpoint == binding.checkpoint then
					review.kind = binding.kind
					review.judged = table.clone(binding.judged)
					bound += 1
				end
			end
		end
	end
	assert(bound > 0, "no recorded review matches the binding")
	return copy
end

return { seal = seal, bindReview = bindReview }
