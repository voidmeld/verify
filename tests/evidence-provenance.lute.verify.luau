--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local temporary = require "./temporary"

local ReportModel = require "../src/core/report"
local fs = require "@std/fs"
local Core = require "../src/core"
local Evidence = require "../src/evidence"
local Store = require "../src/lute/evidence-store"
local Wire = require "../src/lute/wire"

local BUILD: Core.EvidenceBuild = { commit = "c0ffee", tree = "7ee", clean = true, digest = "build-1" }
local SEALED_AT = 1000
local CHECKED_AT = 1010

type Fixture = {
	root: string,
	report: Core.Report,
	sink: Core.EvidenceSink,
	policy: Evidence.Policy,
	sealed: { Evidence.SealIssue },
}

type Setup = {
	build: Core.EvidenceBuild?,
	device: string?,
	sink: Core.EvidenceSink?,
	bind: boolean?,
	sealedAt: number?,
	checkedAt: number?,
	status: string?,
}

local function produce(files: { [string]: string }): Core.Report
	local harness = Core.createHarness { now = os.clock }
	harness:case("flow", function(context)
		context:checkpoint("client-1", "view")
		context:judge("client-1", "view", "readable")
		context:checkpoint("client-2", "view")
		context:judge("client-2", "view", "readable")
	end)
	return harness:run {
		executor = "fixture",
		capabilities = { "capture", "judgment" },
		bind = function(): Core.CaseHost
			return {
				name = "fixture",
				capabilities = { "capture", "judgment" },
				environment = {},
				now = os.clock,
				invoke = function(): unknown
					return nil
				end,
				capture = function(actor: string, name: string): { Core.Artifact }
					return { { name = "view", reference = files[actor], mediaType = "image/png" } }
				end,
				judge = function()
					return { status = "passed", reviewer = "reviewer-1", detail = "looks right" }
				end,
			}
		end,
	}
end

local function build(caseContext: Core.Context, setup: Setup?): Fixture
	local options: Setup = setup or {}
	local root = temporary(caseContext, "verify-provenance-tests")
	fs.writeStringToFile(root .. "/one.png", "png-one\000bytes")
	fs.writeStringToFile(root .. "/two.png", "png-two\000bytes")
	local original = produce { ["client-1"] = root .. "/one.png", ["client-2"] = root .. "/two.png" }
	local sink = options.sink or Core.memorySink(Store.sha256)
	local sealed = Store.seal(original, {
		runId = "run-1",
		build = options.build or BUILD,
		device = options.device or "phone",
		sink = sink,
		now = function()
			return options.sealedAt or SEALED_AT
		end,
	})
	local report = sealed.report
	if options.bind ~= false then
		local judged: { [string]: string } = { ["client-1"] = "png-one\000bytes", ["client-2"] = "png-two\000bytes" }
		for actor, bytes in judged do
			report = Evidence.bindReview(report, {
				caseId = report.results[1].id,
				actor = actor,
				checkpoint = "view",
				kind = "visual",
				judged = { Store.sha256(bytes) },
			})
		end
	end
	local visual: { Core.ReviewKind } = { "visual" }
	return {
		root = root,
		report = report,
		sink = sink,
		sealed = sealed.issues,
		policy = {
			runId = "run-1",
			build = { digest = "build-1", commit = "c0ffee", tree = "7ee", requireClean = true },
			now = function()
				return options.checkedAt or CHECKED_AT
			end,
			maxAgeSeconds = 60,
			maxSkewSeconds = 5,
			required = {
				{
					caseId = report.results[1].id,
					actors = { "client-1", "client-2" },
					checkpoints = { "view" },
					devices = { options.device or "phone" },
					mediaType = "image/png",
					reviews = visual,
				},
			},
			store = sink,
			hash = Store.sha256,
		},
	}
end

type Overrides = { from: Core.EvidenceSubject?, directory: string?, maxAgeSeconds: number?, at: number? }

