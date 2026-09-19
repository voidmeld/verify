--!strict

local test = require "@std/test"

local Bdd = require "../src/bdd"
local Verify = require "../src/core"

local function clock()
	local value = 0
	return function(): number
		value += 0.001
		return value
	end
end

local function run(harness: Verify.Harness, capabilities: { string }?): Verify.Report
	return harness:run {
		executor = "test",
		capabilities = capabilities or {},
		environment = { revision = "fixture" },
	}
end

test.suite("verify core", function(suite)
	suite:case("keeps harness registries isolated", function(assert)
		local first = Verify.createHarness { now = clock() }
		local second = Verify.createHarness { now = clock() }
		first:case("first", function() end)
		second:case("second", function() end)
		local firstReport = run(first)
		local secondReport = run(second)
		assert.eq(firstReport.total, 1)
		assert.eq(firstReport.results[1].name, "first")
		assert.eq(secondReport.total, 1)
		assert.eq(secondReport.results[1].name, "second")
	end)

	suite:case("runs nested hooks and cleanup in contractual order", function(assert)
		local harness = Verify.createHarness { now = clock() }
		local order: { string } = {}
		harness:suite("outer", function()
			harness:beforeEach(function(context)
				table.insert(order, "outer setup")
				context:defer(function()
					table.insert(order, "outer cleanup")
				end)
			end)
			harness:afterEach(function()
				table.insert(order, "outer teardown")
			end)
			harness:suite("inner", function()
				harness:beforeEach(function(context)
					table.insert(order, "inner setup")
					context:defer(function()
						table.insert(order, "inner cleanup")
					end)
				end)
				harness:afterEach(function()
					table.insert(order, "inner teardown")
				end)
				harness:case("case", function()
					table.insert(order, "case")
				end)
			end)
		end)
		local report = run(harness)
		assert.eq(report.failed, 0)
		assert.eq(order, {
			"outer setup",
			"inner setup",
			"case",
			"inner teardown",
			"outer teardown",
			"inner cleanup",
			"outer cleanup",
		})
	end)

	suite:case("continues cleanup after failures and retains every failure", function(assert)
		local harness = Verify.createHarness { now = clock() }
		local order: { string } = {}
		harness:case("failure", function(context)
			context:defer(function()
				table.insert(order, "oldest")
				error "oldest failed"
			end)
			context:defer(function()
				table.insert(order, "newest")
				error "newest failed"
			end)
			error "case failed"
		end)
		local report = run(harness)
		assert.eq(report.failed, 1)
		assert.eq(order, { "newest", "oldest" })
		assert.eq(#report.results[1].failures, 3)
		assert.eq(report.results[1].failures[1].phase, "case")
		assert.eq(report.results[1].failures[1].outcome, "failed")
		assert.eq(report.results[1].failures[2].phase, "cleanup")
		assert.eq(report.results[1].failures[3].phase, "cleanup")
	end)

	suite:case("runs teardown and cleanup after setup failure", function(assert)
		local harness = Verify.createHarness { now = clock() }
		local order: { string } = {}
		harness:suite("suite", function()
			harness:beforeEach(function(context)
				context:defer(function()
					table.insert(order, "cleanup")
				end)
				error "setup failed"
			end)
			harness:afterEach(function()
				table.insert(order, "teardown")
			end)
			harness:case("never runs", function()
				table.insert(order, "case")
			end)
		end)
		local report = run(harness)
		assert.eq(report.failed, 1)
		assert.eq(order, { "teardown", "cleanup" })
		assert.eq(report.results[1].failures[1].phase, "setup")
	end)

	suite:case("reports missing capabilities as unsupported", function(assert)
		local harness = Verify.createHarness { now = clock() }
		harness:case("engine observation", {
			requires = { "layout", "engine", "layout" },
			run = function()
				error "must not run"
			end,
		})
		local report = run(harness, { "engine" })
		assert.eq(report.unsupported, 1)
		assert.eq(report.failed, 0)
		assert.eq(report.results[1].missingCapabilities, { "layout" })
	end)

	suite:case("distinguishes declared and runtime skips", function(assert)
		local harness = Verify.createHarness { now = clock() }
		harness:skip("declared", "fixture unavailable")
		harness:case("runtime", function(context)
			context:skip "executor declined"
		end)
		local report = run(harness)
		assert.eq(report.skipped, 2)
		assert.eq(report.results[1].skipReason, "fixture unavailable")
		assert.eq(report.results[2].skipReason, "executor declined")
	end)

	suite:case("retains steps artifacts limitations and environment", function(assert)
		local harness = Verify.createHarness { now = clock() }
		harness:case("receipt", {
			limitations = { "one viewport", "one viewport", "no network" },
			run = function(context)
				context:step("observe", {
					actor = "server",
					run = function()
						context:expect(4):toBeGreaterThan(3)
					end,
				})
				context:artifact("trace", "build/trace.json", "application/json")
			end,
		})
		local report = run(harness)
		local result = report.results[1]
		assert.eq(report.schemaVersion, 1)
		assert.eq(report.environment.revision, "fixture")
		assert.eq(result.steps[1].status, "passed")
		assert.eq(result.steps[1].actor, "server")
		assert.eq(result.artifacts[1].reference, "build/trace.json")
		assert.eq(result.limitations, { "no network", "one viewport" })
	end)

	suite:case("records a failed step as a case failure", function(assert)
		local harness = Verify.createHarness { now = clock() }
		harness:case("step", function(context)
			context:step("break", function()
				error "step broke"
			end)
		end)
		local report = run(harness)
		assert.eq(report.failed, 1)
		assert.eq(report.results[1].steps[1].status, "failed")
		assert.strContains(report.results[1].steps[1].message :: string, "step broke")
	end)

	suite:case("balances the suite stack when registration fails", function(assert)
		local harness = Verify.createHarness { now = clock() }
		local ok = pcall(function()
			harness:suite("broken", function()
				error "registration failed"
			end)
		end)
		assert.that(not ok)
		harness:case("root case", function() end)
		local report = run(harness)
		assert.eq(report.results[1].path, {})
	end)

	suite:case("selects exact ids suite prefixes tags and capabilities without reordering", function(assert)
		local harness = Verify.createHarness { now = clock() }
		harness:suite("inventory", function()
			harness:case("local", { id = "local", tags = { "fast" }, run = function() end })
			harness:case("engine", {
				id = "engine",
				tags = { "fast" },
				requires = { "engine" },
				run = function() end,
			})
		end)
		local byId = harness:run {
			executor = "test",
			capabilities = { "engine" },
			selection = { ids = { "engine" } },
		}
		assert.eq(byId.total, 1)
		assert.eq(byId.results[1].id, "engine")
		local byShape = harness:run {
			executor = "test",
			capabilities = { "engine" },
			selection = {
				suitePrefixes = { "inventory" },
				tags = { "fast" },
				capabilities = { "engine" },
			},
		}
		assert.eq(byShape.total, 1)
		assert.eq(byShape.results[1].id, "engine")
	end)

	suite:case("records executor-enforced timeout and still tears down and cleans up", function(assert)
		local harness = Verify.createHarness { now = clock() }
		local trace: { string } = {}
		harness:suite("timeout", function()
			harness:beforeEach(function(context)
				context:defer(function()
					table.insert(trace, "cleanup")
				end)
			end)
			harness:afterEach(function()
				table.insert(trace, "teardown")
			end)
			harness:case("case", function()
				table.insert(trace, "must not run")
			end)
		end)
		local report = harness:run {
			executor = "controlled",
			invoke = function(phase, callback)
				if phase == "case" then
					return { outcome = "timed_out", error = "10ms deadline" }
				end
				local ok, message = pcall(function(): unknown
					callback()
					return nil
				end)
				return if ok then { outcome = "returned" } else { outcome = "failed", error = message }
			end,
		}
		assert.eq(report.timedOut, 1)
		assert.eq(report.failed, 0)
		assert.eq(trace, { "teardown", "cleanup" })
		assert.eq(report.results[1].failures[1].outcome, "timed_out")
	end)

	suite:case("records cancellation separately from failure", function(assert)
		local harness = Verify.createHarness { now = clock() }
		harness:case("case", function() end)
		local report = harness:run {
			executor = "controlled",
			invoke = function()
				return { outcome = "cancelled", error = "operator cancelled" }
			end,
		}
		assert.eq(report.cancelled, 1)
		assert.eq(report.results[1].status, "cancelled")
	end)

	suite:case("decodes valid reports and rejects unknown schema majors and count drift", function(assert)
		local harness = Verify.createHarness { now = clock() }
		harness:case("case", function() end)
		local report = run(harness)
		assert.eq(Verify.decode(report).total, 1)
		local future = table.clone(report) :: any
		future.schemaVersion = 2
		local futureOk = pcall(Verify.decode, future)
		assert.that(not futureOk)
		local drifted = table.clone(report) :: any
		drifted.passed = 0
		local driftedOk = pcall(Verify.decode, drifted)
		assert.that(not driftedOk)
	end)

	suite:case("keeps source attribution when it does not compose ids", function(assert)
		local harness = Verify.createHarness { now = clock(), source = "suites/alpha.verify.luau", prefixIds = false }
		harness:case("one", function() end)
		local seen: { string? } = {}
		local report = harness:run {
			executor = "worker",
			environment = {},
			selection = {
				predicate = function(subject: Verify.SelectionSubject): boolean
					table.insert(seen, subject.source)
					return true
				end,
			},
		}
		assert.eq(report.results[1].id, "one")
		assert.eq(report.results[1].source, "suites/alpha.verify.luau")
		assert.eq(seen, { "suites/alpha.verify.luau" })
	end)

	suite:case("refuses to prefix ids with a source it was never given", function(assert)
		local ok, thrown: any = pcall(Verify.createHarness, { now = clock(), prefixIds = true })
		assert.eq(ok, false)
		assert.strContains(tostring(thrown), "cannot prefix ids without a source")
	end)

	suite:case("merges shard reports while preserving result origins", function(assert)
		local first = Verify.createHarness { now = clock(), source = "first" }
		local second = Verify.createHarness { now = clock(), source = "second" }
		first:case("one", function() end)
		second:case("two", function() end)
		local merged = Verify.merge({
			first:run { executor = "worker", environment = { shard = "1" } },
			second:run { executor = "worker", environment = { shard = "2" } },
		}, "aggregate", { run = "fixture" })
		assert.eq(merged.total, 2)
		assert.eq(#merged.sources, 2)
		assert.eq(merged.results[1].origin.environment.shard, "1")
		assert.eq(merged.results[2].origin.environment.shard, "2")
	end)

	suite:case("collapses identical origins instead of one per source", function(assert)
		local reports: { Verify.Report } = {}
		for index = 1, 5 do
			local harness = Verify.createHarness { now = clock(), source = "source" .. index }
			harness:case("case", function() end)
			table.insert(reports, harness:run { executor = "worker", environment = { shard = "1" } })
		end
		local merged = Verify.merge(reports, "aggregate", { run = "fixture" })
		assert.eq(merged.total, 5)
		assert.eq(#merged.sources, 1)
		assert.eq(merged.sources[1].environment.shard, "1")
	end)

	suite:case("composes a crashed shard into a named failure", function(assert)
		local composed = Verify.compose({
			{ id = "worker-1", error = "worker exited before writing a report" },
			{ id = "worker-2" },
		}, "aggregate", { run = "fixture" })
		assert.eq(composed.total, 2)
		assert.eq(composed.failed, 2)
		assert.eq(composed.results[1].id, "shard:worker-1")
		assert.eq(composed.results[1].failures[1].phase, "executor")
		assert.eq(composed.results[1].failures[1].message, "worker exited before writing a report")
		assert.eq(composed.results[2].failures[1].message, "shard produced no report")
	end)

	suite:case("composes an undecodable shard payload into a named failure", function(assert)
		local harness = Verify.createHarness { now = clock(), source = "good" }
		harness:case("passes", function() end)
		local healthy = harness:run { executor = "worker", environment = { shard = "1" } }
		local drifted = table.clone(healthy) :: any
		drifted.passed = 99
		local composed = Verify.compose({
			{ id = "worker-1", report = healthy },
			{ id = "worker-2", report = drifted },
			{ id = "worker-3", report = "truncated" },
		}, "aggregate", { run = "fixture" })
		assert.eq(composed.total, 3)
		assert.eq(composed.passed, 1)
		assert.eq(composed.failed, 2)
		assert.eq(composed.results[2].id, "shard:worker-2")
		assert.strContains(composed.results[2].failures[1].message, "undecodable shard payload")
		assert.eq(composed.results[3].id, "shard:worker-3")
	end)

	suite:case("keeps a duplicated case id across shards as a named failure", function(assert)
		local function claim(shard: string): Verify.Report
			local harness = Verify.createHarness { now = clock(), source = "shared" }
			harness:case("contested", function() end)
			return harness:run { executor = "worker", environment = { shard = shard } }
		end
		local composed = Verify.compose({
			{ id = "worker-1", report = claim "1" },
			{ id = "worker-2", report = claim "2" },
		}, "aggregate", { run = "fixture" })
		assert.eq(composed.total, 2)
		assert.eq(composed.passed, 1)
		assert.eq(composed.failed, 1)
		assert.eq(composed.results[1].id, "shared::contested")
		assert.eq(composed.results[1].origin.environment.shard, "1")
		assert.eq(composed.results[2].id, "shard:worker-2:duplicate:shared::contested")
		assert.strContains(composed.results[2].failures[1].message, 'kept the copy from shard "worker-1"')
	end)

	suite:case("rejects a self-contradicting foreign envelope", function(assert)
		local harness = Verify.createHarness { now = clock(), source = "good" }
		harness:case("passes", function() end)
		local report = harness:run { executor = "worker" }
		local lying = table.clone(report) :: any
		lying.results = { table.clone(report.results[1]) }
		lying.results[1].failures = { { phase = "case", outcome = "failed", message = "invented" } }
		assert.that(not pcall(Verify.decode, lying))

		local unnamedSkip = table.clone(report) :: any
		unnamedSkip.results = { table.clone(report.results[1]) }
		unnamedSkip.results[1].status = "skipped"
		unnamedSkip.passed = 0
		unnamedSkip.skipped = 1
		assert.that(not pcall(Verify.decode, unnamedSkip))
	end)

	suite:case("names a source-level prerequisite skip without inventing a failure", function(assert)
		local report = Verify.syntheticReport {
			executor = "lute",
			id = "source:engine:load",
			name = "engine",
			status = "skipped",
			skipReason = "requires Roblox DataModel (script/game)",
		}
		assert.eq(report.skipped, 1)
		assert.eq(report.failed, 0)
		assert.eq(#report.results[1].failures, 0)
		assert.eq(report.results[1].skipReason, "requires Roblox DataModel (script/game)")
		assert.eq(Verify.decode(report).skipped, 1)
		local unnamedSkip: Verify.SyntheticOptions = {
			executor = "lute",
			id = "source:engine:load",
			name = "engine",
			status = "skipped",
		}
		assert.that(not pcall(Verify.syntheticReport, unnamedSkip))
		local unnamedCapability: Verify.SyntheticOptions = {
			executor = "lute",
			id = "source:engine:load",
			name = "engine",
			status = "unsupported",
		}
		assert.that(not pcall(Verify.syntheticReport, unnamedCapability))
	end)
end)

test.suite("verify matchers", function(suite)
	suite:case("supports values structures containment and throws", function(assert)
		Verify.expect(4):toBe(4)
		Verify.expect({ a = 1, b = { 2 } }):toEqual { b = { 2 }, a = 1 }
		Verify.expect("portable verification"):toContain "table"
		Verify.expect({ "a", "b" }):toHaveLength(2)
		Verify.expect(1.001):toBeCloseTo(1, 0.01)
		Verify.expect(1.001):toBeNear(1, 0.01)
		Verify.expect(0.1):toBeFloat32(0.1)
		Verify.expect(true):toBeTrueWith "fixture"
		Verify.expect(3):toBeGreaterThanOrEqual(3)
		Verify.expect(3):toBeLessThanOrEqual(3)
		Verify.expect(nil):toBeNil()
		Verify.expect("value"):toBeOk()
		Verify.expect(function()
			error "expected marker"
		end):toThrow "marker"
		local ok = pcall(function()
			Verify.expect(1).never:toBe(1)
		end)
		assert.that(not ok)
	end)

	suite:case("keeps negation satisfiable and composable", function(assert)
		Verify.expect(nil).never:toBeNear(1, 0.5)
		Verify.expect("text").never:toBeFloat32(1)
		Verify.expect(1).never.never:toBe(1)
		assert.that(not pcall(function()
			Verify.expect(1).never.never:toBe(2)
		end))
		assert.that(not pcall(function()
			Verify.expect(1):toBeNear(1, "wide" :: any)
		end))
	end)

	suite:case("separates plain containment from pattern matching", function(assert)
		Verify.expect("processed 42 rows"):toContain(42)
		local raises = function()
			error "armor-safe rule rejected"
		end
		Verify.expect(raises):toThrow "armor-safe"
		Verify.expect(raises):toThrowMatching "armor%-safe"

		assert.that(not pcall(function()
			Verify.expect(raises):toThrow "armor%-safe"
		end))
		assert.that(not pcall(function()
			Verify.expect(raises):toThrowMatching "^armor"
		end))
		assert.that(not pcall(function()
			Verify.expect(function() end):toThrowMatching "anything"
		end))
	end)

	suite:case("separates deep containment from identity containment", function(assert)
		local member = { id = "warder" }
		local twin = { id = "warder" }
		local collection = { member }

		Verify.expect(collection):toContain(twin)
		Verify.expect(collection):toContainExactly(member)
		assert.that(not pcall(function()
			Verify.expect(collection):toContainExactly(twin)
		end))

		local scalars: { any } = { 1, "two", true }
		Verify.expect(scalars):toContain "two"
		Verify.expect(scalars):toContainExactly "two"
		assert.that(not pcall(function()
			Verify.expect(scalars):toContainExactly "three"
		end))

		Verify.expect("processed 42 rows"):toContainExactly(42)
		Verify.expect("processed 42 rows").never:toContainExactly "43"
		assert.that(not pcall(function()
			Verify.expect(7 :: any):toContainExactly(7)
		end))
	end)

	suite:case("names the containment rule it applied when it fails", function(assert)
		local _, deep: any = pcall(function()
			Verify.expect({ 1 }):toContain(2)
		end)
		assert.strContains(tostring(deep), "deeply equal member")
		local _, identical: any = pcall(function()
			Verify.expect({ 1 }):toContainExactly(2)
		end)
		assert.strContains(tostring(identical), "identical member")
		local _, substring: any = pcall(function()
			Verify.expect("text"):toContain "absent"
		end)
		assert.strContains(tostring(substring), "substring")
	end)

	suite:case("names both stored representations when a float32 comparison fails", function(assert)
		local _, thrown: any = pcall(function()
			Verify.expect(0.550000011920929):toBeFloat32(0.56)
		end)
		local message = tostring(thrown)
		assert.strContains(message, "at float32 precision")

		assert.strContains(message, "0.55000001192092896")
		assert.strContains(message, "0.56000000238418579")
		local _, nonNumber: any = pcall(function()
			Verify.expect("0.55"):toBeFloat32(0.55)
		end)
		assert.strContains(tostring(nonNumber), "at float32 precision")
		local _, misuse: any = pcall(function()
			Verify.expect(0.55):toBeFloat32("0.55" :: any)
		end)
		assert.strContains(tostring(misuse), "requires the authored number")
	end)

	suite:case("exposes the float32 narrowing it compares by", function(assert)
		assert.eq(Verify.float32(0.55), 0.550000011920929)
		assert.eq(Verify.float32(0.55) == 0.55, false)
		assert.eq(Verify.float32(0.25), 0.25)
		assert.eq(Verify.float32(Verify.float32(0.55)), Verify.float32(0.55))
	end)

	suite:case("reports the distance a tolerance comparison missed by", function(assert)
		local _, thrown: any = pcall(function()
			Verify.expect(1.5):toBeNear(1, 0.25)
		end)
		local message = tostring(thrown)
		assert.strContains(message, "to be near")
		assert.strContains(message, "off")
		assert.strContains(message, "0.5")
		local _, nonNumber: any = pcall(function()
			Verify.expect(nil):toBeNear(1, 0.25)
		end)
		assert.strContains(tostring(nonNumber), "no distance exists")
	end)

	suite:case("carries the caught value into a throw failure", function(assert)
		local _, missed: any = pcall(function()
			Verify.expect(function()
				error "armor-safe rule rejected"
			end):toThrow "shield"
		end)
		assert.strContains(tostring(missed), "armor-safe rule rejected")
		local _, silent: any = pcall(function()
			Verify.expect(function() end):toThrow()
		end)
		assert.strContains(tostring(silent), "(no error)")
		local _, pattern: any = pcall(function()
			Verify.expect(function()
				error "armor-safe rule rejected"
			end):toThrowMatching "^shield"
		end)
		assert.strContains(tostring(pattern), "armor-safe rule rejected")
	end)

	suite:case("states the detail a true-with expectation was given", function(assert)
		Verify.expect(true):toBeTrueWith "the warder holds the gate"
		local _, thrown: any = pcall(function()
			Verify.expect(false):toBeTrueWith "the warder holds the gate"
		end)
		assert.strContains(tostring(thrown), "the warder holds the gate")
		assert.strContains(tostring(thrown), "false")
	end)

	suite:case("raises a failure with no host position spliced onto the front", function(assert)
		local _, thrown: any = pcall(function()
			Verify.expect(1):toBe(2)
		end)
		assert.eq(tostring(thrown), "expected to be 2\n     actual: 1")
		local _, throughBdd: any = pcall(function()
			local harness = Verify.createHarness { now = os.clock }
			Bdd.create(harness).expect(1):toBe(2)
		end)
		assert.eq(tostring(throughBdd), "expected to be 2\n     actual: 1")

		local _, misuse: any = pcall(function()
			Verify.expect(1):toBeNear(1, "wide" :: any)
		end)
		assert.strContains(tostring(misuse), "core.spec.luau")
	end)

	suite:case("names an unknown matcher instead of failing as a nil call", function(assert)
		local ok, thrown: any = pcall(function()
			(Verify.expect(true) :: any):toBeTrue()
		end)
		assert.that(not ok)
		assert.strContains(tostring(thrown), 'unknown matcher "toBeTrue"')
	end)
end)

test.suite("verify spy", function(suite)
	suite:case("records reach, arguments and returns", function(assert)
		local spy = Verify.spy(function(left: number, right: number): number
			return left + right
		end)
		assert.eq(spy.called(), false)
		assert.eq(spy.callCount(), 0)
		assert.eq(spy.lastArgs(), nil)
		assert.eq(spy.lastReturn(), nil)
		assert.eq(spy.fn(2, 3), 5)
		assert.eq(spy.callCount(), 1)
		assert.eq(spy.called(), true)
		assert.eq(spy.lastArgs(), { 2, 3 })
		assert.eq(spy.lastReturn(), 5)
		spy.fn(10, 1)
		assert.eq(spy.callCount(), 2)
		assert.eq(spy.calls[1].args, { 2, 3 })
		assert.eq(spy.calls[2].returnValue, 11)
	end)

	suite:case("stands in for a collaborator with no implementation", function(assert)
		local spy = Verify.spy()
		assert.eq(spy.fn("only", "recorded"), nil)
		assert.eq(spy.callCount(), 1)
		assert.eq(spy.lastArgs(), { "only", "recorded" })
		assert.eq(spy.lastReturn(), nil)
	end)

	suite:case("restates its behavior without losing its record", function(assert)
		local spy = Verify.spy()
		spy.returnValue "fixed"
		assert.eq(spy.fn(), "fixed")
		assert.eq(spy.fn "ignored", "fixed")
		spy.implementation(function(value: string): string
			return value .. "!"
		end)
		assert.eq(spy.fn "loud", "loud!")
		assert.eq(spy.callCount(), 3)
	end)

	suite:case("clears its record in place, so a held reference stays live", function(assert)
		local spy = Verify.spy()
		local held = spy.calls
		spy.fn "before"
		assert.eq(#held, 1)
		spy.reset()
		assert.eq(spy.callCount(), 0)
		assert.eq(spy.called(), false)

		assert.that(rawequal(held, spy.calls))
		spy.fn "after"
		assert.eq(#held, 1)
		assert.eq(held[1].args, { "after" })
	end)

	suite:case("passes every return value through, recording the first", function(assert)
		local spy = Verify.spy(function(): (string, string)
			return "first", "second"
		end)
		local first, second = spy.fn()
		assert.eq(first, "first")
		assert.eq(second, "second")
		assert.eq(spy.lastReturn(), "first")
	end)

	suite:case("records nothing for a call that raised", function(assert)
		local spy = Verify.spy(function()
			error "collaborator refused"
		end)
		assert.that(not pcall(spy.fn))
		assert.eq(spy.callCount(), 0)
	end)

	suite:case("keeps two spies independent", function(assert)
		local left = Verify.spy()
		local right = Verify.spy()
		left.fn "a"
		assert.eq(left.callCount(), 1)
		assert.eq(right.callCount(), 0)
	end)
end)
