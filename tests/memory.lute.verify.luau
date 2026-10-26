--!strict

local Lute = require "../src/lute"
local Verify = require "../src/core"

return function(suite: Verify.Harness)
	suite:suite("retained heap estimates", function()
		suite:case("resolves smaller retained allocations without retaining collection pressure", function(check)
			local result = Lute.memory.measure({
				setup = function()
					return buffer.create(1024 * 1024)
				end,
				run = function(state: buffer)
					buffer.writeu8(state, 0, 17)
				end,
				teardown = function(state: buffer)
					check:expect(buffer.readu8(state, 0)):toEqual(17)
				end,
				iterations = 1,
			}, { cycles = 8 })
			check:expect(result.mountedRetainedKb > 960 and result.mountedRetainedKb < 1088):toBeTrueWith(
				`mounted {result.mountedRetainedKb} teardown {result.teardownRetainedKb} baseline {result.baseline.heapKb}`
			)
			check:expect(result.teardownRetainedKb < 32):toEqual(true)
		end)

		suite:case("finds a retained buffer and observes its release after the state scope ends", function(check)
			local result = Lute.memory.measure {
				setup = function()
					return buffer.create(4 * 1024 * 1024)
				end,
				run = function(state: buffer)
					buffer.writeu8(state, 0, 42)
				end,
				teardown = function(state: buffer)
					check:expect(buffer.readu8(state, 0)):toEqual(42)
				end,
				warmup = 2,
				iterations = 3,
			}
			check:expect(result.method):toEqual(Lute.memory.METHOD)
			check:expect(result.mountedRetainedKb > 3968 and result.mountedRetainedKb < 4224):toEqual(true)
			check:expect(result.teardownRetainedKb < 128):toEqual(true)
			check:expect(result.mounted.cycles):toEqual(4)
		end)

		suite:case("retains evidence of an allocation deliberately held beyond teardown", function(check)
			local held: { buffer } = {}
			check:defer(function()
				table.clear(held)
			end)
			local result = Lute.memory.measure {
				setup = function()
					return buffer.create(4 * 1024 * 1024)
				end,
				run = function(_state: buffer) end,
				teardown = function(state: buffer)
					table.insert(held, state)
				end,
				iterations = 1,
			}
			check:expect(result.teardownRetainedKb > 3968):toEqual(true)
			check:expect(#held):toEqual(1)
		end)

		suite:case("bounds collection progress by allocations and time", function(check)
			local clock = 0
			local memory = Lute.memory.create {
				now = function()
					return clock
				end,
				heap = function()
					return 100
				end,
				witness = function()
					local weak: { token: {}? } = { token = {} }
					return setmetatable(weak, { __mode = "" })
				end,
				pressure = function()
					clock += 1
				end,
			}
			check
				:expect(function()
					memory.settle { maxAllocations = 2, deadlineSeconds = 100 }
				end)
				:toThrow "allocation limit"
			check
				:expect(function()
					memory.settle { maxAllocations = 100, deadlineSeconds = 2 }
				end)
				:toThrow "deadline"
		end)

		suite:case("rejects invalid collection bounds and heap readings", function(check)
			for _, cycles in { 0, 1, 2.5, math.huge, math.nan } do
				check
					:expect(function()
						Lute.memory.settle { cycles = cycles }
					end)
					:toThrow "cycles"
			end
			local memory = Lute.memory.create {
				now = function()
					return 0
				end,
				heap = function()
					return math.nan
				end,
				witness = function()
					local weak: { token: {}? } = { token = nil }
					return setmetatable(weak, { __mode = "" })
				end,
				pressure = function() end,
			}
			check
				:expect(function()
					memory.settle()
				end)
				:toThrow "heap reading"
		end)

		suite:case("runs cleanup after a workload error and keeps both failures", function(check)
			local cleaned = false
			check
				:expect(function()
					Lute.memory.measure {
						setup = function()
							return 1
						end,
						run = function(_state: number)
							error("workload failed", 0)
						end,
						teardown = function(_state: number)
							cleaned = true
							error("release failed", 0)
						end,
						iterations = 1,
					}
				end)
				:toThrow "workload failed; cleanup failed: release failed"
			check:expect(cleaned):toEqual(true)
		end)
	end)
end
