--!strict

local Capability = require "../core/capability"
local Provenance = require "../core/provenance"
local Shape = require "../core/shape"
local Types = require "../core/types"

type Artifact = Types.Artifact
type Checkpoint = Types.Checkpoint
type CaseResult = Types.CaseResult

export type Issue = { code: string, subject: string, detail: string }

export type Expected = {
	digest: string,
	commit: string?,
	tree: string?,
	requireClean: boolean?,
}

export type Requirement = {
	caseId: string,
	actors: { string },
	checkpoints: { string },
	devices: { string },
	mediaType: string?,
	reviews: { Provenance.ReviewKind }?,
}

export type Cell = {
	caseId: string,
	actor: string,
	checkpoint: string,
	device: string,
	mediaType: string?,
	reviews: { Provenance.ReviewKind }?,
}

export type Attestation = (artifact: Artifact, provenance: Provenance.Provenance) -> boolean

export type Policy = {
	from: Provenance.Subject?,
	runId: string?,
	build: Expected?,
	requireClean: boolean?,
	now: () -> number,
	maxAgeSeconds: number?,
	maxSkewSeconds: number?,
	hosts: { string }?,
	capabilities: { string }?,
	required: { Requirement },
	attest: { [string]: Attestation }?,
	store: { get: (reference: string) -> (string?, string?), stat: (reference: string) -> (Provenance.Stat?, string?) },
	hash: Provenance.Hasher,
}

export type Result = { ok: boolean, issues: { Issue }, verified: number }

local MEDIA_PREFIXES: { [string]: { string } } = {
	visual = { "image/", "video/" },
	audio = { "audio/", "video/" },
}

