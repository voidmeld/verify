--!strict

local test = require "@std/test"

local Host = require "../src/host"
local Verify = require "../src/core"

local function passing(name: string): Host.UnitRun
	return function(harness: Verify.Harness)
		harness:case(name, function(context)
			context:expect(1):toBe(1)
		end)
	end
end

local function failing(name: string): Host.UnitRun
	return function(harness: Verify.Harness)
		harness:case(name, function(context)
			context:expect(1):toBe(2)
		end)
	end
end

local UNITS: { [string]: Host.UnitRun } = {
	["alpha/one"] = passing "alpha one",
	["alpha/two"] = passing "alpha two",
	["beta/one"] = passing "beta one",
	["gamma/one"] = passing "gamma one",
}

local PLAN: Verify.PlanDraft = {
	id = "example",
	units = {
		{ id = "alpha/one", locator = "alpha/one.verify.luau", group = "alpha" },
		{ id = "alpha/two", locator = "alpha/two.verify.luau", group = "alpha" },
		{ id = "beta/one", locator = "beta/one.verify.luau", group = "beta" },
		{ id = "gamma/one", locator = "gamma/one.verify.luau", group = "gamma" },
	},
}

local function statusOf(report: Verify.Report, id: string): string?
	for _, result in report.results do
		if result.id == id then
			return result.status
		end
	end
	return nil
end

local function factCodes(execution: Verify.ExecutionReport): { string }
	local codes: { string } = {}
	for _, fact in execution.facts do
		table.insert(codes, fact.code)
	end
	return codes
end

local function hasFact(execution: Verify.ExecutionReport, code: string): boolean
	return table.find(factCodes(execution), code) ~= nil
end

local function factDetail(execution: Verify.ExecutionReport, code: string): string
	for _, fact in execution.facts do
		if fact.code == code then
			return fact.detail
		end
	end
	return ""
end

test.suite("focused runs are never the gate", function(suite)
	suite:case("marks a narrowed run incomplete and names what it did not run", function(assert)
		local focused = Verify.execute(PLAN, Host.fake { units = UNITS }, { selection = { ids = { "beta/one" } } })
		assert.eq(focused.provenance.complete, false)
		assert.eq(focused.provenance.unitCount, 1)
		assert.eq(focused.provenance.planUnitCount, 4)
		assert.eq(hasFact(focused, "focused-run"), true)
		assert.strContains(factDetail(focused, "focused-run"), "is not the plan")

		assert.eq(focused.report.failed, 0)
	end)

	suite:case("marks the complete plan complete and says nothing about focus", function(assert)
		local whole = Verify.execute(PLAN, Host.fake { units = UNITS })
		assert.eq(whole.provenance.complete, true)
		assert.eq(whole.provenance.unitCount, whole.provenance.planUnitCount)
		assert.eq(hasFact(whole, "focused-run"), false)
	end)

	suite:case("cannot be told it was complete when it was not", function(assert)
		local everything = Verify.execute(
			PLAN,
			Host.fake { units = UNITS },
			{ selection = { ids = { "alpha/one", "alpha/two", "beta/one", "gamma/one" } } }
		)
		assert.eq(everything.provenance.complete, true)
		assert.eq(hasFact(everything, "focused-run"), false)

		local narrowed = Verify.execute(PLAN, Host.fake { units = UNITS }, { selection = { tags = { "slow" } } })
		assert.eq(narrowed.provenance.complete, false)
	end)
end)

