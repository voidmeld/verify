--!strict

local Verify = require "../../src/core"
local Evidence = require "../../src/evidence"

export type Runtime = { name: string, sha256: Verify.EvidenceHasher }

local RUN: Verify.EvidenceSubject = {
	runId = "run-1",
	build = { commit = "abc123", tree = "def456", clean = true, digest = "build-1" },
}
local FRAME = "frame-bytes-for-checkpoint"

local function produce(): Verify.Report
	local harness = Verify.createHarness { now = os.clock }
	harness:case("render", function(context)
		context:checkpoint("player-1", "lobby")
		context:judge("player-1", "lobby", "readable")
	end)
	return harness:run {
		executor = "example-host",
		capabilities = { "capture", "judgment" },
		bind = function(): Verify.CaseHost
			return {
				name = "example-host",
				capabilities = { "capture", "judgment" },
				environment = {},
				now = os.clock,
				invoke = function(): unknown
					return nil
				end,
				capture = function(): { Verify.Artifact }
					return { { name = "frame", reference = "capture/frame", mediaType = "image/png" } }
				end,
				judge = function()
					return { status = "passed", reviewer = "reviewer-1", detail = "text is legible" }
				end,
			}
		end,
	}
end

local function run(runtime: Runtime)
	local sink = Verify.memorySink(runtime.sha256)
	local sealed = Evidence.seal(produce(), {
		from = RUN,
		device = "phone",
		now = function()
			return 100
		end,
		hash = runtime.sha256,
		read = function(reference: string): (string?, string?)
			if reference == "capture/frame" then
				return FRAME, nil
			end
			return nil, "no such capture"
		end,
		sink = sink,
	})
	assert(#sealed.issues == 0, "sealing failed")
	local report = Evidence.bindReview(sealed.report, {
		caseId = sealed.report.results[1].id,
		actor = "player-1",
		checkpoint = "lobby",
		kind = "visual",
		judged = { runtime.sha256(FRAME) },
	})
	local kinds: { Verify.ReviewKind } = { "visual" }
	local policy: Evidence.Policy = {
		from = RUN,
		now = function()
			return 110
		end,
		maxAgeSeconds = 60,
		maxSkewSeconds = 5,
		required = {
			{
				caseId = report.results[1].id,
				actors = { "player-1" },
				checkpoints = { "lobby" },
				devices = { "phone" },
				mediaType = "image/png",
				reviews = kinds,
			},
		},
		store = sink,
		hash = runtime.sha256,
	}
	local accepted = Evidence.validate(report, policy)
	print(Evidence.explain(accepted))
	assert(accepted.ok, "fresh, intact, reviewed evidence must validate")

	local function rejected(label: string, code: string, result: Evidence.Result)
		assert(not result.ok, label .. " must be rejected")
		for _, issue in result.issues do
			if issue.code == code then
				print(("rejected %s: %s"):format(label, code))
				return
			end
		end
		error(label .. " was rejected for the wrong reason")
	end

	policy.now = function()
		return 1000
	end
	rejected("stale capture", "stale", Evidence.validate(report, policy))
	policy.now = function()
		return 110
	end
	policy.build = { digest = "build-2", commit = "abc123", tree = "def456", requireClean = true }
	rejected("another build", "build_mismatch", Evidence.validate(report, policy))
	policy.build = { digest = "build-1", commit = "abc123", tree = "def456", requireClean = true }
	policy.required[1].devices = { "physical" }
	rejected("a device class that was not captured", "wrong_device", Evidence.validate(report, policy))
	policy.required[1].devices = { "phone" }

	local evidence = report.results[1].evidence
	assert(evidence, "the report carries evidence")
	local reference = evidence.checkpoints[1].artifacts[1].reference
	sink.blobs[reference] = "frame-bytes-for-checkpoinT"
	rejected("a tampered artifact", "changed", Evidence.validate(report, policy))
	sink.blobs[reference] = FRAME
	sink.available = false
	rejected("an unavailable sink", "unavailable", Evidence.validate(report, policy))
	sink.available = true
	evidence.reviews[1].judged = { runtime.sha256 "another frame" }
	rejected("a review of another artifact", "review_wrong_artifact", Evidence.validate(report, policy))
	print(("evidence-provenance: ok on %s"):format(runtime.name))
end

return { run = run }
