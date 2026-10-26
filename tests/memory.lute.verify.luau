--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Lute = require "../src/lute"

describe("retained heap estimates", function()
	it("resolves smaller retained allocations without retaining collection pressure", function()
		local result = Lute.memory.measure({
			setup = function()
				return buffer.create(1024 * 1024)
			end,
			run = function(state: buffer)
				buffer.writeu8(state, 0, 17)
			end,
			teardown = function(state: buffer)
				expect(buffer.readu8(state, 0)):toEqual(17)
			end,
			iterations = 1,
		}, { cycles = 8 })
		expect(result.mountedRetainedKb > 960 and result.mountedRetainedKb < 1088):toBeTrueWith(
			`mounted {result.mountedRetainedKb} teardown {result.teardownRetainedKb} baseline {result.baseline.heapKb}`
		)
		expect(result.teardownRetainedKb < 32):toEqual(true)
	end)

	it("finds a retained buffer and observes its release after the state scope ends", function()
		local result = Lute.memory.measure {
			setup = function()
				return buffer.create(4 * 1024 * 1024)
			end,
			run = function(state: buffer)
				buffer.writeu8(state, 0, 42)
			end,
			teardown = function(state: buffer)
				expect(buffer.readu8(state, 0)):toEqual(42)
			end,
			warmup = 2,
			iterations = 3,
		}
		expect(result.method):toEqual(Lute.memory.METHOD)
		expect(result.mountedRetainedKb > 3968 and result.mountedRetainedKb < 4224):toEqual(true)
		expect(result.teardownRetainedKb < 128):toEqual(true)
		expect(result.mounted.cycles):toEqual(4)
	end)

	it("retains evidence of an allocation deliberately held beyond teardown", function(own)
		local held: { buffer } = {}
		own(function()
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
		expect(result.teardownRetainedKb > 3968):toEqual(true)
		expect(#held):toEqual(1)
	end)

	it("bounds collection progress by allocations and time", function()
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
		expect(function()
			memory.settle { maxAllocations = 2, deadlineSeconds = 100 }
		end):toThrow "allocation limit"
		expect(function()
			memory.settle { maxAllocations = 100, deadlineSeconds = 2 }
		end):toThrow "deadline"
	end)

	it("rejects invalid collection bounds and heap readings", function()
		for _, cycles in { 0, 1, 2.5, math.huge, math.nan } do
			expect(function()
				Lute.memory.settle { cycles = cycles }
			end):toThrow "cycles"
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
		expect(function()
			memory.settle()
		end):toThrow "heap reading"
	end)

	it("runs cleanup after a workload error and keeps both failures", function()
		local cleaned = false
		expect(function()
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
		end):toThrow "workload failed; cleanup failed: release failed"
		expect(cleaned):toEqual(true)
	end)
end)

return nil
