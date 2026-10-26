--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local temporary = require "./temporary"

local Plan = require "../src/core/plan"
local json = require "@std/json"
local Verify = require "../src/core"
local Channel = require "../src/roblox/report-channel"
local Lute = require "../src/lute"
local Platform = require "../src/lute/platform"
local Wire = require "../src/lute/wire"

local UUID = "123e4567-e89b-12d3-a456-426614174000"
local PATH = "universes/1/places/2/versions/3/luau-execution-sessions/" .. UUID .. "/tasks/" .. UUID

type Fake = {
	options: Lute.OpenCloudOptions,
	calls: { Lute.OpenCloudCall },
	clock: { value: number },
	submit: (Lute.OpenCloudCall) -> Lute.OpenCloudExchange,
	states: { Lute.OpenCloudExchange },
	logs: Lute.OpenCloudExchange,
	rewrite: ((string) -> string)?,
}

local function answer(status: number, value: unknown): Lute.OpenCloudExchange
	return { status = "answered", httpStatus = status, body = Wire.encode(value) }
end

local function report(runId: string, caseId: string, passing: boolean): string
	local harness = Verify.createHarness {
		now = function(): number
			return 0
		end,
	}
	harness:case(caseId, function(context)
		context:expect(1):toBe(if passing then 1 else 2)
	end)
	return Wire.encode(Channel.envelope(runId, harness:run { executor = "fake-task" }))
end

local function runIdOf(call: Lute.OpenCloudCall): string
	local script = (Wire.parse(call.body or "{}") :: { [string]: unknown }).script :: string
	return assert(string.match(script, 'local runId = "([^"]+)"'))
end

local function complete(payload: unknown): Lute.OpenCloudExchange
	return answer(200, { path = PATH, state = "COMPLETE", output = { results = payload } })
end

local function fake(caseId: string?, passing: boolean?): Fake
	local self: Fake
	local options: Lute.OpenCloudOptions = {
		universeId = "1",
		placeId = "2",
		versionId = "3",
		authorize = function(): Lute.StudioAuthorization
			return { ok = true, reason = nil }
		end,
		request = function(call: Lute.OpenCloudCall): Lute.OpenCloudExchange
			table.insert(self.calls, call)
			if call.purpose == "submit" then
				local answered = self.submit(call)
				if answered.status == "answered" and answered.httpStatus == 200 and #self.states == 0 then
					table.insert(self.states, complete { report(runIdOf(call), caseId or "case", passing ~= false) })
				end
				return answered
			elseif call.purpose == "logs" then
				return self.logs
			end
			local current = self.states[1]
			if #self.states > 1 then
				table.remove(self.states, 1)
			end
			return current
		end,
		requestSeconds = 5,
		pollSeconds = 20,
		pollIntervalSeconds = 2,
		now = function(): number
			return self.clock.value
		end,
		sleep = function(seconds: number)
			self.clock.value += seconds
		end,
	}
	self = {
		calls = {},
		clock = { value = 0 },
		submit = function(): Lute.OpenCloudExchange
			return answer(200, { path = PATH, state = "QUEUED" })
		end,
		states = {},
		logs = answer(200, {
			luauExecutionSessionTaskLogs = { { messages = { "boot ok", "case done" } } },
		}),
		options = options,
	}
	return self
end

local function count(self: Fake, purpose: string): number
	local total = 0
	for _, call in self.calls do
		if call.purpose == purpose then
			total += 1
		end
	end
	return total
end

local function session(self: Fake): Lute.OpenCloudSession
	return Lute.openCloud.connect(self.options)
end

local INPUT = { code = "return 1", runId = "run-1", requires = nil }

