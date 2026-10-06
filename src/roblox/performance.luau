--!strict

local Performance = require "../core/performance"

export type Options = {
	connect: (sample: (seconds: number) -> ()) -> () -> (),
	environment: string,
	signal: string,
	maximumSamples: number,
}
export type Collector = {
	finish: () -> Performance.Input,
	count: () -> number,
}

local function collect(options: Options): Collector
	assert(options.environment ~= "" and options.signal ~= "", "collector needs environment and signal")
	assert(
		options.maximumSamples >= 1 and options.maximumSamples < math.huge and options.maximumSamples % 1 == 0,
		"sample limit must be a positive finite integer"
	)
	local samples: { number } = {}
	local active = true
	local failure: string? = nil
	local disconnect = options.connect(function(seconds)
		if not active or #samples >= options.maximumSamples then
			return
		end
		if seconds ~= seconds or seconds < 0 or seconds >= math.huge or seconds * 1000 >= math.huge then
			failure = "signal returned an invalid interval"
			return
		end
		table.insert(samples, seconds * 1000)
	end)
	return {
		count = function()
			return #samples
		end,
		finish = function()
			if active then
				active = false
				disconnect()
			end
			assert(failure == nil, failure or "invalid signal")
			return {
				samples = table.clone(samples),
				unit = "ms",
				context = { environment = options.environment, signal = options.signal, timing = "observed" },
			}
		end,
	}
end

return { collect = collect }
