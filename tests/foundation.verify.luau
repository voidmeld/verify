--!strict

local Verify = require "../src/core"

return function(suite: Verify.Harness)
	suite:suite("result transport", function()
		suite:case("frames a small payload whole and a large one in chunks", function(check)
			check:expect((Verify.frame("VERIFY", "hello", 700))):toEqual { "VERIFY|hello" }
			local lines = Verify.frame("VERIFY", string.rep("x", 25), 10)
			check:expect(#lines):toEqual(3)
			check:expect(lines[1]):toEqual("VERIFY|chunk|1/3|" .. string.rep("x", 10))
			check:expect(lines[3]):toEqual("VERIFY|chunk|3/3|" .. string.rep("x", 5))
		end)

		suite:case("recovers a payload from lines a host prefixed with its own noise", function(check)
			local log = table.concat({
				"12:00:01 info starting",
				"12:00:02 info VERIFY|chunk|1/2|abc",
				"12:00:03 warn something unrelated",
				"12:00:04 info VERIFY|chunk|2/2|def",
				"12:00:05 info done",
			}, "\r\n")
			local payload, problem = Verify.receipt(log, "VERIFY")
			check:expect(problem):toEqual(nil)
			check:expect(payload):toEqual "abcdef"
		end)

		suite:case("round-trips whatever it framed", function(check)
			local payload = string.rep("payload-", 200)
			local lines = Verify.frame("RECEIPT", payload, 64)
			local recovered = Verify.receipt(table.concat(lines, "\n"), "RECEIPT")
			check:expect(recovered):toEqual(payload)
		end)

		suite:case("names a missing chunk instead of returning a truncated payload", function(check)
			local payload, problem =
				Verify.reassemble(Verify.extract("VERIFY|chunk|1/3|a\nVERIFY|chunk|3/3|c", "VERIFY"))
			check:expect(payload):toEqual(nil)
			check:expect((tostring(problem))):toContain "chunk 2 of 3 is missing"
		end)

		suite:case("names a chunk that appeared twice with different bytes", function(check)
			local payload, problem = Verify.reassemble(
				Verify.extract("VERIFY|chunk|1/2|a\nVERIFY|chunk|1/2|z\nVERIFY|chunk|2/2|b", "VERIFY")
			)
			check:expect(payload):toEqual(nil)
			check:expect((tostring(problem))):toContain "appears twice with different bytes"
		end)

		suite:case("tolerates a chunk repeated identically", function(check)
			local payload = Verify.reassemble(
				Verify.extract("VERIFY|chunk|1/2|a\nVERIFY|chunk|1/2|a\nVERIFY|chunk|2/2|b", "VERIFY")
			)
			check:expect(payload):toEqual "ab"
		end)

		suite:case("names disagreeing chunk counts and mixed framing", function(check)
			local _, counts = Verify.reassemble(Verify.extract("VERIFY|chunk|1/2|a\nVERIFY|chunk|2/3|b", "VERIFY"))
			check:expect((tostring(counts))):toContain "chunk counts disagree"
			local _, mixed = Verify.reassemble(Verify.extract("VERIFY|whole\nVERIFY|chunk|1/1|a", "VERIFY"))
			check:expect((tostring(mixed))):toContain "mixed framing"
		end)

		suite:case("names two whole receipts rather than picking one", function(check)
			local _, problem = Verify.reassemble(Verify.extract("VERIFY|first\nVERIFY|second", "VERIFY"))
			check:expect((tostring(problem))):toContain "2 whole records"
		end)

		suite:case("names an absent receipt", function(check)
			local payload, problem = Verify.receipt("nothing here at all", "VERIFY")
			check:expect(payload):toEqual(nil)
			check:expect((tostring(problem))):toContain "no tagged record"
		end)

		suite:case("reports the line each record was found on", function(check)
			local records = Verify.extract("noise\nnoise\nVERIFY|here", "VERIFY")
			check:expect(#records):toEqual(1)
			check:expect(records[1].ordinal):toEqual(3)
			check:expect(records[1].payload):toEqual "here"
		end)

		suite:case("refuses a tag that would collide with the field separator", function(check)
			check:expect((pcall(Verify.frame, "VER|IFY", "x"))):toEqual(false)
			check:expect((pcall(Verify.frame, "", "x"))):toEqual(false)
		end)
	end)

	suite:suite("segmented result transport", function()
		suite:case("segments a small payload to one piece and a large one to several", function(check)
			local one = Verify.segment("hello", 700)
			check:expect(#one):toEqual(1)
			check:expect(one[1].index):toEqual(1)
			check:expect(one[1].count):toEqual(1)
			check:expect(one[1].totalBytes):toEqual(5)
			check:expect(one[1].payload):toEqual "hello"
			check:expect(one[1].digest):toEqual(one[1].totalDigest)
			check:expect(string.match(one[1].digest, "^%x+%-%d+$") ~= nil):toEqual(true)

			local many = Verify.segment(string.rep("x", 25), 10)
			check:expect(#many):toEqual(3)
			check:expect(many[1].payload):toEqual(string.rep("x", 10))
			check:expect(many[3].payload):toEqual(string.rep("x", 5))
			check:expect(many[1].count):toEqual(3)
			check:expect(many[1].totalBytes):toEqual(25)

			check:expect(many[1].totalDigest):toEqual(many[3].totalDigest)
		end)

		suite:case("segments an empty payload to exactly one empty segment", function(check)
			local segments = Verify.segment("", 10)
			check:expect(#segments):toEqual(1)
			check:expect(segments[1].payload):toEqual ""
			check:expect(segments[1].totalBytes):toEqual(0)
		end)

		suite:case("round-trips whatever it segmented, out of order", function(check)
			local payload = string.rep("payload-", 300)
			local segments = Verify.segment(payload, 64)
			local shuffled = { segments[3], segments[1], segments[2] }
			for index = 4, #segments do
				table.insert(shuffled, segments[index])
			end
			local recovered, problem = Verify.reassembleSegments(shuffled)
			check:expect(problem):toEqual(nil)
			check:expect(recovered):toEqual(payload)
		end)

		suite:case("tolerates a duplicated segment and rejects a conflicting duplicate", function(check)
			local segments = Verify.segment("abcdef", 2)
			local withDuplicate = { segments[1], segments[1], segments[2], segments[3] }
			local recovered, problem = Verify.reassembleSegments(withDuplicate)
			check:expect(problem):toEqual(nil)
			check:expect(recovered):toEqual "abcdef"

			local conflicting = table.clone(segments[1])
			conflicting.payload = "zz"

			conflicting.digest = Verify.segment("zz", 1000)[1].digest
			local _, conflict = Verify.reassembleSegments { segments[1], conflicting, segments[2], segments[3] }
			check:expect((tostring(conflict))):toContain "appears twice with different bytes"
		end)

		suite:case("names a missing segment instead of returning a truncated payload", function(check)
			local segments = Verify.segment("abcdef", 2)
			local _, problem = Verify.reassembleSegments { segments[1], segments[3] }
			check:expect((tostring(problem))):toContain "segment 2 of 3 is missing"
		end)

		suite:case("names a segment whose bytes do not match its own digest", function(check)
			local segments = Verify.segment("abcdef", 2)
			local corrupted = table.clone(segments[1])
			corrupted.payload = "zz"
			local _, problem = Verify.reassembleSegments { corrupted, segments[2], segments[3] }
			check:expect((tostring(problem))):toContain "failed its own digest check"
		end)

		suite:case("names segments that disagree about the whole payload", function(check)
			local left = Verify.segment("abcdef", 2)
			local right = Verify.segment("abcxyz", 2)
			local _, digestProblem = Verify.reassembleSegments { left[1], right[2], left[3] }
			check:expect((tostring(digestProblem))):toContain "disagree about the whole payload"

			local longer = Verify.segment("abcdefg", 2)
			local _, countProblem = Verify.reassembleSegments { left[1], longer[1] }
			check:expect((tostring(countProblem))):toContain "disagree about the total count"
		end)

		suite:case("names an empty segment list", function(check)
			local recovered, problem = Verify.reassembleSegments {}
			check:expect(recovered):toEqual(nil)
			check:expect((tostring(problem))):toContain "no segment was supplied"
		end)

		suite:case("refuses a non-positive or fractional segment size", function(check)
			check:expect((pcall(Verify.segment, "x", 0))):toEqual(false)
			check:expect((pcall(Verify.segment, "x", -1))):toEqual(false)
			check:expect((pcall(Verify.segment, "x", 1.5))):toEqual(false)
		end)
	end)

	suite:suite("session framing", function()
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

		suite:case("keeps one isolated registry per source and merges them", function(check)
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
			check:expect(report.total):toEqual(2)
			check:expect(report.results[1].source):toEqual "first.verify.luau"
			check:expect(report.results[2].source):toEqual "second.verify.luau"
			check:expect(report.results[1].id):toEqual "alpha"
		end)

		suite:case("carries the declared capability set so unsupported is reachable", function(check)
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
			check:expect(report.capabilities):toEqual { "in-memory" }
			check:expect(report.unsupported):toEqual(1)
			check:expect(report.passed):toEqual(1)
			check:expect(report.results[1].missingCapabilities):toEqual { "engine-datamodel" }
		end)

		suite:case("prefixes case ids only when the caller asks", function(check)
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
			check:expect((idFor(false))):toEqual "alpha"
			check:expect((idFor(true))):toEqual "source.verify.luau::alpha"
		end)

		suite:case("turns a source that did not load into a named case", function(check)
			local session = Verify.createSession { executor = "test", environment = {}, now = clock }
			session:adoptReport(
				"broken.verify.luau",
				session:sourceReport("source:broken:load", "broken.verify.luau", "failed", "syntax error")
			)
			local report = session:run()
			check:expect(report.failed):toEqual(1)
			check:expect(report.results[1].failures[1].phase):toEqual "load"
			check:expect(report.results[1].failures[1].message):toContain "syntax error"
		end)

		suite:case("routes authoring verbs to the source that is registering", function(check)
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
			check:expect(report.results[1].id):toEqual "alpha"
			check:expect(report.passed):toEqual(1)
		end)

		suite:case("refuses a mid-run reset and still runs the sources queued behind it", function(check)
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
			check:expect(report.total):toEqual(2)
			check:expect(report.failed):toEqual(1)
			check:expect(report.passed):toEqual(1)
			check:expect(report.results[1].failures[1].message):toContain "reset while its run is in progress"
			check:expect(report.results[2].source):toEqual "queued.verify.luau"
			check:expect(report.results[2].id):toEqual "beta"
		end)

		suite:case("lets a case run an isolated nested session without losing the outer queue", function(check)
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
			check:expect(report.total):toEqual(2)
			check:expect(report.passed):toEqual(2)
			check:expect(report.results[2].source):toEqual "queued.verify.luau"
			check:expect(report.results[2].id):toEqual "delta"
		end)

		suite:case("refuses a re-entrant run of the same session", function(check)
			local session = Verify.createSession { executor = "test", environment = {}, now = clock }
			session:open "reentrant.verify.luau"
			local harness = session:harness()
			harness:case("runs the session it is running under", function()
				session:run()
			end)
			session:close()
			local report = session:run()
			check:expect(report.failed):toEqual(1)
			check:expect(report.results[1].failures[1].message):toContain "run is already in progress"
		end)

		suite:case("refuses a registration outside an open source", function(check)
			local session = Verify.createSession { executor = "test", environment = {}, now = clock }
			check
				:expect((pcall(function()
					session:harness()
				end)))
				:toEqual(false)
		end)

		suite:case("narrows a run through a selection predicate", function(check)
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
			check:expect(report.total):toEqual(1)
			check:expect(report.results[1].id):toEqual "kept"
		end)

		suite:case("hands a bare-id session's predicate the case source", function(check)
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
						return subject.source ~= nil and string.find(subject.source :: string, "alpha", 1, true) ~= nil
					end,
				}
				local ids: { string } = {}
				for _, result in session:run().results do
					table.insert(ids, result.id)
				end
				return ids
			end
			check:expect((keptIdsFor(false))):toEqual { "kept" }
			check:expect((keptIdsFor(true))):toEqual { "suites/alpha.verify.luau::kept" }
		end)

		suite:case("hands the predicate one subject carrying identity and attribution", function(check)
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
			check:expect(#seen):toEqual(1)
			check:expect(seen[1].id):toEqual "outer > inner"
			check:expect(seen[1].source):toEqual "suites/alpha.verify.luau"
			check:expect(seen[1].path):toEqual { "outer" }
			check:expect(seen[1].name):toEqual "inner"
			check:expect(seen[1].tags):toEqual { "fast" }
			check:expect(seen[1].requires):toEqual { "in-memory" }
		end)
	end)
end