describe("Open Cloud execution", function()
	it("a complete task with a bound all-passed report passes and captures logs and timing", function()
		local self = fake("case", true)
		local outcome = session(self).run(INPUT)
		expect(outcome.status):toEqual "returned"
		expect(outcome.passed):toEqual(true)
		expect(outcome.delivery):toEqual "answered"
		expect(outcome.state):toEqual "COMPLETE"
		expect((assert(outcome.handle)).path):toEqual(PATH)
		expect(outcome.logs):toEqual "boot ok\ncase done"
		expect((assert(outcome.report)).passed):toEqual(1)
		expect(outcome.timing.polls >= 1):toEqual(true)
		expect(outcome.timing.submitSeconds ~= nil):toEqual(true)
		local submit = self.calls[1]
		expect(submit.url):toEqual "https://apis.roblox.com/cloud/v2/universes/1/places/2/versions/3/luau-execution-session-tasks"
		expect(submit.method):toEqual "POST"
		expect(#submit.digest):toEqual(64)
		expect(runIdOf(submit)):toEqual "run-1"
	end)

	it("a deliberate assertion failure inside a COMPLETE task is a failed run", function()
		local self = fake("case", false)
		local outcome = session(self).run(INPUT)
		expect(outcome.state):toEqual "COMPLETE"
		expect(outcome.status):toEqual "returned"
		expect(outcome.passed):toEqual(false)
		expect((assert(outcome.report)).failed):toEqual(1)
	end)

	it("FAILED and CANCELLED tasks are faults with logs and no report", function()
		for _, state in { "FAILED", "CANCELLED" } do
			local self = fake()
			self.states = {
				answer(200, { path = PATH, state = state, error = { code = "INTERNAL", message = "boom" } }),
			}
			local outcome = session(self).run(INPUT)
			expect(outcome.status):toEqual "faulted"
			expect(outcome.passed):toEqual(false)
			expect(outcome.state):toEqual(state)
			expect(outcome.detail):toContain(state)
			expect(outcome.detail):toContain "boom"
			expect(outcome.report):toBeNil()
			expect(outcome.logs):toContain "boot ok"
		end
	end)

	it("submit errors distinguish unsent from possibly sent and are never retried", function()
		local table_: { { exchange: Lute.OpenCloudExchange, delivery: string } } = {
			{ exchange = answer(401, {}), delivery = "unsent" },
			{ exchange = answer(403, {}), delivery = "unsent" },
			{ exchange = answer(429, {}), delivery = "unsent" },
			{ exchange = answer(400, {}), delivery = "unsent" },
			{ exchange = answer(500, {}), delivery = "possibly_sent" },
			{ exchange = answer(503, {}), delivery = "possibly_sent" },
			{ exchange = answer(408, {}), delivery = "possibly_sent" },
			{ exchange = { status = "unsent", detail = "no route" }, delivery = "unsent" },
			{ exchange = { status = "unanswered", detail = "reset" }, delivery = "possibly_sent" },
			{ exchange = { status = "answered", httpStatus = 200, body = "not json" }, delivery = "possibly_sent" },
			{ exchange = answer(200, { state = "QUEUED" }), delivery = "possibly_sent" },
		}
		for _, row in table_ do
			local self = fake()
			self.submit = function()
				return row.exchange
			end
			local outcome = session(self).run(INPUT)
			expect(outcome.delivery):toEqual(row.delivery)
			expect(outcome.passed):toEqual(false)
			expect(outcome.handle):toBeNil()
			expect(count(self, "submit")):toEqual(1)
			expect(count(self, "poll")):toEqual(0)
		end
	end)

	it("a hung submit is possibly sent at its request deadline", function()
		local self = fake()
		self.options.request = function(): Lute.OpenCloudExchange
			coroutine.yield()
			return { status = "unsent", detail = "unreachable" }
		end
		local outcome = session(self).run(INPUT)
		expect(outcome.delivery):toEqual "possibly_sent"
		expect(outcome.status):toEqual "timed_out"
	end)

	it("a poll deadline returns the handle, cancels nothing and can be reconciled", function()
		local self = fake()
		local running = answer(200, { path = PATH, state = "PROCESSING" })
		self.states = { running }
		local connection = session(self)
		local outcome = connection.run(INPUT)
		expect(outcome.status):toEqual "timed_out"
		expect(outcome.passed):toEqual(false)
		expect(outcome.state):toEqual "PROCESSING"
		expect(outcome.detail):toContain "not cancelled"
		local handle = assert(outcome.handle)
		expect(handle.path):toEqual(PATH)
		expect(handle.runId):toEqual "run-1"
		for _, call in self.calls do
			expect(call.purpose == "submit" or call.method == "GET"):toEqual(true)
		end

		self.states = { complete { report("run-1", "case", true) } }
		local reconciled = connection.reconcile(handle)
		expect(reconciled.passed):toEqual(true)
		expect(reconciled.status):toEqual "returned"
		expect(count(self, "submit")):toEqual(1)
	end)

	it("reconcile refuses handles for another place, version or path", function()
		local self = fake()
		local connection = session(self)
		local before = #self.calls
		local variants: { Lute.OpenCloudHandle } = {
			{ path = PATH, runId = "run-1", universeId = "1", placeId = "9", versionId = "3" },
			{ path = PATH, runId = "run-1", universeId = "1", placeId = "2", versionId = "4" },
			{ path = PATH, runId = "run-1", universeId = "8", placeId = "2", versionId = "3" },
			{ path = "x", runId = "run-1", universeId = "1", placeId = "2", versionId = "3" },
		}
		for _, handle in variants do
			expect(connection.reconcile(handle).status):toEqual "refused"
		end
		expect(#self.calls):toEqual(before)
	end)

	it("poll failures: transient answers are retried until the deadline, fatal ones stop", function()
		local transient = fake("case", true)
		local created = false
		transient.options.request = function(call: Lute.OpenCloudCall): Lute.OpenCloudExchange
			if call.purpose == "submit" then
				return answer(200, { path = PATH, state = "QUEUED" })
			elseif call.purpose == "logs" then
				return answer(200, {})
			elseif not created then
				created = true
				return answer(503, {})
			end
			return complete {
				report(
					runIdOf {
						purpose = "submit",
						method = "POST",
						url = "",
						body = json.serialize { script = 'local runId = "run-1"' },
						digest = "",
						universeId = "1",
						placeId = "2",
						versionId = "3",
					},
					"case",
					true
				),
			}
		end
		transient.options.now = function(): number
			return transient.clock.value
		end
		local outcome = session(transient).run(INPUT)
		expect(outcome.passed):toEqual(true)
		expect(#outcome.diagnostics >= 1):toEqual(true)

		local fatal = fake()
		fatal.states = { answer(403, {}) }
		local stopped = session(fatal).run(INPUT)
		expect(stopped.status):toEqual "faulted"
		expect((assert(stopped.handle)).path):toEqual(PATH)
		expect(stopped.detail):toContain "403"
	end)

	it("reports not bound to this run id, missing or malformed are failures", function()
		local cases: { { name: string, results: unknown, detail: string } } = {
			{ name = "other run", results = { report("another", "case", true) }, detail = "different run id" },
			{ name = "no results", results = {}, detail = "no run-bound" },
			{ name = "not json", results = { "plain text" }, detail = "no run-bound" },
			{ name = "empty string", results = { "" }, detail = "no run-bound" },
			{ name = "not an envelope", results = { json.serialize { ok = true } }, detail = "no run-bound" },
			{
				name = "bad report",
				results = { json.serialize { runId = "run-1", report = { total = 1 } } },
				detail = "not a valid report",
			},
			{
				name = "two reports",
				results = { report("run-1", "a", true), report("run-1", "b", true) },
				detail = "several reports",
			},
		}
		for _, row in cases do
			local self = fake()
			self.states = { complete(row.results) }
			local outcome = session(self).run(INPUT)
			expect(outcome.passed):toEqual(false)
			expect(outcome.status):toEqual "faulted"
			expect(outcome.report):toBeNil()
			expect(outcome.detail):toContain(row.detail)
		end
		local missing = fake()
		missing.states = { answer(200, { path = PATH, state = "COMPLETE" }) }
		expect(session(missing).run(INPUT).status):toEqual "faulted"
	end)

	it("a report with skipped or unsupported cases is not a pass", function()
		local harness = Verify.createHarness {
			now = function(): number
				return 0
			end,
		}
		harness:case("needs", {
			requires = { "missing" },
			run = function(_context: Verify.Context) end,
		})
		local self = fake()
		local encoded = Wire.encode(Channel.envelope("run-1", harness:run { executor = "fake-task" }))
		self.states = { complete { encoded } }
		local outcome = session(self).run(INPUT)
		expect(outcome.status):toEqual "returned"
		expect(outcome.passed):toEqual(false)
		expect((assert(outcome.report)).unsupported):toEqual(1)
	end)

	it("cases needing unavailable capabilities are refused before anything is sent", function()
		local self = fake()
		local connection = session(self)
		local outcome = connection.run {
			code = "return 1",
			runId = "run-1",
			requires = { "native-physics", "action:input.pointer", "action:instance.create" },
		}
		expect(outcome.status):toEqual "refused"
		expect(outcome.delivery):toEqual "unsent"
		expect(outcome.detail):toContain "native-physics"
		expect(outcome.detail):toContain "action:input.pointer"
		expect(#self.calls):toEqual(0)
		for _, name in Lute.openCloud.UNSUPPORTED do
			expect(#Lute.openCloud.refusedCapabilities { name }):toEqual(1)
		end
		expect(#Lute.openCloud.refusedCapabilities { "action:instance.create" }):toEqual(0)
	end)

	it("version, place and universe binding is exact", function()
		local wrong = {
			"universes/1/places/2/versions/4/luau-execution-sessions/" .. UUID .. "/tasks/" .. UUID,
			"universes/1/places/5/versions/3/luau-execution-sessions/" .. UUID .. "/tasks/" .. UUID,
			"universes/9/places/2/versions/3/luau-execution-sessions/" .. UUID .. "/tasks/" .. UUID,
			"universes/1/places/2/versions/3/luau-execution-sessions/" .. UUID .. "/tasks/other",
		}
		for _, path in wrong do
			local self = fake()
			self.submit = function()
				return answer(200, { path = path, state = "QUEUED" })
			end
			local outcome = session(self).run(INPUT)
			expect(outcome.status):toEqual "faulted"
			expect(outcome.handle):toBeNil()
			expect(outcome.detail):toContain "outside the requested"
			expect(count(self, "poll")):toEqual(0)
		end
		local drift = fake()
		drift.states = { answer(200, { path = wrong[1], state = "COMPLETE" }) }
		local outcome = session(drift).run(INPUT)
		expect(outcome.status):toEqual "faulted"
		expect(outcome.detail):toContain "different task path"
		for _, bad in { "", "0", "01", "x", "1.5" } do
			local options = table.clone(fake().options)
			options.versionId = bad
			local accepted = pcall(Lute.openCloud.connect, options)
			expect(accepted):toEqual(false)
		end
	end)

	it("authorize sees every call and a refusal or raise sends nothing", function()
		local self = fake()
		local seen: { string } = {}
		self.options.authorize = function(call: Lute.OpenCloudCall): Lute.StudioAuthorization
			table.insert(seen, call.purpose)
			return { ok = call.purpose ~= "submit", reason = "no submit grant" }
		end
		local outcome = session(self).run(INPUT)
		expect(outcome.status):toEqual "refused"
		expect(outcome.detail):toEqual "no submit grant"
		expect(#self.calls):toEqual(0)
		expect(seen):toEqual { "submit" }

		local raising = fake()
		raising.options.authorize = function(): Lute.StudioAuthorization
			error "policy broke"
		end
		local raised = session(raising).run(INPUT)
		expect(raised.status):toEqual "refused"
		expect(raised.detail):toContain "policy broke"
		expect(#raising.calls):toEqual(0)

		local watching = fake()
		local polled = false
		watching.options.authorize = function(call: Lute.OpenCloudCall): Lute.StudioAuthorization
			if call.purpose == "poll" then
				polled = true
				return { ok = false, reason = "poll denied" }
			end
			return { ok = true, reason = nil }
		end
		local stopped = session(watching).run(INPUT)
		expect(polled):toEqual(true)
		expect(stopped.status):toEqual "faulted"
		expect((assert(stopped.handle)).path):toEqual(PATH)
	end)

	it(
		"the host maps outcomes to batches, refuses banned requirements and reconciles instead of resubmitting",
		function()
			local self = fake()
			local seen: { Lute.OpenCloudOutcome } = {}
			local host = Lute.openCloud.host {
				connection = self.options,
				codeForBatch = function(): string
					return "return 1"
				end,
				runId = function(): string
					return "run-1"
				end,
				onOutcome = function(_, outcome: Lute.OpenCloudOutcome)
					table.insert(seen, outcome)
				end,
			}
			expect(host.capabilities):toEqual { "open-cloud-server" }
			expect(host.environment.versionId):toEqual "3"
			local forbidden: Lute.OpenCloudHostOptions = {
				connection = self.options,
				codeForBatch = function(): string
					return ""
				end,
				capabilities = { "native-physics" },
			}
			local declared = pcall(Lute.openCloud.host, forbidden)
			expect(declared):toEqual(false)

			local unit: Verify.PlanUnit = {
				id = "u",
				locator = "u",
				tags = {},
				requires = {},
				weight = 1,
			}
			local banned = table.clone(unit)
			banned.requires = { "native-multiplayer" }
			local refused = host.runBatch { id = "r", index = 1, units = { banned } }
			expect(refused.status):toEqual "faulted"
			expect(refused.detail):toContain "native-multiplayer"
			expect(#self.calls):toEqual(0)

			self.states = { answer(200, { path = PATH, state = "PROCESSING" }) }
			local first = host.runBatch { id = "b", index = 1, units = { unit } }
			expect(first.status):toEqual "timed_out"
			expect(first.detail):toContain(PATH)
			self.states = { complete { report("run-1", "case", true) } }
			local second = host.runBatch { id = "b", index = 1, units = { unit } }
			expect(second.status):toEqual "returned"
			expect(count(self, "submit")):toEqual(1)
			expect(#seen):toEqual(3)

			local unknown = fake()
			unknown.submit = function()
				return answer(503, {})
			end
			local ambiguous = Lute.openCloud.host {
				connection = unknown.options,
				codeForBatch = function(): string
					return "return 1"
				end,
			}
			local one = ambiguous.runBatch { id = "q", index = 1, units = { unit } }
			local two = ambiguous.runBatch { id = "q", index = 1, units = { unit } }
			expect(one.status):toEqual "faulted"
			expect(two.detail):toContain "not resubmitted"
			expect(count(unknown, "submit")):toEqual(1)
		end
	)

	it("Core.execute drives the host and a failing case stays a failed verdict", function()
		local self = fake("case", false)
		local host = Lute.openCloud.host {
			connection = self.options,
			codeForBatch = function(): string
				return "return 1"
			end,
			runId = function(): string
				return "run-1"
			end,
		}
		local plan = Plan.validate {
			id = "open-cloud",
			units = { { id = "case", locator = "case" } },
		}
		local execution = Verify.execute(plan, host)
		expect(execution.report.failed):toEqual(1)
		expect(execution.report.passed):toEqual(0)
	end)

	it("platform runs the open-cloud host with the same selection and report path", function(_, caseContext)
		local root = temporary(caseContext, "verify-open-cloud-tests")
		local self = fake("instance-state", true)
		local result = Platform.run {
			host = "open-cloud",
			entry = "examples/platform-entry.luau",
			caseIds = { "instance-state" },
			output = root,
			cloud = self.options,
		}
		expect(result.report.passed):toEqual(1)
		expect(result.cloud ~= nil):toEqual(true)
		expect(runIdOf(self.calls[1])):toEqual(result.directory)
		local script = (Wire.parse(self.calls[1].body or "{}") :: { [string]: unknown }).script
		expect(script):toContain "'open-cloud'"

		local mismatch = fake("other", true)
		local selected = Platform.run {
			host = "open-cloud",
			entry = "examples/platform-entry.luau",
			caseIds = { "instance-state" },
			output = root,
			cloud = mismatch.options,
		}
		expect(selected.report.passed ~= selected.report.total):toEqual(true)

		local failing = fake()
		failing.submit = function()
			return answer(401, {})
		end
		local refused = Platform.run {
			host = "open-cloud",
			entry = "examples/platform-entry.luau",
			output = root,
			cloud = failing.options,
		}
		expect(refused.report.passed):toEqual(0)
		expect(refused.report.results[1].failures[1].message):toContain "unsent"

		local missing = Platform.run {
			host = "open-cloud",
			entry = "examples/platform-entry.luau",
			output = root,
		}
		expect(missing.report.passed):toEqual(0)
	end)

	it("a caller-bound run submits the bytes unchanged and exposes raw results and the raw task", function()
		local self = fake()
		self.states = { complete { "alpha", "beta" } }
		local code = "return { 'alpha', 'beta' }"
		local outcome = session(self).run { code = code, runId = "task-a", requires = nil, binding = "caller" }
		local sent = (Wire.parse(self.calls[1].body or "{}") :: { [string]: unknown }).script
		expect(sent):toEqual(code)
		expect(outcome.binding):toEqual "caller"
		expect(outcome.status):toEqual "returned"
		expect(outcome.passed):toEqual(false)
		expect(outcome.report == nil):toEqual(true)
		expect(outcome.state):toEqual "COMPLETE"
		expect(#(assert(outcome.results))):toEqual(2)
		expect((assert(outcome.task)).path):toEqual(PATH)
		expect((assert(outcome.handle)).binding):toEqual "caller"
	end)

	it("a caller-bound failed task is faulted with the raw task retained", function()
		local self = fake()
		self.states = {
			answer(200, { path = PATH, state = "FAILED", error = { code = "SCRIPT_ERROR", message = "boom" } }),
		}
		local outcome = session(self).run { code = "error 'x'", runId = "task-b", requires = nil, binding = "caller" }
		expect(outcome.status):toEqual "faulted"
		expect(outcome.detail):toContain "SCRIPT_ERROR: boom"
		expect((assert(outcome.task)).state):toEqual "FAILED"
	end)

	it("submit returns the task path before any poll, then poll and logs are separate calls", function()
		local self = fake()
		self.states = { complete { "done" } }
		local connection = session(self)
		local submission =
			connection.submit { code = "return 'done'", runId = "task-c", requires = nil, binding = "caller" }
		expect(submission.status):toEqual "submitted"
		expect(submission.delivery):toEqual "answered"
		expect((assert(submission.handle)).path):toEqual(PATH)
		expect(#self.calls):toEqual(1)
		local polled = connection.poll(assert(submission.handle))
		expect(polled.status):toEqual "returned"
		expect(polled.logs):toEqual ""
		expect(count(self, "logs")):toEqual(0)
		local logs = connection.logs(assert(submission.handle))
		expect(logs.ok):toEqual(true)
		expect(logs.text):toEqual "boot ok\ncase done"
	end)

	it("submit reports delivery states without polling and refuses foreign handles", function()
		local unsent = fake()
		unsent.submit = function(): Lute.OpenCloudExchange
			return answer(403, {})
		end
		local refused = session(unsent).submit { code = "return 1", runId = "t", requires = nil, binding = "caller" }
		expect(refused.status):toEqual "faulted"
		expect(refused.delivery):toEqual "unsent"
		expect(refused.handle == nil):toEqual(true)
		local ambiguous = fake()
		ambiguous.submit = function(): Lute.OpenCloudExchange
			return answer(503, {})
		end
		local maybe = session(ambiguous).submit { code = "return 1", runId = "t", requires = nil }
		expect(maybe.delivery):toEqual "possibly_sent"
		expect(count(ambiguous, "poll")):toEqual(0)
		local foreign = session(fake()).poll {
			path = PATH,
			runId = "t",
			universeId = "1",
			placeId = "9",
			versionId = "3",
		}
		expect(foreign.status):toEqual "refused"
		expect(session(fake()).logs({
			path = "x",
			runId = "t",
			universeId = "1",
			placeId = "2",
			versionId = "3",
		}).ok):toEqual(false)
	end)
end)

return nil
