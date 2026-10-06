--!strict

local Verify = require "../src/core"
local Experience = require "../src/core/operations"

local function nothing(value: unknown): nil
	assert(value == nil, "expected no payload")
	return nil
end
local increment = Verify.operation {
	kind = "action",
	name = "increment",
	input = nothing,
	output = function(value: unknown): unknown
		return value
	end,
}
local countQuery = Verify.operation {
	kind = "query",
	name = "count",
	input = nothing,
	output = function(value: unknown): number
		assert(type(value) == "number", "expected count")
		return value
	end,
}

local function fixture(): (Experience.Host, () -> number)
	local count = 0
	local host: Experience.Host = {
		name = "memory",
		capabilities = { "action:increment", "query:count", "capture", "judgment" },
		environment = { runtime = "memory" },
		now = function()
			return 0
		end,
		invoke = function(request)
			assert(request.actor == "server", "unknown actor")
			if request.kind == "action" then
				count += 1
			end
			return count
		end,
		capture = function()
			return { { name = "frame", reference = "fixture.png", mediaType = "image/png" } }
		end,
		judge = function()
			return { status = "passed", reviewer = "fixture", detail = "injected test verdict" }
		end,
	}
	return host, function()
		return count
	end
end

local function spec(run: (Verify.Context) -> ()): Verify.NamedCase
	return {
		id = "counter",
		name = "counter experience",
		requires = { "action:increment", "query:count" },
		timeoutSeconds = 5,
		run = run,
	}
end

return function(suite: Verify.Harness)
	suite:suite("experience cases", function()
		suite:case("uses ordinary harness verdicts and actor steps", function(check)
			local host, count = fixture()
			local closed = false
			host.close = function()
				closed = true
			end
			local result = Verify.runCase(
				spec(function(context)
					context:perform("server", increment, nil)
					context:expect(context:perform("server", countQuery, nil)):toBe(1)
					context:checkpoint("server", "ready")
					context:judge("server", "ready", "counter visible")
				end),
				host
			)
			check:expect(result.passed):toBe(1)
			check:expect(Verify.decode(result).passed):toBe(1)
			check:expect(count()):toBe(1)
			check:expect(closed):toBe(true)
			check:expect(result.results[1].steps[1].actor):toBe "server"
			check:expect(#result.results[1].artifacts):toBe(1)
			check:expect(#(result.results[1].evidence :: Experience.Evidence).reviews):toBe(1)
		end)
		suite:case("missing declared capabilities are unsupported without execution", function(check)
			local host, count = fixture()
			host.capabilities = {}
			local result = Verify.runCase(
				spec(function(context)
					context:perform("server", increment, nil)
				end),
				host
			)
			check:expect(result.unsupported):toBe(1)
			check:expect(count()):toBe(0)
		end)
		suite:case("capture alone cannot satisfy a quality judgment", function(check)
			local host = fixture()
			host.judge = function()
				return { status = "unreviewed", reviewer = "fixture", detail = "no review performed" }
			end
			local result = Verify.runCase(
				spec(function(context)
					context:checkpoint("server", "ready")
					context:judge("server", "ready", "readable")
				end),
				host
			)
			check:expect(result.unsupported):toBe(1)
			check
				:expect((result.results[1].evidence :: Experience.Evidence).reviews[1].judgment.status)
				:toBe "unreviewed"
		end)
		suite:case("judgment requires evidence from the same actor and checkpoint", function(check)
			local host = fixture()
			local result = Verify.runCase(
				spec(function(context)
					context:checkpoint("server", "ready")
					context:judge("client", "ready", "readable")
				end),
				host
			)
			check:expect(result.failed):toBe(1)
			check:expect(#(result.results[1].evidence :: Experience.Evidence).reviews):toBe(0)
		end)
		suite:case("late completion fails and still releases the host", function(check)
			local host = fixture()
			local time = 0
			local closed = false
			host.now = function()
				return time
			end
			host.invoke = function()
				time = 6
				return nil
			end
			host.close = function()
				closed = true
			end
			local result = Verify.runCase(
				spec(function(context)
					context:perform("server", increment, nil)
				end),
				host
			)
			check:expect(result.timedOut):toBe(1)
			check:expect(closed):toBe(true)
		end)
		suite:case("retains immutable portable observations and refuses cycles", function(check)
			local payload = { value = 1 }
			local copied = Experience.snapshot(payload) :: { value: number }
			payload.value = 2
			check:expect(copied.value):toBe(1)
			check:expect(table.isfrozen(copied)):toBe(true)
			local cycle: { [string]: unknown } = {}
			cycle.self = cycle
			local ok = pcall(Experience.snapshot, cycle)
			check:expect(ok):toBe(false)
		end)
		suite:case("parity compares observations and refuses two unsupported runs", function(check)
			local scenario = spec(function(context)
				context:perform("server", countQuery, nil)
			end)
			local first = fixture()
			local second = fixture()
			check
				:expect(
					Verify.observationParity(Verify.runCase(scenario, first), Verify.runCase(scenario, second)).status
				)
				:toBe "passed"
			second.invoke = function()
				return 9
			end
			check
				:expect(
					Verify.observationParity(Verify.runCase(scenario, first), Verify.runCase(scenario, second)).status
				)
				:toBe "failed"
			first.capabilities = {}
			second.capabilities = {}
			check
				:expect(
					Verify.observationParity(Verify.runCase(scenario, first), Verify.runCase(scenario, second)).status
				)
				:toBe "unsupported"
		end)
		suite:case("measured performance participates in the same case verdict", function(check)
			local host = fixture()
			local scenario = spec(function(context)
				context:measure("server", "latency", {
					samples = { 10, 20, 30 },
					unit = "ms",
					context = { environment = "fixture", signal = "response", timing = "observed" },
				}, { unit = "ms", minimumSamples = 3, p95 = 25 })
			end)
			local result = Verify.runCase(scenario, host)
			check:expect(result.failed):toBe(1)
			check
				:expect(
					(result.results[1].evidence :: Experience.Evidence).measurements[1].evaluation.violations[1].observed
				)
				:toBe(30)
		end)

		suite:case("supports integration registration alongside unit cases", function(check)
			local harness = Verify.createHarness {
				now = function()
					return 0
				end,
			}
			harness:case("unit", function(context)
				context:expect(1):toBe(1)
			end)
			local host = fixture()
			local scenario = spec(function(context)
				context:perform("server", increment, nil)
				context:expect(context:perform("server", countQuery, nil)):toBe(1)
			end)
			harness:case(scenario.name, scenario)
			local result = harness:run {
				executor = host.name,
				capabilities = host.capabilities,
				bind = function()
					return fixture()
				end,
			}

			check:expect(result.passed):toBe(2)
		end)
	end)
end
