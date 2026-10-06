--!strict

local fs = require "@std/fs"
local json = require "@std/json"
local Core = require "../src/core"
local Experience = require "../src/core/operations"
local Files = require "../src/lute/files"
local Platform = require "../src/lute/platform"
local ProgressFile = require "../src/lute/progress-file"
local Roblox = require "../src/roblox"

local function nothing(value: unknown): nil
	assert(value == nil, "expected no payload")
	return nil
end
local ask = Core.operation {
	kind = "query",
	name = "answer",
	input = nothing,
	output = function(value: unknown): number
		assert(type(value) == "number", "expected a number")
		return value
	end,
}

local time = 0

local function clock(): number
	return time
end

local function options(events: { Core.ProgressEvent }, silent: string?): Core.RunOptions
	time = 0
	return {
		executor = "progress-test",
		capabilities = { "query:answer" },
		progress = Core.progress.create("run-1", function(event: Core.ProgressEvent)
			table.insert(events, event)
		end),
		bind = function(): Experience.Host
			return {
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
					if request.actor == silent then
						while time < request.deadline do
							time += 0.5
						end
						error("no answer", 0)
					end
					time += 0.1
					return 1
				end,
			}
		end,
	}
end

local function twoActorCase(): Core.NamedCase
	return {
		id = "two-actors",
		name = "two actors",
		requires = { "query:answer" },
		timeoutSeconds = 30,
		run = function(context: Core.Context)
			context:perform("server", ask, nil)
			context:perform("client-1", ask, nil)
			context:perform("client-2", ask, nil, 2)
		end,
	}
end

return function(suite: Core.Harness)
	suite:suite("run progress", function()
		suite:case("orders per-actor events with one monotonic sequence and never changes the report", function(check)
			local events: { Core.ProgressEvent } = {}
			local timeNow = clock
			local report = Core.runCases({ twoActorCase() }, options(events, nil), timeNow)
			local plain = Core.runCases({ twoActorCase() }, options({}, nil), timeNow)
			check:expect(report.passed):toBe(1)
			check:expect(#events):toBe(6)
			for index, event in events do
				check:expect(event.sequence):toBe(index)
				check:expect(event.runId):toBe "run-1"
				check:expect(event.caseId):toBe "two-actors"
			end
			check:expect(events[1].actor):toBe "server"
			check:expect(events[1].phase):toBe "started"
			check:expect(events[2].phase):toBe "finished"
			check:expect(events[2].status):toBe "passed"
			check:expect(events[3].actor):toBe "client-1"
			check:expect(events[5].actor):toBe "client-2"
			check:expect(events[5].step):toBe "query answer"
			check:expect(#Core.progress.pending(events)):toBe(0)
			local stripped = Core.decode(report)
			check:expect(stripped.passed):toBe(plain.passed)
			check:expect(#stripped.results[1].steps):toBe(#plain.results[1].steps)
		end)

		suite:case("leaves a started step open until it finishes so a watchdog can see a stalled actor", function(check)
			local events: { Core.ProgressEvent } = {}
			local report = Core.runCases({ twoActorCase() }, options(events, "client-2"), clock)
			check:expect(report.timedOut):toBe(1)
			check:expect(events[#events].phase):toBe "finished"
			check:expect(events[#events].status):toBe "timed_out"
			check:expect(#Core.progress.pending(events)):toBe(0)
			local cut = table.move(events, 1, #events - 1, 1, {})
			local open = Core.progress.pending(cut)
			check:expect(#open):toBe(1)
			check:expect(open[1].actor):toBe "client-2"
			check:expect(open[1].step):toBe "query answer"
		end)

		suite:case("a failing listener does not change the run", function(check)
			local calls = 0
			local report = Core.runCases({ twoActorCase() }, {
				executor = "progress-test",
				capabilities = { "query:answer" },
				progress = Core.progress.create("run-1", function()
					calls += 1
					error "listener failed"
				end),
				bind = options({}, nil).bind,
			}, clock)
			check:expect(report.passed):toBe(1)
			check:expect(calls > 0):toBe(true)
		end)

		suite:case("frames events on the output channel and collects them in order without repeats", function(check)
			local events: { Core.ProgressEvent } = {}
			Core.runCases({ twoActorCase() }, options(events, nil), clock)
			local lines: { string } = {}
			local publisher = Roblox.progressChannel.publisher("run-1", function(value: unknown): string
				return json.serialize((value :: unknown) :: json.Value)
			end, function(line: string)
				table.insert(lines, line)
			end)
			for _, event in events do
				publisher.publish(event.caseId, event.actor, event.step, event.phase, event.status)
			end
			local noise = "unrelated output\n" .. table.concat(lines, "\n") .. "\n" .. table.concat(lines, "\n")
			local collected = Roblox.progressChannel.collect(noise, "run-1", function(text: string): unknown
				return json.deserialize(text)
			end)
			check:expect(#collected):toBe(#events)
			for index, event in collected do
				check:expect(event.sequence):toBe(index)
			end
			check
				:expect(#Roblox.progressChannel.collect(noise, "other-run", function(text: string): unknown
					return json.deserialize(text)
				end))
				:toBe(0)
		end)
	end)

	suite:suite("platform progress", function()
		suite:case(
			"a simulator run appends progress lines and replays them to the listener without changing the report",
			{
				timeoutSeconds = 40,
				run = function(check: Core.Context)
					local root = Files.claimDirectory "/tmp/verify-progress-tests"
					check:defer(function()
						fs.removeDirectory(root, { recursive = true })
					end)
					local heard: { Core.ProgressEvent } = {}
					local result = Platform.run {
						host = "simulator",
						entry = "examples/platform-entry.luau",
						caseIds = { "instance-state" },
						output = root,
						deadlineSeconds = 20,
						progressFile = root .. "/steps.jsonl",
						onProgress = function(event)
							table.insert(heard, event)
						end,
					}
					check:expect(result.report.passed):toEqual(1)
					local written = ProgressFile.read(root .. "/steps.jsonl", result.directory)
					check:expect(#written > 0):toBe(true)
					check:expect(#heard):toBe(#written)
					for index, event in heard do
						check:expect(event.sequence):toBe(index)
						check:expect(event.caseId):toBe "instance-state"
					end
					local plain = Platform.run {
						host = "simulator",
						entry = "examples/platform-entry.luau",
						caseIds = { "instance-state" },
						output = root .. "/plain",
						deadlineSeconds = 20,
					}
					check:expect(plain.report.passed):toBe(1)
					check:expect(fs.exists(root .. "/plain/progress.jsonl")):toBe(false)
				end,
			}
		)
		suite:case("refuses progress on a host that cannot report it", function(check)
			local result = Platform.run {
				host = "player",
				entry = "examples/platform-entry.luau",
				placeId = 1,
				output = "/tmp/verify-progress-refused",
				progressFile = "/tmp/verify-progress-refused/p.jsonl",
			}
			check:expect(result.report.failed):toBe(1)
			fs.removeDirectory("/tmp/verify-progress-refused", { recursive = true })
		end)
	end)
end
