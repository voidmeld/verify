--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

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

describe("verify core", function()
	it("keeps harness registries isolated", function()
		local first = Verify.createHarness { now = clock() }
		local second = Verify.createHarness { now = clock() }
		first:case("first", function() end)
		second:case("second", function() end)
		local firstReport = run(first)
		local secondReport = run(second)
		expect(firstReport.total):toEqual(1)
		expect(firstReport.results[1].name):toEqual "first"
		expect(secondReport.total):toEqual(1)
		expect(secondReport.results[1].name):toEqual "second"
	end)

	it("runs nested hooks and cleanup in contractual order", function()
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
		expect(report.failed):toEqual(0)
		expect(order):toEqual {
			"outer setup",
			"inner setup",
			"case",
			"inner teardown",
			"outer teardown",
			"inner cleanup",
			"outer cleanup",
		}
	end)

	it("continues cleanup after failures and retains every failure", function()
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
		expect(report.failed):toEqual(1)
		expect(order):toEqual { "newest", "oldest" }
		expect(#report.results[1].failures):toEqual(3)
		expect(report.results[1].failures[1].phase):toEqual "case"
		expect(report.results[1].failures[1].outcome):toEqual "failed"
		expect(report.results[1].failures[2].phase):toEqual "cleanup"
		expect(report.results[1].failures[3].phase):toEqual "cleanup"
	end)

	it("runs teardown and cleanup after setup failure", function()
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
		expect(report.failed):toEqual(1)
		expect(order):toEqual { "teardown", "cleanup" }
		expect(report.results[1].failures[1].phase):toEqual "setup"
	end)

	it("reports missing capabilities as unsupported", function()
		local harness = Verify.createHarness { now = clock() }
		harness:case("engine observation", {
			requires = { "layout", "engine", "layout" },
			run = function()
				error "must not run"
			end,
		})
		local report = run(harness, { "engine" })
		expect(report.unsupported):toEqual(1)
		expect(report.failed):toEqual(0)
		expect(report.results[1].missingCapabilities):toEqual { "layout" }
	end)

	it("distinguishes declared and runtime skips", function()
		local harness = Verify.createHarness { now = clock() }
		harness:skip("declared", "fixture unavailable")
		harness:case("runtime", function(context)
			context:skip "executor declined"
		end)
		local report = run(harness)
		expect(report.skipped):toEqual(2)
		expect(report.results[1].skipReason):toEqual "fixture unavailable"
		expect(report.results[2].skipReason):toEqual "executor declined"
	end)

	it("retains steps artifacts limitations and environment", function()
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
		expect(report.schemaVersion):toEqual(1)
		expect(report.environment.revision):toEqual "fixture"
		expect(result.steps[1].status):toEqual "passed"
		expect(result.steps[1].actor):toEqual "server"
		expect(result.artifacts[1].reference):toEqual "build/trace.json"
		expect(result.limitations):toEqual { "no network", "one viewport" }
	end)

	it("records a failed step as a case failure", function()
		local harness = Verify.createHarness { now = clock() }
		harness:case("step", function(context)
			context:step("break", function()
				error "step broke"
			end)
		end)
		local report = run(harness)
		expect(report.failed):toEqual(1)
		expect(report.results[1].steps[1].status):toEqual "failed"
		expect(report.results[1].steps[1].message):toContain "step broke"
	end)

	it("balances the suite stack when registration fails", function()
		local harness = Verify.createHarness { now = clock() }
		local ok = pcall(function()
			harness:suite("broken", function()
				error "registration failed"
			end)
		end)
		assert(not ok)
		harness:case("root case", function() end)
		local report = run(harness)
		expect(report.results[1].path):toEqual {}
	end)

	it("selects exact ids suite prefixes tags and capabilities without reordering", function()
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
		expect(byId.total):toEqual(1)
		expect(byId.results[1].id):toEqual "engine"
		local byShape = harness:run {
			executor = "test",
			capabilities = { "engine" },
			selection = {
				suitePrefixes = { "inventory" },
				tags = { "fast" },
				capabilities = { "engine" },
			},
		}
		expect(byShape.total):toEqual(1)
		expect(byShape.results[1].id):toEqual "engine"
	end)

	it("records executor-enforced timeout and still tears down and cleans up", function()
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
		expect(report.timedOut):toEqual(1)
		expect(report.failed):toEqual(0)
		expect(trace):toEqual { "teardown", "cleanup" }
		expect(report.results[1].failures[1].outcome):toEqual "timed_out"
	end)

	it("records cancellation separately from failure", function()
		local harness = Verify.createHarness { now = clock() }
		harness:case("case", function() end)
		local report = harness:run {
			executor = "controlled",
			invoke = function()
				return { outcome = "cancelled", error = "operator cancelled" }
			end,
		}
		expect(report.cancelled):toEqual(1)
		expect(report.results[1].status):toEqual "cancelled"
	end)

	it("decodes valid reports and rejects unknown schema majors and count drift", function()
		local harness = Verify.createHarness { now = clock() }
		harness:case("case", function() end)
		local report = run(harness)
		expect(Verify.decode(report).total):toEqual(1)
		local future = table.clone(report)
		future.schemaVersion = 2
		local futureOk = pcall(Verify.decode, future)
		assert(not futureOk)
		local drifted = table.clone(report)
		drifted.passed = 0
		local driftedOk = pcall(Verify.decode, drifted)
		assert(not driftedOk)
	end)

	it("keeps source attribution when it does not compose ids", function()
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
		expect(report.results[1].id):toEqual "one"
		expect(report.results[1].source):toEqual "suites/alpha.verify.luau"
		expect(seen):toEqual { "suites/alpha.verify.luau" }
	end)

	it("refuses to prefix ids with a source it was never given", function()
		local ok, thrown: unknown = pcall(Verify.createHarness, { now = clock(), prefixIds = true })
		expect(ok):toEqual(false)
		expect((tostring(thrown))):toContain "cannot prefix ids without a source"
	end)

	it("merges shard reports while preserving result origins", function()
		local first = Verify.createHarness { now = clock(), source = "first" }
		local second = Verify.createHarness { now = clock(), source = "second" }
		first:case("one", function() end)
		second:case("two", function() end)
		local merged = Verify.merge({
			first:run { executor = "worker", environment = { shard = "1" } },
			second:run { executor = "worker", environment = { shard = "2" } },
		}, "aggregate", { run = "fixture" })
		expect(merged.total):toEqual(2)
		expect(#merged.sources):toEqual(2)
		expect(merged.results[1].origin.environment.shard):toEqual "1"
		expect(merged.results[2].origin.environment.shard):toEqual "2"
	end)

	it("collapses identical origins instead of one per source", function()
		local reports: { Verify.Report } = {}
		for index = 1, 5 do
			local harness = Verify.createHarness { now = clock(), source = "source" .. index }
			harness:case("case", function() end)
			table.insert(reports, harness:run { executor = "worker", environment = { shard = "1" } })
		end
		local merged = Verify.merge(reports, "aggregate", { run = "fixture" })
		expect(merged.total):toEqual(5)
		expect(#merged.sources):toEqual(1)
		expect(merged.sources[1].environment.shard):toEqual "1"
	end)

	it("composes a crashed shard into a named failure", function()
		local composed = Verify.compose({
			{ id = "worker-1", error = "worker exited before writing a report" },
			{ id = "worker-2" },
		}, "aggregate", { run = "fixture" })
		expect(composed.total):toEqual(2)
		expect(composed.failed):toEqual(2)
		expect(composed.results[1].id):toEqual "shard:worker-1"
		expect(composed.results[1].failures[1].phase):toEqual "executor"
		expect(composed.results[1].failures[1].message):toEqual "worker exited before writing a report"
		expect(composed.results[2].failures[1].message):toEqual "shard produced no report"
	end)

	it("composes an undecodable shard payload into a named failure", function()
		local harness = Verify.createHarness { now = clock(), source = "good" }
		harness:case("passes", function() end)
		local healthy = harness:run { executor = "worker", environment = { shard = "1" } }
		local drifted = table.clone(healthy)
		drifted.passed = 99
		local composed = Verify.compose({
			{ id = "worker-1", report = healthy },
			{ id = "worker-2", report = drifted },
			{ id = "worker-3", report = "truncated" },
		}, "aggregate", { run = "fixture" })
		expect(composed.total):toEqual(3)
		expect(composed.passed):toEqual(1)
		expect(composed.failed):toEqual(2)
		expect(composed.results[2].id):toEqual "shard:worker-2"
		expect(composed.results[2].failures[1].message):toContain "undecodable shard payload"
		expect(composed.results[3].id):toEqual "shard:worker-3"
	end)

	it("keeps a duplicated case id across shards as a named failure", function()
		local function claim(shard: string): Verify.Report
			local harness = Verify.createHarness { now = clock(), source = "shared" }
			harness:case("contested", function() end)
			return harness:run { executor = "worker", environment = { shard = shard } }
		end
		local composed = Verify.compose({
			{ id = "worker-1", report = claim "1" },
			{ id = "worker-2", report = claim "2" },
		}, "aggregate", { run = "fixture" })
		expect(composed.total):toEqual(2)
		expect(composed.passed):toEqual(1)
		expect(composed.failed):toEqual(1)
		expect(composed.results[1].id):toEqual "shared::contested"
		expect(composed.results[1].origin.environment.shard):toEqual "1"
		expect(composed.results[2].id):toEqual "shard:worker-2:duplicate:shared::contested"
		expect(composed.results[2].failures[1].message):toContain 'kept the copy from shard "worker-1"'
	end)

	it("rejects a self-contradicting foreign envelope", function()
		local harness = Verify.createHarness { now = clock(), source = "good" }
		harness:case("passes", function() end)
		local report = harness:run { executor = "worker" }
		local lying = table.clone(report)
		lying.results = { table.clone(report.results[1]) }
		lying.results[1].failures = { { phase = "case", outcome = "failed", message = "invented" } }
		assert(not pcall(Verify.decode, lying))

		local unnamedSkip = table.clone(report)
		unnamedSkip.results = { table.clone(report.results[1]) }
		unnamedSkip.results[1].status = "skipped"
		unnamedSkip.passed = 0
		unnamedSkip.skipped = 1
		assert(not pcall(Verify.decode, unnamedSkip))
	end)

	it("names a source-level prerequisite skip without inventing a failure", function()
		local report = Verify.syntheticReport {
			executor = "lute",
			id = "source:engine:load",
			name = "engine",
			status = "skipped",
			skipReason = "requires Roblox DataModel (script/game)",
		}
		expect(report.skipped):toEqual(1)
		expect(report.failed):toEqual(0)
		expect(#report.results[1].failures):toEqual(0)
		expect(report.results[1].skipReason):toEqual "requires Roblox DataModel (script/game)"
		expect(Verify.decode(report).skipped):toEqual(1)
		local unnamedSkip: Verify.SyntheticOptions = {
			executor = "lute",
			id = "source:engine:load",
			name = "engine",
			status = "skipped",
		}
		assert(not pcall(Verify.syntheticReport, unnamedSkip))
		local unnamedCapability: Verify.SyntheticOptions = {
			executor = "lute",
			id = "source:engine:load",
			name = "engine",
			status = "unsupported",
		}
		assert(not pcall(Verify.syntheticReport, unnamedCapability))
	end)
end)

describe("verify matchers", function()
	it("supports values structures containment and throws", function()
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
		assert(not ok)
	end)

	it("keeps negation satisfiable and composable", function()
		Verify.expect(nil).never:toBeNear(1, 0.5)
		Verify.expect("text").never:toBeFloat32(1)
		Verify.expect(1).never.never:toBe(1)
		assert(not pcall(function()
			Verify.expect(1).never.never:toBe(2)
		end))
		assert(not pcall(function()
			Verify.expect(1):toBeNear(1, ("wide" :: unknown) :: number)
		end))
	end)

	it("separates plain containment from pattern matching", function()
		Verify.expect("processed 42 rows"):toContain(42)
		local raises = function()
			error "armor-safe rule rejected"
		end
		Verify.expect(raises):toThrow "armor-safe"
		Verify.expect(raises):toThrowMatching "armor%-safe"

		assert(not pcall(function()
			Verify.expect(raises):toThrow "armor%-safe"
		end))
		assert(not pcall(function()
			Verify.expect(raises):toThrowMatching "^armor"
		end))
		assert(not pcall(function()
			Verify.expect(function() end):toThrowMatching "anything"
		end))
	end)

	it("separates deep containment from identity containment", function()
		local member = { id = "warder" }
		local twin = { id = "warder" }
		local collection = { member }

		Verify.expect(collection):toContain(twin)
		Verify.expect(collection):toContainExactly(member)
		assert(not pcall(function()
			Verify.expect(collection):toContainExactly(twin)
		end))

		local scalars: { unknown } = { 1, "two", true }
		Verify.expect(scalars):toContain "two"
		Verify.expect(scalars):toContainExactly "two"
		assert(not pcall(function()
			Verify.expect(scalars):toContainExactly "three"
		end))

		Verify.expect("processed 42 rows"):toContainExactly(42)
		Verify.expect("processed 42 rows").never:toContainExactly "43"
		assert(not pcall(function()
			Verify.expect(7):toContainExactly(7)
		end))
	end)

	it("names the containment rule it applied when it fails", function()
		local _, deep: unknown = pcall(function()
			Verify.expect({ 1 }):toContain(2)
		end)
		expect((tostring(deep))):toContain "deeply equal member"
		local _, identical: unknown = pcall(function()
			Verify.expect({ 1 }):toContainExactly(2)
		end)
		expect((tostring(identical))):toContain "identical member"
		local _, substring: unknown = pcall(function()
			Verify.expect("text"):toContain "absent"
		end)
		expect((tostring(substring))):toContain "substring"
	end)

	it("names both stored representations when a float32 comparison fails", function()
		local _, thrown: unknown = pcall(function()
			Verify.expect(0.550000011920929):toBeFloat32(0.56)
		end)
		local message = tostring(thrown)
		expect(message):toContain "at float32 precision"

		expect(message):toContain "0.55000001192092896"
		expect(message):toContain "0.56000000238418579"
		local _, nonNumber: unknown = pcall(function()
			Verify.expect("0.55"):toBeFloat32(0.55)
		end)
		expect((tostring(nonNumber))):toContain "at float32 precision"
		local _, misuse: unknown = pcall(function()
			Verify.expect(0.55):toBeFloat32(("0.55" :: unknown) :: number)
		end)
		expect((tostring(misuse))):toContain "requires the authored number"
	end)

	it("exposes the float32 narrowing it compares by", function()
		expect((Verify.float32(0.55))):toEqual(0.550000011920929)
		expect(Verify.float32(0.55) == 0.55):toEqual(false)
		expect((Verify.float32(0.25))):toEqual(0.25)
		expect((Verify.float32(Verify.float32(0.55)))):toEqual(Verify.float32(0.55))
	end)

	it("reports the distance a tolerance comparison missed by", function()
		local _, thrown: unknown = pcall(function()
			Verify.expect(1.5):toBeNear(1, 0.25)
		end)
		local message = tostring(thrown)
		expect(message):toContain "to be near"
		expect(message):toContain "off"
		expect(message):toContain "0.5"
		local _, nonNumber: unknown = pcall(function()
			Verify.expect(nil):toBeNear(1, 0.25)
		end)
		expect((tostring(nonNumber))):toContain "no distance exists"
	end)

	it("carries the caught value into a throw failure", function()
		local _, missed: unknown = pcall(function()
			Verify.expect(function()
				error "armor-safe rule rejected"
			end):toThrow "shield"
		end)
		expect((tostring(missed))):toContain "armor-safe rule rejected"
		local _, silent: unknown = pcall(function()
			Verify.expect(function() end):toThrow()
		end)
		expect((tostring(silent))):toContain "(no error)"
		local _, pattern: unknown = pcall(function()
			Verify.expect(function()
				error "armor-safe rule rejected"
			end):toThrowMatching "^shield"
		end)
		expect((tostring(pattern))):toContain "armor-safe rule rejected"
	end)

	it("states the detail a true-with expectation was given", function()
		Verify.expect(true):toBeTrueWith "the warder holds the gate"
		local _, thrown: unknown = pcall(function()
			Verify.expect(false):toBeTrueWith "the warder holds the gate"
		end)
		expect((tostring(thrown))):toContain "the warder holds the gate"
		expect((tostring(thrown))):toContain "false"
	end)

	it("raises a failure with no host position spliced onto the front", function()
		local _, thrown: unknown = pcall(function()
			Verify.expect(1):toBe(2)
		end)
		expect((tostring(thrown))):toEqual "expected to be 2\n     actual: 1"
		local _, throughBdd: unknown = pcall(function()
			local harness = Verify.createHarness { now = os.clock }
			Bdd.create(harness).expect(1):toBe(2)
		end)
		expect((tostring(throughBdd))):toEqual "expected to be 2\n     actual: 1"

		local _, misuse: unknown = pcall(function()
			Verify.expect(1):toBeNear(1, ("wide" :: unknown) :: number)
		end)
		expect((tostring(misuse))):toContain "core.verify.luau"
	end)

	it("names an unknown matcher instead of failing as a nil call", function()
		local ok, thrown: unknown = pcall(function()
			((Verify.expect(true) :: unknown) :: { toBeTrue: (unknown) -> () }):toBeTrue()
		end)
		assert(not ok)
		expect((tostring(thrown))):toContain 'unknown matcher "toBeTrue"'
	end)
end)

describe("verify spy", function()
	it("records reach, arguments and returns", function()
		local spy = Verify.spy(function(left: number, right: number): number
			return left + right
		end)
		expect((spy.called())):toEqual(false)
		expect((spy.callCount())):toEqual(0)
		expect((spy.lastArgs())):toEqual(nil)
		expect((spy.lastReturn())):toEqual(nil)
		expect((spy.fn(2, 3))):toEqual(5)
		expect((spy.callCount())):toEqual(1)
		expect((spy.called())):toEqual(true)
		expect((spy.lastArgs())):toEqual { 2, 3 }
		expect((spy.lastReturn())):toEqual(5)
		spy.fn(10, 1)
		expect((spy.callCount())):toEqual(2)
		expect(spy.calls[1].args):toEqual { 2, 3 }
		expect(spy.calls[2].returnValue):toEqual(11)
	end)

	it("stands in for a collaborator with no implementation", function()
		local spy = Verify.spy()
		expect((spy.fn("only", "recorded"))):toEqual(nil)
		expect((spy.callCount())):toEqual(1)
		expect((spy.lastArgs())):toEqual { "only", "recorded" }
		expect((spy.lastReturn())):toEqual(nil)
	end)

	it("restates its behavior without losing its record", function()
		local spy = Verify.spy(function(_value: string?): unknown
			return nil
		end)
		spy.returnValue "fixed"
		expect((spy.fn())):toEqual "fixed"
		expect(spy.fn "ignored"):toEqual "fixed"
		spy.implementation(function(value: string?): string
			assert(value ~= nil)
			return value .. "!"
		end)
		expect(spy.fn "loud"):toEqual "loud!"
		expect((spy.callCount())):toEqual(3)
	end)

	it("clears its record in place, so a held reference stays live", function()
		local spy = Verify.spy()
		local held = spy.calls
		spy.fn "before"
		expect(#held):toEqual(1)
		spy.reset()
		expect((spy.callCount())):toEqual(0)
		expect((spy.called())):toEqual(false)

		assert(rawequal(held, spy.calls))
		spy.fn "after"
		expect(#held):toEqual(1)
		expect(held[1].args):toEqual { "after" }
	end)

	it("passes every return value through, recording the first", function()
		local spy = Verify.spy(function(): (string, string)
			return "first", "second"
		end)
		local first, second = spy.fn()
		expect(first):toEqual "first"
		expect(second):toEqual "second"
		expect((spy.lastReturn())):toEqual "first"
	end)

	it("records nothing for a call that raised", function()
		local spy = Verify.spy(function()
			error "collaborator refused"
		end)
		assert(not pcall(spy.fn))
		expect((spy.callCount())):toEqual(0)
	end)

	it("keeps two spies independent", function()
		local left = Verify.spy()
		local right = Verify.spy()
		left.fn "a"
		expect((left.callCount())):toEqual(1)
		expect((right.callCount())):toEqual(0)
	end)
end)

describe("selection by source and case name", function()
	local function registered(): Verify.Harness
		local harness = Verify.createHarness { now = clock(), source = "alpha.luau", prefixIds = false }
		harness:case("opens the door", function() end)
		harness:case("closes the window", function() end)
		return harness
	end

	it("selects cases by an exact source and by a case-name substring", function()
		local harness = registered()
		local byName = harness:run { executor = "test", selection = { nameContains = "door" } }
		expect(byName.total):toEqual(1)
		expect(byName.results[1].name):toEqual "opens the door"
		local bySource = harness:run { executor = "test", selection = { sources = { "alpha.luau" } } }
		expect(bySource.total):toEqual(2)
		local both = harness:run {
			executor = "test",
			selection = { sources = { "alpha.luau" }, nameContains = "window" },
		}
		expect(both.total):toEqual(1)
	end)

	it("selects nothing for another source, a missing name or a substring in the wrong case", function()
		local harness = registered()
		expect(harness:run({ executor = "test", selection = { sources = { "beta.luau" } } }).total):toEqual(0)
		expect(harness:run({ executor = "test", selection = { nameContains = "garage" } }).total):toEqual(0)
		expect(harness:run({ executor = "test", selection = { nameContains = "DOOR" } }).total):toEqual(0)
		expect(harness:run({ executor = "test", selection = { nameContains = "the (door" } }).total):toEqual(0)
	end)
end)

describe("selection by shard", function()
	local function registered(count: number): Verify.Harness
		local harness = Verify.createHarness { now = clock(), source = "alpha.luau", prefixIds = false }
		for index = 1, count do
			harness:case(`case {index}`, function() end)
		end
		return harness
	end

	it("puts every selected case in exactly one shard", function()
		local harness = registered(7)
		local seen: { [string]: number } = {}
		for index = 1, 3 do
			local report = harness:run { executor = "test", selection = { shard = { index = index, count = 3 } } }
			for _, result in report.results do
				seen[result.name] = (seen[result.name] or 0) + 1
			end
		end
		for index = 1, 7 do
			expect(seen[`case {index}`]):toEqual(1)
		end
		local narrowed = harness:run {
			executor = "test",
			selection = { nameContains = "case 1", shard = { index = 1, count = 2 } },
		}
		expect(narrowed.total):toEqual(1)
	end)

	it("rejects invalid shards and accounts for cases another shard runs", function()
		local harness = registered(2)
		for _, shard in
			{ { index = 0, count = 2 }, { index = 3, count = 2 }, { index = 1, count = 0 }, { index = 1.5, count = 2 } }
		do
			expect(function()
				harness:run { executor = "test", selection = { shard = shard } }
			end):toThrow()
		end
		local accounted = harness:run {
			executor = "test",
			selection = { shard = { index = 1, count = 2 }, account = true },
		}
		expect(accounted.passed):toEqual(1)
		expect(accounted.skipped):toEqual(1)
		local runAgain = harness:run { executor = "test" }
		expect(runAgain.passed):toEqual(2)
	end)
end)

describe("report format", function()
	it("prints one line per measurement and nothing for a case without one", function()
		local harness = Verify.createHarness { now = clock() }
		harness:case("plain", function() end)
		harness:case("timed", function(context)
			context:measure("bench", "load", {
				samples = { 1, 2, 3, 4 },
				unit = "milliseconds",
				context = { environment = "lab", signal = "load", timing = "observed" },
				percentiles = { 75 },
			}, { unit = "milliseconds", minimumSamples = 1, measureOnly = true })
		end)
		local text = Verify.format(run(harness))
		expect(text):toContain "load [milliseconds] n=4 p50=2 p95=4 p75=3 measured"
		local lines = string.split(text, "\n")
		local count = 0
		for _, line in lines do
			if string.find(line, "n=", 1, true) ~= nil then
				count += 1
			end
		end
		expect(count):toEqual(1)
		local plain = Verify.createHarness { now = clock() }
		plain:case("plain", function() end)
		expect(Verify.format(run(plain))).never:toContain "n="
	end)
end)

return nil
