--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local function asString(value: unknown): string
	assert(type(value) == "string")
	return value
end

local temporary = require "./temporary"

local fs = require "@std/fs"
local json = require "@std/json"
local process = require "@std/process"
local system = require "@std/system"
local task = require "@std/task"
local crypto = require "@lute/crypto"
local Verify = require "../src/core"
local Channel = require "../src/roblox/report-channel"
local StudioEngine = require "./studio-engine"
local Detached = require "../src/lute/studio-detached"
local Files = require "../src/lute/files"
local Lute = require "../src/lute"
local Mcp = require "../src/lute/studio-mcp"
local ProgressFile = require "../src/lute/progress-file"
local Reply = require "../src/lute/studio-reply"
local Platform = require "../src/lute/platform"
local Roblox = require "../src/roblox"
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
	console: ((runId: string, token: string) -> string)?,
	consoleLimit: number?,
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
	return Wire.encode(Channel.envelope(runId, harness:run { executor = "fake-engine" }))
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
		calls_by_source = {},
		engine = function(datamodel: string, code: string): string
			if string.find(code, 'local P = "VerifyRun', 1, true) ~= nil then
				local body = string.match(code, "publish%(pcall%(function%(%)\n(.-)\nend%)%)")
				local runId = if body ~= nil then string.match(body, 'local runId = "([^"]+)"') else nil
				if
					body ~= nil
					and runId ~= nil
					and string.find(body, "passingReport", 1, true) == nil
					and string.find(body, "gate.", 1, true) == nil
				then
					local start, finish = string.find(code, body, 1, true)
					code = string.sub(code, 1, (assert(start)) - 1)
						.. 'local runId = "'
						.. runId
						.. '"; return passingReport(runId)'
						.. string.sub(code, (assert(finish)) + 1)
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
					result = text(json.serialize(assert { studios = self.studios })),
				}
			elseif tool == "execute_luau" then
				if self.lose.execute_luau then
					return { status = "unanswered", detail = "studio_mcp_exited", lost = true }
				end
				if
					arguments.code == Roblox.progressChannel.read
					or (
						type(arguments.code) == "string"
						and string.find(arguments.code, "local PROGRESS_TOKEN = ", 1, true)
					)
				then
					local make = self.console
					local runId: string?
					local token: string?
					for index = #self.calls_by_source, 1, -1 do
						local source = self.calls_by_source[index]
						local foundToken = string.match(source, 'local progressToken = "([^"]+)"')
						local foundRun = string.match(source, 'local runId = "([^"]+)"')
						if foundToken ~= nil and foundRun ~= nil then
							token, runId = foundToken, foundRun
							break
						end
					end
					if make == nil or runId == nil or token == nil then
						return { status = "answered", result = text "[]" }
					end
					local rows = Wire.parse(make(runId, token))
					local native = StudioEngine.new {
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
											return Wire.encode(value)
										end,
									}
							end,
						},
					}
					local output = native.run("Client", asString(arguments.code))
					return { status = "answered", result = text(string.sub(output, 1, self.consoleLimit or #output)) }
				end
				table.insert(self.calls_by_source, asString(arguments.code))
				local began = os.clock()
				local output = self.engine(asString(arguments.datamodel_type), asString(arguments.code))
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
		if string.find(source, "local I = ", 1, true) ~= nil then
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

describe("attach to an open Studio", function()
	it("selects by id or predicate and refuses absent, ambiguous and implicit targets", function()
		local one = fake(ONE)
		local byId = attached(one)
		expect(byId.studio.id):toEqual "studio-a"
		local byMatch = Lute.studio.attach {
			authorize = allow,
			match = function(info: Lute.StudioInfo): boolean
				return info.name == "Alpha"
			end,
			transport = one.transport,
		}
		expect((assert(byMatch)).studio.id):toEqual "studio-a"

		local absent, absentRefusal = Lute.studio.attach {
			authorize = allow,
			studioId = "missing",
			transport = one.transport,
		}
		expect(absent):toBeNil()
		expect((assert(absentRefusal)).kind):toEqual "absent"
		expect(#((assert(absentRefusal)).candidates :: { Lute.StudioInfo })):toEqual(1)

		local two = fake(TWO)
		local ambiguous, ambiguousRefusal = Lute.studio.attach {
			authorize = allow,
			match = function(info: Lute.StudioInfo): boolean
				return info.name == "Alpha"
			end,
			transport = two.transport,
		}
		expect(ambiguous):toBeNil()
		expect((assert(ambiguousRefusal)).kind):toEqual "ambiguous"
		expect(#((assert(ambiguousRefusal)).candidates :: { Lute.StudioInfo })):toEqual(2)

		local _, implicit = Lute.studio.attach { authorize = allow, transport = one.transport }
		expect((assert(implicit)).kind):toEqual "invalid"
		local _, unauthorized =
			Lute.studio.attach({ studioId = "studio-a", transport = one.transport } :: Lute.StudioAttachOptions)
		expect((assert(unauthorized)).kind):toEqual "invalid"
	end)

	it("sends nothing a refusing authorize hook has not approved and shows exact request bytes", function()
		local denied = fake(ONE)
		local session, refusal = Lute.studio.attach {
			authorize = function(): Lute.StudioAuthorization
				return { ok = false, reason = "not granted" }
			end,
			studioId = "studio-a",
			transport = denied.transport,
		}
		expect(session):toBeNil()
		expect((assert(refusal)).kind):toEqual "refused"
		expect(#denied.calls):toEqual(0)

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
		expect(response.ok):toEqual(false)
		expect(response.refused):toEqual(true)
		expect(response.delivery):toEqual "unsent"
		expect(response.detail):toEqual "digest not granted"
		expect(tools(self)):toEqual { "list_roblox_studios" }
		local request = seen[#seen]
		expect(request.bytes):toEqual '{"name":"execute_luau","arguments":{"studio_id":"studio-a","datamodel_type":"Edit","code":"return 1"}}'
		expect(request.digest):toEqual(sha256(request.bytes))
		expect(request.studioId):toEqual "studio-a"
		expect(request.fields.code):toEqual "return 1"

		local _, raised = Lute.studio.attach {
			authorize = function(): Lute.StudioAuthorization
				error "policy broke"
			end,
			studioId = "studio-a",
			transport = self.transport,
		}
		expect((assert(raised)).kind):toEqual "refused"
		expect((assert(raised)).detail):toContain "policy broke"
	end)

	it("refuses a request aimed at another Studio or an unknown datamodel without sending", function()
		local self = fake(ONE)
		local session = attached(self)
		local before = #self.calls
		local other = session.call("execute_luau", '{"studio_id":"studio-b","datamodel_type":"Edit","code":"x"}')
		expect(other.delivery):toEqual "unsent"
		local unknown = session.execute("Workspace", "x")
		expect(unknown.delivery):toEqual "unsent"
		local malformed = session.call("execute_luau", "not json")
		expect(malformed.delivery):toEqual "unsent"
		expect(#self.calls):toEqual(before)
	end)

	it("executes in Edit, Server and Client", function()
		local self = fake(ONE)
		local session = attached(self)
		for _, datamodel in { "Edit", "Server", "Client" } do
			local response = session.execute(datamodel, "return 7")
			expect(response.ok):toEqual(true)
			expect(response.delivery):toEqual "answered"
			expect(response.text):toEqual(datamodel .. ":return 7")
		end
		local seen: { string } = {}
		for _, call in self.calls do
			if call.tool == "execute_luau" then
				table.insert(seen, asString(call.arguments.datamodel_type))
			end
		end
		expect(seen):toEqual { "Edit", "Server", "Client" }
		self.failTool.execute_luau = true
		local failed = session.execute("Edit", "boom")
		expect(failed.ok):toEqual(false)
		expect(failed.delivery):toEqual "answered"
		expect(failed.detail):toEqual "tool failed"
	end)

	it("starts and stops play and restores the prior mode on close without closing Studio", function()
		local self = fake(ONE)
		local session = attached(self)
		expect(session.play(true).ok):toEqual(true)
		expect(self.playing):toEqual(true)
		local cleanup = session.close()
		expect(cleanup.acknowledged):toEqual(true)
		expect(cleanup.restored):toEqual(true)
		expect(self.playing):toEqual(false)
		expect(self.closes):toEqual(1)
		expect(session.close()):toBe(cleanup)
		for _, tool in tools(self) do
			expect(tool == "list_roblox_studios" or tool == "start_stop_play"):toEqual(true)
		end

		local playingStudio = fake(ONE)
		playingStudio.playing = true
		local resumed = attached(playingStudio, function(options)
			options.mode = "play"
		end)
		expect(resumed.play(false).ok):toEqual(true)
		expect(resumed.close().restored):toEqual(true)
		expect(playingStudio.playing):toEqual(true)

		local untouched = fake(ONE)
		local idle = attached(untouched)
		expect(idle.close().acknowledged):toEqual(true)
		expect(tools(untouched)):toEqual { "list_roblox_studios" }
	end)

	it("reports a cleanup the consumer refused as unacknowledged", function()
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
		expect(cleanup.acknowledged):toEqual(false)
		expect(cleanup.detail):toEqual "stop not granted"
		expect(self.closes):toEqual(1)
	end)

	it("ends a call at its deadline, never retries it and still cleans up", function()
		local self = fake(ONE)
		local session = attached(self)
		expect(session.play(true).ok):toEqual(true)
		self.hang.execute_luau = true
		local began = os.clock()
		local response = session.execute("Client", "while true do end")
		expect(os.clock() - began < 2):toEqual(true)
		expect(response.ok):toEqual(false)
		expect(response.delivery):toEqual "possibly_sent"
		expect(response.expired):toEqual(true)
		expect(self.closes >= 1):toEqual(true)
		local executions = 0
		for _, call in self.calls do
			if call.tool == "execute_luau" then
				executions += 1
			end
		end
		expect(executions):toEqual(1)
		self.hang.execute_luau = false
		local cleanup = session.close()
		expect(cleanup.acknowledged):toEqual(true)
		expect(self.playing):toEqual(false)
	end)

	it("distinguishes an unanswered play start and still restores the mode", function()
		local self = fake(ONE)
		local session = attached(self)
		self.silent.start_stop_play = true
		local response = session.play(true)
		expect(response.delivery):toEqual "possibly_sent"
		self.silent.start_stop_play = false
		local cleanup = session.close()
		expect(cleanup.acknowledged):toEqual(true)
		local plays = 0
		for _, call in self.calls do
			if call.tool == "start_stop_play" then
				plays += 1
			end
		end
		expect(plays):toEqual(2)
	end)

	it("enforces the run deadline across calls but allows cleanup", function()
		local self = fake(ONE)
		local session = attached(self, function(options)
			options.runSeconds = 0.15
		end)
		expect(session.play(true).ok):toEqual(true)
		task.wait(0.25)
		local late = session.execute("Server", "return 1")
		expect(late.delivery):toEqual "unsent"
		expect(late.expired):toEqual(true)
		expect(session.close().acknowledged):toEqual(true)
		expect(self.playing):toEqual(false)
	end)

	it("retrieves the ordinary run-bound report and rejects another run", function()
		local self = fake(ONE)
		local session = attached(self)
		local result = session.report("Server", 'local runId = "run-1"; return 1', "run-1")
		expect(result.problem):toBeNil()
		expect((assert(result.report)).passed):toEqual(1)
		local wrong = session.report("Server", 'local runId = "run-1"; return 1', "run-2")
		expect(wrong.report):toBeNil()
		expect(wrong.problem):toContain "identity"
		local foreign = session.report("Server", "return 'not a report'", "run-1")
		expect(foreign.report):toBeNil()
		expect(foreign.problem ~= nil):toBe(true)
	end)

	it("returns a report of any size in segments and a small one in one segment", function()
		local self = fake(ONE)
		local session = attached(self, function(options)
			options.callSeconds = 3
		end)
		local small = session.report("Server", 'local runId = "run-1"; return passingReport(runId)', "run-1")
		expect(small.problem):toBeNil()
		expect(segmentCalls(self)):toEqual(1)
		local large = session.report("Server", 'local runId = "run-1"; return passingReport(runId, 250000)', "run-1")
		expect(large.problem):toBeNil()
		local size = #(assert(large.response.text))
		expect(size > 250000):toBe(true)
		expect(segmentCalls(self)):toEqual(1 + math.ceil(size / Detached.SEGMENT_BYTES))
		expect((assert(large.report)).passed):toEqual(1)
	end)

	it("terminates execution and publication failures with intact errors and owned cleanup", function()
		for _, failure in
			{
				{
					code = 'error(string.rep("execution failure", 20))',
					needle = string.rep("execution failure", 20),
				},
				{
					code = 'local occupied = Instance.new("Folder") occupied.Name = "p1" occupied.Parent = RS:FindFirstChild(P) return "report"',
					needle = "Value",
				},
			}
		do
			local runs = 0
			local engine = StudioEngine.new {
				run = function()
					runs += 1
				end,
			}
			local outcome = Detached.run {
				execute = function(datamodel, code): Detached.Reply
					return { ok = true, text = engine.run(datamodel, code), lost = false, expired = false }
				end,
				datamodel = "Server",
				code = "run() " .. failure.code,
				runId = "failed-publication",
				deadline = os.clock() + 3,
			}
			expect(outcome.status):toBe "failed"
			expect(outcome.detail):toContain(failure.needle)
			expect(runs):toBe(1)
			expect(engine.run("Server", 'return #game:GetService("ReplicatedStorage"):GetChildren()')):toBe "0"
		end
	end)

	it("keeps multibyte text whole when it cuts a segment", function()
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
		expect(outcome.status):toEqual "done"
		expect(outcome.text):toEqual(expected)
	end)

	it("fails closed on a corrupted, missing, repeated or mismatched segment", function()
		local function failing(change: (segment: number, reply: string) -> string): string
			local self = fake(ONE)
			local base = self.engine
			self.engine = function(datamodel: string, code: string): string
				local reply = base(datamodel, code)
				local index = string.match(code, "local I = (%d+)")
				if index == nil then
					return reply
				end
				return change(assert(tonumber(index)), reply)
			end
			local session = attached(self, function(options)
				options.callSeconds = 2
			end)
			local result = session.report("Server", "return string.rep('x', 70000)", "run-1")
			expect(result.report):toBeNil()
			session.close()
			return result.problem or ""
		end
		expect(failing(function(index: number, reply: string): string
			return if index == 2 then reply:gsub('"payload":"x', '"payload":"y', 1) else reply
		end)):toContain "segment 2/3 failed its own digest check"
		expect(failing(function(index: number, reply: string): string
			return if index == 3 then reply:gsub(',?"payload":"[^"]*"', "", 1) else reply
		end)):toContain "segment 3 of 3 is missing or malformed"
		expect(failing(function(index: number, reply: string): string
			return if index == 2 then reply:gsub('"index":2', '"index":1', 1) else reply
		end)):toContain "requested segment 2 of 3 but the engine returned segment 1"
		expect(failing(function(index: number, reply: string): string
			return if index == 3 then reply:gsub('"totalDigest":"%x+', '"totalDigest":"00000000', 1) else reply
		end)):toContain "whole payload's digest"
	end)

	it("completes a run that outlasts the request timeout of the MCP server", function()
		local self = fake(ONE)
		self.requestSeconds = 0.3
		local body = 'local runId = "run-1"; task.wait(0.9); return passingReport(runId)'
		local blocking = attached(self, function(options)
			options.callSeconds = 3
		end)
		local direct = blocking.execute("Server", body)
		expect(direct.ok):toBe(false)
		expect(direct.detail):toContain "Request timeout"
		local session = attached(self, function(options)
			options.callSeconds = 3
		end)
		local began = os.clock()
		local result = session.report("Server", body, "run-1")
		expect(result.problem):toBeNil()
		expect(os.clock() - began > 0.8):toBe(true)
		expect((assert(result.report)).passed):toEqual(1)
	end)

	it("times out at the caller deadline when the engine never completes", function(own)
		local self = fake(ONE)
		own(function()
			self.gate.open = true
		end)
		local body = "while not gate.open do task.wait(0.02) end return 1"
		local session = attached(self, function(options)
			options.runSeconds = 1.2
		end)
		local began = os.clock()
		local result = session.report("Server", body, "run-1")
		expect(result.report):toBeNil()
		expect(result.response.expired):toBe(true)
		expect(result.problem):toContain "deadline"
		expect(os.clock() - began < 3):toBe(true)
		local outcome = Lute.studio.run {
			code = body,
			deadlineSeconds = 1.2,
			directory = Files.claimDirectory(Files.temporary "verify-attach-tests-never"),
			attach = { authorize = allow, studioId = "studio-a", transport = self.transport },
		}
		expect(outcome.status):toEqual "timed_out"
		pcall(fs.removeDirectory, Files.temporary "verify-attach-tests-never", { recursive = true })
	end)

	it("classifies a run that vanished or a lost session as session_lost", function(own)
		local self = fake(ONE)
		own(function()
			self.gate.open = true
		end)
		local session = attached(self, function(options)
			options.runSeconds = 3
		end)
		task.delay(0.2, function()
			self.sandbox.clear "Server"
		end)
		local gone = session.report("Server", "while not gate.open do task.wait(0.02) end return 1", "run-1")
		expect(gone.report):toBeNil()
		expect(gone.response.sessionLost):toBe(true)
		expect(gone.problem):toContain "session_lost"
		self.lose.execute_luau = true
		local lost = attached(self).report("Server", "return 1", "run-1")
		expect(lost.response.sessionLost):toBe(true)
		expect(lost.problem):toContain "did not start"
	end)

	it("captures an image to a file", function(_, caseContext)
		local root = temporary(caseContext, "verify-attach-tests")
		local self = fake(ONE)
		local session = attached(self)
		local response = session.capture { directory = root, stem = "view" }
		expect(response.ok):toEqual(true)
		local artifact = assert(response.artifact)
		expect(artifact.mediaType):toEqual "image/png"
		expect(fs.readFileToString(artifact.reference):sub(1, 8)):toEqual "\137PNG\r\n\26\n"
	end)

	it("decodes capture data in Luau for every padding length and refuses malformed data", function()
		expect(Reply.decodeBase64 "TWFu"):toEqual "Man"
		expect(Reply.decodeBase64 "TWE="):toEqual "Ma"
		expect(Reply.decodeBase64 "TQ=="):toEqual "M"
		expect(Reply.decodeBase64 "iVBO\nRw0K\r\nGgo="):toEqual "\137PNG\r\n\26\n"
		expect(Reply.decodeBase64 ""):toEqual ""
		expect((pcall(Reply.decodeBase64, "TWF"))):toEqual(false)
		expect((pcall(Reply.decodeBase64, "T*Fu"))):toEqual(false)
		expect((pcall(Reply.decodeBase64, "T=Fu"))):toEqual(false)
	end)
end)

describe("one authored case, launched or attached", function()
	it("platform.run in studio host attaches, starts play, reports and stops", {
		timeoutSeconds = 20,
		run = function(_, caseContext)
			local root = temporary(caseContext, "verify-attach-tests")
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
			expect(result.report.passed):toEqual(1)
			expect(result.report.results[1].artifacts[1].mediaType):toEqual "image/png"
			expect(tools(self)):toEqual {
				"list_roblox_studios",
				"start_stop_play",
				"execute_luau",
				"execute_luau",
				"execute_luau",
				"execute_luau",
				"execute_luau",
				"execute_luau",
				"screen_capture",
				"start_stop_play",
			}
			expect(self.calls[3].arguments.datamodel_type):toEqual "Server"
			expect(self.calls[4].arguments.datamodel_type):toEqual "Client"
			expect(self.playing):toEqual(false)
		end,
	})

	it("a hung attached run times out and still stops play", {
		timeoutSeconds = 20,
		run = function(_, caseContext)
			local root = temporary(caseContext, "verify-attach-tests")
			local self = fake(ONE)
			self.hang.execute_luau = true
			local outcome = Lute.studio.run {
				code = "return 1",
				deadlineSeconds = 0.4,
				directory = root,
				attach = { authorize = allow, studioId = "studio-a", transport = self.transport, callSeconds = 0.2 },
			}
			expect(outcome.status):toEqual "timed_out"
			expect(self.playing):toEqual(false)
			expect(tools(self)[#tools(self)]):toEqual "start_stop_play"
		end,
	})

	it("an attached run fails when the consumer refuses or the Studio is absent or multiplayer is requested", function()
		local self = fake(ONE)
		local refused = Lute.studio.run {
			code = "return 1",
			directory = Files.temporary "verify-attach-tests-refused",
			attach = {
				authorize = function(): Lute.StudioAuthorization
					return { ok = false, reason = "no grant" }
				end,
				studioId = "studio-a",
				transport = self.transport,
			},
		}
		expect(refused.status):toEqual "faulted"
		expect(refused.detail):toContain "no grant"
		expect(#self.calls):toEqual(0)
		local players = Lute.studio.run {
			code = "return 1",
			players = 2,
			attach = { authorize = allow, studioId = "studio-a", transport = self.transport },
		}
		expect(players.status):toEqual "faulted"
		local absent = Lute.studio.run {
			code = "return 1",
			directory = Files.temporary "verify-attach-tests-refused",
			attach = { authorize = allow, studioId = "gone", transport = self.transport },
		}
		expect(absent.detail):toContain "absent"
		pcall(fs.removeDirectory, Files.temporary "verify-attach-tests-refused", { recursive = true })
	end)

	it("the Studio host attaches per batch with the same code builder", function(_, caseContext)
		local root = temporary(caseContext, "verify-attach-tests")
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
		expect(outcome.status):toEqual "returned"
	end)
end)

describe("a Studio MCP child that exits", function()
	local SCRIPT = table.concat({
		"#!/bin/sh",
		'[ -e "$(dirname "$0")/broken" ] && exit 0',
		"while IFS= read -r line; do",
		"  id=$(printf '%s' \"$line\" | sed -n 's/.*\"id\":\\([0-9]*\\).*/\\1/p')",
		'  [ -n "$id" ] || continue',
		"  case $line in *die_now*) exit 0 ;; esac",
		"  case $line in *hold_reply*) continue ;; esac",
		"  case $line in",
		'    *list_roblox_studios*) printf \'{"jsonrpc":"2.0","id":%s,"result":{"content":[{"type":"text","text":"[{\\\\"id\\\\":\\\\"studio-a\\\\",\\\\"name\\\\":\\\\"A\\\\"}]"}]}}\\n\' "$id" ;;',
		'    *) printf \'{"jsonrpc":"2.0","id":%s,"result":{"content":[{"type":"text","text":"ok"}]}}\\n\' "$id" ;;',
		"  esac",
		"done",
	}, "\n")

	local ARGS = '{"studio_id":"studio-a"}'

	local function child(caseContext: Verify.Context): (string, string)
		local root = temporary(caseContext, "verify-mcp-exit-tests")
		if system.win32 then
			local program = Files.absolute "tests/programs/fake-mcp.luau"
			local launcher = root .. "/child.cmd"
			fs.writeStringToFile(
				launcher,
				('@"%s" run "%s" "%s"\r\n'):format(tostring(process.execPath()), program, root)
			)
			return launcher, root
		end
		local script = root .. "/child.sh"
		fs.writeStringToFile(script, SCRIPT .. "\n")
		process.run { "chmod", "755", script }
		return script, root
	end

	it("reopens a pipe with no reader without repeating its uncertain call", function(_, caseContext)
		local script, root = child(caseContext)
		local connection = Mcp.connect(script, root .. "/direct", os.clock() + 5)
		expect(connection.callRaw("echo", "{}", os.clock() + 5).status):toBe "answered"
		local began = os.clock()
		local dying = connection.callRaw("die_now", "{}", os.clock() + 5)
		expect(dying.status):toBe "unanswered"
		expect(dying.lost):toBe(true)
		expect(os.clock() - began < 4):toBe(true)
		local after = os.clock()
		local resumed = connection.callRaw("echo", "{}", os.clock() + 5)
		expect(resumed.status):toBe "answered"
		expect(os.clock() - after < 5):toBe(true)
		connection.close()
	end)

	it("reopens the session once and retries after the child exited", function(_, caseContext)
		local script, root = child(caseContext)
		local session = attached(fake(ONE), function(options)
			options.transport = nil
			options.mcpExecutable = script
			options.directory = root .. "/attach"
			options.callSeconds = 6
			options.runSeconds = 20
		end)
		expect(session.call("echo", ARGS).ok):toBe(true)
		local lost = session.call("die_now", ARGS)
		expect(lost.ok):toBe(false)
		expect(lost.sessionLost):toBe(true)
		expect(lost.expired):toBe(false)
		local began = os.clock()
		local again = session.call("echo", ARGS)
		expect(again.ok):toBe(true)
		expect(os.clock() - began < 5):toBe(true)
		session.close()
	end)

	it("reopens the session for the next call after a call passes its deadline", function(_, caseContext)
		local script, root = child(caseContext)
		local session = attached(fake(ONE), function(options)
			options.transport = nil
			options.mcpExecutable = script
			options.directory = root .. "/slow"
			options.callSeconds = 3
			options.runSeconds = 30
		end)
		expect(session.call("echo", ARGS).ok):toBe(true)
		local held = session.call("hold_reply", ARGS)
		expect(held.ok):toBe(false)
		expect(held.delivery):toBe "possibly_sent"
		expect(held.expired):toBe(true)
		local again = session.call("echo", ARGS)
		expect(again.ok == true):toBeTrueWith(again.detail or "no detail")
		expect(fs.exists(root .. "/slow/reconnect-2/pid")):toBe(true)
		session.close()
	end)

	it("classifies a session that cannot be reopened as session_lost, not a deadline", function(_, caseContext)
		local script, root = child(caseContext)
		local session = attached(fake(ONE), function(options)
			options.transport = nil
			options.mcpExecutable = script
			options.directory = root .. "/lost"
			options.callSeconds = 6
			options.runSeconds = 20
		end)
		expect(session.call("echo", ARGS).ok):toBe(true)
		session.call("die_now", ARGS)
		fs.writeStringToFile(root .. "/broken", "")
		local began = os.clock()
		local response = session.call("echo", ARGS)
		expect(response.ok):toBe(false)
		expect(response.sessionLost == true):toBeTrueWith(response.detail or "no detail")
		expect(response.expired):toBe(false)
		expect(response.delivery):toBe "unsent"
		expect(response.detail):toContain "session_lost"
		expect(os.clock() - began < 6):toBe(true)
		session.close()
	end)
	it("polls Logger history for structured progress during an attached run and writes it in order", function()
		local self = fake(ONE)
		self.console = function(runId: string, token: string): string
			local lines: { unknown } = {}
			local publisher = Roblox.progressChannel.publisher(runId, token, function(message, context)
				table.insert(
					lines,
					{ message = message, loggerFullPath = Roblox.progressChannel.LOGGER, context = context }
				)
			end)
			publisher.publish("case-1", "server", "first", "started", nil)
			publisher.publish("case-1", "server", "first", "finished", "passed")
			return Wire.encode(lines)
		end
		local directory = Files.claimDirectory(Files.temporary "verify-attach-progress-a")
		local file = directory .. "/progress.jsonl"
		local seen: { string } = {}
		local runIdSeen = ""
		local frames = assert(self.console)
		self.console = function(runId: string, token: string): string
			runIdSeen = runId
			return frames(runId, token)
		end
		local outcome = Lute.studio.run {
			code = "return 1",
			directory = directory,
			progressFile = file,
			attach = {
				authorize = function(request): Lute.StudioAuthorization
					table.insert(seen, request.tool)
					return allow()
				end,
				studioId = "studio-a",
				transport = self.transport,
			},
		}
		expect(outcome.status):toEqual "returned"
		expect(table.find(seen, "get_console_output")):toBeNil()
		local first = table.find(seen, "execute_luau")
		local read = false
		for _, call in self.calls do
			read = read or string.find(tostring(call.arguments.code), "local PROGRESS_TOKEN = ", 1, true) ~= nil
		end
		expect(first ~= nil and read):toBe(true)
		local events = ProgressFile.read(file, runIdSeen)
		expect(#events):toBe(2)
		expect(events[1].sequence):toBe(1)
		expect(events[2].sequence):toBe(2)
		expect(fs.exists(file .. ".diagnostics")):toBe(false)
		local injected = false
		for _, source in self.calls_by_source do
			injected = injected or string.find(source, "local progressToken = ", 1, true) ~= nil
		end
		expect(injected):toBe(true)
		pcall(fs.removeDirectory, directory, { recursive = true })
	end)

	it("drains long progress histories below the Studio output limit without losing events", function(_, caseContext)
		local self = fake(ONE)
		self.consoleLimit = 100000
		local runIdSeen = ""
		self.console = function(runId: string, token: string): string
			runIdSeen = runId
			local rows: { unknown } = {}
			local publisher = Roblox.progressChannel.publisher(runId, token, function(_, context)
				table.insert(rows, { loggerFullPath = Roblox.progressChannel.LOGGER, context = context })
			end)
			for index = 1, 256 do
				local step = tostring(index) .. string.rep('long/quoted"/é/', 40)
				publisher.publish("case-1", "client", step, "started", nil)
				publisher.publish("case-1", "client", step, "finished", "passed")
			end
			return Wire.encode(rows)
		end
		local directory = temporary(caseContext, "verify-attach-progress-large")
		local file = directory .. "/progress.jsonl"
		local outcome = Lute.studio.run {
			code = "return 1",
			directory = directory,
			progressFile = file,
			attach = { authorize = allow, studioId = "studio-a", transport = self.transport },
		}
		expect(outcome.status):toEqual "returned"
		local events: { Verify.ProgressEvent } = if fs.exists(file) then ProgressFile.read(file, runIdSeen) else {}
		expect(#events):toBe(512)
		for index, event in events do
			expect(event.sequence):toBe(index)
		end
		expect(fs.exists(file .. ".diagnostics")):toBe(false)
	end)

	it("surfaces rejected progress contexts and a refused history read without failing the run", function()
		local tampered = fake(ONE)
		tampered.console = function(runId: string, token: string): string
			local lines: { unknown } = {}
			local publisher = Roblox.progressChannel.publisher(runId, token, function(message, context)
				table.insert(
					lines,
					{ message = message, loggerFullPath = Roblox.progressChannel.LOGGER, context = context }
				)
			end)
			publisher.publish("case-1", "server", "first", "started", nil)
			publisher.publish("case-1", "server", "first", "finished", "passed")
			lines[2] = { loggerFullPath = Roblox.progressChannel.LOGGER, context = { token = token, event = {} } }
			return Wire.encode(lines)
		end
		local directory = Files.claimDirectory(Files.temporary "verify-attach-progress-b")
		local file = directory .. "/progress.jsonl"
		local outcome = Lute.studio.run {
			code = "return 1",
			directory = directory,
			progressFile = file,
			attach = { authorize = allow, studioId = "studio-a", transport = tampered.transport },
		}
		expect(outcome.status):toEqual "returned"
		expect(fs.exists(file .. ".diagnostics")):toBe(true)
		pcall(fs.removeDirectory, directory, { recursive = true })
		local refused = fake(ONE)
		refused.console = tampered.console
		local second = Files.claimDirectory(Files.temporary "verify-attach-progress-c")
		local outcome2 = Lute.studio.run {
			code = "return 1",
			directory = second,
			progressFile = second .. "/progress.jsonl",
			attach = {
				authorize = function(request): Lute.StudioAuthorization
					return {
						ok = string.find(tostring(request.fields.code), "local PROGRESS_TOKEN = ", 1, true) == nil,
						reason = "history reads are not granted",
					}
				end,
				studioId = "studio-a",
				transport = refused.transport,
			},
		}
		expect(outcome2.status):toEqual "returned"
		local diagnostics = fs.readFileToString(second .. "/progress.jsonl.diagnostics")
		expect(diagnostics):toContain "history read"
		pcall(fs.removeDirectory, second, { recursive = true })
	end)

	it("an attached run without a listener never reads the console or injects a token", function()
		local self = fake(ONE)
		local directory = Files.claimDirectory(Files.temporary "verify-attach-progress-d")
		local tools: { string } = {}
		local outcome = Lute.studio.run {
			code = "return 1",
			directory = directory,
			attach = {
				authorize = function(request): Lute.StudioAuthorization
					table.insert(tools, request.tool)
					return allow()
				end,
				studioId = "studio-a",
				transport = self.transport,
			},
		}
		expect(outcome.status):toEqual "returned"
		expect(table.find(tools, "get_console_output")):toBeNil()
		for _, source in self.calls_by_source do
			expect((string.find(source, "progressToken", 1, true))):toBeNil()
		end
		pcall(fs.removeDirectory, directory, { recursive = true })
	end)
end)

return nil
