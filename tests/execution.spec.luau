--!strict

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

return function(suite: Verify.Harness)
	suite:suite("focused runs are never the gate", function()
		suite:case("marks a narrowed run incomplete and names what it did not run", function(check)
			local focused = Verify.execute(PLAN, Host.fake { units = UNITS }, { selection = { ids = { "beta/one" } } })
			check:expect(focused.provenance.complete):toEqual(false)
			check:expect(focused.provenance.unitCount):toEqual(1)
			check:expect(focused.provenance.planUnitCount):toEqual(4)
			check:expect((hasFact(focused, "focused-run"))):toEqual(true)
			check:expect((factDetail(focused, "focused-run"))):toContain "is not the plan"

			check:expect(focused.report.failed):toEqual(0)
		end)

		suite:case("marks the complete plan complete and says nothing about focus", function(check)
			local whole = Verify.execute(PLAN, Host.fake { units = UNITS })
			check:expect(whole.provenance.complete):toEqual(true)
			check:expect(whole.provenance.unitCount):toEqual(whole.provenance.planUnitCount)
			check:expect((hasFact(whole, "focused-run"))):toEqual(false)
		end)

		suite:case("cannot be told it was complete when it was not", function(check)
			local everything = Verify.execute(
				PLAN,
				Host.fake { units = UNITS },
				{ selection = { ids = { "alpha/one", "alpha/two", "beta/one", "gamma/one" } } }
			)
			check:expect(everything.provenance.complete):toEqual(true)
			check:expect((hasFact(everything, "focused-run"))):toEqual(false)

			local narrowed = Verify.execute(PLAN, Host.fake { units = UNITS }, { selection = { tags = { "slow" } } })
			check:expect(narrowed.provenance.complete):toEqual(false)
		end)
	end)

	suite:suite("execution equivalence", function()
		suite:case("produces the same report serially and four ways in parallel", function(check)
			local serial = Verify.execute(PLAN, Host.fake { units = UNITS }, { batchCount = 4, parallel = 1 })
			local parallel = Verify.execute(
				PLAN,
				Host.fake { units = UNITS, maxParallelBatches = 4, completionOrder = "reverse" },
				{ batchCount = 4, parallel = 4 }
			)
			check:expect((Verify.canonical(parallel.report))):toEqual(Verify.canonical(serial.report))
			check:expect(serial.provenance.parallelism):toEqual(1)
			check:expect(parallel.provenance.parallelism):toEqual(4)
			check:expect(serial.provenance.planDigest):toEqual(parallel.provenance.planDigest)
			check:expect(serial.report.passed):toEqual(4)
		end)

		suite:case("produces the same report at every batch count", function(check)
			local one = Verify.execute(PLAN, Host.fake { units = UNITS }, { batchCount = 1 })
			for count = 2, 5 do
				local other = Verify.execute(
					PLAN,
					Host.fake { units = UNITS, maxParallelBatches = count, completionOrder = "reverse" },
					{ batchCount = count, parallel = count }
				)
				check:expect((Verify.canonical(other.report))):toEqual(Verify.canonical(one.report))
			end
		end)

		suite:case("never exceeds the parallelism the host declares", function(check)
			local execution = Verify.execute(
				PLAN,
				Host.fake { units = UNITS, maxParallelBatches = 2 },
				{ batchCount = 4, parallel = 8 }
			)
			check:expect(execution.provenance.parallelism):toEqual(2)
			check:expect(execution.report.passed):toEqual(4)
		end)

		suite:case("keeps a failing case failing however the run was scheduled", function(check)
			local units = table.clone(UNITS)
			units["beta/one"] = failing "beta one"
			local serial = Verify.execute(PLAN, Host.fake { units = units }, { batchCount = 4, parallel = 1 })
			local parallel = Verify.execute(
				PLAN,
				Host.fake { units = units, maxParallelBatches = 4, completionOrder = "reverse" },
				{ batchCount = 4, parallel = 4 }
			)
			check:expect((Verify.canonical(parallel.report))):toEqual(Verify.canonical(serial.report))
			check:expect(serial.report.failed):toEqual(1)
		end)
	end)

	suite:suite("execution capability negotiation", function()
		suite:case("never dispatches a unit whose requirement the host lacks", function(check)
			local host = Host.fake { units = UNITS, capabilities = { "in-memory" } }
			local plan = table.clone(PLAN)
			plan.units = {
				{ id = "alpha/one", locator = "alpha/one.verify.luau" },
				{ id = "beta/one", locator = "beta/one.verify.luau", requires = { "engine-datamodel" } },
			}
			local execution = Verify.execute(plan, host)
			check:expect((statusOf(execution.report, "unit:beta/one:unsupported"))):toEqual "unsupported"
			check:expect(execution.report.unsupported):toEqual(1)
			check:expect(execution.report.passed):toEqual(1)
			check:expect((hasFact(execution, "capability-missing"))):toEqual(true)
			check:expect(table.find(host.dispatched, "batch-1") ~= nil):toEqual(true)
			check:expect(#host.dispatched):toEqual(1)
		end)

		suite:case("carries the declared capability set into the report", function(check)
			local execution =
				Verify.execute(PLAN, Host.fake { units = UNITS, capabilities = { "in-memory", "worker" } })
			check:expect(execution.capabilities):toEqual { "in-memory", "worker" }
			check:expect(execution.report.capabilities):toEqual { "in-memory", "worker" }
		end)

		suite:case("makes an unservable plan unsupported rather than failed", function(check)
			local plan = table.clone(PLAN)
			plan.requires = { "engine-datamodel" }
			local execution = Verify.execute(plan, Host.fake { units = UNITS })
			check:expect(execution.report.unsupported):toEqual(4)
			check:expect(execution.report.passed):toEqual(0)
			check:expect((hasFact(execution, "plan-capability-missing"))):toEqual(true)
		end)
	end)

	suite:suite("execution provenance and artifacts", function()
		suite:case("stamps the plan identity and digest onto the report environment", function(check)
			local execution = Verify.execute(PLAN, Host.fake { units = UNITS })
			check:expect(execution.report.environment["verify.plan"]):toEqual "example"
			check:expect(execution.report.environment["verify.planDigest"]):toEqual(execution.provenance.planDigest)
			check:expect(execution.report.environment["verify.planSchema"]):toEqual "1"
			check:expect(execution.report.environment["verify.executionSchema"]):toEqual "1"
			check:expect(execution.provenance.unitCount):toEqual(4)
			check:expect(execution.provenance.host):toEqual "fake"
		end)

		suite:case("routes every artifact reference through the host sink", function(check)
			local units: { [string]: Host.UnitRun } = {
				["alpha/one"] = function(harness: Verify.Harness)
					harness:case("emits", function(context)
						context:artifact("trace", "trace.json", "application/json")
					end)
				end,
			}
			local plan: Verify.PlanDraft = { id = "p", units = { { id = "alpha/one", locator = "a.verify.luau" } } }
			local execution = Verify.execute(plan, Host.fake { units = units, artifactPrefix = "store://" })
			check
				:expect(execution.report.results[1].artifacts[1].reference)
				:toEqual "store://a.verify.luau::emits/trace.json"
			check:expect(execution.report.results[1].artifacts[1].mediaType):toEqual "application/json"
		end)

		suite:case("attributes fake-host cases to the locator its synthetic reports already name", function(check)
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
			check:expect(ran.source):toEqual "alpha/one.verify.luau"
			check:expect(missing.source):toEqual "alpha/two.verify.luau"
			check:expect(ran.id):toEqual "alpha/one.verify.luau::runs"
		end)

		suite:case("keeps the original reference and names a sink that refused", function(check)
			local units: { [string]: Host.UnitRun } = {
				["alpha/one"] = function(harness: Verify.Harness)
					harness:case("emits", function(context)
						context:artifact("trace", "trace.json")
					end)
				end,
			}
			local plan: Verify.PlanDraft = { id = "p", units = { { id = "alpha/one", locator = "a.verify.luau" } } }
			local execution = Verify.execute(plan, Host.fake { units = units, artifactFailsFor = "trace" })
			check:expect(execution.report.results[1].artifacts[1].reference):toEqual "trace.json"
			check:expect((hasFact(execution, "artifact-sink-failed"))):toEqual(true)
		end)
	end)

	suite:suite("execution fixtures", function()
		suite:case("releases fixtures newest-first, exactly once", function(check)
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
			check:expect(order):toEqual { "acquire outer", "acquire inner", "release inner", "release outer" }
			check:expect(execution.report.passed):toEqual(4)
		end)

		suite:case("dispatches nothing when a fixture will not acquire", function(check)
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
			check:expect(#host.dispatched):toEqual(0)
			check:expect(released):toEqual(true)
			check:expect((hasFact(execution, "fixture-setup-failed"))):toEqual(true)
			check:expect((statusOf(execution.report, "execution:fixture-setup-failed:broken"))):toEqual "failed"
			check:expect((statusOf(execution.report, "unit:alpha/one:not-dispatched"))):toEqual "cancelled"
			check:expect(execution.report.cancelled):toEqual(4)
		end)

		suite:case("keeps releasing after a release fails, and names the one that failed", function(check)
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
			check:expect(releases):toEqual { "inner", "outer" }
			check:expect((statusOf(execution.report, "execution:fixture-cleanup-failed:middle"))):toEqual "failed"
			check:expect(execution.report.passed):toEqual(4)
		end)
	end)

	suite:suite("execution retry policy", function()
		suite:case("never retries a batch that returned failing cases", function(check)
			local units = table.clone(UNITS)
			units["alpha/one"] = failing "alpha one"
			local host = Host.fake { units = units }
			local plan = table.clone(PLAN)
			plan.policy = { retry = { maxAttempts = 3, on = { "faulted", "timed_out" } } }
			local execution = Verify.execute(plan, host, { batchCount = 4 })
			check:expect(execution.report.failed):toEqual(1)
			for _, record in execution.batches do
				check:expect(record.attempts):toEqual(if record.dispatched then 1 else 0)
			end
			check:expect((hasFact(execution, "retry-performed"))):toEqual(false)
		end)

		suite:case("retries an infrastructure fault and keeps every attempt", function(check)
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
			check:expect(host.attemptsOf "batch-1"):toEqual(2)
			check:expect(host.attemptsOf "batch-2"):toEqual(1)
			check:expect(#execution.attempts):toEqual(3)
			check:expect(execution.attempts[1].status):toEqual "faulted"
			check:expect(execution.attempts[1].detail):toEqual "worker vanished"
			check:expect(execution.attempts[1].adopted):toEqual(false)
			check:expect(execution.attempts[2].status):toEqual "returned"
			check:expect(execution.attempts[2].adopted):toEqual(true)
			check:expect((hasFact(execution, "retry-performed"))):toEqual(true)
			check:expect(execution.report.passed):toEqual(4)
			check:expect(execution.report.failed):toEqual(0)
		end)

		suite:case("stops retrying at the attempt ceiling and accounts for every unit", function(check)
			local plan = table.clone(PLAN)
			plan.policy = { retry = { maxAttempts = 2, on = { "faulted" } } }
			local host = Host.fake {
				units = UNITS,
				faults = { { batch = "batch-1", status = "faulted" :: Verify.BatchStatus, detail = "worker vanished" } },
			}
			local execution = Verify.execute(plan, host, { batchCount = 2 })
			check:expect(host.attemptsOf "batch-1"):toEqual(2)
			check:expect((hasFact(execution, "batch-not-returned"))):toEqual(true)
			check:expect(execution.report.failed):toEqual(2)
			check:expect(execution.report.passed):toEqual(2)
		end)

		suite:case("does not retry a timeout the policy did not name", function(check)
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
			check:expect(host.attemptsOf "batch-1"):toEqual(1)
			check:expect(execution.report.timedOut):toEqual(2)
		end)

		suite:case("names two attempts that disagreed instead of adopting the last", function(check)
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
			check:expect((hasFact(execution, "attempt-disagreement"))):toEqual(true)
			check:expect((factDetail(execution, "attempt-disagreement"))):toContain "alpha/one::alpha one"
			check:expect((statusOf(execution.report, "execution:attempt-disagreement:batch-1"))):toEqual "failed"
			check:expect(execution.attempts[1].produced):toEqual(true)
			check:expect(execution.attempts[1].adopted):toEqual(false)
			assert(execution.attempts[1].verdictDigest ~= execution.attempts[2].verdictDigest)
		end)
	end)

	suite:suite("execution transport faults", function()
		suite:case("names a batch the host never delivered an outcome for", function(check)
			local execution = Verify.execute(
				PLAN,
				Host.fake { units = UNITS, maxParallelBatches = 4, dropped = { "batch-2" } },
				{ batchCount = 4, parallel = 4 }
			)
			check:expect((hasFact(execution, "missing-batch-outcome"))):toEqual(true)
			check:expect(execution.report.failed):toEqual(1)
			check:expect(execution.report.passed):toEqual(3)
		end)

		suite:case("keeps one outcome when the host delivers a batch twice", function(check)
			local execution = Verify.execute(
				PLAN,
				Host.fake { units = UNITS, maxParallelBatches = 4, duplicated = { "batch-3" } },
				{ batchCount = 4, parallel = 4 }
			)
			check:expect((hasFact(execution, "duplicate-batch-outcome"))):toEqual(true)
			check:expect(execution.report.passed):toEqual(4)
			check:expect(execution.report.total):toEqual(4)
		end)

		suite:case("names an undecodable payload as a fault rather than believing it", function(check)
			local execution = Verify.execute(
				PLAN,
				Host.fake {
					units = UNITS,
					faults = {
						{
							batch = "batch-1",
							status = "returned" :: Verify.BatchStatus,
							report = { schemaVersion = 99 },
						},
					},
				},
				{ batchCount = 2 }
			)
			check:expect(execution.attempts[1].status):toEqual "faulted"
			check:expect((tostring(execution.attempts[1].detail))):toContain "undecodable batch report"
			check:expect(execution.report.failed):toEqual(2)
		end)

		suite:case("names a host that raised mid-batch", function(check)
			local host = Host.fake { units = UNITS }
			local wrapped: Verify.Host = host
			wrapped.runBatch = function(): Verify.BatchOutcome
				error("the host exploded", 0)
			end
			local execution = Verify.execute(PLAN, wrapped, { batchCount = 1 })
			check:expect(execution.attempts[1].status):toEqual "faulted"
			check:expect((tostring(execution.attempts[1].detail))):toContain "the host exploded"
			check:expect(execution.report.failed):toEqual(4)
		end)
	end)

	suite:suite("execution deadlines cancellation and fail-fast", function()
		suite:case("marks what a run deadline stopped as timed out", function(check)
			local plan = table.clone(PLAN)

			plan.policy = { runDeadlineSeconds = 0.000001 }
			local host = Host.fake { units = UNITS }
			local execution = Verify.execute(plan, host, { batchCount = 4 })
			check:expect(#host.dispatched):toEqual(0)
			check:expect((hasFact(execution, "run-deadline-exceeded"))):toEqual(true)
			check:expect(execution.report.timedOut):toEqual(4)
		end)

		suite:case("marks what a cancellation stopped as cancelled", function(check)
			local host = Host.fake { units = UNITS, cancelAfter = 2 }
			local execution = Verify.execute(PLAN, host, { batchCount = 4 })
			check:expect(#host.dispatched):toEqual(2)
			check:expect((hasFact(execution, "cancelled"))):toEqual(true)
			check:expect(execution.report.passed):toEqual(3)
			check:expect(execution.report.cancelled):toEqual(1)
			check:expect((statusOf(execution.report, "unit:gamma/one:not-dispatched"))):toEqual "cancelled"
		end)

		suite:case("stops on the first failing batch under fail-fast and says so", function(check)
			local units = table.clone(UNITS)
			units["alpha/one"] = failing "alpha one"
			local plan = table.clone(PLAN)
			plan.policy = { failFast = true }
			local host = Host.fake { units = units }
			local execution = Verify.execute(plan, host, { batchCount = 4, parallel = 1 })
			check:expect(#host.dispatched):toEqual(1)
			check:expect((hasFact(execution, "fail-fast-stopped"))):toEqual(true)
			check:expect(execution.report.failed):toEqual(1)
			check:expect(execution.report.passed):toEqual(1)
			check:expect(execution.report.skipped):toEqual(2)
			check:expect((statusOf(execution.report, "unit:beta/one:not-dispatched"))):toEqual "skipped"
		end)

		suite:case("names its own granularity when fail-fast runs in parallel", function(check)
			local plan = table.clone(PLAN)
			plan.policy = { failFast = true }
			local execution = Verify.execute(
				plan,
				Host.fake { units = UNITS, maxParallelBatches = 4 },
				{ batchCount = 4, parallel = 4 }
			)
			check:expect((hasFact(execution, "fail-fast-granularity"))):toEqual(true)
			check:expect(execution.report.passed):toEqual(4)
		end)

		suite:case("fails a run that proved nothing", function(check)
			local execution = Verify.execute({ id = "empty", units = {} }, Host.fake { units = {} })
			check:expect((hasFact(execution, "no-cases"))):toEqual(true)
			check:expect((statusOf(execution.report, "execution:no-cases:empty"))):toEqual "failed"
		end)
	end)

	suite:suite("owned resources", function()
		suite:case("releases a function, a dispose handle and a destroy handle", function(check)
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
			check:expect(report.passed):toEqual(1)
			check:expect(released):toEqual { "destroy", "dispose", "function" }
		end)

		suite:case("refuses a resource with no release method", function(check)
			local harness = Verify.createHarness {
				now = function(): number
					return 0
				end,
			}
			harness:case("owns nothing releasable", function(context)
				context:own(({ handle = true } :: any) :: Verify.Resource)
			end)
			local report = harness:run { executor = "test" }
			check:expect(report.failed):toEqual(1)
			check:expect(report.results[1].failures[1].message):toContain "dispose or destroy"
		end)

		suite:case("releases an owned resource even when the case failed", function(check)
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
			check:expect(report.failed):toEqual(1)
			check:expect(released):toEqual(true)
		end)
	end)
end
