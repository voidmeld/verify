--!strict

local fs = require "@std/fs"
local Core = require "../src/core"
local Files = require "../src/lute/files"
local Evidence = require "../src/lute/evidence"
local Wire = require "../src/lute/wire"

local function report(reference: string): Core.Report
	local harness = Core.createHarness { now = os.clock }
	harness:case("flow", function(context)
		context:artifact("same", reference, "image/png")
		context:checkpoint("client-1", "view")
		context:checkpoint("client-2", "view")
	end)
	return harness:run {
		executor = "fixture",
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
					return { { name = "same", reference = reference, mediaType = "image/png" } }
				end,
			}
		end,
	}
end

return function(suite: Core.Harness)
	suite:suite("durable report evidence", function()
		suite:case("copies colliding names by actor without mutating the source report", function(check)
			local root = Files.claimDirectory "/tmp/verify-evidence-tests"
			check:defer(function()
				fs.removeDirectory(root, { recursive = true })
			end)
			local source = root .. "/source.png"
			fs.writeStringToFile(source, "fixture-bytes\000binary")
			local original = report(source)
			local id = original.results[1].id
			local result = Evidence.write(original, root .. "/out", {
				{ caseId = id, actor = "client-1", checkpoint = "view", mediaType = "image/png" },
				{ caseId = id, actor = "client-2", checkpoint = "view", mediaType = "image/png" },
			})
			check:expect(#result.issues):toEqual(0)
			check:expect(original.results[1].artifacts[1].reference):toEqual(source)
			local evidence = result.report.results[1].evidence
			assert(evidence)
			local first = evidence.checkpoints[1].artifacts[1].reference
			local second = evidence.checkpoints[2].artifacts[1].reference
			check:expect(first ~= second):toEqual(true)
			fs.remove(source)
			check:expect(fs.readFileToString(first)):toEqual "fixture-bytes\000binary"
			check:expect(fs.readFileToString(second)):toEqual "fixture-bytes\000binary"
			check:expect(Wire.decode(fs.readFileToString(result.reportPath)).passed):toEqual(1)
			check:expect(fs.readFileToString(root .. "/out/summary.txt")):toContain "client-2 / view"
		end)
		suite:case("temporary, remote, missing and empty references never satisfy requirements", function(check)
			local root = Files.claimDirectory "/tmp/verify-evidence-tests"
			check:defer(function()
				fs.removeDirectory(root, { recursive = true })
			end)
			local empty = root .. "/empty.png"
			fs.writeStringToFile(empty, "")
			for index, reference in
				{ "rbxtemp://capture", "https://example.invalid/capture.png", root .. "/missing.png", empty }
			do
				local original = report(reference)
				local result = Evidence.write(
					original,
					root .. "/out-" .. index,
					{ { caseId = original.results[1].id, actor = "client-1", mediaType = "image/png" } }
				)
				check:expect(#result.issues):toEqual(1)
				check:expect(fs.readFileToString(root .. "/out-" .. index .. "/summary.txt")):toContain "MISSING"
			end
		end)
		suite:case("selectors cannot borrow media from another actor or nonexistent case", function(check)
			local root = Files.claimDirectory "/tmp/verify-evidence-tests"
			check:defer(function()
				fs.removeDirectory(root, { recursive = true })
			end)
			local source = root .. "/source.png"
			fs.writeStringToFile(source, "bytes")
			local original = report(source)
			local requirements: { Evidence.Requirement } = {
				{ caseId = original.results[1].id, actor = "client-3", mediaType = "image/png" },
				{ caseId = "absent", mediaType = "image/png" },
				{ caseId = original.results[1].id, mediaType = "audio/wav" },
			}
			local result = Evidence.write(original, root .. "/out", requirements)
			check:expect(#result.issues):toEqual(3)
			local failure = Core.createHarness { now = os.clock }
			failure:case("evidence failure", function()
				error "missing required image"
			end)
			local final = failure:run { executor = "final" }
			Evidence.finish(final, root .. "/out")
			check:expect(Wire.decode(fs.readFileToString(result.reportPath)).failed):toEqual(1)
			local summary = fs.readFileToString(root .. "/out/summary.txt")
			check:expect(summary):toContain "evidence failure"
			check:expect(summary):toContain "required durable evidence missing"
		end)
	end)
end