local function codes(result: Evidence.Result): { string }
	local found: { string } = {}
	for _, issue in result.issues do
		if not table.find(found, issue.code) then
			table.insert(found, issue.code)
		end
	end
	table.sort(found)
	return found
end

local function rejects(caseContext: Core.Context, fixture: Fixture, code: string)
	local result = Evidence.validate(fixture.report, fixture.policy)
	expect(result.ok):toEqual(false)
	expect(codes(result)):toContain(code)
end

local function checkpoint(report: Core.Report, actor: string): Core.Checkpoint
	local evidence = report.results[1].evidence
	assert(evidence)
	for _, candidate in evidence.checkpoints do
		if candidate.actor == actor then
			return candidate
		end
	end
	error "no checkpoint"
end

local function requirement(fixture: Fixture): Evidence.Requirement
	return fixture.policy.required[1]
end

describe("evidence provenance acceptance", function()
	it("accepts complete fresh evidence bound to the build, run and reviewed artifacts", function(_, caseContext)
		local fixture = build(caseContext)
		expect(#fixture.sealed):toEqual(0)
		local result = Evidence.validate(fixture.report, fixture.policy)
		expect(Evidence.explain(result)):toContain "evidence valid"
		expect(result.ok):toEqual(true)
		expect(result.verified):toEqual(2)
		local artifact = checkpoint(fixture.report, "client-1").artifacts[1]
		expect(artifact.sha256):toEqual(Store.sha256 "png-one\000bytes")
		expect(artifact.size):toEqual(#"png-one\000bytes")
		local provenance = artifact.provenance
		assert(provenance)
		expect(provenance.host):toEqual "fixture"
		expect(provenance.checkpoint):toEqual "view"
	end)

	it("provenance and review bindings survive report transport", function(_, caseContext)
		local fixture = build(caseContext)
		local decoded = Wire.decode(Wire.encode(fixture.report))
		expect(Evidence.validate(decoded, fixture.policy).ok):toEqual(true)
		expect(ReportModel.canonical(decoded)):toEqual(ReportModel.canonical(fixture.report))
	end)

	it("the local directory sink stores by content and re-validates from disk", function(_, caseContext)
		local root = temporary(caseContext, "verify-provenance-sink")
		local fixture = build(caseContext, { sink = Store.localDirectory(root .. "/store") })
		expect(Evidence.validate(fixture.report, fixture.policy).ok):toEqual(true)
		local reference = checkpoint(fixture.report, "client-1").artifacts[1].reference
		fs.removeDirectory(fixture.root, { recursive = true })
		fs.createDirectory(fixture.root)
		expect(Evidence.validate(fixture.report, fixture.policy).ok):toEqual(true)
		expect((string.find(reference, root .. "/store/", 1, true))):toEqual(1)
	end)
end)

describe("evidence provenance rejection", function()
	it("rejects a different build digest, commit, tree or a dirty build", function(_, caseContext)
		local fixture = build(caseContext)
		fixture.policy.build = { digest = "build-2", commit = "c0ffee", tree = "7ee", requireClean = true }
		rejects(caseContext, fixture, "build_mismatch")
		fixture.policy.build = { digest = "build-1", commit = "other", tree = "7ee", requireClean = true }
		rejects(caseContext, fixture, "build_mismatch")
		fixture.policy.build = { digest = "build-1", commit = "c0ffee", tree = "other", requireClean = true }
		rejects(caseContext, fixture, "build_mismatch")
		local dirty =
			build(caseContext, { build = { commit = "c0ffee", tree = "7ee", clean = false, digest = "build-1" } })
		rejects(caseContext, dirty, "build_dirty")
		dirty.policy.build = { digest = "build-1", commit = "c0ffee", tree = "7ee", requireClean = false }
		expect(Evidence.validate(dirty.report, dirty.policy).ok):toEqual(true)
	end)

	it("rejects stale, future and boundary-aged captures against the injected clock", function(_, caseContext)
		rejects(caseContext, build(caseContext, { checkedAt = SEALED_AT + 61 }), "stale")
		rejects(caseContext, build(caseContext, { checkedAt = SEALED_AT - 6 }), "future_capture")
		expect(
			Evidence.validate(
				build(caseContext, { checkedAt = SEALED_AT + 60 }).report,
				build(caseContext, { checkedAt = SEALED_AT + 60 }).policy
			).ok
		):toEqual(true)
		local skewed = build(caseContext, { checkedAt = SEALED_AT - 5 })
		expect(Evidence.validate(skewed.report, skewed.policy).ok):toEqual(true)
	end)

	it("rejects a run that is not the declared run and an unaccepted host or capability", function(_, caseContext)
		local fixture = build(caseContext)
		fixture.policy.runId = "run-2"
		rejects(caseContext, fixture, "wrong_run")
		fixture.policy.runId = "run-1"
		fixture.policy.hosts = { "elsewhere" }
		rejects(caseContext, fixture, "wrong_host")
		fixture.policy.hosts = { "fixture" }
		fixture.policy.capabilities = { "capture", "touch-input" }
		rejects(caseContext, fixture, "missing_capability")
		fixture.policy.capabilities = { "capture", "judgment" }
		expect(Evidence.validate(fixture.report, fixture.policy).ok):toEqual(true)
	end)

	it("rejects missing actors, checkpoints and cases", function(_, caseContext)
		local fixture = build(caseContext)
		requirement(fixture).actors = { "client-1", "client-3" }
		rejects(caseContext, fixture, "missing_observation")
		requirement(fixture).actors = { "client-1" }
		requirement(fixture).checkpoints = { "menu" }
		rejects(caseContext, fixture, "missing_observation")
		requirement(fixture).checkpoints = { "view" }
		requirement(fixture).caseId = "absent"
		rejects(caseContext, fixture, "missing_case")
	end)

	it("rejects an observation from another device class", function(_, caseContext)
		local fixture = build(caseContext)
		requirement(fixture).devices = { "tablet" }
		rejects(caseContext, fixture, "wrong_device")
		requirement(fixture).devices = { "phone", "tablet" }
		rejects(caseContext, fixture, "wrong_device")
	end)

	it("never infers physical device proof from metadata", function(_, caseContext)
		local fixture = build(caseContext, { device = "physical" })
		rejects(caseContext, fixture, "unattested_device")
		local refuse: Evidence.Attestation = function(): boolean
			return false
		end
		fixture.policy.attest = { physical = refuse }
		rejects(caseContext, fixture, "unattested_device")
		local broken: Evidence.Attestation = function(): boolean
			error "attestation backend down"
		end
		fixture.policy.attest = { physical = broken }
		rejects(caseContext, fixture, "unattested_device")
		fixture.policy.attest = {
			physical = function(artifact: Core.Artifact, provenance: Core.ArtifactProvenance): boolean
				return provenance.device == "physical" and artifact.sha256 ~= nil
			end,
		}
		expect(Evidence.validate(fixture.report, fixture.policy).ok):toEqual(true)
	end)

	it("rejects evidence filed under a different actor or checkpoint", function(_, caseContext)
		local fixture = build(caseContext)
		local first, second = checkpoint(fixture.report, "client-1"), checkpoint(fixture.report, "client-2")
		first.artifacts, second.artifacts = second.artifacts, first.artifacts
		rejects(caseContext, fixture, "wrong_identity")
	end)

	it("rejects a case that did not pass", function(_, caseContext)
		local fixture = build(caseContext)
		fixture.report.results[1].status = "failed"
		rejects(caseContext, fixture, "case_not_passed")
	end)

	it("rejects duplicate and conflicting observations", function(_, caseContext)
		local fixture = build(caseContext)
		local first = checkpoint(fixture.report, "client-1")
		table.insert(first.artifacts, table.clone(first.artifacts[1]))
		rejects(caseContext, fixture, "duplicate_observation")
		local conflicting = build(caseContext)
		local other = checkpoint(conflicting.report, "client-1")
		local twin = table.clone(checkpoint(conflicting.report, "client-2").artifacts[1])
		twin.provenance = other.artifacts[1].provenance
		table.insert(other.artifacts, twin)
		rejects(caseContext, conflicting, "conflicting_observation")
		local repeated = build(caseContext)
		table.insert(repeated.report.results, table.clone(repeated.report.results[1]))
		rejects(caseContext, repeated, "conflicting_case")
	end)

	it("rejects artifacts without identity or with an invalid recorded identity", function(_, caseContext)
		local fixture = build(caseContext)
		local artifact = checkpoint(fixture.report, "client-1").artifacts[1]
		artifact.sha256, artifact.size, artifact.provenance = nil, nil, nil
		rejects(caseContext, fixture, "missing_identity")
		local forged = build(caseContext)
		local identity = checkpoint(forged.report, "client-1").artifacts[1]
		identity.sha256 = Store.sha256 "forged"
		rejects(caseContext, forged, "changed")
		expect(function()
			local report = build(caseContext).report
			local target = checkpoint(report, "client-1").artifacts[1]
			target.sha256 = "ABC"
			Core.decode(report)
		end):toThrow "lowercase hex sha-256"
		expect(function()
			local report = build(caseContext).report
			local target = checkpoint(report, "client-1").artifacts[1]
			target.sha256, target.size = nil, nil
			Core.decode(report)
		end):toThrow "requires a content identity"
	end)

	it("expands required coverage into one capture cell per actor, checkpoint and device", function()
		local cells = Evidence.expand {
			{
				caseId = "case-a",
				actors = { "one", "two" },
				checkpoints = { "start", "end" },
				devices = { "phone", "wide" },
				mediaType = "image/png",
			},
			{ caseId = "case-b", actors = { "one" }, checkpoints = { "start" }, devices = { "phone" } },
		}
		expect(#cells):toBe(9)
		expect(cells[1]):toEqual {
			caseId = "case-a",
			actor = "one",
			checkpoint = "start",
			device = "phone",
			mediaType = "image/png",
		}
		expect(cells[4].checkpoint):toBe "end"
		expect(cells[4].device):toBe "wide"
		expect(cells[9].caseId):toBe "case-b"
		expect(function()
			Evidence.expand {}
		end):toThrow "required coverage"
		expect(function()
			Evidence.expand { { caseId = "case-a", actors = {}, checkpoints = { "x" }, devices = { "y" } } }
		end):toThrow "requirement actors"
	end)

	it("rejects policy that could not establish a verdict", function(_, caseContext)
		local fixture = build(caseContext)
		fixture.policy.required = {}
		expect(function()
			Evidence.validate(fixture.report, fixture.policy)
		end):toThrow "required coverage"
		fixture.policy.required = { { caseId = "flow", actors = {}, checkpoints = { "view" }, devices = { "phone" } } }
		expect(function()
			Evidence.validate(fixture.report, fixture.policy)
		end):toThrow "requirement actors"
		local clock = build(caseContext)
		clock.policy.now = function()
			return math.huge
		end
		expect(function()
			Evidence.validate(clock.report, clock.policy)
		end):toThrow "injected clock"
		local ages = build(caseContext)
		ages.policy.maxAgeSeconds = 0
		expect(function()
			Evidence.validate(ages.report, ages.policy)
		end):toThrow "maxAgeSeconds"
	end)
end)

describe("evidence tamper and availability", function()
	it("rejects an artifact changed on disk by content, size or removal", function(_, caseContext)
		local root = temporary(caseContext, "verify-provenance-sink")
		local fixture = build(caseContext, { sink = Store.localDirectory(root .. "/store") })
		local reference = checkpoint(fixture.report, "client-1").artifacts[1].reference
		local original = fs.readFileToString(reference)
		fs.writeStringToFile(reference, string.rep("x", #original))
		rejects(caseContext, fixture, "changed")
		fs.writeStringToFile(reference, original .. "!")
		rejects(caseContext, fixture, "changed")
		fs.writeStringToFile(reference, original)
		expect(Evidence.validate(fixture.report, fixture.policy).ok):toEqual(true)
		fs.remove(reference)
		rejects(caseContext, fixture, "unavailable")
	end)

	it("rejects a tampered or unavailable custom sink and never turns an outage green", function(_, caseContext)
		local memory = Core.memorySink(Store.sha256)
		local fixture = build(caseContext, { sink = memory })
		local reference = checkpoint(fixture.report, "client-2").artifacts[1].reference
		memory.blobs[reference] = "png-two\000bytez"
		rejects(caseContext, fixture, "changed")
		memory.blobs[reference] = "png-two\000bytes"
		memory.available = false
		local result = Evidence.validate(fixture.report, fixture.policy)
		expect(result.ok):toEqual(false)
		expect(codes(result)):toEqual { "unavailable" }
		fixture.policy.store = {
			stat = function(): (Core.EvidenceStat?, string?)
				error "network down"
			end,
			get = function(): (string?, string?)
				error "network down"
			end,
		}
		rejects(caseContext, fixture, "unavailable")
		fixture.policy.store = memory
		memory.available = true
		fixture.policy.hash = function(): string
			error "hash backend down"
		end
		rejects(caseContext, fixture, "hash_failed")
	end)

	it("an unavailable sink at capture time seals nothing and cannot validate", function(_, caseContext)
		local memory = Core.memorySink(Store.sha256)
		memory.available = false
		local fixture = build(caseContext, { sink = memory })
		expect(#fixture.sealed):toEqual(4)
		expect(fixture.sealed[1].code):toEqual "sink_unavailable"
		memory.available = true
		rejects(caseContext, fixture, "missing_identity")
	end)

	it("sealing reports unreadable references, a bad clock and a bad hash without sealing", function(_, caseContext)
		local root = temporary(caseContext, "verify-provenance-sink")
		local report = produce { ["client-1"] = root .. "/missing.png", ["client-2"] = "https://example.invalid/x.png" }
		local sink = Core.memorySink(Store.sha256)
		local sealed = Store.seal(report, { runId = "run-1", build = BUILD, device = "phone", sink = sink })
		expect(#sealed.issues):toEqual(4)
		expect(sealed.issues[1].code):toEqual "unreadable"
		expect(checkpoint(sealed.report, "client-1").artifacts[1].sha256):toEqual(nil)
		local files = { ["client-1"] = root .. "/one.png", ["client-2"] = root .. "/one.png" }
		fs.writeStringToFile(root .. "/one.png", "content")
		local clock = Store.seal(produce(files), {
			runId = "run-1",
			build = BUILD,
			device = "phone",
			sink = sink,
			now = function()
				return math.nan
			end,
		})
		expect(clock.issues[1].code):toEqual "clock_invalid"
		local hashed = Evidence.seal(produce(files), {
			runId = "run-1",
			build = BUILD,
			device = "phone",
			sink = sink,
			now = os.time,
			read = Store.readFile,
			hash = function(): string
				return "not-a-digest"
			end,
		})
		expect(hashed.issues[1].code):toEqual "hash_failed"
	end)
end)

describe("review binding", function()
	it("a required review that was never recorded is rejected", function(_, caseContext)
		rejects(caseContext, build(caseContext, { bind = false }), "missing_review")
	end)

	it("a review bound to another artifact is rejected", function(_, caseContext)
		local fixture = build(caseContext)
		local evidence = fixture.report.results[1].evidence
		assert(evidence)
		evidence.reviews[1].judged = { Store.sha256 "something else" }
		rejects(caseContext, fixture, "review_wrong_artifact")
		evidence.reviews[1].judged = { Store.sha256 "png-two\000bytes" }
		rejects(caseContext, fixture, "review_wrong_artifact")
	end)

	it("a review naming no artifact is unbound and fails", function(_, caseContext)
		local fixture = build(caseContext)
		local evidence = fixture.report.results[1].evidence
		assert(evidence)
		evidence.reviews[1].judged = {}
		rejects(caseContext, fixture, "review_unbound")
		expect(function()
			Evidence.bindReview(fixture.report, {
				caseId = fixture.report.results[1].id,
				actor = "client-1",
				checkpoint = "view",
				kind = "visual",
				judged = {},
			})
		end):toThrow "judged"
	end)

	it("changing a judged artifact after review invalidates the review and the evidence", function(_, caseContext)
		local memory = Core.memorySink(Store.sha256)
		local fixture = build(caseContext, { sink = memory })
		expect(Evidence.validate(fixture.report, fixture.policy).ok):toEqual(true)
		memory.blobs[checkpoint(fixture.report, "client-1").artifacts[1].reference] = "repainted"
		local result = Evidence.validate(fixture.report, fixture.policy)
		expect(result.ok):toEqual(false)
		expect(codes(result)):toContain "changed"
	end)

	it("a review of the wrong kind, rejected status or absent artifact kind fails", function(_, caseContext)
		local fixture = build(caseContext)
		local audio: { Core.ReviewKind } = { "audio" }
		requirement(fixture).reviews = audio
		rejects(caseContext, fixture, "missing_review")
		local evidence = fixture.report.results[1].evidence
		assert(evidence)
		for _, review in evidence.reviews do
			review.kind = "audio"
		end
		rejects(caseContext, fixture, "missing_observation")
		local visual: { Core.ReviewKind } = { "visual" }
		requirement(fixture).reviews = visual
		for _, review in evidence.reviews do
			review.kind = "visual"
		end
		evidence.reviews[1].judgment.status = "failed"
		rejects(caseContext, fixture, "review_not_passed")
	end)

	it("metadata alone is not a review", function(_, caseContext)
		local fixture = build(caseContext, { bind = false })
		local evidence = fixture.report.results[1].evidence
		assert(evidence)
		expect(#evidence.reviews):toEqual(2)
		expect(Evidence.validate(fixture.report, fixture.policy).ok):toEqual(false)
		requirement(fixture).reviews = nil
		expect(Evidence.validate(fixture.report, fixture.policy).ok):toEqual(true)
	end)
end)

describe("local directory sink", function()
	it("refuses mismatched identities, outside references and divergent content", function(_, caseContext)
		local root = temporary(caseContext, "verify-provenance-sink")
		local sink = Store.localDirectory(root .. "/store")
		local digest = Store.sha256 "bytes"
		local meta: Core.EvidenceMeta = { name = "shot.png", mediaType = "image/png", sha256 = digest, size = 5 }
		local reference = sink.put({ kind = "bytes", bytes = "bytes" }, meta)
		assert(reference)
		expect((sink.put({ kind = "bytes", bytes = "bytes" }, meta))):toEqual(reference)
		local refused, reason = sink.put({ kind = "bytes", bytes = "other" }, meta)
		expect(refused):toEqual(nil)
		expect(reason):toContain "declared identity"
		expect((sink.get(root .. "/store/../outside"))):toEqual(nil)
		expect((sink.stat "/etc/hosts")):toEqual(nil)
		expect((assert(sink.stat(reference))).size):toEqual(5)
		fs.writeStringToFile(root .. "/source.png", "bytes")
		expect((sink.put({ kind = "path", path = root .. "/source.png" }, meta))):toEqual(reference)
		fs.writeStringToFile(reference, "xxxxx")
		local divergent, why = sink.put({ kind = "bytes", bytes = "bytes" }, meta)
		expect(divergent):toEqual(nil)
		expect(why):toContain "different artifact"
	end)
end)

describe("sealing and validating straight from an outcome", function()
	local SUBJECT: Core.EvidenceSubject = { runId = "run-9", build = BUILD }

	local function sealed(caseContext: Core.Context, subject: Core.EvidenceSubject): (Core.Report, string)
		local root = temporary(caseContext, "verify-provenance-outcome")
		fs.writeStringToFile(root .. "/one.png", "png-one\000bytes")
		fs.writeStringToFile(root .. "/two.png", "png-two\000bytes")
		local original = produce { ["client-1"] = root .. "/one.png", ["client-2"] = root .. "/two.png" }
		local result = Store.seal(original, {
			from = subject,
			device = "phone",
			directory = root .. "/store",
			now = function()
				return SEALED_AT
			end,
		})
		expect(#result.issues):toEqual(0)
		return result.report, root .. "/store"
	end

	local function required(report: Core.Report): { Evidence.Requirement }
		return {
			{
				caseId = report.results[1].id,
				actors = { "client-1", "client-2" },
				checkpoints = { "view" },
				devices = { "phone" },
				mediaType = "image/png",
			},
		}
	end

	it("binds run, build, case and artifact from the outcome and validates with defaults", function(_, caseContext)
		local report, store = sealed(caseContext, SUBJECT)
		local provenance = assert(report.results[1].evidence).checkpoints[1].artifacts[1].provenance
		expect(provenance ~= nil and provenance.runId):toEqual "run-9"
		expect(provenance ~= nil and provenance.build.digest):toEqual "build-1"
		expect(provenance ~= nil and provenance.caseId):toEqual(report.results[1].id)
		local result = Store.validate(report, {
			from = SUBJECT,
			directory = store,
			required = required(report),
			now = function()
				return CHECKED_AT
			end,
		})
		expect(result.ok):toEqual(true)
		expect(result.verified):toEqual(2)
	end)

	it("refuses another build, a dirty build, stale evidence and a missing store by default", function(_, caseContext)
		local report, store = sealed(caseContext, SUBJECT)
		local function validate(overrides: Overrides): Evidence.Result
			return Store.validate(report, {
				from = overrides.from or SUBJECT,
				directory = overrides.directory or store,
				required = required(report),
				maxAgeSeconds = overrides.maxAgeSeconds,
				now = function()
					return overrides.at or CHECKED_AT
				end,
			})
		end
		local other: Core.EvidenceSubject =
			{ runId = "run-9", build = { commit = "c0ffee", tree = "7ee", clean = true, digest = "build-2" } }
		expect(codes(validate { from = other })):toContain "build_mismatch"
		local otherRun: Core.EvidenceSubject = { runId = "run-10", build = BUILD }
		expect(codes(validate { from = otherRun })):toContain "wrong_run"
		expect(codes(validate { at = SEALED_AT + 7200 })):toContain "stale"
		expect(validate({ at = SEALED_AT + 7200, maxAgeSeconds = 86400 }).ok):toEqual(true)
		expect(codes(validate { directory = store .. "-elsewhere" })):toContain "unavailable"
		local dirtyReport, dirtyStore = sealed(
			caseContext,
			{ runId = "run-9", build = { commit = "c0ffee", tree = "7ee", clean = false, digest = "build-1" } }
		)
		local dirty: Core.EvidenceSubject =
			{ runId = "run-9", build = { commit = "c0ffee", tree = "7ee", clean = false, digest = "build-1" } }
		local function dirtyValidate(clean: boolean?): Evidence.Result
			return Store.validate(dirtyReport, {
				from = dirty,
				directory = dirtyStore,
				requireClean = clean,
				required = required(dirtyReport),
				now = function()
					return CHECKED_AT
				end,
			})
		end
		expect(codes(dirtyValidate())):toContain "build_dirty"
		expect(dirtyValidate(false).ok):toEqual(true)
	end)

	it("needs a build from somewhere and never defaults an empty requirement", function(_, caseContext)
		local report, store = sealed(caseContext, SUBJECT)
		expect(function()
			Store.validate(report, {
				from = { runId = "run-9" },
				directory = store,
				required = required(report),
			})
		end):toThrow "expected build"
		expect(function()
			Store.seal(report, { from = { runId = "run-9" }, device = "phone", directory = store })
		end):toThrow "needs the build"
		expect(function()
			Store.validate(report, { from = SUBJECT, directory = store, required = {} })
		end):toThrow "required coverage"
	end)
end)

return nil
