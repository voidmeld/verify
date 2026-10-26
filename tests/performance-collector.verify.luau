--!strict

local Verify = require "../src/core"
local Collector = require "../src/roblox/performance"

return function(suite: Verify.Harness)
	suite:case("signal collector bounds samples and disconnects exactly once", function(check)
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
		check:expect(samples.samples):toEqual { 10, 20 }
		feed(0.04)
		collector.finish()
		check:expect(disconnected):toBe(1)
		check:expect(collector.count()):toBe(2)
	end)
	suite:case("invalid signal evidence is refused after cleanup", function(check)
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
		check:expect(ok):toBe(false)
		check:expect(disconnected):toBe(true)
	end)
end
