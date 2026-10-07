--!strict

local Verify = require "../src/core"

local function clock(): (Verify.WaitOps, { now: number, sleeps: number })
	local state = { now = 0, sleeps = 0 }
	return {
		now = function(): number
			return state.now
		end,
		sleep = function(seconds: number)
			state.sleeps += 1
			state.now += seconds
		end,
	},
		state
end

return function(suite: Verify.Harness)
	suite:suite("bounded condition waits", function()
		suite:case("returns as soon as the condition holds without sleeping again", function(check)
			local ops, state = clock()
			local calls = 0
			local result = Verify.waitUntil({
				name = "ready",
				deadlineSeconds = 10,
				pollSeconds = 1,
				probe = function(): (boolean, unknown, string?)
					calls += 1
					return calls == 3, calls
				end,
			}, ops)
			check:expect(result.ok):toEqual(true)
			check:expect(result.reason):toEqual "satisfied"
			check:expect(result.polls):toEqual(3)
			check:expect(state.sleeps):toEqual(2)
		end)

		suite:case("times out naming the wait, its duration and the last observed state", function(check)
			local ops = clock()
			local result = Verify.waitUntil({
				name = "loaded source",
				deadlineSeconds = 5,
				pollSeconds = 2,
				probe = function(): (boolean, unknown, string?)
					return false, "abc123"
				end,
				describe = function(observed: unknown): string
					return "commit " .. tostring(observed) .. " expected def456"
				end,
			}, ops)
			check:expect(result.ok):toEqual(false)
			check:expect(result.reason):toEqual "timeout"
			check:expect(result.observed):toEqual "abc123"
			check:expect(result.waitedSeconds):toEqual(5)
			check:expect(result.detail):toContain "loaded source: timed out after 5.0s"
			check:expect(result.detail):toContain "last observed: commit abc123 expected def456"
		end)

		suite:case("tells the probe how long it may run so the host can stop it", function(check)
			local ops = clock()
			local remaining: { number } = {}
			Verify.waitUntil({
				name = "bounded",
				deadlineSeconds = 4,
				pollSeconds = 3,
				probe = function(left: number): (boolean, unknown, string?)
					table.insert(remaining, left)
					return false, nil
				end,
			}, ops)
			check:expect(remaining):toEqual { 4, 1 }
		end)

		suite:case("stops on a refusal, a throwing probe and cancellation without further polls", function(check)
			local ops = clock()
			local refused = Verify.waitUntil({
				name = "identity",
				deadlineSeconds = 9,
				pollSeconds = 1,
				probe = function(): (boolean, unknown, string?)
					return false, "other-run", "run_mismatch"
				end,
			}, ops)
			check:expect(refused.reason):toEqual "refused"
			check:expect(refused.polls):toEqual(1)
			check:expect(refused.detail):toEqual "identity: run_mismatch"
			local threw = Verify.waitUntil({
				name = "probe",
				deadlineSeconds = 9,
				pollSeconds = 1,
				probe = function(): (boolean, unknown, string?)
					error "bridge gone"
				end,
			}, ops)
			check:expect(threw.reason):toEqual "probe_threw"
			check:expect(threw.detail):toContain "bridge gone"
			local cancelled = false
			ops.cancelled = function(): boolean
				return cancelled
			end
			local polls = 0
			local result = Verify.waitUntil({
				name = "cancel",
				deadlineSeconds = 99,
				pollSeconds = 1,
				probe = function(): (boolean, unknown, string?)
					polls += 1
					cancelled = polls == 2
					return false, polls
				end,
			}, ops)
			check:expect(result.reason):toEqual "cancelled"
			check:expect(result.detail):toContain "last observed: 2"
			check:expect(polls):toEqual(2)
		end)
	end)
end
