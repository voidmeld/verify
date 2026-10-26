--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Verify = require "../src/core"

describe("result transport", function()
	it("frames a small payload whole and a large one in chunks", function()
		expect((Verify.frame("VERIFY", "hello", 700))):toEqual { "VERIFY|hello" }
		local lines = Verify.frame("VERIFY", string.rep("x", 25), 10)
		expect(#lines):toEqual(3)
		expect(lines[1]):toEqual("VERIFY|chunk|1/3|" .. string.rep("x", 10))
		expect(lines[3]):toEqual("VERIFY|chunk|3/3|" .. string.rep("x", 5))
	end)

	it("recovers a payload from lines a host prefixed with its own noise", function()
		local log = table.concat({
			"12:00:01 info starting",
			"12:00:02 info VERIFY|chunk|1/2|abc",
			"12:00:03 warn something unrelated",
			"12:00:04 info VERIFY|chunk|2/2|def",
			"12:00:05 info done",
		}, "\r\n")
		local payload, problem = Verify.receipt(log, "VERIFY")
		expect(problem):toEqual(nil)
		expect(payload):toEqual "abcdef"
	end)

	it("round-trips whatever it framed", function()
		local payload = string.rep("payload-", 200)
		local lines = Verify.frame("RECEIPT", payload, 64)
		local recovered = Verify.receipt(table.concat(lines, "\n"), "RECEIPT")
		expect(recovered):toEqual(payload)
	end)

	it("names a missing chunk instead of returning a truncated payload", function()
		local payload, problem = Verify.reassemble(Verify.extract("VERIFY|chunk|1/3|a\nVERIFY|chunk|3/3|c", "VERIFY"))
		expect(payload):toEqual(nil)
		expect((tostring(problem))):toContain "chunk 2 of 3 is missing"
	end)

	it("names a chunk that appeared twice with different bytes", function()
		local payload, problem =
			Verify.reassemble(Verify.extract("VERIFY|chunk|1/2|a\nVERIFY|chunk|1/2|z\nVERIFY|chunk|2/2|b", "VERIFY"))
		expect(payload):toEqual(nil)
		expect((tostring(problem))):toContain "appears twice with different bytes"
	end)

	it("tolerates a chunk repeated identically", function()
		local payload =
			Verify.reassemble(Verify.extract("VERIFY|chunk|1/2|a\nVERIFY|chunk|1/2|a\nVERIFY|chunk|2/2|b", "VERIFY"))
		expect(payload):toEqual "ab"
	end)

	it("names disagreeing chunk counts and mixed framing", function()
		local _, counts = Verify.reassemble(Verify.extract("VERIFY|chunk|1/2|a\nVERIFY|chunk|2/3|b", "VERIFY"))
		expect((tostring(counts))):toContain "chunk counts disagree"
		local _, mixed = Verify.reassemble(Verify.extract("VERIFY|whole\nVERIFY|chunk|1/1|a", "VERIFY"))
		expect((tostring(mixed))):toContain "mixed framing"
	end)

	it("names two whole receipts rather than picking one", function()
		local _, problem = Verify.reassemble(Verify.extract("VERIFY|first\nVERIFY|second", "VERIFY"))
		expect((tostring(problem))):toContain "2 whole records"
	end)

	it("names an absent receipt", function()
		local payload, problem = Verify.receipt("nothing here at all", "VERIFY")
		expect(payload):toEqual(nil)
		expect((tostring(problem))):toContain "no tagged record"
	end)

	it("reports the line each record was found on", function()
		local records = Verify.extract("noise\nnoise\nVERIFY|here", "VERIFY")
		expect(#records):toEqual(1)
		expect(records[1].ordinal):toEqual(3)
		expect(records[1].payload):toEqual "here"
	end)

	it("refuses a tag that would collide with the field separator", function()
		expect((pcall(Verify.frame, "VER|IFY", "x"))):toEqual(false)
		expect((pcall(Verify.frame, "", "x"))):toEqual(false)
	end)
end)

describe("segmented result transport", function()
	it("segments a small payload to one piece and a large one to several", function()
		local one = Verify.segment("hello", 700)
		expect(#one):toEqual(1)
		expect(one[1].index):toEqual(1)
		expect(one[1].count):toEqual(1)
		expect(one[1].totalBytes):toEqual(5)
		expect(one[1].payload):toEqual "hello"
		expect(one[1].digest):toEqual(one[1].totalDigest)
		expect(string.match(one[1].digest, "^%x+%-%d+$") ~= nil):toEqual(true)

		local many = Verify.segment(string.rep("x", 25), 10)
		expect(#many):toEqual(3)
		expect(many[1].payload):toEqual(string.rep("x", 10))
		expect(many[3].payload):toEqual(string.rep("x", 5))
		expect(many[1].count):toEqual(3)
		expect(many[1].totalBytes):toEqual(25)

		expect(many[1].totalDigest):toEqual(many[3].totalDigest)
	end)

	it("segments an empty payload to exactly one empty segment", function()
		local segments = Verify.segment("", 10)
		expect(#segments):toEqual(1)
		expect(segments[1].payload):toEqual ""
		expect(segments[1].totalBytes):toEqual(0)
	end)

	it("round-trips whatever it segmented, out of order", function()
		local payload = string.rep("payload-", 300)
		local segments = Verify.segment(payload, 64)
		local shuffled = { segments[3], segments[1], segments[2] }
		for index = 4, #segments do
			table.insert(shuffled, segments[index])
		end
		local recovered, problem = Verify.reassembleSegments(shuffled)
		expect(problem):toEqual(nil)
		expect(recovered):toEqual(payload)
	end)

	it("tolerates a duplicated segment and rejects a conflicting duplicate", function()
		local segments = Verify.segment("abcdef", 2)
		local withDuplicate = { segments[1], segments[1], segments[2], segments[3] }
		local recovered, problem = Verify.reassembleSegments(withDuplicate)
		expect(problem):toEqual(nil)
		expect(recovered):toEqual "abcdef"

		local conflicting = table.clone(segments[1])
		conflicting.payload = "zz"

		conflicting.digest = Verify.segment("zz", 1000)[1].digest
		local _, conflict = Verify.reassembleSegments { segments[1], conflicting, segments[2], segments[3] }
		expect((tostring(conflict))):toContain "appears twice with different bytes"
	end)

	it("names a missing segment instead of returning a truncated payload", function()
		local segments = Verify.segment("abcdef", 2)
		local _, problem = Verify.reassembleSegments { segments[1], segments[3] }
		expect((tostring(problem))):toContain "segment 2 of 3 is missing"
	end)

	it("names a segment whose bytes do not match its own digest", function()
		local segments = Verify.segment("abcdef", 2)
		local corrupted = table.clone(segments[1])
		corrupted.payload = "zz"
		local _, problem = Verify.reassembleSegments { corrupted, segments[2], segments[3] }
		expect((tostring(problem))):toContain "failed its own digest check"
	end)

	it("names segments that disagree about the whole payload", function()
		local left = Verify.segment("abcdef", 2)
		local right = Verify.segment("abcxyz", 2)
		local _, digestProblem = Verify.reassembleSegments { left[1], right[2], left[3] }
		expect((tostring(digestProblem))):toContain "disagree about the whole payload"

		local longer = Verify.segment("abcdefg", 2)
		local _, countProblem = Verify.reassembleSegments { left[1], longer[1] }
		expect((tostring(countProblem))):toContain "disagree about the total count"
	end)

	it("names an empty segment list", function()
		local recovered, problem = Verify.reassembleSegments {}
		expect(recovered):toEqual(nil)
		expect((tostring(problem))):toContain "no segment was supplied"
	end)

	it("validates decoded segment rows before trusting their fields", function()
		local segments = Verify.segment("decoded payload", 64)
		local decoded: { unknown } = { segments[1] }
		local recovered, problem = Verify.reassembleSegments(decoded)
		expect(recovered):toEqual "decoded payload"
		expect(problem):toEqual(nil)
		local malformed: { unknown } = { false, "segment", {}, { count = "one" } }
		for _, row in malformed do
			local value, reason = Verify.reassembleSegments { row }
			expect(value):toEqual(nil)
			expect(reason):toEqual "a segment is malformed"
		end
	end)

	it("refuses every malformed field in a decoded segment without modifying its input", function()
		local segment = Verify.segment("decoded payload", 64)[1]
		local wire: { [string]: unknown } = {
			index = segment.index,
			count = segment.count,
			digest = segment.digest,
			totalDigest = segment.totalDigest,
			totalBytes = segment.totalBytes,
			payload = segment.payload,
		}
		for _, field in { "index", "count", "digest", "totalDigest", "totalBytes", "payload" } do
			local invalid = table.clone(wire)
			invalid[field] = false
			local value, reason = Verify.reassembleSegments { invalid }
			expect(value):toEqual(nil)
			expect(reason):toEqual "a segment is malformed"
			expect(invalid[field]):toEqual(false)
			expect(wire[field]):toEqual(segment[field])
		end
	end)

	it("refuses a non-positive or fractional segment size", function()
		expect((pcall(Verify.segment, "x", 0))):toEqual(false)
		expect((pcall(Verify.segment, "x", -1))):toEqual(false)
		expect((pcall(Verify.segment, "x", 1.5))):toEqual(false)
	end)
end)

describe("session framing", function()
	local function clock(): number
		return 0
	end

	local function specFor(name: string, requires: { string }?): (Verify.Harness) -> ()
		return function(harness: Verify.Harness)
			harness:case(name, {
				requires = requires,
				run = function(context)
					context:expect(true):toBe(true)
				end,
			})
		end
	end

	it("keeps one isolated registry per source and merges them", function()
		local session = Verify.createSession {
			executor = "test",
			environment = { runtime = "test" },
			capabilities = { "in-memory" },
			now = clock,
		}
		session:open "first.verify.luau"
		specFor "alpha"(session:harness())
		session:close()
		session:open "second.verify.luau"
		specFor "beta"(session:harness())
		session:close()
		local report = session:run()
		expect(report.total):toEqual(2)
		expect(report.results[1].source):toEqual "first.verify.luau"
		expect(report.results[2].source):toEqual "second.verify.luau"
		expect(report.results[1].id):toEqual "alpha"
	end)

	it("carries the declared capability set so unsupported is reachable", function()
		local session = Verify.createSession {
			executor = "test",
			environment = { runtime = "test" },
			capabilities = { "in-memory" },
			now = clock,
		}
		session:open "source.verify.luau"
		specFor("needs an engine", { "engine-datamodel" })(session:harness())
		specFor("needs memory", { "in-memory" })(session:harness())
		session:close()
		local report = session:run()
		expect(report.capabilities):toEqual { "in-memory" }
		expect(report.unsupported):toEqual(1)
		expect(report.passed):toEqual(1)
		expect(report.results[1].missingCapabilities):toEqual { "engine-datamodel" }
	end)

	it("prefixes case ids only when the caller asks", function()
		local function idFor(prefix: boolean): string
			local session = Verify.createSession {
				executor = "test",
				environment = {},
				now = clock,
				prefixCaseIds = prefix,
			}
			session:open "source.verify.luau"
			specFor "alpha"(session:harness())
			session:close()
			return session:run().results[1].id
		end
		expect((idFor(false))):toEqual "alpha"
		expect((idFor(true))):toEqual "source.verify.luau::alpha"
	end)

	it("turns a source that did not load into a named case", function()
		local session = Verify.createSession { executor = "test", environment = {}, now = clock }
		session:adoptReport(
			"broken.verify.luau",
			session:sourceReport("source:broken:load", "broken.verify.luau", "failed", "syntax error")
		)
		local report = session:run()
		expect(report.failed):toEqual(1)
		expect(report.results[1].failures[1].phase):toEqual "load"
		expect(report.results[1].failures[1].message):toContain "syntax error"
	end)

	it("routes authoring verbs to the source that is registering", function()
		type AuthoringSurface = { it: (string, (Verify.Context) -> ()) -> () }
		local options: Verify.SessionProvidedOptions<AuthoringSurface> = {
			executor = "test",
			environment = {},
			now = clock,
			surface = function(harness: Verify.Harness)
				return {
					it = function(name: string, body: (Verify.Context) -> ())
						harness:case(name, body)
					end,
				}
			end,
		}
		local session = Verify.createSession(options)
		session:open "first.verify.luau"
		session.verbs.it("alpha", function(context)
			context:expect(1):toBe(1)
		end)
		session:close()
		local report = session:run()
		expect(report.results[1].id):toEqual "alpha"
		expect(report.passed):toEqual(1)
	end)

	it("refuses a mid-run reset and still runs the sources queued behind it", function()
		local session = Verify.createSession { executor = "test", environment = {}, now = clock }
		session:open "resetting.verify.luau"
		local harness = session:harness()
		harness:case("resets the ambient session", function()
			session:reset()
		end)
		session:close()
		session:open "queued.verify.luau"
		specFor "beta"(session:harness())
		session:close()
		local report = session:run()
		expect(report.total):toEqual(2)
		expect(report.failed):toEqual(1)
		expect(report.passed):toEqual(1)
		expect(report.results[1].failures[1].message):toContain "reset while its run is in progress"
		expect(report.results[2].source):toEqual "queued.verify.luau"
		expect(report.results[2].id):toEqual "beta"
	end)

	it("lets a case run an isolated nested session without losing the outer queue", function()
		local session = Verify.createSession { executor = "test", environment = {}, now = clock }
		session:open "nesting.verify.luau"
		local harness = session:harness()
		harness:case("runs and resets a session of its own", function(context)
			local nested = Verify.createSession { executor = "nested", environment = {}, now = clock }
			nested:open "nested.verify.luau"
			specFor "gamma"(nested:harness())
			nested:close()
			local produced = nested:run()
			nested:reset()
			context:expect(produced.passed):toBe(1)
		end)
		session:close()
		session:open "queued.verify.luau"
		specFor "delta"(session:harness())
		session:close()
		local report = session:run()
		expect(report.total):toEqual(2)
		expect(report.passed):toEqual(2)
		expect(report.results[2].source):toEqual "queued.verify.luau"
		expect(report.results[2].id):toEqual "delta"
	end)

	it("refuses a re-entrant run of the same session", function()
		local session = Verify.createSession { executor = "test", environment = {}, now = clock }
		session:open "reentrant.verify.luau"
		local harness = session:harness()
		harness:case("runs the session it is running under", function()
			session:run()
		end)
		session:close()
		local report = session:run()
		expect(report.failed):toEqual(1)
		expect(report.results[1].failures[1].message):toContain "run is already in progress"
	end)

	it("refuses a registration outside an open source", function()
		local session = Verify.createSession { executor = "test", environment = {}, now = clock }
		expect((pcall(function()
			session:harness()
		end))):toEqual(false)
	end)

	it("narrows a run through a selection predicate", function()
		local session = Verify.createSession { executor = "test", environment = {}, now = clock }
		session:open "source.verify.luau"
		specFor "kept"(session:harness())
		specFor "dropped"(session:harness())
		session:close()
		session:setSelection {
			predicate = function(subject: Verify.SelectionSubject): boolean
				return subject.id == "kept"
			end,
		}
		local report = session:run()
		expect(report.total):toEqual(1)
		expect(report.results[1].id):toEqual "kept"
	end)

	it("hands a bare-id session's predicate the case source", function()
		local function keptIdsFor(prefix: boolean): { string }
			local session = Verify.createSession {
				executor = "test",
				environment = {},
				now = clock,
				prefixCaseIds = prefix,
			}
			session:open "suites/alpha.verify.luau"
			specFor "kept"(session:harness())
			session:close()
			session:open "suites/beta.verify.luau"
			specFor "dropped"(session:harness())
			session:close()
			session:setSelection {
				predicate = function(subject: Verify.SelectionSubject): boolean
					return subject.source ~= nil and string.find(subject.source, "alpha", 1, true) ~= nil
				end,
			}
			local ids: { string } = {}
			for _, result in session:run().results do
				table.insert(ids, result.id)
			end
			return ids
		end
		expect((keptIdsFor(false))):toEqual { "kept" }
		expect((keptIdsFor(true))):toEqual { "suites/alpha.verify.luau::kept" }
	end)

	it("hands the predicate one subject carrying identity and attribution", function()
		local session = Verify.createSession { executor = "test", environment = {}, now = clock }
		session:open "suites/alpha.verify.luau"
		local harness = session:harness()
		harness:suite("outer", function()
			harness:case("inner", {
				tags = { "fast" },
				requires = { "in-memory" },
				run = function(context)
					context:expect(true):toBe(true)
				end,
			})
		end)
		session:close()
		local seen: { Verify.SelectionSubject } = {}
		session:setSelection {
			predicate = function(subject: Verify.SelectionSubject): boolean
				table.insert(seen, subject)
				return true
			end,
		}
		session:run()
		expect(#seen):toEqual(1)
		expect(seen[1].id):toEqual "outer > inner"
		expect(seen[1].source):toEqual "suites/alpha.verify.luau"
		expect(seen[1].path):toEqual { "outer" }
		expect(seen[1].name):toEqual "inner"
		expect(seen[1].tags):toEqual { "fast" }
		expect(seen[1].requires):toEqual { "in-memory" }
	end)
end)

return nil
