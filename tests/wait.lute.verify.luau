--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Core = require "../src/core"

it("bounded waits retain terminal outcomes and clamp the final sleep", function()
	local now = 0
	local ops = {
		now = function(): number
			return now
		end,
		sleep = function(seconds: number)
			now += seconds
		end,
	}
	local spec = {
		name = "fixture",
		deadlineSeconds = 0.25,
		pollSeconds = 0.2,
		probe = function(): (boolean, unknown, string?)
			return false, "pending", nil
		end,
	}
	local timed = Core.waitUntil(spec, ops)
	expect(timed.reason):toBe "timeout"
	expect(now):toBe(0.25)
	expect(timed.observed):toBe "pending"
	spec.probe = function(): (boolean, unknown, string?)
		return true, false, nil
	end
	expect(Core.waitUntil(spec, ops).observed):toBe(false)
	expect(Core.awaitValue(function(): boolean?
		return false
	end, 1, 0.1, ops)):toBe(false)
	expect(Core.awaitValue(function(): boolean?
		return false
	end, 0, 0.1, ops, true)):toBe(nil)
	expect((pcall(Core.waitUntil, { name = "invalid", deadlineSeconds = 1, pollSeconds = 0, probe = spec.probe }, ops))):toBe(
		false
	)
	spec.probe = function(): (boolean, unknown, string?)
		return true, nil, "not authorized"
	end
	expect(Core.waitUntil(spec, ops).reason):toBe "refused"
	spec.probe = function(): (boolean, unknown, string?)
		error "failed probe"
	end
	expect(Core.waitUntil(spec, ops).reason):toBe "probe_threw"
	expect(Core.waitUntil(spec, {
		now = ops.now,
		sleep = ops.sleep,
		cancelled = function(): boolean
			return true
		end,
	}).reason):toBe "cancelled"
end)

return nil
