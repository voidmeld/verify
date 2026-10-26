--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Wire = require "../src/lute/wire"

local temporary = require "./temporary"

local Verify = require "../src/core"
local Player = require "../src/lute/player"
local Channel = require "../src/roblox/report-channel"
local fs = require "@std/fs"
local Files = require "../src/lute/files"
local Platform = require "../src/lute/platform"
local system = require "@std/system"

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
		return Wire.encode(value)
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

describe("Player launcher", function()
	it("uses the documented deep link and percent encodes launch data", function()
		local address = Player.url(123, "run&+#")
		expect(address):toContain "roblox://placeId=123&launchData="
		expect(address):toContain "run%26%2B%23"
		expect((pcall(Player.url, 0, "run"))):toBe(false)
		expect((pcall(Player.url, 1, ""))):toBe(false)
	end)
	it("forwards explicit case and entry selection", function()
		local address = Player.url(123, "run", { caseIds = { "motion" }, entry = "tests/shared" })
		expect(address):toContain "verifyCases"
		expect(address):toContain "motion"
		expect(address):toContain "verifyEntry"
		expect(address):toContain "tests%2Fshared"
		expect((pcall(Player.url, 123, "run", { caseIds = {} }))):toBe(false)
		expect((pcall(Player.url, 123, "run", { caseIds = { "x", "x" } }))):toBe(false)
	end)
	it("collects a bound report and closes its client", function()
		local backend, state = fixture(reportBytes "new")
		local outcome = Player.run { placeId = 123, runId = "new", backend = backend }
		expect(outcome.status):toBe "returned"
		if outcome.status == "returned" then
			expect(Verify.decode(outcome.report).passed):toBe(1)
		end
		expect(state.closed):toBe(true)
	end)
	it("rejects reports from another run and still closes", function()
		local backend, state = fixture(reportBytes "old")
		local outcome = Player.run { placeId = 123, runId = "new", backend = backend }
		expect(outcome.status):toBe "faulted"
		expect(state.closed):toBe(true)
	end)
	it("rejects conflicting reports instead of selecting a convenient success", function()
		local bytes = reportBytes "new"
		local backend, state = fixture(bytes .. "VERIFY_REPORT|{}\n")
		expect(Player.run({ placeId = 123, runId = "new", backend = backend }).status):toBe "faulted"
		expect(state.closed):toBe(true)
	end)
	it("times out incomplete output and closes the client", function()
		local backend, state = fixture "VERIFY_REPORT|chunk|1/2|partial\n"
		expect(Player.run({ placeId = 123, runId = "new", backend = backend, deadlineSeconds = 1 }).status):toBe "timed_out"
		expect(state.closed):toBe(true)
	end)
	it("fails if the client disappears before reporting", function()
		local backend, state = fixture ""
		state.alive = false
		expect(Player.run({ placeId = 123, runId = "new", backend = backend }).status):toBe "faulted"
		expect(state.closed):toBe(true)
	end)
	it("rejects a complete report delivered after the deadline", function()
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
		expect(Player.run({ placeId = 123, runId = "new", backend = backend, deadlineSeconds = 1 }).status):toBe "timed_out"
		expect(state.closed):toBe(true)
	end)
	it("reports launch failure without inventing a session", function()
		local backend, state = fixture ""
		backend.launch = function()
			error("launch failed", 0)
		end
		expect(Player.run({ placeId = 123, runId = "new", backend = backend }).status):toBe "faulted"
		expect(state.closed):toBe(false)
	end)
	it("saves requested raw log evidence before cleanup", function()
		local bytes = reportBytes "new"
		local backend, state = fixture(bytes)
		local directory = Files.claimDirectory(Files.temporary "verify-player-test")
		local path = directory .. "/host.log"
		local result = Player.run { placeId = 123, runId = "new", backend = backend, logPath = path }
		expect(result.status):toBe "returned"
		expect(fs.readFileToString(path)):toBe(bytes)
		expect(state.closed):toBe(true)
		fs.remove(path)
		fs.removeDirectory(directory)
	end)
	it("cleanup failure cannot turn into success", function()
		local backend, state = fixture(reportBytes "new")
		state.cleanupFails = true
		expect(Player.run({ placeId = 123, runId = "new", backend = backend }).status):toBe "faulted"
	end)

	it("refuses the reference launcher on Windows and reports the Player host unsupported", function(_, caseContext)
		local able, reason = Player.supported()
		expect(able):toBe(not system.win32)
		if not system.win32 then
			expect(reason):toBeNil()
			return
		end
		expect(reason):toContain "macOS only"
		local direct = Player.run { placeId = 123, runId = "windows" }
		expect(direct.status):toBe "faulted"
		expect(direct.detail):toContain "macOS only"
		local root = temporary(caseContext, "verify-player-windows")
		local result = Platform.run {
			host = "player",
			entry = "examples/platform-entry.luau",
			placeId = 123,
			output = root,
		}
		expect(result.report.unsupported):toBe(1)
		expect(result.report.passed):toBe(0)
		expect(result.report.results[1].missingCapabilities):toEqual { "roblox-player-launcher" }
	end)
end)

return nil
