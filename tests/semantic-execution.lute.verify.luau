--!strict

local Verify = require "../src/core"
local Bdd = require "../src/bdd"
local Operations = require "../src/core/operations"
local Lute = require "../src/lute"

local function nothing(value: unknown): nil
	assert(value == nil, "expected no payload")
	return nil
end
local count = Verify.operation {
	kind = "query",
	name = "count",
	input = nothing,
	output = function(value: unknown): number
		assert(type(value) == "number", "count must be a number")
		return value
	end,
}

return function(suite: Verify.Harness)
	suite:suite("one case execution model", function()
		suite:case("typed host evidence survives worker wire, decode and merge", function(check)
			local host: Operations.Host = {
				name = "memory",
				capabilities = { "query:count" },
				environment = { runtime = "memory" },
				now = function()
					return 0
				end,
				invoke = function(request)
					return Verify.bindOperation(count, function()
						return 7
					end).run(request.payload, request)
				end,
			}
			host.invoke = function(request)
				return Verify.bindOperation(count, function()
					return 7
				end).run(request.payload, request)
			end
			local report = Verify.runCase({
				name = "typed observation",
				timeoutSeconds = 1,
				run = function(context: Verify.Context)
					local value: number = context:perform("server", count, nil)
					context:expect(value):toBe(7)
				end,
			}, host)
			local wire = Lute.encode(report)
			local decoded = Verify.decode(Lute.decode(wire))
			local merged = Verify.merge({ decoded }, "merged", {})
			local evidence = merged.results[1].evidence :: Operations.Evidence
			check:expect(evidence.observations[1].value):toBe(7)
			check:expect(merged.results[1].steps[evidence.observations[1].step].name):toBe "query count"
			check:expect(Verify.observationParity(report, merged).status):toBe "passed"
		end)
		suite:case("canonical report retains changed observations and rejects dangling evidence", function(check)
			local host: Operations.Host = {
				name = "memory",
				capabilities = { "query:count" },
				environment = {},
				now = function()
					return 0
				end,
				invoke = function()
					return 1
				end,
			}
			local case: Verify.NamedCase = {
				name = "observed",
				timeoutSeconds = 1,
				run = function(context: Verify.Context)
					context:perform("server", count, nil)
				end,
			}
			local first = Verify.runCase(case, host)
			host.invoke = function()
				return 2
			end
			local second = Verify.runCase(case, host)
			check:expect(Verify.canonical(first) == Verify.canonical(second)):toBe(false)
			local evidence = second.results[1].evidence :: Operations.Evidence
			evidence.observations[1].step = 99
			local decoded = pcall(Verify.decode, second)
			check:expect(decoded):toBe(false)
		end)
		suite:case("a host throwing after its deadline is still a timeout", function(check)
			local time = 0
			local host: Operations.Host = {
				name = "late",
				capabilities = { "query:count" },
				environment = {},
				now = function()
					return time
				end,
				invoke = function()
					time = 2
					error "native request exceeded its bound"
				end,
			}
			local report = Verify.runCase({
				name = "late fault",
				timeoutSeconds = 1,
				run = function(context: Verify.Context)
					context:perform("server", count, nil)
				end,
			}, host)
			check:expect(report.timedOut):toBe(1)
			check:expect(report.results[1].steps[1].status):toBe "timed_out"
		end)

		suite:case("ordinary and BDD cases use the same deadline and cleanup classifier", function(check)
			local time = 0
			local cleaned = 0
			local harness = Verify.createHarness {
				now = function()
					return time
				end,
			}
			local bdd = Bdd.create(harness)
			bdd.it("deadline", {
				timeoutSeconds = 1,
				run = function(own)
					own(function()
						cleaned += 1
						error "cleanup defect"
					end)
					time += 2
				end,
			})
			local result = harness:run { executor = "clock" }
			check:expect(result.timedOut):toBe(1)
			check:expect(cleaned):toBe(1)
			check:expect(result.results[1].failures[1].outcome):toBe "timed_out"
			check:expect(result.results[1].failures[2].phase):toBe "cleanup"
		end)
		suite:case("unsupported and unselected cases acquire no host", function(check)
			local bound = 0
			local harness = Verify.createHarness {
				now = function()
					return 0
				end,
			}
			harness:case("unsupported", {
				requires = { "query:count" },
				run = function()
					error "should not enter"
				end,
			})
			local report = harness:run {
				executor = "empty",
				bind = function(): Operations.Host
					bound += 1
					error "unexpected bind"
				end,
			}
			check:expect(report.unsupported):toBe(1)
			check:expect(bound):toBe(0)
			report = harness:run {
				executor = "empty",
				selection = { ids = { "missing" } },
				bind = function(): Operations.Host
					bound += 1
					error "unexpected bind"
				end,
			}
			check:expect(report.total):toBe(0)
			check:expect(bound):toBe(0)
		end)
		suite:case("partially acquired host cleanup survives setup failure", function(check)
			local released = false
			local harness = Verify.createHarness {
				now = function()
					return 0
				end,
			}
			harness:case("setup", function()
				error "body must not run"
			end)
			local report = harness:run {
				executor = "setup",
				bind = function(context): Operations.Host
					context:defer(function()
						released = true
					end)
					error "readiness failed"
				end,
			}
			check:expect(report.failed):toBe(1)
			check:expect(report.results[1].failures[1].phase):toBe "setup"
			check:expect(released):toBe(true)
		end)
		suite:case("cancelled execution stops mutations and preserves cleanup", function(check)
			local cancel, cleaned = false, false
			local harness = Verify.createHarness {
				now = function()
					return 0
				end,
			}
			harness:case("cancel", function(context)
				context:defer(function()
					cleaned = true
				end)
				cancel = true
				context:step("must not execute", function()
					error "executed"
				end)
			end)
			local report = harness:run {
				executor = "cancel",
				cancelled = function()
					return cancel
				end,
			}
			check:expect(report.cancelled):toBe(1)
			check:expect(cleaned):toBe(true)
		end)
		suite:case("query waits share the virtual clock and never retry a mutation", function(check)
			local time, queries = 0, 0
			local host: Operations.Host = {
				name = "virtual",
				capabilities = { "query:count" },
				environment = {},
				now = function()
					return time
				end,
				sleep = function(seconds)
					time += seconds
				end,
				invoke = function()
					queries += 1
					return queries
				end,
			}
			local report = Verify.runCase({
				name = "readiness",
				timeoutSeconds = 1,
				run = function(context: Verify.Context)
					local value: number = context:await("client", count, nil, function(value)
						return value == 3
					end, 0.1)
					context:expect(value):toBe(3)
				end,
			}, host)
			check:expect(report.passed):toBe(1)
			check:expect(queries):toBe(3)
			check:expect(time):toBe(0.2)
			local action = Verify.operation { kind = "action", name = "count", input = nothing, output = count.output }
			report = Verify.runCase({
				name = "invalid wait",
				timeoutSeconds = 1,
				run = function(context: Verify.Context)
					context:await("client", action, nil, function()
						return true
					end, 0.1)
				end,
			}, host)
			check:expect(report.failed):toBe(1)
			check:expect(queries):toBe(3)
		end)
		suite:case("recovery operations receive a fresh bounded cleanup budget", function(check)
			local time, recovered = 0, false
			local host: Operations.Host = {
				name = "clock",
				capabilities = { "query:count" },
				environment = {},
				now = function()
					return time
				end,
				invoke = function(request)
					assert(request.deadline > time and request.deadline <= time + 2, "invalid cleanup deadline")
					recovered = true
					return 0
				end,
			}
			local report = Verify.runCase({
				name = "recover",
				timeoutSeconds = 1,
				cleanupTimeoutSeconds = 2,
				run = function(context: Verify.Context)
					context:defer(function()
						context:perform("server", count, nil)
					end)
					time = 3
				end,
			}, host)
			check:expect(report.timedOut):toBe(1)
			check:expect(recovered):toBe(true)
			check:expect(#report.results[1].failures):toBe(1)
		end)
		suite:case("malformed query output is a step failure rather than an unchecked cast", function(check)
			local host: Operations.Host = {
				name = "bad",
				capabilities = { "query:count" },
				environment = {},
				now = function()
					return 0
				end,
				invoke = function()
					return "seven"
				end,
			}
			local report = Verify.runCase({
				name = "bad output",
				timeoutSeconds = 1,
				run = function(context: Verify.Context)
					context:perform("server", count, nil)
				end,
			}, host)
			check:expect(report.failed):toBe(1)
			check:expect(report.results[1].failures[1].phase):toBe "step"
		end)
	end)

	suite:suite("JSON values on the wire", function()
		suite:case("encodes and parses plain JSON values that are not reports", function(check)
			local value = { name = "run", samples = { 1, 2.5 }, nested = { ok = true } }
			local text = Lute.encode(value)
			check:expect(Lute.parse(text)):toEqual(value)
			check:expect(Lute.encode { 1, 2, 3 }):toEqual "[1,2,3]"
			check:expect(Lute.encode "text"):toEqual '"text"'
		end)

		suite:case("refuses to encode a value that JSON cannot hold and to decode a non-report", function(check)
			check:expect((pcall(Lute.encode, function() end))):toEqual(false)
			check:expect((pcall(Lute.decode, Lute.encode { name = "run" }))):toEqual(false)
		end)
	end)
end
