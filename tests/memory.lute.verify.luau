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
		expect(result.mountedKb > 960 and result.mountedKb < 1088):toBeTrueWith(
			`mounted {result.mountedKb} teardown {result.teardownRetainedKb} baseline {result.baseline.heapKb}`
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
		expect(result.mountedKb > 3968 and result.mountedKb < 4224):toEqual(true)
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
		expect(result.mountedKb > 3968):toBeTrueWith(`mounted {result.mountedKb}`)
		expect(result.releasedKb < 128):toBeTrueWith(`released {result.releasedKb}`)
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

describe("rehearsed lifecycles", function()
	it("keeps a one-time cache out of teardown retention after a rehearsal", function()
		local function measured(rehearsals: number): number
			local cache: { buffer } = {}
			local result = Lute.memory.measure({
				setup = function()
					return true
				end,
				run = function(_state: boolean)
					if #cache == 0 then
						table.insert(cache, buffer.create(2 * 1024 * 1024))
					end
				end,
				teardown = function(_state: boolean) end,
				iterations = 1,
				rehearsals = rehearsals,
			}, { cycles = 4 })
			return result.teardownRetainedKb
		end
		local cold = measured(0)
		local rehearsed = measured(1)
		expect(cold > 1900):toBeTrueWith(`cold teardown {cold}`)
		expect(rehearsed < 256):toBeTrueWith(`rehearsed teardown {rehearsed}`)
	end)

	it("still finds growth that repeats every lifecycle", function()
		local held: { buffer } = {}
		local result = Lute.memory.measure({
			setup = function()
				return true
			end,
			run = function(_state: boolean)
				table.insert(held, buffer.create(1024 * 1024))
			end,
			teardown = function(_state: boolean) end,
			iterations = 1,
			rehearsals = 1,
		}, { cycles = 4 })
		expect(result.teardownRetainedKb > 960):toBeTrueWith(`teardown {result.teardownRetainedKb}`)
		expect(#held):toEqual(2)
	end)

	it("settles a rehearsal the same way as the measured lifecycle", function()
		local steps: { string } = {}
		local now = 0
		local memory = Lute.memory.create {
			now = function()
				now += 1
				return now
			end,
			heap = function()
				return 1
			end,
			witness = function()
				table.insert(steps, "settle")
				local weak: { token: {}? } = { token = nil }
				return setmetatable(weak, { __mode = "" })
			end,
			pressure = function() end,
		}
		memory.measure({
			setup = function()
				table.insert(steps, "setup")
				return true
			end,
			run = function(_state: boolean) end,
			teardown = function(_state: boolean)
				table.insert(steps, "teardown")
			end,
			iterations = 1,
			rehearsals = 1,
		}, { cycles = 2 })
		local rehearsal = "setup settle settle teardown"
		local baseline = "settle settle"
		local measured = "setup settle settle teardown settle settle"
		expect(table.concat(steps, " ")):toEqual(`{rehearsal} {baseline} {measured}`)
	end)

	it("grows the string table before anything it would otherwise count as retained", function()
		local steps: { string } = {}
		local now = 0
		local memory = Lute.memory.create {
			now = function()
				now += 1
				return now
			end,
			heap = function()
				return 1
			end,
			witness = function()
				table.insert(steps, "settle")
				local weak: { token: {}? } = { token = nil }
				return setmetatable(weak, { __mode = "" })
			end,
			growStringTable = function()
				table.insert(steps, "grow")
				return { "anchor" }
			end,
			pressure = function() end,
		}
		memory.measure({
			setup = function()
				table.insert(steps, "setup")
				return true
			end,
			run = function(_state: boolean) end,
			teardown = function(_state: boolean) end,
			iterations = 1,
			rehearsals = 1,
		}, { cycles = 2 })
		expect(table.concat(steps, " ", 1, 4)):toEqual "grow settle settle setup"
	end)

	it("does not count string table capacity reached during a lifecycle as retained", function()
		local held: { string } = {}
		local result = Lute.memory.measure({
			setup = function()
				held = table.create(70000, "")
				return true
			end,
			run = function(_state: boolean)
				for index = 1, 70000 do
					held[index] = `retained{index}`
				end
			end,
			teardown = function(_state: boolean)
				held = {}
			end,
			iterations = 1,
			rehearsals = 1,
		}, { cycles = 4 })
		expect(result.teardownRetainedKb < 256):toBeTrueWith(`teardown {result.teardownRetainedKb}`)
	end)

	it("measures the mounted footprint from the baseline and the release from the teardown", function()
		local heap = 100
		local now = 0
		local memory = Lute.memory.create {
			now = function()
				now += 1
				return now
			end,
			heap = function()
				return heap
			end,
			witness = function()
				local weak: { token: {}? } = { token = nil }
				return setmetatable(weak, { __mode = "" })
			end,
			pressure = function() end,
		}
		local result = memory.measure({
			setup = function()
				heap = 150
				return true
			end,
			run = function(_state: boolean) end,
			teardown = function(_state: boolean)
				heap = 90
			end,
			iterations = 1,
		}, { cycles = 2 })
		expect(result.mountedKb):toEqual(50)
		expect(result.releasedKb):toEqual(60)
		expect(result.teardownRetainedKb):toEqual(0)
	end)

	it("rejects a negative rehearsal count", function()
		expect(function()
			Lute.memory.measure {
				setup = function()
					return true
				end,
				run = function(_state: boolean) end,
				teardown = function(_state: boolean) end,
				iterations = 1,
				rehearsals = -1,
			}
		end):toThrow "memory rehearsals must be a nonnegative integer"
	end)
end)

describe("engine scheduler retention", function()
	it("releases terminal task contexts while callers retain their threads", function()
		local Scheduler = require "../src/roblox/scheduler"
		for _, terminal in { "finished", "failed", "cancelled" } do
			local scheduler = Scheduler.create()
			local probe: { context: {}? } = {}
			setmetatable(probe, { __mode = "v" })
			local function launch(): thread
				local context = {}
				probe.context = context
				return scheduler.spawnTagged(context, function()
					if terminal == "failed" then
						error("task failed", 0)
					elseif terminal == "cancelled" then
						scheduler.wait(1)
					end
				end)
			end
			local thread = launch()
			if terminal == "cancelled" then
				scheduler.cancel(thread)
			end
			Lute.memory.settle { cycles = 4 }
			expect(probe.context):toBe(nil)
			expect(coroutine.status(thread)):toBe "dead"
			expect(scheduler.pending()):toBe(0)
		end
	end)

	it("preserves a suspended task's context until it completes", function()
		local Scheduler = require "../src/roblox/scheduler"
		local scheduler = Scheduler.create()
		local context = {}
		local seen: { unknown } = {}
		local thread = scheduler.spawnTagged(context, function()
			table.insert(seen, scheduler.context())
			scheduler.wait(1)
			table.insert(seen, scheduler.context())
		end)
		Lute.memory.settle { cycles = 4 }
		scheduler.advance(1)
		scheduler.drain(16)
		expect(seen):toEqual { context, context }
		expect(coroutine.status(thread)):toBe "dead"
	end)

	it("releases a finished tagged thread", function()
		local Scheduler = require "../src/roblox/scheduler"
		local scheduler = Scheduler.create()
		local probe: { [thread]: true } = {}
		setmetatable(probe, { __mode = "k" })
		local function launch()
			local thread = scheduler.spawnTagged("finished", function() end)
			probe[thread] = true
		end
		launch()
		scheduler.drain(16)
		local pressure = 0
		while next(probe) ~= nil and pressure < 512 do
			pressure += 1
			buffer.create(64 * 1024)
		end
		expect(next(probe)):toEqual(nil)
	end)
end)

describe("engine registry capacity", function()
	it("releases datatype registry capacity after a burst", function()
		local Datatypes = require "../src/roblox/datatypes"
		local result = Lute.memory.measure({
			setup = function()
				local values: { Datatypes.UDim2Value } = {}
				for index = 1, 32768 do
					values[index] = Datatypes.UDim2.new(0, index, 0, index)
				end
				return values
			end,
			run = function(values: { Datatypes.UDim2Value })
				expect(values[32768].X.Offset):toBe(32768)
			end,
			teardown = function(_values: { Datatypes.UDim2Value }) end,
			iterations = 1,
		}, { cycles = 8 })
		expect(result.mountedKb > 8192):toBeTrueWith(`mounted {result.mountedKb}`)
		expect(result.teardownRetainedKb < 128):toBeTrueWith(`teardown {result.teardownRetainedKb}`)
	end)

	it("releases instance registration capacity after an environment is discarded", function()
		local Environment = require "../src/roblox/environment"
		type State = { environment: Environment.Environment, objects: { Environment.Instance } }
		local result = Lute.memory.measure({
			setup = function(): State
				local environment = Environment.create()
				local objects: { Environment.Instance } = {}
				for index = 1, 32768 do
					objects[index] = environment.createInstance "Folder"
				end
				return { environment = environment, objects = objects }
			end,
			run = function(state: State)
				expect(state.environment.liveObjects()):toBe(32768)
			end,
			teardown = function(state: State)
				for _, object in state.objects do
					object:Destroy()
				end
			end,
			iterations = 1,
		}, { cycles = 8 })
		expect(result.teardownRetainedKb < 128):toBeTrueWith(`teardown {result.teardownRetainedKb}`)
	end)

	it("releases the signals of destroyed instances while their environment stays alive", function()
		local Environment = require "../src/roblox/environment"
		local environment = Environment.create()
		local function cycle()
			for _ = 1, 2000 do
				local object = environment.createInstance "Folder"
				object:GetPropertyChangedSignal("Name"):Connect(function() end)
				object.Changed:Connect(function() end)
				object.AncestryChanged:Connect(function() end)
				object:Destroy()
			end
		end
		cycle()
		local before = Lute.memory.settle({ cycles = 8 }).heapKb
		cycle()
		cycle()
		local after = Lute.memory.settle({ cycles = 8 }).heapKb
		expect(after - before < 64):toBeTrueWith(`retained {after - before} KiB`)
	end)

	it("returns registry capacity after a burst of instances while their environment stays alive", function()
		local Environment = require "../src/roblox/environment"
		local environment = Environment.create()
		local function burst()
			local objects: { Environment.Instance } = {}
			local root = environment.createInstance "Frame"
			for index = 1, 32768 do
				local object = environment.createInstance "Frame"
				object.Parent = root
				objects[index] = object
			end
			for _, object in objects do
				object:Destroy()
			end
			table.clear(objects)
			root:Destroy()
		end
		local before = Lute.memory.settle({ cycles = 8 }).heapKb
		burst()
		local after = Lute.memory.settle({ cycles = 8 }).heapKb
		expect(after - before < 128):toBeTrueWith(`retained {after - before} KiB`)
	end)

	it("reads the same mounted heap whatever the number of strings already alive", function()
		local readings: { number } = {}
		for offset = 0, 280000, 40000 do
			local alive = table.create(offset, "")
			for index = 1, offset do
				alive[index] = `alive{index}`
			end
			local result = Lute.memory.measure({
				setup = function(): { string }
					return {}
				end,
				run = function(state: { string })
					for index = 1, 40000 do
						state[index] = `mounted{index}`
					end
				end,
				teardown = function(state: { string })
					table.clear(state)
				end,
				iterations = 1,
			}, { cycles = 8 })
			table.insert(readings, result.mountedKb)
			expect(#alive):toBe(offset)
		end
		local low, high = math.huge, 0
		for _, reading in readings do
			low, high = math.min(low, reading), math.max(high, reading)
		end
		expect(high - low < 256):toBeTrueWith(`mounted readings {table.concat(readings, ", ")} KiB`)
	end)
end)

return nil
