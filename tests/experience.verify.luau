--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

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

describe("experience cases", function()
	it("uses ordinary harness verdicts and actor steps", function()
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
		expect(result.passed):toBe(1)
		expect(Verify.decode(result).passed):toBe(1)
		expect(count()):toBe(1)
		expect(closed):toBe(true)
		expect(result.results[1].steps[1].actor):toBe "server"
		expect(#result.results[1].artifacts):toBe(1)
		expect(#(assert(result.results[1].evidence)).reviews):toBe(1)
	end)
	it("missing declared capabilities are unsupported without execution", function()
		local host, count = fixture()
		host.capabilities = {}
		local result = Verify.runCase(
			spec(function(context)
				context:perform("server", increment, nil)
			end),
			host
		)
		expect(result.unsupported):toBe(1)
		expect(count()):toBe(0)
	end)
	it("capture alone cannot satisfy a quality judgment", function()
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
		expect(result.unsupported):toBe(1)
		expect((assert(result.results[1].evidence)).reviews[1].judgment.status):toBe "unreviewed"
	end)
	it("judgment requires evidence from the same actor and checkpoint", function()
		local host = fixture()
		local result = Verify.runCase(
			spec(function(context)
				context:checkpoint("server", "ready")
				context:judge("client", "ready", "readable")
			end),
			host
		)
		expect(result.failed):toBe(1)
		expect(#(assert(result.results[1].evidence)).reviews):toBe(0)
	end)
	it("late completion fails and still releases the host", function()
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
		expect(result.timedOut):toBe(1)
		expect(closed):toBe(true)
	end)
	it("retains immutable portable observations and refuses cycles", function()
		local payload = { value = 1 }
		local copied = Experience.snapshot(payload) :: { value: number }
		payload.value = 2
		expect(copied.value):toBe(1)
		expect(table.isfrozen(copied)):toBe(true)
		local cycle: { [string]: unknown } = {}
		cycle.self = cycle
		local ok = pcall(Experience.snapshot, cycle)
		expect(ok):toBe(false)
	end)
	it("parity compares observations and refuses two unsupported runs", function()
		local scenario = spec(function(context)
			context:perform("server", countQuery, nil)
		end)
		local first = fixture()
		local second = fixture()
		expect(Verify.observationParity(Verify.runCase(scenario, first), Verify.runCase(scenario, second)).status):toBe "passed"
		second.invoke = function()
			return 9
		end
		expect(Verify.observationParity(Verify.runCase(scenario, first), Verify.runCase(scenario, second)).status):toBe "failed"
		first.capabilities = {}
		second.capabilities = {}
		expect(Verify.observationParity(Verify.runCase(scenario, first), Verify.runCase(scenario, second)).status):toBe "unsupported"
	end)
	it("measured performance participates in the same case verdict", function()
		local host = fixture()
		local scenario = spec(function(context)
			context:measure("server", "latency", {
				samples = { 10, 20, 30 },
				unit = "ms",
				context = { environment = "fixture", signal = "response", timing = "observed" },
			}, { unit = "ms", minimumSamples = 3, p95 = 25 })
		end)
		local result = Verify.runCase(scenario, host)
		expect(result.failed):toBe(1)
		expect((assert(result.results[1].evidence)).measurements[1].evaluation.violations[1].observed):toBe(30)
	end)

	it("supports integration registration alongside unit cases", function()
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

		expect(result.passed):toBe(2)
	end)
end)

return nil