test.suite("execution equivalence", function(suite)
	suite:case("produces the same report serially and four ways in parallel", function(assert)
		local serial = Verify.execute(PLAN, Host.fake { units = UNITS }, { batchCount = 4, parallel = 1 })
		local parallel = Verify.execute(
			PLAN,
			Host.fake { units = UNITS, maxParallelBatches = 4, completionOrder = "reverse" },
			{ batchCount = 4, parallel = 4 }
		)
		assert.eq(Verify.canonical(parallel.report), Verify.canonical(serial.report))
		assert.eq(serial.provenance.parallelism, 1)
		assert.eq(parallel.provenance.parallelism, 4)
		assert.eq(serial.provenance.planDigest, parallel.provenance.planDigest)
		assert.eq(serial.report.passed, 4)
	end)

	suite:case("produces the same report at every batch count", function(assert)
		local one = Verify.execute(PLAN, Host.fake { units = UNITS }, { batchCount = 1 })
		for count = 2, 5 do
			local other = Verify.execute(
				PLAN,
				Host.fake { units = UNITS, maxParallelBatches = count, completionOrder = "reverse" },
				{ batchCount = count, parallel = count }
			)
			assert.eq(Verify.canonical(other.report), Verify.canonical(one.report))
		end
	end)

	suite:case("never exceeds the parallelism the host declares", function(assert)
		local execution =
			Verify.execute(PLAN, Host.fake { units = UNITS, maxParallelBatches = 2 }, { batchCount = 4, parallel = 8 })
		assert.eq(execution.provenance.parallelism, 2)
		assert.eq(execution.report.passed, 4)
	end)

	suite:case("keeps a failing case failing however the run was scheduled", function(assert)
		local units = table.clone(UNITS)
		units["beta/one"] = failing "beta one"
		local serial = Verify.execute(PLAN, Host.fake { units = units }, { batchCount = 4, parallel = 1 })
		local parallel = Verify.execute(
			PLAN,
			Host.fake { units = units, maxParallelBatches = 4, completionOrder = "reverse" },
			{ batchCount = 4, parallel = 4 }
		)
		assert.eq(Verify.canonical(parallel.report), Verify.canonical(serial.report))
		assert.eq(serial.report.failed, 1)
	end)
end)

