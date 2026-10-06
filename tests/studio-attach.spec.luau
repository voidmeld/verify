--!strict

local fs = require "@std/fs"
local json = require "@std/json"
local process = require "@std/process"
local task = require "@std/task"
local crypto = require "@lute/crypto"
local Verify = require "../src/core"
local Channel = require "../src/roblox/report-channel"
local StudioEngine = require "./studio-engine"
local Detached = require "../src/lute/studio-detached"
local Files = require "../src/lute/files"
local Lute = require "../src/lute"
local Mcp = require "../src/lute/studio-mcp"
local Platform = require "../src/lute/platform"
local Wire = require "../src/lute/wire"

local PNG = "iVBORw0KGgp2ZXJpZnktZnJhbWU="

type Call = { tool: string, arguments: { [string]: unknown } }

type Fake = {
	transport: Lute.StudioTransport,
	calls: { Call },
	closes: number,
	playing: boolean,
	studios: { Lute.StudioInfo },
	hang: { [string]: boolean },
	silent: { [string]: boolean },
	failTool: { [string]: boolean },
	engine: (datamodel: string, code: string) -> string,
	sandbox: StudioEngine.Engine,
	gate: { open: boolean },
	lose: { [string]: boolean },
	requestSeconds: number?,
	calls_by_source: { string },
}

local function text(value: string): unknown
	return { content = { { type = "text", text = value } } }
end

local function passingReport(runId: string, extra: number?): string
	local harness = Verify.createHarness {
		now = function(): number
			return 0
		end,
	}
	harness:case("attached" .. string.rep("n", extra or 0), function(context)
		context:expect(1):toBe(1)
	end)
	return json.serialize((Channel.envelope(runId, harness:run { executor = "fake-engine" }) :: unknown) :: json.Value)
end

local function fake(studios: { Lute.StudioInfo }): Fake
	local gate = { open = false }
	local sandbox = StudioEngine.new { passingReport = passingReport, gate = gate }
	local self: Fake = {
		transport = {
			call = function(): Mcp.Exchange
				return { status = "unsent", detail = "not wired" }
			end,
			close = function() end,
		},
		calls = {},
		closes = 0,
		playing = false,
		studios = studios,
		hang = {},
		silent = {},
		failTool = {},
		sandbox = sandbox,
		gate = gate,
		lose = {},
		requestSeconds = nil,
		calls_by_source = {},
		engine = function(datamodel: string, code: string): string
			if string.find(code, 'local P = "VerifyRun', 1, true) ~= nil then
				local body = string.match(code, "publish%(pcall%(function%(%)\n(.-)\nend%)%)\nend%)\nreturn 'started'")
				local runId = if body ~= nil then string.match(body, 'local runId = "([^"]+)"') else nil
				if
					body ~= nil
					and runId ~= nil
					and string.find(body, "passingReport", 1, true) == nil
					and string.find(body, "gate.", 1, true) == nil
				then
					local start, finish = string.find(code, body, 1, true)
					code = string.sub(code, 1, (start :: number) - 1)
						.. 'local runId = "'
						.. runId
						.. '"; return passingReport(runId)'
						.. string.sub(code, (finish :: number) + 1)
				end
				return sandbox.run(datamodel, code)
			end
			local runId = string.match(code, 'local runId = "([^"]+)"')
			if string.find(code, "passingReport", 1, true) ~= nil then
				return sandbox.run(datamodel, code)
			end
			return if runId ~= nil then passingReport(runId) else datamodel .. ":" .. code
		end,
	}
	local released = false
	self.transport = {
		call = function(tool: string, argumentsJson: string, deadline: number): Mcp.Exchange
			released = false
			local arguments = Wire.parse(argumentsJson) :: { [string]: unknown }
			table.insert(self.calls, { tool = tool, arguments = arguments })
			if self.hang[tool] then
				while os.clock() < deadline + 5 and not released do
					task.wait(0.01)
				end
				return { status = "unanswered", detail = "released" }
			end
			if self.silent[tool] then
				return { status = "unanswered", detail = "connection lost" }
			end
			if self.failTool[tool] then
				return {
					status = "answered",
					result = { isError = true, content = { { type = "text", text = "tool failed" } } },
				}
			end
			if tool == "list_roblox_studios" then
				return {
					status = "answered",
					result = text(json.serialize(({ studios = self.studios } :: unknown) :: json.Value)),
				}
			elseif tool == "execute_luau" then
				if self.lose.execute_luau then
					return { status = "unanswered", detail = "studio_mcp_exited", lost = true }
				end
				table.insert(self.calls_by_source, arguments.code :: string)
				local began = os.clock()
				local output = self.engine(arguments.datamodel_type :: string, arguments.code :: string)
				if self.requestSeconds ~= nil and os.clock() - began > self.requestSeconds then
					return { status = "answered", detail = '{"message":"Request timeout","code":-32603}' }
				end
				return { status = "answered", result = text(output) }
			elseif tool == "start_stop_play" then
				self.playing = arguments.is_start == true
				return { status = "answered", result = text "ok" }
			elseif tool == "screen_capture" then
				return {
					status = "answered",
					result = { content = { { type = "image", mimeType = "image/png", data = PNG } } },
				}
			end
			return { status = "unsent", detail = "unknown tool" }
		end,
		close = function()
			self.closes += 1
			released = true
		end,
	}
	return self
