--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Detached = require "../src/lute/studio-detached"
local Reconnect = require "../src/lute/studio-reconnect"
local Engine = require "./studio-engine"

type World = {
	calls: { string },
	opens: number,
	closes: number,
	time: number,
	failOpen: boolean,
	reply: Reconnect.Exchange,
}

local function world(): (World, Reconnect.Connection)
	local self: World = {
		calls = {},
		opens = 0,
		closes = 0,
		time = 0,
		failOpen = false,
		reply = { status = "answered", result = "ok" },
	}
	local function open(_deadline: number): Reconnect.Connection
		self.opens += 1
		if self.failOpen then
			error("cannot reopen", 0)
		end
		return {
			alive = function(): boolean
				return true
			end,
			close = function()
				self.closes += 1
			end,
			callRaw = function(name, arguments, deadline): Reconnect.Exchange
				table.insert(self.calls, name .. ":" .. arguments .. ":" .. deadline)
				return self.reply
			end,
		}
	end
	local primary = Reconnect.wrap(open(10), {
		open = open,
		now = function(): number
			return self.time
		end,
		wait = function(seconds)
			self.time += seconds
		end,
	})
	return self, primary
end

describe("Studio MCP lifetime", function()
	it("keeps one healthy connection and closes it once", function()
		local self, primary = world()
		primary.callRaw("read", '{"studio_id":"a"}', 10)
		primary.callRaw("read", '{"studio_id":"b"}', 10)
		expect(self.opens):toBe(1)
		primary.close()
		primary.close()
		expect(self.closes):toBe(1)
		expect(primary.alive()):toBe(false)
		expect(primary.callRaw("read", "{}", 10).status):toBe "unsent"
		expect(#self.calls):toBe(2)
	end)

	it("reopens on the next call after a reset, and a close stays final", function()
		local self, _ = world()
		local connection = Reconnect.wrap(nil, {
			open = function(_deadline): Reconnect.Connection
				self.opens += 1
				return {
					alive = function(): boolean
						return true
					end,
					close = function()
						self.closes += 1
					end,
					callRaw = function(): Reconnect.Exchange
						return self.reply
					end,
				}
			end,
			now = function(): number
				return 0
			end,
			wait = function() end,
		})
		local before = self.opens
		expect(connection.callRaw("read", "{}", 10).status):toBe "answered"
		connection.reset()
		expect(self.closes):toBe(1)
		expect(connection.alive()):toBe(false)
		expect(connection.callRaw("read", "{}", 10).status):toBe "answered"
		expect(self.opens):toBe(before + 2)
		expect(connection.alive()):toBe(true)
		connection.close()
		connection.reset()
		expect(connection.callRaw("read", "{}", 10).status):toBe "unsent"
		expect(self.opens):toBe(before + 2)
		expect(self.closes):toBe(2)
	end)

	it("recovers a failed initial handshake before sending a tool", function()
		local self, primary = world()
		local attempts = 0
		local connection = Reconnect.wrap(nil, {
			open = function(_deadline): Reconnect.Connection
				attempts += 1
				if attempts == 1 then
					error("handshake exited", 0)
				end
				return primary
			end,
			now = function(): number
				return 0
			end,
			wait = function() end,
		})
		expect(connection.callRaw("read", "{}", 10).status):toBe "answered"
		expect(attempts):toBe(2)
		expect(#self.calls):toBe(1)
		connection.close()
	end)

	for _, during in { "wait", "open" } do
		it("does not resurrect a connection closed during " .. during, function()
			local self, primary = world()
			local replacement, replacementConnection = world()
			self.reply = { status = "unanswered", lost = true }
			local connection: Reconnect.Connection? = nil
			connection = Reconnect.wrap(primary, {
				open = function(_deadline): Reconnect.Connection
					if during == "open" then
						(assert(connection)).close()
					end
					return replacementConnection
				end,
				now = function(): number
					return 0
				end,
				wait = function()
					if during == "wait" then
						(assert(connection)).close()
					end
				end,
			})
			local connected = assert(connection)
			connected.callRaw("read", "{}", 10, true)
			expect(connected.alive()):toBe(false)
			expect(#replacement.calls):toBe(0)
			expect(self.closes):toBe(1)
			expect(replacement.closes):toBe(if during == "open" then 1 else 0)
		end)
	end

	local statuses: { "unsent" | "unanswered" } = { "unsent", "unanswered" }
	for statusIndex = 1, #statuses do
		local status: "unsent" | "unanswered" = statuses[statusIndex]
		it("bounds reconnect attempts for " .. status .. " loss", function()
			local self, primary = world()
			self.reply = { status = status, lost = true, detail = "exited" }
			local reply = primary.callRaw("execute_luau", '{"studio_id":"a"}', 10, true)
			expect(reply.lost):toBe(true)
			expect(self.opens):toBe(3)
			expect(self.closes):toBe(3)
			expect(#self.calls):toBe(3)
			expect(self.calls[1]):toBe(self.calls[3])
			expect(self.time):toBe(0.75)
		end)
	end

	it("never replays an uncertain mutation and can reopen for the next call", function()
		local self, primary = world()
		self.reply = { status = "unanswered", lost = true }
		expect(primary.callRaw("mutate", "{}", 10).status):toBe "unanswered"
		expect(#self.calls):toBe(1)
		self.reply = { status = "answered", result = "resumed" }
		expect(primary.callRaw("read", "{}", 10).result):toBe "resumed"
		expect(self.opens):toBe(2)
	end)

	it("closing one of three runs leaves the other connections and targets intact", function()
		local _first, firstConnection = world()
		local second, secondConnection = world()
		local third, thirdConnection = world()
		firstConnection.callRaw("read", '{"studio_id":"first"}', 10)
		second.reply = { status = "unanswered", lost = true }
		secondConnection.callRaw("execute_luau", '{"studio_id":"second"}', 10)
		firstConnection.close()
		second.reply = { status = "answered", result = "resumed" }
		expect(secondConnection.callRaw("read", '{"studio_id":"second"}', 10).status):toBe "answered"
		expect(thirdConnection.callRaw("read", '{"studio_id":"third"}', 10).status):toBe "answered"
		expect(second.calls):toEqual {
			'execute_luau:{"studio_id":"second"}:10',
			'read:{"studio_id":"second"}:10',
		}
		expect(third.calls):toEqual { 'read:{"studio_id":"third"}:10' }
		expect(third.opens):toBe(1)
		expect(third.closes):toBe(0)
		secondConnection.close()
		thirdConnection.close()
	end)

	it("retries a definitely unsent mutation with unchanged bytes", function()
		local self, primary = world()
		self.reply = { status = "unsent", lost = true }
		primary.callRaw("mutate", '{"studio_id":"a"}', 10)
		expect(#self.calls):toBe(3)
		expect(self.calls[1]):toBe(self.calls[3])
	end)

	it("does not retry tool errors or ordinary call timeouts", function()
		local replies: { Reconnect.Exchange } = {
			{ status = "answered", detail = "tool error" },
			{ status = "unanswered", detail = "deadline" },
		}
		for _, reply in replies do
			local self, primary = world()
			self.reply = reply
			expect(primary.callRaw("read", "{}", 10, true)):toBe(reply)
			expect(#self.calls):toBe(1)
			expect(self.closes):toBe(0)
		end
	end)

	it("keeps the original deadline and delivery when reopening fails", function()
		local self, primary = world()
		self.reply = { status = "unanswered", lost = true }
		self.failOpen = true
		local reply = primary.callRaw("read", "{}", 0.3, true)
		expect(reply.status):toBe "unanswered"
		expect(reply.lost):toBe(true)
		expect(reply.detail):toContain "cannot reopen"
		expect(self.opens):toBe(2)
		expect(self.time):toBe(0.3)
		local expired, expiredConnection = world()
		expect(expiredConnection.callRaw("read", "{}", 0).status):toBe "unsent"
		expect(#expired.calls):toBe(0)
	end)

	it("resumes detached start, poll and segments after reply loss without repeating the case", function()
		for _, loseAt in { "local SIZE =", "local out =", "local I =" } do
			local runs = 0
			local engine = Engine.new {
				body = function(): string
					runs += 1
					return "the report"
				end,
			}
			local opens, lost = 0, false
			local function open(_deadline: number): Reconnect.Connection
				opens += 1
				return {
					alive = function(): boolean
						return true
					end,
					close = function() end,
					callRaw = function(_name, code, _limit): Reconnect.Exchange
						local text = engine.run("Server", code)
						if string.find(code, loseAt, 1, true) ~= nil and not lost then
							lost = true
							return { status = "unanswered", lost = true }
						end
						return { status = "answered", result = text }
					end,
				}
			end
			local connection = Reconnect.wrap(open(10), { open = open, now = os.clock, wait = function() end })
			local outcome = Detached.run {
				execute = function(_model, code, replaySafe): Detached.Reply
					local reply = connection.callRaw("execute_luau", code, os.clock() + 5, replaySafe)
					local text: string? = nil
					if reply.result ~= nil then
						assert(type(reply.result) == "string")
						text = reply.result
					end
					return {
						ok = reply.status == "answered",
						text = text,
						lost = reply.lost == true,
						expired = false,
					}
				end,
				datamodel = "Server",
				code = "return body()",
				runId = "run-a",
				deadline = os.clock() + 5,
				pollSeconds = 0.001,
			}
			expect(outcome.status):toBe "done"
			expect(outcome.text):toBe "the report"
			expect(runs):toBe(1)
			expect(opens):toBe(2)
		end
	end)
end)

return nil
