--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Collector = require "../src/roblox/performance"

it("signal collector bounds samples and disconnects exactly once", function()
	local feed: (number) -> () = function() end
	local disconnected = 0
	local collector = Collector.collect {
		environment = "fixture",
		signal = "frame",
		maximumSamples = 2,
		connect = function(handler)
			feed = handler
			return function()
				disconnected += 1
			end
		end,
	}
	feed(0.01)
	feed(0.02)
	feed(0.03)
	local samples = collector.finish()
	expect(samples.samples):toEqual { 10, 20 }
	feed(0.04)
	collector.finish()
	expect(disconnected):toBe(1)
	expect(collector.count()):toBe(2)
end)
it("invalid signal evidence is refused after cleanup", function()
	local disconnected = false
	local collector = Collector.collect {
		environment = "fixture",
		signal = "frame",
		maximumSamples = 1,
		connect = function(handler)
			handler(-1)
			return function()
				disconnected = true
			end
		end,
	}
	local ok = pcall(collector.finish)
	expect(ok):toBe(false)
	expect(disconnected):toBe(true)
end)

return nil
