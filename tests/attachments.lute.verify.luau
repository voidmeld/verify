--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local function asString(value: unknown): string
	assert(type(value) == "string")
	return value
end

local temporary = require "./temporary"

local fs = require "@std/fs"
local json = require "@std/json"
local Core = require "../src/core"
local Channel = require "../src/roblox/report-channel"
local Files = require "../src/lute/files"
local Lute = require "../src/lute"
local Platform = require "../src/lute/platform"
local Store = require "../src/lute/evidence-store"
local StudioEngine = require "./studio-engine"
local Wire = require "../src/lute/wire"

local ENTRY = "examples/attachments-entry.luau"
local BUILD: Core.EvidenceBuild = { commit = "c0ffee", tree = "7ee", clean = true, digest = "build-1" }

local function simulate(caseContext: Core.Context, id: string, patch: ((Lute.PlatformOptions) -> ())?): Platform.Result
	local root = temporary(caseContext, "verify-attachment-tests")
	local options: Lute.PlatformOptions = {
		host = "simulator",
		entry = ENTRY,
		caseIds = { id },
		output = root,
		deadlineSeconds = 20,
	}
	if patch ~= nil then
		patch(options)
	end
	return Platform.run(options)
end

local function failureText(result: Platform.Result): string
	local lines: { string } = {}
	for _, case in result.report.results do
		for _, failure in case.failures do
			table.insert(lines, failure.message)
		end
	end
	return table.concat(lines, "\n")
end

local function reportWith(text: string, name: string?): Core.Report
	local harness = Core.createHarness { now = os.clock }
	harness:case("held", function(context)
		context:attach(name or "held.txt", "text/plain", text)
	end)
	return harness:run { executor = "fake-engine", capabilities = {} }
end