local function matchesKind(artifact: Artifact, kind: string): boolean
	local mediaType = artifact.mediaType
	if mediaType == nil then
		return false
	end
	local prefixes: { string } = MEDIA_PREFIXES[kind]
	for _, prefix in prefixes do
		if string.sub(mediaType, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

local function strings(values: { string }, label: string): { string }
	assert(#values > 0, label .. " must not be empty")
	for _, value in values do
		assert(type(value) == "string" and value ~= "", label .. " must contain only non-empty strings")
	end
	return values
end

local function contains(values: { string }, wanted: string): boolean
	return table.find(values, wanted) ~= nil
end

local function checkedRequirement(requirement: Requirement)
	assert(requirement.caseId ~= "", "a requirement needs a case id")
	strings(requirement.actors, "requirement actors")
	strings(requirement.checkpoints, "requirement checkpoints")
	strings(requirement.devices, "requirement devices")
end

local function expand(required: { Requirement }): { Cell }
	assert(#required > 0, "required coverage must not be empty")
	local cells: { Cell } = {}
	for _, requirement in required do
		checkedRequirement(requirement)
		for _, actor in requirement.actors do
			for _, checkpoint in requirement.checkpoints do
				for _, device in requirement.devices do
					table.insert(cells, {
						caseId = requirement.caseId,
						actor = actor,
						checkpoint = checkpoint,
						device = device,
						mediaType = requirement.mediaType,
						reviews = requirement.reviews,
					})
				end
			end
		end
	end
	return cells
end

local DEFAULT_MAX_AGE_SECONDS = 3600
local DEFAULT_MAX_SKEW_SECONDS = 5

local function validate(report: Types.Report, policy: Policy): Result
	local maxAge = if policy.maxAgeSeconds ~= nil then policy.maxAgeSeconds else DEFAULT_MAX_AGE_SECONDS
	local maxSkew = if policy.maxSkewSeconds ~= nil then policy.maxSkewSeconds else DEFAULT_MAX_SKEW_SECONDS
	assert(Shape.finiteNonnegative(maxAge) and maxAge > 0, "maxAgeSeconds must be a positive finite number")
	assert(Shape.finiteNonnegative(maxSkew), "maxSkewSeconds must be a finite non-negative number")
	local expectedRun = if policy.runId ~= nil
		then policy.runId
		elseif policy.from ~= nil then policy.from.runId
		else nil
	local expected: Expected? = policy.build
	if expected == nil and policy.from ~= nil and policy.from.build ~= nil then
		local subject = Provenance.copyBuild(policy.from.build, "from.build")
		expected = {
			digest = subject.digest,
			commit = subject.commit,
			tree = subject.tree,
			requireClean = policy.requireClean ~= false,
		}
	end
	assert(expected ~= nil, "validation needs the expected build, directly or from an outcome that carries one")
	assert(expected.digest ~= "", "the expected build needs a digest")
	local requireClean = if expected.requireClean ~= nil then expected.requireClean else policy.requireClean ~= false
	assert(#policy.required > 0, "required coverage must not be empty")
	local now = policy.now()
	assert(Shape.finiteNonnegative(now), "the injected clock must return a finite non-negative time")
	for _, requirement in policy.required do
		checkedRequirement(requirement)
	end

	local issues: { Issue } = {}
	local reported: { [string]: boolean } = {}
	local function refuse(code: string, subject: string, detail: string)
		local key = code .. "\0" .. subject .. "\0" .. detail
		if not reported[key] then
			reported[key] = true
			table.insert(issues, { code = code, subject = subject, detail = detail })
		end
	end

	local cases: { [string]: CaseResult } = {}
	local conflicted: { [string]: boolean } = {}
	for _, result in report.results do
		if cases[result.id] ~= nil then
			conflicted[result.id] = true
		end
		cases[result.id] = result
	end

	local verdicts: { [Artifact]: boolean } = {}
	local function intact(artifact: Artifact, subject: string): boolean
		local reference = artifact.reference
		local statOk, stat, statReason = pcall(policy.store.stat, reference)
		if not statOk or stat == nil then
			refuse("unavailable", subject, tostring(if statOk then statReason or "artifact is not stored" else stat))
			return false
		end
		if stat.size ~= artifact.size then
			refuse(
				"changed",
				subject,
				("stored size %d differs from recorded %s"):format(stat.size, tostring(artifact.size))
			)
			return false
		end
		local getOk, bytes, getReason = pcall(policy.store.get, reference)
		if not getOk or bytes == nil then
			refuse("unavailable", subject, tostring(if getOk then getReason or "artifact is not readable" else bytes))
			return false
		end
		local hashOk, digest = pcall(policy.hash, bytes)
		if not hashOk then
			refuse("hash_failed", subject, "the hash binding failed")
			return false
		end
		if #bytes ~= artifact.size or digest ~= artifact.sha256 then
			refuse("changed", subject, "stored bytes no longer match the recorded sha-256")
			return false
		end
		return true
	end

	for _, result in report.results do
		for _, artifact in result.artifacts do
			if artifact.sha256 ~= nil then
				intact(artifact, result.id .. " / " .. artifact.name)
			end
		end
	end

	local function sound(
		artifact: Artifact,
		result: CaseResult,
		actor: string,
		checkpoint: string,
		subject: string
	): boolean
		local known = verdicts[artifact]
		if known ~= nil then
			return known
		end
		local good = true
		local function bad(code: string, detail: string)
			good = false
			refuse(code, subject, detail)
		end
		local provenance = artifact.provenance
		if artifact.sha256 == nil or artifact.size == nil or provenance == nil then
			refuse("missing_identity", subject, "artifact carries no content identity or provenance")
			verdicts[artifact] = false
			return false
		end
		if provenance.caseId ~= result.id or provenance.actor ~= actor or provenance.checkpoint ~= checkpoint then
			bad("wrong_identity", "provenance names a different case, actor or checkpoint than where it is filed")
		end
		if expectedRun ~= nil and provenance.runId ~= expectedRun then
			bad("wrong_run", ("captured by run %s, expected %s"):format(provenance.runId, expectedRun))
		end
		local build = provenance.build
		if
			build.digest ~= expected.digest
			or (expected.commit ~= nil and build.commit ~= expected.commit)
			or (expected.tree ~= nil and build.tree ~= expected.tree)
		then
			bad("build_mismatch", ("captured against build %s, expected %s"):format(build.digest, expected.digest))
		end
		if requireClean and not build.clean then
			bad("build_dirty", "captured from a build with uncommitted changes")
		end
		if policy.hosts ~= nil and not contains(policy.hosts, provenance.host) then
			bad("wrong_host", "host " .. provenance.host .. " is not an accepted host")
		end
		if policy.capabilities ~= nil then
			local negotiation = Capability.negotiate(provenance.capabilities, policy.capabilities)
			if not negotiation.satisfied then
				bad("missing_capability", Capability.explain(negotiation))
			end
		end
		local age = now - provenance.capturedAt
		if age < -maxSkew then
			bad("future_capture", ("captured %.3f seconds after the validation clock"):format(-age))
		elseif age > maxAge then
			bad("stale", ("captured %.3f seconds ago; at most %.3f allowed"):format(age, maxAge))
		end
		local attest = if policy.attest ~= nil then policy.attest[provenance.device] else nil
		if provenance.device == "physical" and attest == nil then
			bad("unattested_device", "physical device proof must be asserted by caller policy with its own evidence")
		elseif attest ~= nil then
			local attestOk, attested = pcall(attest, artifact, provenance)
			if not attestOk or attested ~= true then
				bad("unattested_device", "caller attestation refused device class " .. provenance.device)
			end
		end
		if not intact(artifact, subject) then
			good = false
		end
		verdicts[artifact] = good
		return good
	end

	local scanned: { [Checkpoint]: boolean } = {}
	local function scan(checkpoint: Checkpoint, subject: string)
		if scanned[checkpoint] then
			return
		end
		scanned[checkpoint] = true
		local seen: { [string]: Artifact } = {}
		for _, artifact in checkpoint.artifacts do
			local device = if artifact.provenance ~= nil then artifact.provenance.device else "undeclared"
			local key = artifact.name .. "\0" .. device
			local prior = seen[key]
			if prior ~= nil then
				if prior.sha256 == artifact.sha256 then
					refuse(
						"duplicate_observation",
						subject,
						("artifact %s on %s recorded twice"):format(artifact.name, device)
					)
				else
					refuse(
						"conflicting_observation",
						subject,
						("artifact %s on %s recorded with different content"):format(artifact.name, device)
					)
				end
			end
			seen[key] = artifact
		end
	end

	local verified = 0
	for _, requirement in policy.required do
		local result = cases[requirement.caseId]
		for _, actor in requirement.actors do
			for _, name in requirement.checkpoints do
				for _, device in requirement.devices do
					local subject = ("%s / %s / %s / %s"):format(requirement.caseId, actor, name, device)
					if result == nil then
						refuse("missing_case", subject, "the report has no such case")
						continue
					end
					if conflicted[result.id] then
						refuse("conflicting_case", subject, "the report records this case more than once")
						continue
					end
					if result.status ~= "passed" then
						refuse("case_not_passed", subject, "the case status is " .. result.status)
						continue
					end
					local evidence = result.evidence
					local checkpoint: Checkpoint? = nil
					if evidence ~= nil then
						for _, candidate in evidence.checkpoints do
							if candidate.actor == actor and candidate.name == name then
								checkpoint = candidate
							end
						end
					end
					if evidence == nil or checkpoint == nil then
						refuse("missing_observation", subject, "no checkpoint was recorded for this actor and name")
						continue
					end
					scan(checkpoint, subject)
					local matching: { Artifact } = {}
					local otherDevices: { string } = {}
					for _, artifact in checkpoint.artifacts do
						local provenance = artifact.provenance
						if requirement.mediaType ~= nil and artifact.mediaType ~= requirement.mediaType then
							continue
						end
						if provenance == nil or provenance.device == device then
							table.insert(matching, artifact)
						elseif not contains(otherDevices, provenance.device) then
							table.insert(otherDevices, provenance.device)
						end
					end
					if #matching == 0 then
						refuse(
							if #otherDevices > 0 then "wrong_device" else "missing_observation",
							subject,
							if #otherDevices > 0
								then "observed only on " .. table.concat(otherDevices, ", ")
								else "the checkpoint holds no matching artifact"
						)
						continue
					end
					local kinds: { Provenance.ReviewKind } = requirement.reviews or {}
					local allSound = true
					for _, artifact in matching do
						if not sound(artifact, result, actor, name, subject .. " / " .. artifact.name) then
							allSound = false
						end
					end
					if allSound then
						verified += 1
					end
					for _, kind in kinds do
						local found = 0
						local covered: { [string]: boolean } = {}
						local reviewSubject = subject .. " / " .. kind .. " review"
						for _, review in evidence.reviews do
							if review.actor ~= actor or review.checkpoint ~= name or review.kind ~= kind then
								continue
							end
							found += 1
							if review.judgment.status ~= "passed" then
								refuse(
									"review_not_passed",
									reviewSubject,
									"reviewer " .. review.judgment.reviewer .. " recorded " .. review.judgment.status
								)
							end
							if review.judged == nil or #review.judged == 0 then
								refuse("review_unbound", reviewSubject, "the review names no judged artifact")
								continue
							end
							for _, digest in review.judged do
								covered[digest] = true
							end
						end
						if found == 0 then
							refuse(
								"missing_review",
								reviewSubject,
								"no review of this kind is recorded for the checkpoint"
							)
							continue
						end
						local reviewable = 0
						for _, artifact in matching do
							if matchesKind(artifact, kind) then
								reviewable += 1
								if artifact.sha256 == nil or not covered[artifact.sha256] then
									refuse(
										"review_wrong_artifact",
										reviewSubject,
										"artifact " .. artifact.name .. " was not among the judged content"
									)
								end
							end
						end
						if reviewable == 0 then
							refuse("missing_observation", reviewSubject, "no artifact of this kind exists to review")
						end
						for digest in covered do
							local present = false
							for _, artifact in checkpoint.artifacts do
								if artifact.sha256 == digest then
									present = true
								end
							end
							if not present then
								refuse(
									"review_wrong_artifact",
									reviewSubject,
									"judged content " .. digest .. " is not at this checkpoint"
								)
							end
						end
					end
				end
			end
		end
	end
	return { ok = #issues == 0 and verified > 0, issues = issues, verified = verified }
end

local function explain(result: Result): string
	if result.ok then
		return ("evidence valid: %d observation set(s) verified"):format(result.verified)
	end
	local lines: { string } = { ("evidence rejected: %d issue(s)"):format(#result.issues) }
	for _, issue in result.issues do
		table.insert(lines, ("  %s %s: %s"):format(issue.code, issue.subject, issue.detail))
	end
	return table.concat(lines, "\n")
end

return { validate = validate, explain = explain, expand = expand }
