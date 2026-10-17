--!strict

local temporary = require "./temporary"

local fs = require "@std/fs"
local Core = require "../src/core"
local Experience = require "../src/core/operations"
local Files = require "../src/lute/files"
local Platform = require "../src/lute/platform"
local ProgressFile = require "../src/lute/progress-file"
local Roblox = require "../src/roblox"
local StudioProgress = require "../src/lute/studio-progress"
local StudioEngine = require "./studio-engine"
local Wire = require "../src/lute/wire"
local json = require "@std/json"

local function historyReader(rows: { unknown }): StudioEngine.Engine
	return StudioEngine.new {
		game = {
			GetService = function(_self: unknown, name: string): unknown
				return if name == "LogService"
					then {
						GetLogHistory = function()
							return rows
						end,
					}
					else {
						JSONEncode = function(_http: unknown, value: unknown): string
							return json.serialize(value :: json.Value)
						end,
					}
			end,
		},
	}
end

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

		suite:case("collects structured contexts in order, deduplicates and rejects invalid events", function(check)
			local rows: { unknown } = {}
			local publisher = Roblox.progressChannel.publisher("/tmp/run/1", "abc123", function(message, context)
				table.insert(
					rows,
					{ message = message, loggerFullPath = Roblox.progressChannel.LOGGER, context = context }
				)
			end)
			publisher.publish("dir/case::one", "client/1", "step/one", "started", nil)
			publisher.publish("dir/case::one", "client/1", "step/one", "finished", "passed")
			table.insert(rows, rows[1])
			table.insert(rows, { loggerFullPath = "Other", context = {} })
			local collected = Roblox.progressChannel.collect(rows, "abc123", "/tmp/run/1")
			check:expect(#collected.events):toBe(2)
			check:expect(collected.events[1].sequence):toBe(1)
			check:expect(collected.events[2].sequence):toBe(2)
			check:expect(collected.events[1].caseId):toBe "dir/case::one"
			check:expect(collected.rejected):toBe(0)
			local foreign = Roblox.progressChannel.collect(rows, "different", "/tmp/run/1")
			check:expect(foreign.foreign):toBe(3)
			check:expect(#foreign.events):toBe(0)
			table.insert(rows, { loggerFullPath = Roblox.progressChannel.LOGGER })
			table.insert(
				rows,
				{ loggerFullPath = Roblox.progressChannel.LOGGER, context = { token = "abc123", event = {} } }
			)
			local broken = Roblox.progressChannel.collect(rows, "abc123", "/tmp/run/1")
			check:expect(broken.rejected):toBe(2)
			check:expect(#broken.events):toBe(2)
			check:expect(broken.first):toContain "context"
		end)
	end)

	suite:suite("Studio progress history", function()
		suite:case("pages only newer events of the token and retains malformed contexts for diagnosis", function(check)
			local rows: { unknown } = {}
			local token = 'quoted"\\é'
			local function receive(_message: string, context: unknown)
				table.insert(rows, { loggerFullPath = Roblox.progressChannel.LOGGER, context = context })
			end
			local own = Roblox.progressChannel.publisher("run", token, receive)
			local foreign = Roblox.progressChannel.publisher("other", "foreign", receive)
			own.publish("case", "client", "step", "started", nil)
			foreign.publish("case", "client", "step", "started", nil)
			own.publish("case", "client", "step", "finished", "passed")
			table.insert(rows, { loggerFullPath = Roblox.progressChannel.LOGGER })
			table.insert(
				rows,
				{ loggerFullPath = Roblox.progressChannel.LOGGER, context = { token = token, event = {} } }
			)
			local native = historyReader(rows)
			local page = native.run("Client", Roblox.progressChannel.readPage(token, 1))
			local collected = Roblox.progressChannel.collect(Wire.parse(page) :: { unknown }, token, "run")
			check:expect(#page <= 32768):toBe(true)
			check:expect(#collected.events):toBe(1)
			check:expect(collected.events[1].sequence):toBe(2)
			check:expect(collected.rejected):toBe(2)
			check:expect(collected.foreign):toBe(0)
			local all = Roblox.progressChannel.collect(
				Wire.parse(native.run("Client", Roblox.progressChannel.read)) :: { unknown },
				token,
				"run"
			)
			check:expect(#all.events):toBe(2)
			check:expect(all.foreign):toBe(1)
		end)

		suite:case("refuses an oversized event and invalid cursors instead of truncating progress", function(check)
			local rows: { unknown } = {}
			local publisher = Roblox.progressChannel.publisher("run", "token", function(_, context)
				table.insert(rows, { loggerFullPath = Roblox.progressChannel.LOGGER, context = context })
			end)
			publisher.publish("case", "client", string.rep("x", 40000), "started", nil)
			local native = historyReader(rows)
			check
				:expect(function()
					native.run("Client", Roblox.progressChannel.readPage("token", 0))
				end)
				:toThrow "page limit"
			for _, cursor in { -1, 1.5, math.huge, math.nan } do
				check
					:expect(function()
						Roblox.progressChannel.readPage("token", cursor)
					end)
					:toThrow "cursor"
			end
			check
				:expect(function()
					Roblox.progressChannel.readPage("", 0)
				end)
				:toThrow "token"
		end)

		suite:case("reports overwritten history while appending each surviving sequence once", function(check)
			local root = temporary(check, "verify-progress-history")
			local path = root .. "/events.jsonl"
			local rows: { unknown } = {}
			local listener = StudioProgress.listener(path, "run", function()
				return json.serialize((rows :: unknown) :: json.Value)
			end)
			local publisher = Roblox.progressChannel.publisher("run", listener.token, function(_, context)
				table.insert(rows, { loggerFullPath = Roblox.progressChannel.LOGGER, context = context })
			end)
			publisher.publish("case", "server", "step", "started", nil)
			publisher.publish("case", "server", "step", "finished", "passed")
			table.remove(rows, 1)
			listener.poll()
			listener.finish()
			local events = ProgressFile.read(path, "run")
			check:expect(#events):toBe(1)
			check:expect(events[1].sequence):toBe(2)
			check:expect(fs.readFileToString(path .. ".diagnostics")):toContain "history lost"
		end)
	end)
	suite:suite("platform progress", function()
		suite:case(
			"a simulator run appends progress lines and replays them to the listener without changing the report",
			{
				timeoutSeconds = 40,
				run = function(check: Core.Context)
					local root = temporary(check, "verify-progress-tests")
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
				output = Files.temporary "verify-progress-refused",
				progressFile = Files.temporary "verify-progress-refused" .. "/p.jsonl",
			}
			check:expect(result.report.failed):toBe(1)
			fs.removeDirectory(Files.temporary "verify-progress-refused", { recursive = true })
		end)
	end)
end