end

local ONE: { Lute.StudioInfo } = { { id = "studio-a", name = "Alpha" } }
local TWO: { Lute.StudioInfo } = { { id = "studio-a", name = "Alpha" }, { id = "studio-b", name = "Alpha" } }

local function allow(): Lute.StudioAuthorization
	return { ok = true, reason = nil }
end

local function attached(self: Fake, patch: ((Lute.StudioAttachOptions) -> ())?): Lute.StudioSession
	local options: Lute.StudioAttachOptions = {
		authorize = allow,
		studioId = "studio-a",
		transport = self.transport,
		callSeconds = 0.3,
		runSeconds = 5,
		cleanupSeconds = 1,
	}
	if patch ~= nil then
		patch(options)
	end
	local session, refusal = Lute.studio.attach(options)
	assert(session ~= nil, refusal and refusal.detail or "attach failed")
	return session
end

local function sha256(bytes: string): string
	local value = crypto.digest(crypto.hash.sha256, bytes)
	local out: { string } = {}
	for index = 0, buffer.len(value) - 1 do
		table.insert(out, string.format("%02x", buffer.readu8(value, index)))
	end
	return table.concat(out)
end

local function segmentCalls(self: Fake): number
	local count = 0
	for _, source in self.calls_by_source do
		if string.find(source, 'P .. "p" .. I', 1, true) ~= nil then
			count += 1
		end
	end
	return count
end

local function tools(self: Fake): { string }
	local names: { string } = {}
	for _, call in self.calls do
		table.insert(names, call.tool)
	end
	return names
end

