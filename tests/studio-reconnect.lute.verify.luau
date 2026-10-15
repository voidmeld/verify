--!strict

local Core = require "../src/core"
local Detached = require "../src/lute/studio-detached"
local Reconnect = require "../src/lute/studio-reconnect"
local Engine = require "./studio-engine"

type World = {
	connection: Reconnect.Connection,
	calls: { string },
	opens: number,
	closes: number,
	time: number,
	failOpen: boolean,
	reply: Reconnect.Exchange,
}

local function world(): World
	local self: World = {
		connection = (nil :: unknown) :: Reconnect.Connection,
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
	self.connection = Reconnect.wrap(open(10), {
		open = open,
		now = function(): number
			return self.time
		end,
		wait = function(seconds)
			self.time += seconds
		end,
	})
	return self
end

return function(suite: Core.Harness)
	suite:suite("Studio MCP lifetime", function()
		suite:case("keeps one healthy connection and closes it once", function(check)
			local self = world()
			self.connection.callRaw("read", '{"studio_id":"a"}', 10)
			self.connection.callRaw("read", '{"studio_id":"b"}', 10)
			check:expect(self.opens):toBe(1)
			self.connection.close()
			self.connection.close()
			check:expect(self.closes):toBe(1)
			check:expect(self.connection.alive()):toBe(false)
			check:expect(self.connection.callRaw("read", "{}", 10).status):toBe "unsent"
			check:expect(#self.calls):toBe(2)
		end)

		suite:case("recovers a failed initial handshake before sending a tool", function(check)
			local self = world()
			local attempts = 0
			local connection = Reconnect.wrap(nil, {
				open = function(_deadline): Reconnect.Connection
					attempts += 1
					if attempts == 1 then
						error("handshake exited", 0)
					end
					return self.connection
				end,
				now = function(): number
					return 0
				end,
				wait = function() end,
			})
			check:expect(connection.callRaw("read", "{}", 10).status):toBe "answered"
			check:expect(attempts):toBe(2)
			check:expect(#self.calls):toBe(1)
			connection.close()
		end)

		for _, during in { "wait", "open" } do
			suite:case("does not resurrect a connection closed during " .. during, function(check)
				local self = world()
				local replacement = world()
				self.reply = { status = "unanswered", lost = true }
				local connection: Reconnect.Connection? = nil
				connection = Reconnect.wrap(self.connection, {
					open = function(_deadline): Reconnect.Connection
						if during == "open" then
							(connection :: Reconnect.Connection).close()
						end
						return replacement.connection
					end,
					now = function(): number
						return 0
					end,
					wait = function()
						if during == "wait" then
							(connection :: Reconnect.Connection).close()
						end
					end,
				})
				local connected = connection :: Reconnect.Connection
				connected.callRaw("read", "{}", 10, true)
				check:expect(connected.alive()):toBe(false)
				check:expect(#replacement.calls):toBe(0)
				check:expect(self.closes):toBe(1)
				check:expect(replacement.closes):toBe(if during == "open" then 1 else 0)
			end)
		end

		for _, status in { "unsent", "unanswered" } do
			suite:case("bounds reconnect attempts for " .. status .. " loss", function(check)
				local self = world()
				self.reply = { status = status :: "unsent" | "unanswered", lost = true, detail = "exited" }
				local reply = self.connection.callRaw("execute_luau", '{"studio_id":"a"}', 10, true)
				check:expect(reply.lost):toBe(true)
				check:expect(self.opens):toBe(3)
				check:expect(self.closes):toBe(3)
				check:expect(#self.calls):toBe(3)
				check:expect(self.calls[1]):toBe(self.calls[3])
				check:expect(self.time):toBe(0.75)
			end)
		end

		suite:case("never replays an uncertain mutation and can reopen for the next call", function(check)
			local self = world()
			self.reply = { status = "unanswered", lost = true }
			check:expect(self.connection.callRaw("mutate", "{}", 10).status):toBe "unanswered"
			check:expect(#self.calls):toBe(1)
			self.reply = { status = "answered", result = "resumed" }
			check:expect(self.connection.callRaw("read", "{}", 10).result):toBe "resumed"
			check:expect(self.opens):toBe(2)
		end)

		suite:case("closing one of three runs leaves the other connections and targets intact", function(check)
			local first, second, third = world(), world(), world()
			first.connection.callRaw("read", '{"studio_id":"first"}', 10)
			second.reply = { status = "unanswered", lost = true }
			second.connection.callRaw("execute_luau", '{"studio_id":"second"}', 10)
			first.connection.close()
			second.reply = { status = "answered", result = "resumed" }
			check:expect(second.connection.callRaw("read", '{"studio_id":"second"}', 10).status):toBe "answered"
			check:expect(third.connection.callRaw("read", '{"studio_id":"third"}', 10).status):toBe "answered"
			check:expect(second.calls):toEqual {
				'execute_luau:{"studio_id":"second"}:10',
				'read:{"studio_id":"second"}:10',
			}
			check:expect(third.calls):toEqual { 'read:{"studio_id":"third"}:10' }
			check:expect(third.opens):toBe(1)
			check:expect(third.closes):toBe(0)
			second.connection.close()
			third.connection.close()
		end)

		suite:case("retries a definitely unsent mutation with unchanged bytes", function(check)
			local self = world()
			self.reply = { status = "unsent", lost = true }
			self.connection.callRaw("mutate", '{"studio_id":"a"}', 10)
			check:expect(#self.calls):toBe(3)
			check:expect(self.calls[1]):toBe(self.calls[3])
		end)

		suite:case("does not retry tool errors or ordinary call timeouts", function(check)
			local replies: { Reconnect.Exchange } = {
				{ status = "answered", detail = "tool error" },
				{ status = "unanswered", detail = "deadline" },
			}
			for _, reply in replies do
				local self = world()
				self.reply = reply
				check:expect(self.connection.callRaw("read", "{}", 10, true)):toBe(reply)
				check:expect(#self.calls):toBe(1)
				check:expect(self.closes):toBe(0)
			end
		end)

		suite:case("keeps the original deadline and delivery when reopening fails", function(check)
			local self = world()
			self.reply = { status = "unanswered", lost = true }
			self.failOpen = true
			local reply = self.connection.callRaw("read", "{}", 0.3, true)
			check:expect(reply.status):toBe "unanswered"
			check:expect(reply.lost):toBe(true)
			check:expect(reply.detail):toContain "cannot reopen"
			check:expect(self.opens):toBe(2)
			check:expect(self.time):toBe(0.3)
			local expired = world()
			check:expect(expired.connection.callRaw("read", "{}", 0).status):toBe "unsent"
			check:expect(#expired.calls):toBe(0)
		end)

		suite:case(
			"resumes detached start, poll and segments after reply loss without repeating the case",
			function(check)
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
							return {
								ok = reply.status == "answered",
								text = reply.result :: string?,
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
					check:expect(outcome.status):toBe "done"
					check:expect(outcome.text):toBe "the report"
					check:expect(runs):toBe(1)
					check:expect(opens):toBe(2)
				end
			end
		)
	end)
end
