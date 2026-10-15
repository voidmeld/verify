--!strict

local Core = require "../src/core"

return function(suite: Core.Harness)
	suite:case("bounded waits retain terminal outcomes and clamp the final sleep", function(check)
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
		check:expect(timed.reason):toBe "timeout"
		check:expect(now):toBe(0.25)
		check:expect(timed.observed):toBe "pending"
		spec.probe = function(): (boolean, unknown, string?)
			return true, false, nil
		end
		check:expect(Core.waitUntil(spec, ops).observed):toBe(false)
		check
			:expect(Core.awaitValue(function(): boolean?
				return false
			end, 1, 0.1, ops))
			:toBe(false)
		check
			:expect(Core.awaitValue(function(): boolean?
				return false
			end, 0, 0.1, ops, true))
			:toBe(nil)
		check
			:expect(
				(
					pcall(
						Core.waitUntil,
						{ name = "invalid", deadlineSeconds = 1, pollSeconds = 0, probe = spec.probe },
						ops
					)
				)
			)
			:toBe(false)
		spec.probe = function(): (boolean, unknown, string?)
			return true, nil, "not authorized"
		end
		check:expect(Core.waitUntil(spec, ops).reason):toBe "refused"
		spec.probe = function(): (boolean, unknown, string?)
			error "failed probe"
		end
		check:expect(Core.waitUntil(spec, ops).reason):toBe "probe_threw"
		check
			:expect(Core.waitUntil(spec, {
				now = ops.now,
				sleep = ops.sleep,
				cancelled = function(): boolean
					return true
				end,
			}).reason)
			:toBe "cancelled"
	end)
end