test.suite("execution capability negotiation", function(suite)
	suite:case("never dispatches a unit whose requirement the host lacks", function(assert)
		local host = Host.fake { units = UNITS, capabilities = { "in-memory" } }
		local plan = table.clone(PLAN)
		plan.units = {
			{ id = "alpha/one", locator = "alpha/one.verify.luau" },
			{ id = "beta/one", locator = "beta/one.verify.luau", requires = { "engine-datamodel" } },
		}
		local execution = Verify.execute(plan, host)
		assert.eq(statusOf(execution.report, "unit:beta/one:unsupported"), "unsupported")
		assert.eq(execution.report.unsupported, 1)
		assert.eq(execution.report.passed, 1)
		assert.eq(hasFact(execution, "capability-missing"), true)
		assert.eq(table.find(host.dispatched, "batch-1") ~= nil, true)
		assert.eq(#host.dispatched, 1)
	end)

	suite:case("carries the declared capability set into the report", function(assert)
		local execution = Verify.execute(PLAN, Host.fake { units = UNITS, capabilities = { "in-memory", "worker" } })
		assert.eq(execution.capabilities, { "in-memory", "worker" })
		assert.eq(execution.report.capabilities, { "in-memory", "worker" })
	end)

	suite:case("makes an unservable plan unsupported rather than failed", function(assert)
		local plan = table.clone(PLAN)
		plan.requires = { "engine-datamodel" }
		local execution = Verify.execute(plan, Host.fake { units = UNITS })
		assert.eq(execution.report.unsupported, 4)
		assert.eq(execution.report.passed, 0)
		assert.eq(hasFact(execution, "plan-capability-missing"), true)
	end)
end)

test.suite("execution provenance and artifacts", function(suite)
	suite:case("stamps the plan identity and digest onto the report environment", function(assert)
		local execution = Verify.execute(PLAN, Host.fake { units = UNITS })
		assert.eq(execution.report.environment["verify.plan"], "example")
		assert.eq(execution.report.environment["verify.planDigest"], execution.provenance.planDigest)
		assert.eq(execution.report.environment["verify.planSchema"], "1")
		assert.eq(execution.report.environment["verify.executionSchema"], "1")
		assert.eq(execution.provenance.unitCount, 4)
		assert.eq(execution.provenance.host, "fake")
	end)

	suite:case("routes every artifact reference through the host sink", function(assert)
		local units: { [string]: Host.UnitRun } = {
			["alpha/one"] = function(harness: Verify.Harness)
				harness:case("emits", function(context)
					context:artifact("trace", "trace.json", "application/json")
				end)
			end,
		}
		local plan: Verify.PlanDraft = { id = "p", units = { { id = "alpha/one", locator = "a.verify.luau" } } }
		local execution = Verify.execute(plan, Host.fake { units = units, artifactPrefix = "store://" })
		assert.eq(execution.report.results[1].artifacts[1].reference, "store://a.verify.luau::emits/trace.json")
		assert.eq(execution.report.results[1].artifacts[1].mediaType, "application/json")
	end)

	suite:case("attributes fake-host cases to the locator its synthetic reports already name", function(assert)
		local units: { [string]: Host.UnitRun } = {
			["alpha/one"] = function(harness: Verify.Harness)
				harness:case("runs", function() end)
			end,
		}
		local plan: Verify.PlanDraft = {
			id = "attribution",
			units = {
				{ id = "alpha/one", locator = "alpha/one.verify.luau" },
				{ id = "alpha/two", locator = "alpha/two.verify.luau" },
			},
		}
		local execution = Verify.execute(plan, Host.fake { units = units })
		local ran = execution.report.results[1]
		local missing = execution.report.results[2]
		assert.eq(ran.source, "alpha/one.verify.luau")
		assert.eq(missing.source, "alpha/two.verify.luau")
		assert.eq(ran.id, "alpha/one.verify.luau::runs")
	end)

	suite:case("keeps the original reference and names a sink that refused", function(assert)
		local units: { [string]: Host.UnitRun } = {
			["alpha/one"] = function(harness: Verify.Harness)
				harness:case("emits", function(context)
					context:artifact("trace", "trace.json")
				end)
			end,
		}
		local plan: Verify.PlanDraft = { id = "p", units = { { id = "alpha/one", locator = "a.verify.luau" } } }
		local execution = Verify.execute(plan, Host.fake { units = units, artifactFailsFor = "trace" })
		assert.eq(execution.report.results[1].artifacts[1].reference, "trace.json")
		assert.eq(hasFact(execution, "artifact-sink-failed"), true)
	end)
end)

test.suite("execution fixtures", function(suite)
	suite:case("releases fixtures newest-first, exactly once", function(assert)
		local order: { string } = {}
		local execution = Verify.execute(PLAN, Host.fake { units = UNITS }, {
			fixtures = {
				{
					name = "outer",
					acquire = function()
						table.insert(order, "acquire outer")
					end,
					release = function()
						table.insert(order, "release outer")
					end,
				},
				{
					name = "inner",
					acquire = function()
						table.insert(order, "acquire inner")
					end,
					release = function()
						table.insert(order, "release inner")
					end,
				},
			},
		})
		assert.eq(order, { "acquire outer", "acquire inner", "release inner", "release outer" })
		assert.eq(execution.report.passed, 4)
	end)

	suite:case("dispatches nothing when a fixture will not acquire", function(assert)
		local host = Host.fake { units = UNITS }
		local released = false
		local fixtures: { Verify.Fixture } = {
			{
				name = "outer",
				acquire = function() end,
				release = function()
					released = true
				end,
			},
			{
				name = "broken",
				acquire = function()
					error("no environment", 0)
				end,
			},
		}
		local execution = Verify.execute(PLAN, host, { fixtures = fixtures })
		assert.eq(#host.dispatched, 0)
		assert.eq(released, true)
		assert.eq(hasFact(execution, "fixture-setup-failed"), true)
		assert.eq(statusOf(execution.report, "execution:fixture-setup-failed:broken"), "failed")
		assert.eq(statusOf(execution.report, "unit:alpha/one:not-dispatched"), "cancelled")
		assert.eq(execution.report.cancelled, 4)
	end)

	suite:case("keeps releasing after a release fails, and names the one that failed", function(assert)
		local releases: { string } = {}
		local execution = Verify.execute(PLAN, Host.fake { units = UNITS }, {
			fixtures = {
				{
					name = "outer",
					acquire = function() end,
					release = function()
						table.insert(releases, "outer")
					end,
				},
				{
					name = "middle",
					acquire = function() end,
					release = function()
						error("release refused", 0)
					end,
				},
				{
					name = "inner",
					acquire = function() end,
					release = function()
						table.insert(releases, "inner")
					end,
				},
			},
		})
		assert.eq(releases, { "inner", "outer" })
		assert.eq(statusOf(execution.report, "execution:fixture-cleanup-failed:middle"), "failed")
		assert.eq(execution.report.passed, 4)
	end)
end)

test.suite("execution retry policy", function(suite)
	suite:case("never retries a batch that returned failing cases", function(assert)
		local units = table.clone(UNITS)
		units["alpha/one"] = failing "alpha one"
		local host = Host.fake { units = units }
		local plan = table.clone(PLAN)
		plan.policy = { retry = { maxAttempts = 3, on = { "faulted", "timed_out" } } }
		local execution = Verify.execute(plan, host, { batchCount = 4 })
		assert.eq(execution.report.failed, 1)
		for _, record in execution.batches do
			assert.eq(record.attempts, if record.dispatched then 1 else 0)
		end
		assert.eq(hasFact(execution, "retry-performed"), false)
	end)

	suite:case("retries an infrastructure fault and keeps every attempt", function(assert)
		local plan = table.clone(PLAN)
		plan.policy = { retry = { maxAttempts = 3, on = { "faulted" } } }
		local host = Host.fake {
			units = UNITS,
			faults = {
				{
					batch = "batch-1",
					attempt = 1,
					status = "faulted" :: Verify.BatchStatus,
					detail = "worker vanished",
				},
			},
		}
		local execution = Verify.execute(plan, host, { batchCount = 2 })
		assert.eq(host.attemptsOf "batch-1", 2)
		assert.eq(host.attemptsOf "batch-2", 1)
		assert.eq(#execution.attempts, 3)
		assert.eq(execution.attempts[1].status, "faulted")
		assert.eq(execution.attempts[1].detail, "worker vanished")
		assert.eq(execution.attempts[1].adopted, false)
		assert.eq(execution.attempts[2].status, "returned")
		assert.eq(execution.attempts[2].adopted, true)
		assert.eq(hasFact(execution, "retry-performed"), true)
		assert.eq(execution.report.passed, 4)
		assert.eq(execution.report.failed, 0)
	end)

	suite:case("stops retrying at the attempt ceiling and accounts for every unit", function(assert)
		local plan = table.clone(PLAN)
		plan.policy = { retry = { maxAttempts = 2, on = { "faulted" } } }
		local host = Host.fake {
			units = UNITS,
			faults = { { batch = "batch-1", status = "faulted" :: Verify.BatchStatus, detail = "worker vanished" } },
		}
		local execution = Verify.execute(plan, host, { batchCount = 2 })
		assert.eq(host.attemptsOf "batch-1", 2)
		assert.eq(hasFact(execution, "batch-not-returned"), true)
		assert.eq(execution.report.failed, 2)
		assert.eq(execution.report.passed, 2)
	end)

	suite:case("does not retry a timeout the policy did not name", function(assert)
		local plan = table.clone(PLAN)
		plan.policy = { retry = { maxAttempts = 3, on = { "faulted" } } }
		local host = Host.fake {
			units = UNITS,
			faults = {
				{
					batch = "batch-1",
					status = "timed_out" :: Verify.BatchStatus,
					detail = "the batch deadline elapsed",
				},
			},
		}
		local execution = Verify.execute(plan, host, { batchCount = 2 })
		assert.eq(host.attemptsOf "batch-1", 1)
		assert.eq(execution.report.timedOut, 2)
	end)

	suite:case("names two attempts that disagreed instead of adopting the last", function(assert)
		local plan = table.clone(PLAN)
		plan.policy = { retry = { maxAttempts = 2, on = { "faulted" } } }

		local disagreeing = Verify.syntheticReport {
			executor = "fake",
			environment = { runtime = "fake" },
			capabilities = { "in-memory" },
			id = "alpha/one::alpha one",
			name = "alpha one",
			status = "failed",
			phase = "case",
			message = "it failed the first time",
		}
		local host = Host.fake {
			units = UNITS,
			faults = {
				{
					batch = "batch-1",
					attempt = 1,
					status = "faulted" :: Verify.BatchStatus,
					detail = "worker vanished after reporting",
					report = disagreeing,
				},
			},
		}
		local execution = Verify.execute(plan, host, { batchCount = 4 })
		assert.eq(hasFact(execution, "attempt-disagreement"), true)
		assert.strContains(factDetail(execution, "attempt-disagreement"), "alpha/one::alpha one")
		assert.eq(statusOf(execution.report, "execution:attempt-disagreement:batch-1"), "failed")
		assert.eq(execution.attempts[1].produced, true)
		assert.eq(execution.attempts[1].adopted, false)
		assert.that(execution.attempts[1].verdictDigest ~= execution.attempts[2].verdictDigest)
	end)
end)

test.suite("execution transport faults", function(suite)
	suite:case("names a batch the host never delivered an outcome for", function(assert)
		local execution = Verify.execute(
			PLAN,
			Host.fake { units = UNITS, maxParallelBatches = 4, dropped = { "batch-2" } },
			{ batchCount = 4, parallel = 4 }
		)
		assert.eq(hasFact(execution, "missing-batch-outcome"), true)
		assert.eq(execution.report.failed, 1)
		assert.eq(execution.report.passed, 3)
	end)

	suite:case("keeps one outcome when the host delivers a batch twice", function(assert)
		local execution = Verify.execute(
			PLAN,
			Host.fake { units = UNITS, maxParallelBatches = 4, duplicated = { "batch-3" } },
			{ batchCount = 4, parallel = 4 }
		)
		assert.eq(hasFact(execution, "duplicate-batch-outcome"), true)
		assert.eq(execution.report.passed, 4)
		assert.eq(execution.report.total, 4)
	end)

	suite:case("names an undecodable payload as a fault rather than believing it", function(assert)
		local execution = Verify.execute(
			PLAN,
			Host.fake {
				units = UNITS,
				faults = {
					{ batch = "batch-1", status = "returned" :: Verify.BatchStatus, report = { schemaVersion = 99 } },
				},
			},
			{ batchCount = 2 }
		)
		assert.eq(execution.attempts[1].status, "faulted")
		assert.strContains(tostring(execution.attempts[1].detail), "undecodable batch report")
		assert.eq(execution.report.failed, 2)
	end)

	suite:case("names a host that raised mid-batch", function(assert)
		local host = Host.fake { units = UNITS }
		local wrapped: Verify.Host = host
		wrapped.runBatch = function(): Verify.BatchOutcome
			error("the host exploded", 0)
		end
		local execution = Verify.execute(PLAN, wrapped, { batchCount = 1 })
		assert.eq(execution.attempts[1].status, "faulted")
		assert.strContains(tostring(execution.attempts[1].detail), "the host exploded")
		assert.eq(execution.report.failed, 4)
	end)
end)

test.suite("execution deadlines cancellation and fail-fast", function(suite)
	suite:case("marks what a run deadline stopped as timed out", function(assert)
		local plan = table.clone(PLAN)

		plan.policy = { runDeadlineSeconds = 0.000001 }
		local host = Host.fake { units = UNITS }
		local execution = Verify.execute(plan, host, { batchCount = 4 })
		assert.eq(#host.dispatched, 0)
		assert.eq(hasFact(execution, "run-deadline-exceeded"), true)
		assert.eq(execution.report.timedOut, 4)
	end)

	suite:case("marks what a cancellation stopped as cancelled", function(assert)
		local host = Host.fake { units = UNITS, cancelAfter = 2 }
		local execution = Verify.execute(PLAN, host, { batchCount = 4 })
		assert.eq(#host.dispatched, 2)
		assert.eq(hasFact(execution, "cancelled"), true)
		assert.eq(execution.report.passed, 3)
		assert.eq(execution.report.cancelled, 1)
		assert.eq(statusOf(execution.report, "unit:gamma/one:not-dispatched"), "cancelled")
	end)

	suite:case("stops on the first failing batch under fail-fast and says so", function(assert)
		local units = table.clone(UNITS)
		units["alpha/one"] = failing "alpha one"
		local plan = table.clone(PLAN)
		plan.policy = { failFast = true }
		local host = Host.fake { units = units }
		local execution = Verify.execute(plan, host, { batchCount = 4, parallel = 1 })
		assert.eq(#host.dispatched, 1)
		assert.eq(hasFact(execution, "fail-fast-stopped"), true)
		assert.eq(execution.report.failed, 1)
		assert.eq(execution.report.passed, 1)
		assert.eq(execution.report.skipped, 2)
		assert.eq(statusOf(execution.report, "unit:beta/one:not-dispatched"), "skipped")
	end)

	suite:case("names its own granularity when fail-fast runs in parallel", function(assert)
		local plan = table.clone(PLAN)
		plan.policy = { failFast = true }
		local execution =
			Verify.execute(plan, Host.fake { units = UNITS, maxParallelBatches = 4 }, { batchCount = 4, parallel = 4 })
		assert.eq(hasFact(execution, "fail-fast-granularity"), true)
		assert.eq(execution.report.passed, 4)
	end)

	suite:case("fails a run that proved nothing", function(assert)
		local execution = Verify.execute({ id = "empty", units = {} }, Host.fake { units = {} })
		assert.eq(hasFact(execution, "no-cases"), true)
		assert.eq(statusOf(execution.report, "execution:no-cases:empty"), "failed")
	end)
end)

test.suite("owned resources", function(suite)
	suite:case("releases a function, a dispose handle and a destroy handle", function(assert)
		local released: { string } = {}
		local harness = Verify.createHarness {
			now = function(): number
				return 0
			end,
		}
		harness:case("owns three shapes", function(context)
			context:own(function()
				table.insert(released, "function")
			end)
			context:own {
				dispose = function()
					table.insert(released, "dispose")
				end,
			}
			context:own {
				destroy = function()
					table.insert(released, "destroy")
				end,
			}
		end)
		local report = harness:run { executor = "test" }
		assert.eq(report.passed, 1)
		assert.eq(released, { "destroy", "dispose", "function" })
	end)

	suite:case("refuses a resource with no release method", function(assert)
		local harness = Verify.createHarness {
			now = function(): number
				return 0
			end,
		}
		harness:case("owns nothing releasable", function(context)
			context:own(({ handle = true } :: any) :: Verify.Resource)
		end)
		local report = harness:run { executor = "test" }
		assert.eq(report.failed, 1)
		assert.strContains(report.results[1].failures[1].message, "dispose or destroy")
	end)

	suite:case("releases an owned resource even when the case failed", function(assert)
		local released = false
		local harness = Verify.createHarness {
			now = function(): number
				return 0
			end,
		}
		harness:case("fails after owning", function(context)
			context:own(function()
				released = true
			end)
			context:expect(1):toBe(2)
		end)
		local report = harness:run { executor = "test" }
		assert.eq(report.failed, 1)
		assert.eq(released, true)
	end)
end)