describe("inline text attachments on the simulator", function()
	it("materializes each attachment into the run directory with its identity", {
		timeoutSeconds = 30,
		run = function(_, caseContext)
			local result = simulate(caseContext, "attach-ok")
			expect(result.report.passed):toEqual(1)
			local artifacts = result.report.results[1].artifacts
			expect(#artifacts):toEqual(2)
			local first = artifacts[1]
			expect(first.name):toEqual "logs/run.txt"
			expect(first.content):toBeNil()
			expect(first.mediaType):toEqual "text/plain"
			expect(first.size):toEqual(18)
			expect(first.sha256):toEqual(Store.sha256 "line one\nline two\n")
			expect(fs.readFileToString(first.reference)):toEqual "line one\nline two\n"
			expect(fs.exists(result.directory .. "/attachments/attach-ok/logs/run.txt")):toBe(true)
		end,
	})

	it("hands each attachment to an injected sink instead", {
		timeoutSeconds = 30,
		run = function(_, caseContext)
			local stored: { [string]: string } = {}
			local result = simulate(caseContext, "attach-ok", function(options)
				options.attachmentSink = function(caseId, name, text, meta)
					stored[caseId .. "/" .. name] = text
					expect(meta.sha256):toEqual(Store.sha256(text))
					return "sink://" .. caseId .. "/" .. name, nil
				end
			end)
			expect(stored["attach-ok/summary.json"]):toEqual '{"lines":2}'
			expect(result.report.results[1].artifacts[2].reference):toEqual "sink://attach-ok/summary.json"
		end,
	})

	it("round-trips a 300 KB attachment", {
		timeoutSeconds = 30,
		run = function(_, caseContext)
			local result = simulate(caseContext, "attach-large")
			local artifact = result.report.results[1].artifacts[1]
			expect(artifact.size):toEqual(307200)
			expect(#fs.readFileToString(artifact.reference)):toEqual(307200)
		end,
	})

	it("fails closed on an over-limit, duplicate, unsafe or non-UTF-8 attachment", {
		timeoutSeconds = 60,
		run = function(_, caseContext)
			local cases: { { id: string, text: string } } = {
				{ id = "attach-too-large", text = "the limit is 1048576" },
				{ id = "attach-duplicate", text = "already attached" },
				{ id = "attach-unsafe", text = "must not contain a . or .. segment" },
				{ id = "attach-binary", text = "not valid UTF-8" },
			}
			for _, item in cases do
				local result = simulate(caseContext, item.id)
				expect(result.report.failed >= 1):toBe(true)
				expect(failureText(result)):toContain(item.text)
			end
		end,
	})

	it("honors configured limits", {
		timeoutSeconds = 30,
		run = function(_, caseContext)
			local result = simulate(caseContext, "attach-large", function(options)
				options.attachments = { maxBytes = 1000 }
			end)
			expect(result.report.failed >= 1):toBe(true)
			expect(failureText(result)):toContain "the limit is 1000"
		end,
	})
end)

describe("host-side checks", function()
	it("refuses a count, a report total and a duplicate that the engine did not stop", function()
		local harness = Core.createHarness { now = os.clock }
		harness:case("many", function(context)
			for index = 1, 3 do
				context:attach("n" .. index .. ".txt", "text/plain", "abc")
			end
		end)
		local report = harness:run {
			executor = "fake-engine",
			capabilities = {},
			attachments = { maxCount = 5 },
		}
		local _, issues = Lute.attachments.materialize(
			report,
			{ directory = Files.temporary "verify-attachment-unused", limits = { maxCount = 2 } }
		)
		expect(#issues):toEqual(1)
		expect(issues[1]):toContain "per-case count limit of 2"
		local _, totals = Lute.attachments.materialize(
			report,
			{ directory = Files.temporary "verify-attachment-unused", limits = { maxTotalBytes = 7 } }
		)
		expect(totals[1]):toContain "per-report limit of 7"
	end)

	it("reports an attachment as unsupported on a host that cannot carry it", function()
		local report = reportWith "text"
		local copy, issues = Lute.attachments.materialize(
			report,
			{ directory = Files.temporary "verify-attachment-unused", supported = false, host = "open-cloud" }
		)
		expect(#issues):toEqual(1)
		expect(issues[1]):toContain "unsupported on host open-cloud"
		expect(#copy.results[1].artifacts):toEqual(0)
	end)

	it("seals and validates, and a modified stored file fails validation", function(_, caseContext)
		local root = temporary(caseContext, "verify-attachment-seal")
		fs.writeStringToFile(root .. "/view.png", "png-bytes")
		local harness = Core.createHarness { now = os.clock }
		harness:case("flow", function(context)
			context:checkpoint("client-1", "view")
			context:attach("notes.txt", "text/plain", "sealed text")
		end)
		local report = harness:run {
			executor = "fixture",
			capabilities = { "capture" },
			bind = function(): Core.CaseHost
				return {
					name = "fixture",
					capabilities = { "capture" },
					environment = {},
					now = os.clock,
					invoke = function(): unknown
						return nil
					end,
					capture = function(): { Core.Artifact }
						return { { name = "view", reference = root .. "/view.png", mediaType = "image/png" } }
					end,
				}
			end,
		}
		local delivered, issues = Lute.attachments.materialize(report, { directory = root .. "/run" })
		expect(#issues):toEqual(0)
		local sealed = Store.seal(delivered, {
			runId = "run-1",
			build = BUILD,
			device = "phone",
			directory = root .. "/store",
			now = function()
				return 100
			end,
		})
		expect(#sealed.issues):toEqual(0)
		local policy: Lute.EvidenceValidateOptions = {
			runId = "run-1",
			build = { digest = "build-1", commit = "c0ffee", tree = "7ee", requireClean = true },
			directory = root .. "/store",
			now = function()
				return 105
			end,
			maxAgeSeconds = 60,
			maxSkewSeconds = 5,
			required = {
				{
					caseId = "flow",
					actors = { "client-1" },
					checkpoints = { "view" },
					devices = { "phone" },
					mediaType = "image/png",
					reviews = {},
				},
			},
		}
		local clean = Store.validate(sealed.report, policy)
		expect(#clean.issues):toEqual(0)
		local reference = ""
		for _, artifact in sealed.report.results[1].artifacts do
			if artifact.name == "notes.txt" then
				reference = artifact.reference
			end
		end
		expect(reference ~= ""):toBe(true)
		fs.writeStringToFile(reference, "tampered text")
		local changed = Store.validate(sealed.report, policy)
		expect(#changed.issues > 0):toBe(true)
	end)
end)

describe("attachments through a Studio transport", function()
	it("a 300 KB attachment crosses in segments and materializes", {
		timeoutSeconds = 30,
		run = function(_, caseContext)
			local root = temporary(caseContext, "verify-attachment-studio")
			local big = string.rep("0123456789abcdef", 19200)
			local function produce(runId: string): string
				local harness = Core.createHarness { now = os.clock }
				harness:case("studio-case", function(context)
					context:attach("big.txt", "text/plain", big)
				end)
				local report = harness:run { executor = "fake-engine", capabilities = {} }
				return Wire.encode(Channel.envelope(runId, report))
			end
			local engine = StudioEngine.new { produce = produce }
			local fetches = 0
			local transport: Lute.StudioTransport = {
				call = function(tool: string, argumentsJson: string): Lute.StudioExchange
					local arguments = Wire.parse(argumentsJson) :: { [string]: unknown }
					local function text(value: string): unknown
						return { content = { { type = "text", text = value } } }
					end
					if tool == "list_roblox_studios" then
						return {
							status = "answered",
							result = text(json.serialize { studios = { { id = "a", name = "A" } } }),
						}
					elseif tool == "execute_luau" then
						local code = asString(arguments.code)
						if string.find(code, "local I = ", 1, true) ~= nil then
							fetches += 1
						end
						local started = string.gsub(code, "return produce", "return produce")
						return {
							status = "answered",
							result = text(engine.run(asString(arguments.datamodel_type), started)),
						}
					end
					return { status = "answered", result = text "ok" }
				end,
				close = function() end,
			}
			local session = assert(Lute.studio.attach {
				authorize = function()
					return { ok = true }
				end,
				studioId = "a",
				transport = transport,
				callSeconds = 5,
				runSeconds = 20,
			})
			local result = session.report("Server", 'local runId = "run-9"; return produce(runId)', "run-9")
			expect(result.problem):toBeNil()
			expect(fetches > 12):toBe(true)
			local delivered, issues =
				Lute.attachments.materialize(assert(result.report), { directory = root, supported = true })
			expect(#issues):toEqual(0)
			local artifact = delivered.results[1].artifacts[1]
			expect(artifact.size):toEqual(#big)
			expect(fs.readFileToString(artifact.reference)):toEqual(big)
		end,
	})
end)

return nil
