--!strict

local Verify = require "../src/core"
local Experience = require "../src/core/operations"

local function nothing(value: unknown): nil
	assert(value == nil, "expected no payload")
	return nil
end
local ask = Verify.operation {
	kind = "query",
	name = "answer",
	input = nothing,
	output = function(value: unknown): number
		assert(type(value) == "number", "expected a number")
		return value
	end,
}

type Fixture = { host: Experience.Host, clock: () -> number, seen: { number } }

local function fixture(silent: { [string]: boolean }): Fixture
	local time = 0
	local seen: { number } = {}
	local host: Experience.Host = {
		name = "memory",
		capabilities = { "query:answer" },
		environment = { runtime = "memory" },
		now = function()
			return time
		end,
		sleep = function(seconds: number)
			time += seconds
		end,
		invoke = function(request)
			table.insert(seen, request.deadline)
			if silent[request.actor] then
				while time < request.deadline do
					time += 0.5
				end
				error("no answer from " .. request.actor, 0)
			end
			time += 0.1
			return 7
		end,
	}
	return {
		host = host,
		clock = function()
			return time
		end,
		seen = seen,
	}
end

local function spec(run: (Verify.Context) -> (), cleaned: { boolean }?): Verify.NamedCase
	return {
		id = "deadline",
		name = "per-call deadline",
		requires = { "query:answer" },
		timeoutSeconds = 60,
		run = function(context)
			if cleaned ~= nil then
				context:defer(function()
					table.insert(cleaned, true)
				end)
			end
			run(context)
		end,
	}
end

return function(suite: Verify.Harness)
	suite:suite("per-call operation deadlines", function()
		suite:case("fails a stuck call as a timeout naming the actor and operation and still cleans up", function(check)
			local state = fixture { ghost = true }
			local cleaned: { boolean } = {}
			local report = Verify.runCase(
				spec(function(context)
					context:perform("ghost", ask, nil, 2)
					context:expect(false):toBe(true)
				end, cleaned),
				state.host
			)
			check:expect(report.timedOut):toBe(1)
			local result = report.results[1]
			check:expect(result.status):toBe "timed_out"
			local step = result.steps[1]
			check:expect(step.status):toBe "timed_out"
			check:expect(step.actor):toBe "ghost"
			check:expect(step.message or ""):toContain "operation deadline exceeded: ghost query answer"
			check:expect(#cleaned):toBe(1)
			check:expect(state.clock() < 5):toBe(true)
			check:expect(state.seen[1]):toBe(2)
		end)

		suite:case("bounds a call by the case time and leaves a prompt call untouched", function(check)
			local state = fixture {}
			local report = Verify.runCase(
				spec(function(context)
					check:expect(context:perform("server", ask, nil, 1000)):toBe(7)
					check:expect(context:perform("server", ask, nil)):toBe(7)
				end),
				state.host
			)
			check:expect(report.passed):toBe(1)
			check:expect(state.seen[1]):toBe(60)
			check:expect(state.seen[2]):toBe(60)
		end)

		suite:case("bounds a whole await and names the actor and query", function(check)
			local state = fixture {}
			local report = Verify.runCase(
				spec(function(context)
					context:await("server", ask, nil, function(value: number): boolean
						return value > 100
					end, 0.5, 3)
				end),
				state.host
			)
			check:expect(report.timedOut):toBe(1)
			local steps = report.results[1].steps
			local named = false
			for _, step in steps do
				if string.find(step.message or "", "await deadline exceeded: server answer", 1, true) ~= nil then
					named = true
				end
			end
			check:expect(named):toBe(true)
			check:expect(state.clock() < 8):toBe(true)
		end)

		suite:case("refuses a deadline that is not positive and finite", function(check)
			local state = fixture {}
			local report = Verify.runCase(
				spec(function(context)
					context:perform("server", ask, nil, 0)
				end),
				state.host
			)
			check:expect(report.failed):toBe(1)
			local again = Verify.runCase(
				spec(function(context)
					context:await("server", ask, nil, function()
						return true
					end, 0.1, math.huge)
				end),
				state.host
			)
			check:expect(again.failed):toBe(1)
		end)
	end)
end
