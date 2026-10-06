--!strict

local Verify = require "../src/core"
local Player = require "../src/lute/player"
local Channel = require "../src/roblox/report-channel"
local json = require "@std/json"
local fs = require "@std/fs"
local Files = require "../src/lute/files"

local function reportBytes(runId: string): string
	local harness = Verify.createHarness {
		now = function()
			return 0
		end,
	}
	harness:case("native fixture", function() end)
	local report = harness:run { executor = "player", capabilities = {}, environment = { runtime = "roblox-player" } }
	local lines: { string } = {}
	Channel.publish(runId, report, function(value)
		return json.serialize(value :: json.Object)
	end, function(line)
		table.insert(lines, line)
	end)
	return table.concat(lines, "\n") .. "\n"
end

local function fixture(bytes: string): (Player.Backend, {
	closed: boolean,
	alive: boolean,
	bytes: string,
	cleanupFails: boolean,
	address: string,
})
	local state = { closed = false, alive = true, bytes = bytes, cleanupFails = false, address = "" }
	local now = 0
	local backend: Player.Backend = {
		now = function()
			return now
		end,
		sleep = function(seconds)
			now += seconds
		end,
		launch = function(address)
			state.address = address
			return {
				read = function()
					return state.bytes
				end,
				alive = function()
					return state.alive
				end,
				close = function()
					state.closed = true
					assert(not state.cleanupFails, "cleanup failure")
				end,
			}
		end,
	}
	return backend, state
end

return function(suite: Verify.Harness)
	suite:suite("Player launcher", function()
		suite:case("uses the documented deep link and percent encodes launch data", function(check)
			local address = Player.url(123, "run&+#")
			check:expect(address):toContain "roblox://placeId=123&launchData="
			check:expect(address):toContain "run%26%2B%23"
			check:expect((pcall(Player.url, 0, "run"))):toBe(false)
			check:expect((pcall(Player.url, 1, ""))):toBe(false)
		end)
		suite:case("forwards explicit case and entry selection", function(check)
			local address = Player.url(123, "run", { caseIds = { "motion" }, entry = "tests/shared" })
			check:expect(address):toContain "verifyCases"
			check:expect(address):toContain "motion"
			check:expect(address):toContain "verifyEntry"
			check:expect(address):toContain "tests%2Fshared"
			check:expect((pcall(Player.url, 123, "run", { caseIds = {} }))):toBe(false)
			check:expect((pcall(Player.url, 123, "run", { caseIds = { "x", "x" } }))):toBe(false)
		end)
		suite:case("collects a bound report and closes its client", function(check)
			local backend, state = fixture(reportBytes "new")
			local outcome = Player.run { placeId = 123, runId = "new", backend = backend }
			check:expect(outcome.status):toBe "returned"
			if outcome.status == "returned" then
				check:expect(Verify.decode(outcome.report).passed):toBe(1)
			end
			check:expect(state.closed):toBe(true)
		end)
		suite:case("rejects reports from another run and still closes", function(check)
			local backend, state = fixture(reportBytes "old")
			local outcome = Player.run { placeId = 123, runId = "new", backend = backend }
			check:expect(outcome.status):toBe "faulted"
			check:expect(state.closed):toBe(true)
		end)
		suite:case("rejects conflicting reports instead of selecting a convenient success", function(check)
			local bytes = reportBytes "new"
			local backend, state = fixture(bytes .. "VERIFY_REPORT|{}\n")
			check:expect(Player.run({ placeId = 123, runId = "new", backend = backend }).status):toBe "faulted"
			check:expect(state.closed):toBe(true)
		end)
		suite:case("times out incomplete output and closes the client", function(check)
			local backend, state = fixture "VERIFY_REPORT|chunk|1/2|partial\n"
			check
				:expect(Player.run({ placeId = 123, runId = "new", backend = backend, deadlineSeconds = 1 }).status)
				:toBe "timed_out"
			check:expect(state.closed):toBe(true)
		end)
		suite:case("fails if the client disappears before reporting", function(check)
			local backend, state = fixture ""
			state.alive = false
			check:expect(Player.run({ placeId = 123, runId = "new", backend = backend }).status):toBe "faulted"
			check:expect(state.closed):toBe(true)
		end)
		suite:case("rejects a complete report delivered after the deadline", function(check)
			local backend, state = fixture(reportBytes "new")
			local launch = backend.launch
			backend.launch = function(address, deadline)
				local session = launch(address, deadline)
				local read = session.read
				session.read = function(remaining)
					backend.sleep(remaining + 1)
					return read(remaining)
				end
				return session
			end
			check
				:expect(Player.run({ placeId = 123, runId = "new", backend = backend, deadlineSeconds = 1 }).status)
				:toBe "timed_out"
			check:expect(state.closed):toBe(true)
		end)
		suite:case("reports launch failure without inventing a session", function(check)
			local backend, state = fixture ""
			backend.launch = function()
				error("launch failed", 0)
			end
			check:expect(Player.run({ placeId = 123, runId = "new", backend = backend }).status):toBe "faulted"
			check:expect(state.closed):toBe(false)
		end)
		suite:case("saves requested raw log evidence before cleanup", function(check)
			local bytes = reportBytes "new"
			local backend, state = fixture(bytes)
			local directory = Files.claimDirectory "/tmp/verify-player-test"
			local path = directory .. "/host.log"
			local result = Player.run { placeId = 123, runId = "new", backend = backend, logPath = path }
			check:expect(result.status):toBe "returned"
			check:expect(fs.readFileToString(path)):toBe(bytes)
			check:expect(state.closed):toBe(true)
			fs.remove(path)
			fs.removeDirectory(directory)
		end)
		suite:case("cleanup failure cannot turn into success", function(check)
			local backend, state = fixture(reportBytes "new")
			state.cleanupFails = true
			check:expect(Player.run({ placeId = 123, runId = "new", backend = backend }).status):toBe "faulted"
		end)
	end)
end
