--!strict

local test = require "@std/test"

local Verify = require "../src/core"

test.suite("result transport", function(suite)
	suite:case("frames a small payload whole and a large one in chunks", function(assert)
		assert.eq(Verify.frame("VERIFY", "hello", 700), { "VERIFY|hello" })
		local lines = Verify.frame("VERIFY", string.rep("x", 25), 10)
		assert.eq(#lines, 3)
		assert.eq(lines[1], "VERIFY|chunk|1/3|" .. string.rep("x", 10))
		assert.eq(lines[3], "VERIFY|chunk|3/3|" .. string.rep("x", 5))
	end)

	suite:case("recovers a payload from lines a host prefixed with its own noise", function(assert)
		local log = table.concat({
			"12:00:01 info starting",
			"12:00:02 info VERIFY|chunk|1/2|abc",
			"12:00:03 warn something unrelated",
			"12:00:04 info VERIFY|chunk|2/2|def",
			"12:00:05 info done",
		}, "\r\n")
		local payload, problem = Verify.receipt(log, "VERIFY")
		assert.eq(problem, nil)
		assert.eq(payload, "abcdef")
	end)

	suite:case("round-trips whatever it framed", function(assert)
		local payload = string.rep("payload-", 200)
		local lines = Verify.frame("RECEIPT", payload, 64)
		local recovered = Verify.receipt(table.concat(lines, "\n"), "RECEIPT")
		assert.eq(recovered, payload)
	end)

	suite:case("names a missing chunk instead of returning a truncated payload", function(assert)
		local payload, problem = Verify.reassemble(Verify.extract("VERIFY|chunk|1/3|a\nVERIFY|chunk|3/3|c", "VERIFY"))
		assert.eq(payload, nil)
		assert.strContains(tostring(problem), "chunk 2 of 3 is missing")
	end)

	suite:case("names a chunk that appeared twice with different bytes", function(assert)
		local payload, problem =
			Verify.reassemble(Verify.extract("VERIFY|chunk|1/2|a\nVERIFY|chunk|1/2|z\nVERIFY|chunk|2/2|b", "VERIFY"))
		assert.eq(payload, nil)
		assert.strContains(tostring(problem), "appears twice with different bytes")
	end)

	suite:case("tolerates a chunk repeated identically", function(assert)
		local payload =
			Verify.reassemble(Verify.extract("VERIFY|chunk|1/2|a\nVERIFY|chunk|1/2|a\nVERIFY|chunk|2/2|b", "VERIFY"))
		assert.eq(payload, "ab")
	end)

	suite:case("names disagreeing chunk counts and mixed framing", function(assert)
		local _, counts = Verify.reassemble(Verify.extract("VERIFY|chunk|1/2|a\nVERIFY|chunk|2/3|b", "VERIFY"))
		assert.strContains(tostring(counts), "chunk counts disagree")
		local _, mixed = Verify.reassemble(Verify.extract("VERIFY|whole\nVERIFY|chunk|1/1|a", "VERIFY"))
		assert.strContains(tostring(mixed), "mixed framing")
	end)

	suite:case("names two whole receipts rather than picking one", function(assert)
		local _, problem = Verify.reassemble(Verify.extract("VERIFY|first\nVERIFY|second", "VERIFY"))
		assert.strContains(tostring(problem), "2 whole records")
	end)

	suite:case("names an absent receipt", function(assert)
		local payload, problem = Verify.receipt("nothing here at all", "VERIFY")
		assert.eq(payload, nil)
		assert.strContains(tostring(problem), "no tagged record")
	end)

	suite:case("reports the line each record was found on", function(assert)
		local records = Verify.extract("noise\nnoise\nVERIFY|here", "VERIFY")
		assert.eq(#records, 1)
		assert.eq(records[1].ordinal, 3)
		assert.eq(records[1].payload, "here")
	end)

	suite:case("refuses a tag that would collide with the field separator", function(assert)
		assert.eq(pcall(Verify.frame, "VER|IFY", "x"), false)
		assert.eq(pcall(Verify.frame, "", "x"), false)
	end)
end)

test.suite("segmented result transport", function(suite)
	suite:case("segments a small payload to one piece and a large one to several", function(assert)
		local one = Verify.segment("hello", 700)
		assert.eq(#one, 1)
		assert.eq(one[1].index, 1)
		assert.eq(one[1].count, 1)
		assert.eq(one[1].totalBytes, 5)
		assert.eq(one[1].payload, "hello")
		assert.eq(one[1].digest, one[1].totalDigest)
		assert.eq(string.match(one[1].digest, "^%x+%-%d+$") ~= nil, true)

		local many = Verify.segment(string.rep("x", 25), 10)
		assert.eq(#many, 3)
		assert.eq(many[1].payload, string.rep("x", 10))
		assert.eq(many[3].payload, string.rep("x", 5))
		assert.eq(many[1].count, 3)
		assert.eq(many[1].totalBytes, 25)

		assert.eq(many[1].totalDigest, many[3].totalDigest)
	end)

	suite:case("segments an empty payload to exactly one empty segment", function(assert)
		local segments = Verify.segment("", 10)
		assert.eq(#segments, 1)
		assert.eq(segments[1].payload, "")
		assert.eq(segments[1].totalBytes, 0)
	end)

	suite:case("round-trips whatever it segmented, out of order", function(assert)
		local payload = string.rep("payload-", 300)
		local segments = Verify.segment(payload, 64)
		local shuffled = { segments[3], segments[1], segments[2] }
		for index = 4, #segments do
			table.insert(shuffled, segments[index])
		end
		local recovered, problem = Verify.reassembleSegments(shuffled)
		assert.eq(problem, nil)
		assert.eq(recovered, payload)
	end)

	suite:case("tolerates a duplicated segment and rejects a conflicting duplicate", function(assert)
		local segments = Verify.segment("abcdef", 2)
		local withDuplicate = { segments[1], segments[1], segments[2], segments[3] }
		local recovered, problem = Verify.reassembleSegments(withDuplicate)
		assert.eq(problem, nil)
		assert.eq(recovered, "abcdef")

		local conflicting = table.clone(segments[1])
		conflicting.payload = "zz"

		conflicting.digest = Verify.segment("zz", 1000)[1].digest
		local _, conflict = Verify.reassembleSegments { segments[1], conflicting, segments[2], segments[3] }
		assert.strContains(tostring(conflict), "appears twice with different bytes")
	end)

	suite:case("names a missing segment instead of returning a truncated payload", function(assert)
		local segments = Verify.segment("abcdef", 2)
		local _, problem = Verify.reassembleSegments { segments[1], segments[3] }
		assert.strContains(tostring(problem), "segment 2 of 3 is missing")
	end)

	suite:case("names a segment whose bytes do not match its own digest", function(assert)
		local segments = Verify.segment("abcdef", 2)
		local corrupted = table.clone(segments[1])
		corrupted.payload = "zz"
		local _, problem = Verify.reassembleSegments { corrupted, segments[2], segments[3] }
		assert.strContains(tostring(problem), "failed its own digest check")
	end)

	suite:case("names segments that disagree about the whole payload", function(assert)
		local left = Verify.segment("abcdef", 2)
		local right = Verify.segment("abcxyz", 2)
		local _, digestProblem = Verify.reassembleSegments { left[1], right[2], left[3] }
		assert.strContains(tostring(digestProblem), "disagree about the whole payload")

		local longer = Verify.segment("abcdefg", 2)
		local _, countProblem = Verify.reassembleSegments { left[1], longer[1] }
		assert.strContains(tostring(countProblem), "disagree about the total count")
	end)

	suite:case("names an empty segment list", function(assert)
		local recovered, problem = Verify.reassembleSegments {}
		assert.eq(recovered, nil)
		assert.strContains(tostring(problem), "no segment was supplied")
	end)

	suite:case("refuses a non-positive or fractional segment size", function(assert)
		assert.eq(pcall(Verify.segment, "x", 0), false)
		assert.eq(pcall(Verify.segment, "x", -1), false)
		assert.eq(pcall(Verify.segment, "x", 1.5), false)
	end)
end)

test.suite("session framing", function(suite)
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

	suite:case("keeps one isolated registry per source and merges them", function(assert)
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
		assert.eq(report.total, 2)
		assert.eq(report.results[1].source, "first.verify.luau")
		assert.eq(report.results[2].source, "second.verify.luau")
		assert.eq(report.results[1].id, "alpha")
	end)

	suite:case("carries the declared capability set so unsupported is reachable", function(assert)
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
		assert.eq(report.capabilities, { "in-memory" })
		assert.eq(report.unsupported, 1)
		assert.eq(report.passed, 1)
		assert.eq(report.results[1].missingCapabilities, { "engine-datamodel" })
	end)

	suite:case("prefixes case ids only when the caller asks", function(assert)
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
		assert.eq(idFor(false), "alpha")
		assert.eq(idFor(true), "source.verify.luau::alpha")
	end)

	suite:case("turns a source that did not load into a named case", function(assert)
		local session = Verify.createSession { executor = "test", environment = {}, now = clock }
		session:adoptReport(
			"broken.verify.luau",
			session:sourceReport("source:broken:load", "broken.verify.luau", "failed", "syntax error")
		)
		local report = session:run()
		assert.eq(report.failed, 1)
		assert.eq(report.results[1].failures[1].phase, "load")
		assert.strContains(report.results[1].failures[1].message, "syntax error")
	end)

	suite:case("routes authoring verbs to the source that is registering", function(assert)
		local session = Verify.createSession {
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
		session:open "first.verify.luau"
		session.verbs.it("alpha", function(context)
			context:expect(1):toBe(1)
		end)
		session:close()
		local report = session:run()
		assert.eq(report.results[1].id, "alpha")
		assert.eq(report.passed, 1)
	end)

	suite:case("refuses a mid-run reset and still runs the sources queued behind it", function(assert)
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
		assert.eq(report.total, 2)
		assert.eq(report.failed, 1)
		assert.eq(report.passed, 1)
		assert.strContains(report.results[1].failures[1].message, "reset while its run is in progress")
		assert.eq(report.results[2].source, "queued.verify.luau")
		assert.eq(report.results[2].id, "beta")
	end)

	suite:case("lets a case run an isolated nested session without losing the outer queue", function(assert)
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
		assert.eq(report.total, 2)
		assert.eq(report.passed, 2)
		assert.eq(report.results[2].source, "queued.verify.luau")
		assert.eq(report.results[2].id, "delta")
	end)

	suite:case("refuses a re-entrant run of the same session", function(assert)
		local session = Verify.createSession { executor = "test", environment = {}, now = clock }
		session:open "reentrant.verify.luau"
		local harness = session:harness()
		harness:case("runs the session it is running under", function()
			session:run()
		end)
		session:close()
		local report = session:run()
		assert.eq(report.failed, 1)
		assert.strContains(report.results[1].failures[1].message, "run is already in progress")
	end)

	suite:case("refuses a registration outside an open source", function(assert)
		local session = Verify.createSession { executor = "test", environment = {}, now = clock }
		assert.eq(
			pcall(function()
				session:harness()
			end),
			false
		)
	end)

	suite:case("narrows a run through a selection predicate", function(assert)
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
		assert.eq(report.total, 1)
		assert.eq(report.results[1].id, "kept")
	end)

	suite:case("hands a bare-id session's predicate the case source", function(assert)
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
		assert.eq(keptIdsFor(false), { "kept" })
		assert.eq(keptIdsFor(true), { "suites/alpha.verify.luau::kept" })
	end)

	suite:case("hands the predicate one subject carrying identity and attribution", function(assert)
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
		assert.eq(#seen, 1)
		assert.eq(seen[1].id, "outer > inner")
		assert.eq(seen[1].source, "suites/alpha.verify.luau")
		assert.eq(seen[1].path, { "outer" })
		assert.eq(seen[1].name, "inner")
		assert.eq(seen[1].tags, { "fast" })
		assert.eq(seen[1].requires, { "in-memory" })
	end)
end)

test.suite("observation bundle", function(suite)
	local DRAFT: Verify.BundleDraft = {
		executor = "collector",
		environment = { target = "sandbox", version = 42, live = false },
		capabilities = { "log-capture" },
		actors = { "operator" },
		artifacts = { { name = "log", reference = "run.log", mediaType = "text/plain" } },
		timeline = { { name = "started", actor = "operator", atSeconds = 0 } },
		observations = { readings = { 1, 2, 3 }, ended = true },
	}

	suite:case("seals to the leaves so an observation cannot be edited", function(assert)
		local bundle = Verify.sealObservations(DRAFT)
		assert.eq(Verify.isSealedBundle(bundle), true)
		assert.eq(bundle.contract, Verify.OBSERVATION_CONTRACT)
		assert.eq(bundle.environment.version, "42")
		assert.eq(bundle.environment.live, "false")
		assert.eq(
			pcall(function()
				(bundle.observations.readings :: any)[1] = 99
			end),
			false
		)
		assert.eq(
			pcall(function()
				(bundle :: any).contract = "something else"
			end),
			false
		)
	end)

	suite:case("snapshots shallow-frozen parents without mutating their owners", function(assert)
		local child = { value = 1 }
		local observations = table.freeze { child = child, alias = child }
		local bundle = Verify.sealObservations { executor = "snapshot", environment = {}, observations = observations }
		child.value = 2
		assert.eq(bundle.observations.child.value, 1)
		assert.eq(bundle.observations.child, bundle.observations.alias)
		assert.eq(table.isfrozen(child), false)
		assert.eq(
			pcall(function()
				bundle.observations.child.value = 3
			end),
			false
		)
	end)

	suite:case("seals cyclic observations without recursion failure", function(assert)
		local observations: any = {}
		observations.self = observations
		local bundle = Verify.sealObservations { executor = "snapshot", environment = {}, observations = observations }
		assert.eq(bundle.observations.self, bundle.observations)
		assert.eq(table.isfrozen(bundle.observations), true)
		assert.eq(table.isfrozen(observations), false)
	end)

	suite:case("holds every nonpassing case even when it carries no failures", function(assert)
		for _, status in { "skipped", "unsupported", "timed_out", "cancelled", "failed" } do
			local report: any = Verify.evaluateObservations(
				Verify.sealObservations(DRAFT),
				"statuses",
				function(harness)
					harness:case("case", function() end)
				end
			)
			report.results[1].status = status
			assert.eq(Verify.observationVerdict(report, "clear").status, "held")
		end
	end)

	suite:case("holds inconsistent aggregate counts", function(assert)
		local report: any = Verify.evaluateObservations(Verify.sealObservations(DRAFT), "counts", function(harness)
			harness:case("case", function() end)
		end)
		report.unsupported = 1
		assert.eq(Verify.observationVerdict(report, "clear").reason, "observation_counts_not_clear")
	end)

	suite:case("carries no verdict of its own", function(assert)
		local bundle = Verify.sealObservations(DRAFT) :: any
		assert.eq(bundle.ok, nil)
		assert.eq(bundle.passed, nil)
		assert.eq(bundle.status, nil)
	end)

	suite:case("refuses a non-scalar environment field and an unsealed bundle", function(assert)
		assert.eq(
			pcall(Verify.sealObservations, {
				executor = "collector",
				environment = { nested = {} },
				observations = {},
			}),
			false
		)
		assert.eq(
			pcall(Verify.evaluateObservations, { contract = Verify.OBSERVATION_CONTRACT } :: any, "s", function() end),
			false
		)
	end)

	suite:case("evaluates through a real harness and stamps the run identity", function(assert)
		local bundle = Verify.sealObservations(DRAFT)
		local report = Verify.evaluateObservations(bundle, "collector-suite", function(harness, observations)
			harness:case("ended", function(context)
				context:step("run_ended", function()
					context:expect(observations.ended):toBe(true)
				end)
			end)
			harness:case("needs an engine", {
				requires = { "engine-datamodel" },
				run = function() end,
			})
		end)
		assert.eq(report.executor, "collector")
		assert.eq(report.environment.target, "sandbox")
		assert.eq(report.capabilities, { "log-capture" })
		assert.eq(report.passed, 1)
		assert.eq(report.unsupported, 1)
		assert.eq(report.results[1].id, "collector-suite::ended")
		assert.eq(Verify.observationVerdict(report, "all clear").status, "held")
	end)

	suite:case("reads a refusal back as the name of the step that failed", function(assert)
		local bundle = Verify.sealObservations(DRAFT)
		local report = Verify.evaluateObservations(bundle, "collector-suite", function(harness)
			harness:case("ended", function(context)
				context:step("run_ended", function()
					context:expect(false):toBe(true)
				end)
			end)
		end)
		local verdict = Verify.observationVerdict(report, "all clear")
		assert.eq(verdict.status, "held")
		assert.eq(verdict.reason, "run_ended")
	end)

	suite:case("holds a run that evaluated nothing", function(assert)
		local bundle = Verify.sealObservations(DRAFT)
		local report = Verify.evaluateObservations(bundle, "collector-suite", function() end)
		assert.eq(Verify.observationVerdict(report, "all clear").reason, "no_cases_evaluated")
	end)

	suite:case("turns a registration that threw into a named failure", function(assert)
		local bundle = Verify.sealObservations(DRAFT)
		local report = Verify.evaluateObservations(bundle, "collector-suite", function()
			error("the suite could not register", 0)
		end)
		assert.eq(report.failed, 1)
		assert.eq(report.results[1].failures[1].phase, "registration")
		assert.eq(Verify.observationVerdict(report, "all clear").status, "held")
	end)
end)
