--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local ReportModel = require "../src/core/report"
local Execution = require "../src/core/execution"
local Plan = require "../src/core/plan"
local Host = require "./fake-host"
local Verify = require "../src/core"

local FAULTED: Verify.BatchStatus = "faulted"
local TIMED_OUT: Verify.BatchStatus = "timed_out"
local RETURNED: Verify.BatchStatus = "returned"

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

local function queued(host: Verify.Host): Verify.Host
	host.runQueue = function(_parallel, take, deliver)
		while true do
			local batch = take()
			if batch == nil then
				break
			end
			deliver(batch.index, host.runBatch(batch))
		end
	end
	return host
end

local QUEUE_PLAN: Verify.PlanDraft = { id = "queued-example", units = {} }
for _, entry in PLAN.units do
	table.insert(QUEUE_PLAN.units, { id = entry.id, locator = entry.locator })
end

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

describe("queued execution", function()
	it("keeps reports and attempt order independent of completion order", function()
		local host = queued(Host.create { units = UNITS })
		host.runQueue = function(_parallel, take, deliver)
			local pending: { Verify.PlanBatch } = {}
			while true do
				local batch = take()
				if batch == nil then
					break
				end
				table.insert(pending, batch)
			end
			for index = #pending, 1, -1 do
				local batch = pending[index]
				deliver(batch.index, host.runBatch(batch))
			end
		end
		local actual = Verify.execute(QUEUE_PLAN, host, { batchCount = 4, parallel = 2 })
		local expected = Verify.execute(QUEUE_PLAN, Host.create { units = UNITS }, { batchCount = 4, parallel = 1 })
		expect(ReportModel.canonical(actual.report)):toEqual(ReportModel.canonical(expected.report))
		for index, attempt in actual.attempts do
			expect(attempt.batchIndex):toEqual(index)
		end
	end)
	it("stops taking new batches after a returned failure", function()
		local plan = table.clone(QUEUE_PLAN)
		plan.policy = { failFast = true }
		local units = table.clone(UNITS)
		units["alpha/one"] = failing "alpha one"
		local result = Verify.execute(plan, queued(Host.create { units = units }), { batchCount = 4, parallel = 2 })
		expect(result.report.failed):toEqual(1)
		expect(result.report.skipped):toEqual(3)
		expect(#result.attempts):toEqual(1)
		expect(hasFact(result, "fail-fast-stopped")):toEqual(true)
	end)
	it("checks cancellation before every queued dispatch", function()
		local result = Verify.execute(
			QUEUE_PLAN,
			queued(Host.create { units = UNITS, cancelAfter = 2 }),
			{ batchCount = 4, parallel = 2 }
		)
		expect(result.report.passed):toEqual(2)
		expect(result.report.cancelled):toEqual(2)
		expect(#result.attempts):toEqual(2)
	end)
	it("retains a dropped outcome and an early host return as faults", function()
		local host = queued(Host.create { units = UNITS })
		host.runQueue = function(_parallel, take, _deliver)
			take()
		end
		local result = Verify.execute(QUEUE_PLAN, host, { batchCount = 4, parallel = 2 })
		expect(result.report.failed):toEqual(4)
		expect(hasFact(result, "missing-batch-outcome")):toEqual(true)
	end)
	it("bounds each new batch by the remaining run deadline", function()
		local plan = table.clone(QUEUE_PLAN)
		plan.policy = { runDeadlineSeconds = 0.5 }
		local host = queued(Host.create { units = UNITS, latency = { ["batch-1"] = 1 } })
		local runBatch = host.runBatch
		local deadlines: { number } = {}
		host.runBatch = function(batch)
			table.insert(deadlines, assert(batch.deadlineSeconds))
			return runBatch(batch)
		end
		local result = Verify.execute(plan, host, { batchCount = 4, parallel = 2 })
		expect(#deadlines):toEqual(1)
		expect(deadlines[1] > 0 and deadlines[1] < 0.5):toBe(true)
		expect(result.report.passed):toEqual(1)
		expect(result.report.timedOut):toEqual(3)
	end)
	it("rejects an outcome for a batch that was never dispatched", function()
		local host = queued(Host.create { units = UNITS })
		local dispatch = assert(host.runQueue)
		host.runQueue = function(parallel, take, deliver)
			deliver(99, { status = "faulted", detail = "foreign outcome" })
			dispatch(parallel, take, deliver)
		end
		local result = Verify.execute(QUEUE_PLAN, host, { batchCount = 4, parallel = 2 })
		expect(result.report.passed):toEqual(4)
		expect(result.report.failed):toEqual(1)
		expect(hasFact(result, "unexpected-batch-outcome")):toEqual(true)
	end)
	it("retains declared infrastructure retries without retrying verdicts", function()
		local plan = table.clone(QUEUE_PLAN)
		plan.policy = { retry = { maxAttempts = 2, on = { "faulted" } } }
		local fault: Host.Fault = { batch = "batch-1", attempt = 1, status = "faulted", detail = "worker vanished" }
		local host = queued(Host.create {
			units = UNITS,
			faults = { fault },
		})
		local result = Verify.execute(plan, host, { batchCount = 4, parallel = 2 })
		expect(result.report.passed):toEqual(4)
		expect(#result.attempts):toEqual(5)
		expect(result.attempts[5].attempt):toEqual(2)
	end)
end)
describe("focused runs are never the gate", function()
	it("marks a narrowed run incomplete and names what it did not run", function()
		local focused = Verify.execute(PLAN, Host.create { units = UNITS }, { selection = { ids = { "beta/one" } } })
		expect(focused.provenance.complete):toEqual(false)
		expect(focused.provenance.unitCount):toEqual(1)
		expect(focused.provenance.planUnitCount):toEqual(4)
		expect((hasFact(focused, "focused-run"))):toEqual(true)
		expect((factDetail(focused, "focused-run"))):toContain "is not the plan"

		expect(focused.report.failed):toEqual(0)
	end)

	it("marks the complete plan complete and says nothing about focus", function()
		local whole = Verify.execute(PLAN, Host.create { units = UNITS })
		expect(whole.provenance.complete):toEqual(true)
		expect(whole.provenance.unitCount):toEqual(whole.provenance.planUnitCount)
		expect((hasFact(whole, "focused-run"))):toEqual(false)
	end)

	it("cannot be told it was complete when it was not", function()
		local everything = Verify.execute(
			PLAN,
			Host.create { units = UNITS },
			{ selection = { ids = { "alpha/one", "alpha/two", "beta/one", "gamma/one" } } }
		)
		expect(everything.provenance.complete):toEqual(true)
		expect((hasFact(everything, "focused-run"))):toEqual(false)

		local narrowed = Verify.execute(PLAN, Host.create { units = UNITS }, { selection = { tags = { "slow" } } })
		expect(narrowed.provenance.complete):toEqual(false)
	end)
end)

describe("execution equivalence", function()
	it("produces the same report serially and four ways in parallel", function()
		local serial = Verify.execute(PLAN, Host.create { units = UNITS }, { batchCount = 4, parallel = 1 })
		local parallel = Verify.execute(
			PLAN,
			Host.create { units = UNITS, maxParallelBatches = 4, completionOrder = "reverse" },
			{ batchCount = 4, parallel = 4 }
		)
		expect((ReportModel.canonical(parallel.report))):toEqual(ReportModel.canonical(serial.report))
		expect(serial.provenance.parallelism):toEqual(1)
		expect(parallel.provenance.parallelism):toEqual(4)
		expect(serial.provenance.planDigest):toEqual(parallel.provenance.planDigest)
		expect(serial.report.passed):toEqual(4)
	end)

	it("produces the same report at every batch count", function()
		local one = Verify.execute(PLAN, Host.create { units = UNITS }, { batchCount = 1 })
		for count = 2, 5 do
			local other = Verify.execute(
				PLAN,
				Host.create { units = UNITS, maxParallelBatches = count, completionOrder = "reverse" },
				{ batchCount = count, parallel = count }
			)
			expect((ReportModel.canonical(other.report))):toEqual(ReportModel.canonical(one.report))
		end
	end)

	it("never exceeds the parallelism the host declares", function()
		local execution = Verify.execute(
			PLAN,
			Host.create { units = UNITS, maxParallelBatches = 2 },
			{ batchCount = 4, parallel = 8 }
		)
		expect(execution.provenance.parallelism):toEqual(2)
		expect(execution.report.passed):toEqual(4)
	end)

	it("keeps a failing case failing however the run was scheduled", function()
		local units = table.clone(UNITS)
		units["beta/one"] = failing "beta one"
		local serial = Verify.execute(PLAN, Host.create { units = units }, { batchCount = 4, parallel = 1 })
		local parallel = Verify.execute(
			PLAN,
			Host.create { units = units, maxParallelBatches = 4, completionOrder = "reverse" },
			{ batchCount = 4, parallel = 4 }
		)
		expect((ReportModel.canonical(parallel.report))):toEqual(ReportModel.canonical(serial.report))
		expect(serial.report.failed):toEqual(1)
	end)
end)

describe("execution capability negotiation", function()
	it("never dispatches a unit whose requirement the host lacks", function()
		local host = Host.create { units = UNITS, capabilities = { "in-memory" } }
		local plan = table.clone(PLAN)
		plan.units = {
			{ id = "alpha/one", locator = "alpha/one.verify.luau" },
			{ id = "beta/one", locator = "beta/one.verify.luau", requires = { "engine-datamodel" } },
		}
		local execution = Verify.execute(plan, host)
		expect((statusOf(execution.report, "unit:beta/one:unsupported"))):toEqual "unsupported"
		expect(execution.report.unsupported):toEqual(1)
		expect(execution.report.passed):toEqual(1)
		expect((hasFact(execution, "capability-missing"))):toEqual(true)
		expect(table.find(host.dispatched, "batch-1") ~= nil):toEqual(true)
		expect(#host.dispatched):toEqual(1)
	end)

	it("carries the declared capability set into the report", function()
		local execution = Verify.execute(PLAN, Host.create { units = UNITS, capabilities = { "in-memory", "worker" } })
		expect(execution.capabilities):toEqual { "in-memory", "worker" }
		expect(execution.report.capabilities):toEqual { "in-memory", "worker" }
	end)

	it("makes an unservable plan unsupported rather than failed", function()
		local plan = table.clone(PLAN)
		plan.requires = { "engine-datamodel" }
		local execution = Verify.execute(plan, Host.create { units = UNITS })
		expect(execution.report.unsupported):toEqual(4)
		expect(execution.report.passed):toEqual(0)
		expect((hasFact(execution, "plan-capability-missing"))):toEqual(true)
	end)
end)

describe("execution provenance and artifacts", function()
	it("stamps the plan identity and digest onto the report environment", function()
		local execution = Verify.execute(PLAN, Host.create { units = UNITS })
		expect(execution.report.environment["verify.plan"]):toEqual "example"
		expect(execution.report.environment["verify.planDigest"]):toEqual(execution.provenance.planDigest)
		expect(execution.report.environment["verify.planSchema"]):toEqual "1"
		expect(execution.report.environment["verify.executionSchema"]):toEqual "1"
		expect(execution.provenance.unitCount):toEqual(4)
		expect(execution.provenance.host):toEqual "fake"
	end)

	it("routes every artifact reference through the host sink", function()
		local units: { [string]: Host.UnitRun } = {
			["alpha/one"] = function(harness: Verify.Harness)
				harness:case("emits", function(context)
					context:artifact("trace", "trace.json", "application/json")
				end)
			end,
		}
		local plan: Verify.PlanDraft = { id = "p", units = { { id = "alpha/one", locator = "a.verify.luau" } } }
		local execution = Verify.execute(plan, Host.create { units = units, artifactPrefix = "store://" })
		expect(execution.report.results[1].artifacts[1].reference):toEqual "store://a.verify.luau::emits/trace.json"
		expect(execution.report.results[1].artifacts[1].mediaType):toEqual "application/json"
	end)

	it("attributes fake-host cases to the locator its synthetic reports already name", function()
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
		local execution = Verify.execute(plan, Host.create { units = units })
		local ran = execution.report.results[1]
		local missing = execution.report.results[2]
		expect(ran.source):toEqual "alpha/one.verify.luau"
		expect(missing.source):toEqual "alpha/two.verify.luau"
		expect(ran.id):toEqual "alpha/one.verify.luau::runs"
	end)

	it("keeps the original reference and names a sink that refused", function()
		local units: { [string]: Host.UnitRun } = {
			["alpha/one"] = function(harness: Verify.Harness)
				harness:case("emits", function(context)
					context:artifact("trace", "trace.json")
				end)
			end,
		}
		local plan: Verify.PlanDraft = { id = "p", units = { { id = "alpha/one", locator = "a.verify.luau" } } }
		local execution = Verify.execute(plan, Host.create { units = units, artifactFailsFor = "trace" })
		expect(execution.report.results[1].artifacts[1].reference):toEqual "trace.json"
		expect((hasFact(execution, "artifact-sink-failed"))):toEqual(true)
	end)
end)

describe("execution fixtures", function()
	it("releases fixtures newest-first, exactly once", function()
		local order: { string } = {}
		local execution = Verify.execute(PLAN, Host.create { units = UNITS }, {
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
		expect(order):toEqual { "acquire outer", "acquire inner", "release inner", "release outer" }
		expect(execution.report.passed):toEqual(4)
	end)

	it("dispatches nothing when a fixture will not acquire", function()
		local host = Host.create { units = UNITS }
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
		expect(#host.dispatched):toEqual(0)
		expect(released):toEqual(true)
		expect((hasFact(execution, "fixture-setup-failed"))):toEqual(true)
		expect((statusOf(execution.report, "execution:fixture-setup-failed:broken"))):toEqual "failed"
		expect((statusOf(execution.report, "unit:alpha/one:not-dispatched"))):toEqual "cancelled"
		expect(execution.report.cancelled):toEqual(4)
	end)

	it("keeps releasing after a release fails, and names the one that failed", function()
		local releases: { string } = {}
		local execution = Verify.execute(PLAN, Host.create { units = UNITS }, {
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
		expect(releases):toEqual { "inner", "outer" }
		expect((statusOf(execution.report, "execution:fixture-cleanup-failed:middle"))):toEqual "failed"
		expect(execution.report.passed):toEqual(4)
	end)
end)

describe("execution retry policy", function()
	it("never retries a batch that returned failing cases", function()
		local units = table.clone(UNITS)
		units["alpha/one"] = failing "alpha one"
		local host = Host.create { units = units }
		local plan = table.clone(PLAN)
		plan.policy = { retry = { maxAttempts = 3, on = { "faulted", "timed_out" } } }
		local execution = Verify.execute(plan, host, { batchCount = 4 })
		expect(execution.report.failed):toEqual(1)
		for _, record in execution.batches do
			expect(record.attempts):toEqual(if record.dispatched then 1 else 0)
		end
		expect((hasFact(execution, "retry-performed"))):toEqual(false)
	end)

	it("retries an infrastructure fault and keeps every attempt", function()
		local plan = table.clone(PLAN)
		plan.policy = { retry = { maxAttempts = 3, on = { "faulted" } } }
		local host = Host.create {
			units = UNITS,
			faults = {
				{
					batch = "batch-1",
					attempt = 1,
					status = FAULTED,
					detail = "worker vanished",
				},
			},
		}
		local execution = Verify.execute(plan, host, { batchCount = 2 })
		expect(host.attemptsOf "batch-1"):toEqual(2)
		expect(host.attemptsOf "batch-2"):toEqual(1)
		expect(#execution.attempts):toEqual(3)
		expect(execution.attempts[1].status):toEqual "faulted"
		expect(execution.attempts[1].detail):toEqual "worker vanished"
		expect(execution.attempts[1].adopted):toEqual(false)
		expect(execution.attempts[2].status):toEqual "returned"
		expect(execution.attempts[2].adopted):toEqual(true)
		expect((hasFact(execution, "retry-performed"))):toEqual(true)
		expect(execution.report.passed):toEqual(4)
		expect(execution.report.failed):toEqual(0)
	end)

	it("stops retrying at the attempt ceiling and accounts for every unit", function()
		local plan = table.clone(PLAN)
		plan.policy = { retry = { maxAttempts = 2, on = { "faulted" } } }
		local host = Host.create {
			units = UNITS,
			faults = { { batch = "batch-1", status = FAULTED, detail = "worker vanished" } },
		}
		local execution = Verify.execute(plan, host, { batchCount = 2 })
		expect(host.attemptsOf "batch-1"):toEqual(2)
		expect((hasFact(execution, "batch-not-returned"))):toEqual(true)
		expect(execution.report.failed):toEqual(2)
		expect(execution.report.passed):toEqual(2)
	end)

	it("does not retry a timeout the policy did not name", function()
		local plan = table.clone(PLAN)
		plan.policy = { retry = { maxAttempts = 3, on = { "faulted" } } }
		local host = Host.create {
			units = UNITS,
			faults = {
				{
					batch = "batch-1",
					status = TIMED_OUT,
					detail = "the batch deadline elapsed",
				},
			},
		}
		local execution = Verify.execute(plan, host, { batchCount = 2 })
		expect(host.attemptsOf "batch-1"):toEqual(1)
		expect(execution.report.timedOut):toEqual(2)
	end)

	it("names two attempts that disagreed instead of adopting the last", function()
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
		local host = Host.create {
			units = UNITS,
			faults = {
				{
					batch = "batch-1",
					attempt = 1,
					status = FAULTED,
					detail = "worker vanished after reporting",
					report = disagreeing,
				},
			},
		}
		local execution = Verify.execute(plan, host, { batchCount = 4 })
		expect((hasFact(execution, "attempt-disagreement"))):toEqual(true)
		expect((factDetail(execution, "attempt-disagreement"))):toContain "alpha/one::alpha one"
		expect((statusOf(execution.report, "execution:attempt-disagreement:batch-1"))):toEqual "failed"
		expect(execution.attempts[1].produced):toEqual(true)
		expect(execution.attempts[1].adopted):toEqual(false)
		assert(execution.attempts[1].verdictDigest ~= execution.attempts[2].verdictDigest)
	end)
end)

describe("execution transport faults", function()
	it("names a batch the host never delivered an outcome for", function()
		local execution = Verify.execute(
			PLAN,
			Host.create { units = UNITS, maxParallelBatches = 4, dropped = { "batch-2" } },
			{ batchCount = 4, parallel = 4 }
		)
		expect((hasFact(execution, "missing-batch-outcome"))):toEqual(true)
		expect(execution.report.failed):toEqual(1)
		expect(execution.report.passed):toEqual(3)
	end)

	it("keeps one outcome when the host delivers a batch twice", function()
		local execution = Verify.execute(
			PLAN,
			Host.create { units = UNITS, maxParallelBatches = 4, duplicated = { "batch-3" } },
			{ batchCount = 4, parallel = 4 }
		)
		expect((hasFact(execution, "duplicate-batch-outcome"))):toEqual(true)
		expect(execution.report.passed):toEqual(4)
		expect(execution.report.total):toEqual(4)
	end)

	it("names an undecodable payload as a fault rather than believing it", function()
		local execution = Verify.execute(
			PLAN,
			Host.create {
				units = UNITS,
				faults = {
					{
						batch = "batch-1",
						status = RETURNED,
						report = { schemaVersion = 99 },
					},
				},
			},
			{ batchCount = 2 }
		)
		expect(execution.attempts[1].status):toEqual "faulted"
		expect((tostring(execution.attempts[1].detail))):toContain "undecodable batch report"
		expect(execution.report.failed):toEqual(2)
	end)

	it("names a host that raised mid-batch", function()
		local host = Host.create { units = UNITS }
		local wrapped: Verify.Host = host
		wrapped.runBatch = function(): Verify.BatchOutcome
			error("the host exploded", 0)
		end
		local execution = Verify.execute(PLAN, wrapped, { batchCount = 1 })
		expect(execution.attempts[1].status):toEqual "faulted"
		expect((tostring(execution.attempts[1].detail))):toContain "the host exploded"
		expect(execution.report.failed):toEqual(4)
	end)
end)

describe("execution deadlines cancellation and fail-fast", function()
	it("marks what a run deadline stopped as timed out", function()
		local plan = table.clone(PLAN)

		plan.policy = { runDeadlineSeconds = 0.000001 }
		local host = Host.create { units = UNITS }
		local execution = Verify.execute(plan, host, { batchCount = 4 })
		expect(#host.dispatched):toEqual(0)
		expect((hasFact(execution, "run-deadline-exceeded"))):toEqual(true)
		expect(execution.report.timedOut):toEqual(4)
	end)

	it("marks what a cancellation stopped as cancelled", function()
		local host = Host.create { units = UNITS, cancelAfter = 2 }
		local execution = Verify.execute(PLAN, host, { batchCount = 4 })
		expect(#host.dispatched):toEqual(2)
		expect((hasFact(execution, "cancelled"))):toEqual(true)
		expect(execution.report.passed):toEqual(3)
		expect(execution.report.cancelled):toEqual(1)
		expect((statusOf(execution.report, "unit:gamma/one:not-dispatched"))):toEqual "cancelled"
	end)

	it("stops on the first failing batch under fail-fast and says so", function()
		local units = table.clone(UNITS)
		units["alpha/one"] = failing "alpha one"
		local plan = table.clone(PLAN)
		plan.policy = { failFast = true }
		local host = Host.create { units = units }
		local execution = Verify.execute(plan, host, { batchCount = 4, parallel = 1 })
		expect(#host.dispatched):toEqual(1)
		expect((hasFact(execution, "fail-fast-stopped"))):toEqual(true)
		expect(execution.report.failed):toEqual(1)
		expect(execution.report.passed):toEqual(1)
		expect(execution.report.skipped):toEqual(2)
		expect((statusOf(execution.report, "unit:beta/one:not-dispatched"))):toEqual "skipped"
	end)

	it("names its own granularity when fail-fast runs in parallel", function()
		local plan = table.clone(PLAN)
		plan.policy = { failFast = true }
		local execution = Verify.execute(
			plan,
			Host.create { units = UNITS, maxParallelBatches = 4 },
			{ batchCount = 4, parallel = 4 }
		)
		expect((hasFact(execution, "fail-fast-granularity"))):toEqual(true)
		expect(execution.report.passed):toEqual(4)
	end)

	it("fails a run that proved nothing", function()
		local execution = Verify.execute({ id = "empty", units = {} }, Host.create { units = {} })
		expect((hasFact(execution, "no-cases"))):toEqual(true)
		expect((statusOf(execution.report, "execution:no-cases:empty"))):toEqual "failed"
	end)
end)

describe("owned resources", function()
	it("releases a function, a dispose handle and a destroy handle", function()
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
		expect(report.passed):toEqual(1)
		expect(released):toEqual { "destroy", "dispose", "function" }
	end)

	it("refuses a resource with no release method", function()
		local harness = Verify.createHarness {
			now = function(): number
				return 0
			end,
		}
		harness:case("owns nothing releasable", function(context)
			context:own(({ handle = true } :: unknown) :: Verify.Resource)
		end)
		local report = harness:run { executor = "test" }
		expect(report.failed):toEqual(1)
		expect(report.results[1].failures[1].message):toContain "dispose or destroy"
	end)

	it("releases an owned resource even when the case failed", function()
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
		expect(report.failed):toEqual(1)
		expect(released):toEqual(true)
	end)

	describe("selection accounting", function()
		it("says exactly what ran, what the host could not run and what was not run", function()
			local plan = Plan.validate {
				id = "catalogue",
				units = {
					{ id = "unit/a", locator = "a.luau", tags = { "unit" } },
					{ id = "unit/b", locator = "b.luau", tags = { "unit" } },
					{ id = "e2e/c", locator = "c.luau", tags = { "e2e" }, requires = { "player" } },
				},
			}
			local units: { [string]: Host.UnitRun } = {
				["unit/a"] = passing "a",
				["unit/b"] = passing "b",
				["e2e/c"] = passing "c",
			}
			local execution = Verify.execute(
				plan,
				Host.create { units = units, capabilities = { "in-memory" } },
				{ selection = { tags = { "unit" } } }
			)
			local account = Execution.account(plan, execution)
			expect(account.ran):toEqual { "unit/a", "unit/b" }
			expect(account.unsupported):toEqual { ["e2e/c"] = { "player" } }
			expect(account.notRun):toEqual {}
			expect(account.complete):toEqual(false)
			local narrowed = Execution.account(
				plan,
				Verify.execute(
					plan,
					Host.create { units = units, capabilities = { "in-memory", "player" } },
					{ selection = { ids = { "unit/a" } } }
				)
			)
			expect(narrowed.ran):toEqual { "unit/a" }
			expect(narrowed.notRun):toEqual { "unit/b", "e2e/c" }
		end)
	end)
end)

return nil