return function(suite: Verify.Harness)
	suite:suite("attach to an open Studio", function()
		suite:case("selects by id or predicate and refuses absent, ambiguous and implicit targets", function(check)
			local one = fake(ONE)
			local byId = attached(one)
			check:expect(byId.studio.id):toEqual "studio-a"
			local byMatch = Lute.studio.attach {
				authorize = allow,
				match = function(info: Lute.StudioInfo): boolean
					return info.name == "Alpha"
				end,
				transport = one.transport,
			}
			check:expect((byMatch :: Lute.StudioSession).studio.id):toEqual "studio-a"

			local absent, absentRefusal = Lute.studio.attach {
				authorize = allow,
				studioId = "missing",
				transport = one.transport,
			}
			check:expect(absent):toBeNil()
			check:expect((absentRefusal :: Lute.StudioAttachRefusal).kind):toEqual "absent"
			check:expect(#((absentRefusal :: Lute.StudioAttachRefusal).candidates :: { Lute.StudioInfo })):toEqual(1)

			local two = fake(TWO)
			local ambiguous, ambiguousRefusal = Lute.studio.attach {
				authorize = allow,
				match = function(info: Lute.StudioInfo): boolean
					return info.name == "Alpha"
				end,
				transport = two.transport,
			}
			check:expect(ambiguous):toBeNil()
			check:expect((ambiguousRefusal :: Lute.StudioAttachRefusal).kind):toEqual "ambiguous"
			check:expect(#((ambiguousRefusal :: Lute.StudioAttachRefusal).candidates :: { Lute.StudioInfo })):toEqual(2)

			local _, implicit = Lute.studio.attach { authorize = allow, transport = one.transport }
			check:expect((implicit :: Lute.StudioAttachRefusal).kind):toEqual "invalid"
			local _, unauthorized =
				Lute.studio.attach({ studioId = "studio-a", transport = one.transport } :: Lute.StudioAttachOptions)
			check:expect((unauthorized :: Lute.StudioAttachRefusal).kind):toEqual "invalid"
		end)

		suite:case(
			"sends nothing a refusing authorize hook has not approved and shows exact request bytes",
			function(check)
				local denied = fake(ONE)
				local session, refusal = Lute.studio.attach {
					authorize = function(): Lute.StudioAuthorization
						return { ok = false, reason = "not granted" }
					end,
					studioId = "studio-a",
					transport = denied.transport,
				}
				check:expect(session):toBeNil()
				check:expect((refusal :: Lute.StudioAttachRefusal).kind):toEqual "refused"
				check:expect(#denied.calls):toEqual(0)

				local seen: { Lute.StudioRequest } = {}
				local self = fake(ONE)
				local session2 = attached(self, function(options)
					options.authorize = function(request: Lute.StudioRequest): Lute.StudioAuthorization
						table.insert(seen, request)
						if request.tool == "execute_luau" then
							return { ok = false, reason = "digest not granted" }
						end
						return { ok = true, reason = nil }
					end
				end)
				local response = session2.execute("Edit", "return 1")
				check:expect(response.ok):toEqual(false)
				check:expect(response.refused):toEqual(true)
				check:expect(response.delivery):toEqual "unsent"
				check:expect(response.detail):toEqual "digest not granted"
				check:expect(tools(self)):toEqual { "list_roblox_studios" }
				local request = seen[#seen]
				check
					:expect(request.bytes)
					:toEqual '{"name":"execute_luau","arguments":{"studio_id":"studio-a","datamodel_type":"Edit","code":"return 1"}}'
				check:expect(request.digest):toEqual(sha256(request.bytes))
				check:expect(request.studioId):toEqual "studio-a"
				check:expect(request.fields.code):toEqual "return 1"

				local _, raised = Lute.studio.attach {
					authorize = function(): Lute.StudioAuthorization
						error "policy broke"
					end,
					studioId = "studio-a",
					transport = self.transport,
				}
				check:expect((raised :: Lute.StudioAttachRefusal).kind):toEqual "refused"
				check:expect((raised :: Lute.StudioAttachRefusal).detail):toContain "policy broke"
			end
		)

		suite:case("refuses a request aimed at another Studio or an unknown datamodel without sending", function(check)
			local self = fake(ONE)
			local session = attached(self)
			local before = #self.calls
			local other = session.call("execute_luau", '{"studio_id":"studio-b","datamodel_type":"Edit","code":"x"}')
			check:expect(other.delivery):toEqual "unsent"
			local unknown = session.execute("Workspace", "x")
			check:expect(unknown.delivery):toEqual "unsent"
			local malformed = session.call("execute_luau", "not json")
			check:expect(malformed.delivery):toEqual "unsent"
			check:expect(#self.calls):toEqual(before)
		end)

		suite:case("executes in Edit, Server and Client", function(check)
			local self = fake(ONE)
			local session = attached(self)
			for _, datamodel in { "Edit", "Server", "Client" } do
				local response = session.execute(datamodel, "return 7")
				check:expect(response.ok):toEqual(true)
				check:expect(response.delivery):toEqual "answered"
				check:expect(response.text):toEqual(datamodel .. ":return 7")
			end
			local seen: { string } = {}
			for _, call in self.calls do
				if call.tool == "execute_luau" then
					table.insert(seen, call.arguments.datamodel_type :: string)
				end
			end
			check:expect(seen):toEqual { "Edit", "Server", "Client" }
			self.failTool.execute_luau = true
			local failed = session.execute("Edit", "boom")
			check:expect(failed.ok):toEqual(false)
			check:expect(failed.delivery):toEqual "answered"
			check:expect(failed.detail):toEqual "tool failed"
		end)

		suite:case("starts and stops play and restores the prior mode on close without closing Studio", function(check)
			local self = fake(ONE)
			local session = attached(self)
			check:expect(session.play(true).ok):toEqual(true)
			check:expect(self.playing):toEqual(true)
			local cleanup = session.close()
			check:expect(cleanup.acknowledged):toEqual(true)
			check:expect(cleanup.restored):toEqual(true)
			check:expect(self.playing):toEqual(false)
			check:expect(self.closes):toEqual(1)
			check:expect(session.close()):toBe(cleanup)
			for _, tool in tools(self) do
				check:expect(tool == "list_roblox_studios" or tool == "start_stop_play"):toEqual(true)
			end

			local playingStudio = fake(ONE)
			playingStudio.playing = true
			local resumed = attached(playingStudio, function(options)
				options.mode = "play"
			end)
			check:expect(resumed.play(false).ok):toEqual(true)
			check:expect(resumed.close().restored):toEqual(true)
			check:expect(playingStudio.playing):toEqual(true)

			local untouched = fake(ONE)
			local idle = attached(untouched)
			check:expect(idle.close().acknowledged):toEqual(true)
			check:expect(tools(untouched)):toEqual { "list_roblox_studios" }
		end)

		suite:case("reports a cleanup the consumer refused as unacknowledged", function(check)
			local self = fake(ONE)
			local session = attached(self, function(options)
				options.authorize = function(request: Lute.StudioRequest): Lute.StudioAuthorization
					if request.tool == "start_stop_play" and request.fields.is_start == false then
						return { ok = false, reason = "stop not granted" }
					end
					return { ok = true, reason = nil }
				end
			end)
			session.play(true)
			local cleanup = session.close()
			check:expect(cleanup.acknowledged):toEqual(false)
			check:expect(cleanup.detail):toEqual "stop not granted"
			check:expect(self.closes):toEqual(1)
		end)

		suite:case("ends a call at its deadline, never retries it and still cleans up", function(check)
			local self = fake(ONE)
			local session = attached(self)
			check:expect(session.play(true).ok):toEqual(true)
			self.hang.execute_luau = true
			local began = os.clock()
			local response = session.execute("Client", "while true do end")
			check:expect(os.clock() - began < 2):toEqual(true)
			check:expect(response.ok):toEqual(false)
			check:expect(response.delivery):toEqual "possibly_sent"
			check:expect(response.expired):toEqual(true)
			check:expect(self.closes >= 1):toEqual(true)
			local executions = 0
			for _, call in self.calls do
				if call.tool == "execute_luau" then
					executions += 1
				end
			end
			check:expect(executions):toEqual(1)
			self.hang.execute_luau = false
			local cleanup = session.close()
			check:expect(cleanup.acknowledged):toEqual(true)
			check:expect(self.playing):toEqual(false)
		end)

		suite:case("distinguishes an unanswered play start and still restores the mode", function(check)
			local self = fake(ONE)
			local session = attached(self)
			self.silent.start_stop_play = true
			local response = session.play(true)
			check:expect(response.delivery):toEqual "possibly_sent"
			self.silent.start_stop_play = false
			local cleanup = session.close()
			check:expect(cleanup.acknowledged):toEqual(true)
			local plays = 0
			for _, call in self.calls do
				if call.tool == "start_stop_play" then
					plays += 1
				end
			end
			check:expect(plays):toEqual(2)
		end)

		suite:case("enforces the run deadline across calls but allows cleanup", function(check)
			local self = fake(ONE)
			local session = attached(self, function(options)
				options.runSeconds = 0.15
			end)
			check:expect(session.play(true).ok):toEqual(true)
			task.wait(0.25)
			local late = session.execute("Server", "return 1")
			check:expect(late.delivery):toEqual "unsent"
			check:expect(late.expired):toEqual(true)
			check:expect(session.close().acknowledged):toEqual(true)
			check:expect(self.playing):toEqual(false)
		end)

		suite:case("retrieves the ordinary run-bound report and rejects another run", function(check)
			local self = fake(ONE)
			local session = attached(self)
			local result = session.report("Server", 'local runId = "run-1"; return 1', "run-1")
			check:expect(result.problem):toBeNil()
			check:expect((result.report :: Verify.Report).passed):toEqual(1)
			local wrong = session.report("Server", 'local runId = "run-1"; return 1', "run-2")
			check:expect(wrong.report):toBeNil()
			check:expect(wrong.problem):toContain "identity"
			local foreign = session.report("Server", "return 'not a report'", "run-1")
			check:expect(foreign.report):toBeNil()
			check:expect(foreign.problem ~= nil):toBe(true)
		end)

		suite:case("returns a report of any size in segments and a small one in one segment", function(check)
			local self = fake(ONE)
			local session = attached(self, function(options)
				options.callSeconds = 3
			end)
			local small = session.report("Server", 'local runId = "run-1"; return passingReport(runId)', "run-1")
			check:expect(small.problem):toBeNil()
			check:expect(segmentCalls(self)):toEqual(1)
			local large =
				session.report("Server", 'local runId = "run-1"; return passingReport(runId, 250000)', "run-1")
			check:expect(large.problem):toBeNil()
			local size = #(large.response.text :: string)
			check:expect(size > 250000):toBe(true)
			check:expect(segmentCalls(self)):toEqual(1 + math.ceil(size / Detached.SEGMENT_BYTES))
			check:expect((large.report :: Verify.Report).passed):toEqual(1)
		end)

		suite:case("keeps multibyte text whole when it cuts a segment", function(check)
			local self = fake(ONE)
			local expected = "a" .. string.rep("\226\130\172", 20000)
			local outcome = Detached.run {
				execute = function(datamodel: string, code: string): Detached.Reply
					return { ok = true, text = self.sandbox.run(datamodel, code), lost = false, expired = false }
				end,
				datamodel = "Server",
				code = "return 'a' .. string.rep('\\226\\130\\172', 20000)",
				runId = "run-1",
				deadline = os.clock() + 5,
			}
			check:expect(outcome.status):toEqual "done"
			check:expect(outcome.text):toEqual(expected)
		end)

		suite:case("fails closed on a corrupted, missing, repeated or mismatched segment", function(check)
			local function failing(change: (segment: number, reply: string) -> string): string
				local self = fake(ONE)
				local base = self.engine
				self.engine = function(datamodel: string, code: string): string
					local reply = base(datamodel, code)
					local index = string.match(code, "local I = (%d+)")
					if index == nil then
						return reply
					end
					return change(tonumber(index) :: number, reply)
				end
				local session = attached(self, function(options)
					options.callSeconds = 2
				end)
				local result = session.report("Server", "return string.rep('x', 70000)", "run-1")
				check:expect(result.report):toBeNil()
				session.close()
				return result.problem or ""
			end
			check
				:expect(failing(function(index: number, reply: string): string
					return if index == 2 then reply:gsub('"payload":"x', '"payload":"y', 1) else reply
				end))
				:toContain "segment 2/3 failed its own digest check"
			check
				:expect(failing(function(index: number, reply: string): string
					return if index == 3 then reply:gsub(',?"payload":"[^"]*"', "", 1) else reply
				end))
				:toContain "segment 3 of 3 is missing or malformed"
			check
				:expect(failing(function(index: number, reply: string): string
					return if index == 2 then reply:gsub('"index":2', '"index":1', 1) else reply
				end))
				:toContain "requested segment 2 of 3 but the engine returned segment 1"
			check
				:expect(failing(function(index: number, reply: string): string
					return if index == 3 then reply:gsub('"totalDigest":"%x+', '"totalDigest":"00000000', 1) else reply
				end))
				:toContain "whole payload's digest"
		end)

		suite:case("completes a run that outlasts the request timeout of the MCP server", function(check)
			local self = fake(ONE)
			self.requestSeconds = 0.3
			local body = 'local runId = "run-1"; task.wait(0.9); return passingReport(runId)'
			local blocking = attached(self, function(options)
				options.callSeconds = 3
			end)
			local direct = blocking.execute("Server", body)
			check:expect(direct.ok):toBe(false)
			check:expect(direct.detail):toContain "Request timeout"
			local session = attached(self, function(options)
				options.callSeconds = 3
			end)
			local began = os.clock()
			local result = session.report("Server", body, "run-1")
			check:expect(result.problem):toBeNil()
			check:expect(os.clock() - began > 0.8):toBe(true)
			check:expect((result.report :: Verify.Report).passed):toEqual(1)
		end)

		suite:case("times out at the caller deadline when the engine never completes", function(check)
			local self = fake(ONE)
			check:defer(function()
				self.gate.open = true
			end)
			local body = "while not gate.open do task.wait(0.02) end return 1"
			local session = attached(self, function(options)
				options.runSeconds = 1.2
			end)
			local began = os.clock()
			local result = session.report("Server", body, "run-1")
			check:expect(result.report):toBeNil()
			check:expect(result.response.expired):toBe(true)
			check:expect(result.problem):toContain "deadline"
			check:expect(os.clock() - began < 3):toBe(true)
			local outcome = Lute.studio.run {
				code = body,
				deadlineSeconds = 1.2,
				directory = Files.claimDirectory "/tmp/verify-attach-tests-never",
				attach = { authorize = allow, studioId = "studio-a", transport = self.transport },
			}
			check:expect(outcome.status):toEqual "timed_out"
			pcall(fs.removeDirectory, "/tmp/verify-attach-tests-never", { recursive = true })
		end)

		suite:case("classifies a run that vanished or a lost session as session_lost", function(check)
			local self = fake(ONE)
			check:defer(function()
				self.gate.open = true
			end)
			local session = attached(self, function(options)
				options.runSeconds = 3
			end)
			task.delay(0.2, function()
				self.sandbox.clear "Server"
			end)
			local gone = session.report("Server", "while not gate.open do task.wait(0.02) end return 1", "run-1")
			check:expect(gone.report):toBeNil()
			check:expect(gone.response.sessionLost):toBe(true)
			check:expect(gone.problem):toContain "session_lost"
			self.lose.execute_luau = true
			local lost = attached(self).report("Server", "return 1", "run-1")
			check:expect(lost.response.sessionLost):toBe(true)
			check:expect(lost.problem):toContain "did not start"
		end)

		suite:case("captures an image to a file", function(check)
			local root = Files.claimDirectory "/tmp/verify-attach-tests"
			check:defer(function()
				fs.removeDirectory(root, { recursive = true })
			end)
			local self = fake(ONE)
			local session = attached(self)
			local response = session.capture { directory = root, stem = "view" }
			check:expect(response.ok):toEqual(true)
			local artifact = response.artifact :: { reference: string, mediaType: string }
			check:expect(artifact.mediaType):toEqual "image/png"
			check:expect(fs.readFileToString(artifact.reference):sub(1, 8)):toEqual "\137PNG\r\n\26\n"
		end)
	end)

	suite:suite("one authored case, launched or attached", function()
		suite:case("platform.run in studio host attaches, starts play, reports and stops", {
			timeoutSeconds = 20,
			run = function(check: Verify.Context)
				local root = Files.claimDirectory "/tmp/verify-attach-tests"
				check:defer(function()
					fs.removeDirectory(root, { recursive = true })
				end)
				local self = fake(ONE)
				local result = Platform.run {
					host = "studio",
					entry = "examples/platform-entry.luau",
					output = root,
					deadlineSeconds = 5,
					context = "Client",
					finalCapture = true,
					attach = {
						authorize = allow,
						studioId = "studio-a",
						transport = self.transport,
					},
				}
				check:expect(result.report.passed):toEqual(1)
				check:expect(result.report.results[1].artifacts[1].mediaType):toEqual "image/png"
				check:expect(tools(self)):toEqual {
					"list_roblox_studios",
					"start_stop_play",
					"execute_luau",
					"execute_luau",
					"execute_luau",
					"execute_luau",
					"screen_capture",
					"start_stop_play",
				}
				check:expect(self.calls[3].arguments.datamodel_type):toEqual "Client"
				check:expect(self.playing):toEqual(false)
			end,
		})

		suite:case("a hung attached run times out and still stops play", {
			timeoutSeconds = 20,
			run = function(check: Verify.Context)
				local root = Files.claimDirectory "/tmp/verify-attach-tests"
				check:defer(function()
					fs.removeDirectory(root, { recursive = true })
				end)
				local self = fake(ONE)
				self.hang.execute_luau = true
				local outcome = Lute.studio.run {
					code = "return 1",
					deadlineSeconds = 0.4,
					directory = root,
					attach = { authorize = allow, studioId = "studio-a", transport = self.transport, callSeconds = 0.2 },
				}
				check:expect(outcome.status):toEqual "timed_out"
				check:expect(self.playing):toEqual(false)
				check:expect(tools(self)[#tools(self)]):toEqual "start_stop_play"
			end,
		})

		suite:case(
			"an attached run fails when the consumer refuses or the Studio is absent or multiplayer is requested",
			function(check)
				local self = fake(ONE)
				local refused = Lute.studio.run {
					code = "return 1",
					directory = "/tmp/verify-attach-tests-refused",
					attach = {
						authorize = function(): Lute.StudioAuthorization
							return { ok = false, reason = "no grant" }
						end,
						studioId = "studio-a",
						transport = self.transport,
					},
				}
				check:expect(refused.status):toEqual "faulted"
				check:expect(refused.detail):toContain "no grant"
				check:expect(#self.calls):toEqual(0)
				local players = Lute.studio.run {
					code = "return 1",
					players = 2,
					attach = { authorize = allow, studioId = "studio-a", transport = self.transport },
				}
				check:expect(players.status):toEqual "faulted"
				local absent = Lute.studio.run {
					code = "return 1",
					directory = "/tmp/verify-attach-tests-refused",
					attach = { authorize = allow, studioId = "gone", transport = self.transport },
				}
				check:expect(absent.detail):toContain "absent"
				pcall(fs.removeDirectory, "/tmp/verify-attach-tests-refused", { recursive = true })
			end
		)

		suite:case("the Studio host attaches per batch with the same code builder", function(check)
			local root = Files.claimDirectory "/tmp/verify-attach-tests"
			check:defer(function()
				fs.removeDirectory(root, { recursive = true })
			end)
			local self = fake(ONE)
			local host = Lute.studio.host {
				attach = { authorize = allow, studioId = "studio-a", transport = self.transport },
				capabilities = { "studio" },
				directory = root,
				codeForBatch = function(): string
					return "return 1"
				end,
			}
			local outcome = host.runBatch { id = "b", index = 1, units = {}, deadlineSeconds = 5 }
			check:expect(outcome.status):toEqual "returned"
		end)
	end)

	suite:suite("a Studio MCP child that exits", function()
		local SCRIPT = table.concat({
			"#!/bin/sh",
			'[ -e "$(dirname "$0")/broken" ] && exit 0',
			"while IFS= read -r line; do",
			"  id=$(printf '%s' \"$line\" | sed -n 's/.*\"id\":\\([0-9]*\\).*/\\1/p')",
			'  [ -n "$id" ] || continue',
			"  case $line in *die_now*) exit 0 ;; esac",
			"  case $line in",
			'    *list_roblox_studios*) printf \'{"jsonrpc":"2.0","id":%s,"result":{"content":[{"type":"text","text":"[{\\\\"id\\\\":\\\\"studio-a\\\\",\\\\"name\\\\":\\\\"A\\\\"}]"}]}}\\n\' "$id" ;;',
			'    *) printf \'{"jsonrpc":"2.0","id":%s,"result":{"content":[{"type":"text","text":"ok"}]}}\\n\' "$id" ;;',
			"  esac",
			"done",
		}, "\n")

		local ARGS = '{"studio_id":"studio-a"}'

		local function child(check: Verify.Context): (string, string)
			local root = Files.claimDirectory "/tmp/verify-mcp-exit-tests"
			check:defer(function()
				fs.removeDirectory(root, { recursive = true })
			end)
			local script = root .. "/child.sh"
			fs.writeStringToFile(script, SCRIPT .. "\n")
			process.run { "chmod", "755", script }
			return script, root
		end

		suite:case("returns unsent at once for a pipe with no reader and never hangs", function(check)
			local script, root = child(check)
			local connection = Mcp.connect(script, root .. "/direct", os.clock() + 5)
			check:expect(connection.callRaw("echo", "{}", os.clock() + 5).status):toBe "answered"
			local began = os.clock()
			local dying = connection.callRaw("die_now", "{}", os.clock() + 5)
			check:expect(dying.status):toBe "unanswered"
			check:expect(dying.lost):toBe(true)
			check:expect(os.clock() - began < 4):toBe(true)
			local after = os.clock()
			local unsent = connection.callRaw("echo", "{}", os.clock() + 5)
			check:expect(unsent.status):toBe "unsent"
			check:expect(unsent.detail):toBe(Mcp.EXITED)
			check:expect(os.clock() - after < 2):toBe(true)
			connection.close()
		end)

		suite:case("reopens the session once and retries after the child exited", function(check)
			local script, root = child(check)
			local session = attached(fake(ONE), function(options)
				options.transport = nil
				options.mcpExecutable = script
				options.directory = root .. "/attach"
				options.callSeconds = 6
			end)
			check:expect(session.call("echo", ARGS).ok):toBe(true)
			local lost = session.call("die_now", ARGS)
			check:expect(lost.ok):toBe(false)
			check:expect(lost.sessionLost):toBe(true)
			check:expect(lost.expired):toBe(false)
			local began = os.clock()
			local again = session.call("echo", ARGS)
			check:expect(again.ok):toBe(true)
			check:expect(os.clock() - began < 5):toBe(true)
			session.close()
		end)

		suite:case("classifies a session that cannot be reopened as session_lost, not a deadline", function(check)
			local script, root = child(check)
			local session = attached(fake(ONE), function(options)
				options.transport = nil
				options.mcpExecutable = script
				options.directory = root .. "/lost"
				options.callSeconds = 6
			end)
			check:expect(session.call("echo", ARGS).ok):toBe(true)
			session.call("die_now", ARGS)
			fs.writeStringToFile(root .. "/broken", "")
			local began = os.clock()
			local response = session.call("echo", ARGS)
			check:expect(response.ok):toBe(false)
			check:expect(response.sessionLost):toBe(true)
			check:expect(response.expired):toBe(false)
			check:expect(response.delivery):toBe "unsent"
			check:expect(response.detail):toContain "session_lost"
			check:expect(os.clock() - began < 6):toBe(true)
			session.close()
		end)
	end)
end
