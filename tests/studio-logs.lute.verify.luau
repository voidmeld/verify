--!strict

local luau = require "@std/luau"
local Core = require "../src/core"
local Entry = require "../src/roblox/case-entry"
local Logs = require "../src/lute/studio-logs"
local Engine = require "./studio-engine"

local world = [==[
local nodes, callbacks, history = {}, {}, {Server = {}, Client = {}}
local model = 'Server'
local function find(name)
    for _, node in nodes do if node.Name == name then return node end end
end
local RS = {FindFirstChild = function(_, name) return find(name) end, WaitForChild = function(_, name) return assert(find(name)) end}
local remote
local function new(class)
    local node = {ClassName = class}
    function node:Invoke() return self.OnInvoke() end
    function node:InvokeServer() return self.OnServerInvoke() end
    function node:InvokeClient() return self.OnClientInvoke() end
    table.insert(nodes, node)
    return node
end
local services = {
    ReplicatedStorage = RS,
    RunService = {IsServer = function() return model == 'Server' end},
    Players = {GetPlayers = function() return {{UserId = 42}} end},
    LogService = {
        GetLogHistory = function() return history[model] end,
        MessageOut = {Connect = function(_, callback) callbacks[model] = callback end},
    },
}
return {
    game = {GetService = function(_, name) return assert(services[name], name) end},
    Instance = {new = new},
    switch = function(value) model = value end,
    emit = function(side, message, kind) callbacks[side](message, 'Enum.MessageType.' .. kind) end,
    history = history,
    drain = function() return find('VerifyEngineLogsServer'):Invoke() end,
}
]==]

type World = {
	game: unknown,
	Instance: unknown,
	switch: (string) -> (),
	emit: (string, string, string) -> (),
	history: { [string]: { { message: string, messageType: string } } },
	drain: () -> { { message: string, kind: string, actor: string, source: string?, line: number? } },
}

local function fake(): World
	local factory = luau.load(luau.compile(world), "=log-world", { table = table, assert = assert })
	local native = factory() :: World
	local engine = Engine.new { game = native.game, Instance = native.Instance }
	for _, model in { "Server", "Client" } do
		table.insert(
			native.history[model],
			{ message = model .. "Script:12: startup crash", messageType = "Enum.MessageType.MessageError" }
		)
		native.switch(model)
		engine.run(model, Logs.source)
		engine.run(model, Logs.source)
	end
	return native
end

return function(suite: Core.Harness)
	suite:suite("Studio engine log capture", function()
		suite:case("captures both startup histories once and filters only internal source roots", function(check)
			local native = fake()
			native.emit("Server", "CorePackages.Internal:1: engine noise", "MessageError")
			native.emit("Client", "CoreGui.Internal:2: engine noise", "MessageWarning")
			native.emit("Server", "ServerScriptService.Game:45: CorePackages in payload", "MessageError")
			native.emit("Client", "Players.Player.Client:9: warning", "MessageWarning")
			native.emit("Server", "ordinary output", "MessageOutput")
			local rows = native.drain()
			check:expect(#rows):toBe(4)
			check:expect(rows[1].source):toBe "ServerScript"
			check:expect(rows[1].line):toBe(12)
			check:expect(rows[2].source):toBe "ServerScriptService.Game"
			check:expect(rows[4].actor):toBe "client-42"
			check:expect(rows[4].line):toBe(9)
			check:expect(#native.drain()):toBe(0)
		end)

		suite:case(
			"fails the first case on startup crashes and isolates later warnings and expected errors",
			function(check)
				local native = fake()
				local report = Entry.run(function()
					return {
						cases = {
							{ id = "startup", name = "startup", run = function() end },
							{
								id = "expected",
								name = "expected",
								run = function()
									native.emit("Client", "ClientScript:7: deliberate error", "MessageError")
									native.emit("Server", "plain warning", "MessageWarning")
								end,
							},
							{ id = "clean", name = "clean", run = function() end },
						},
						expectedErrors = { expected = { "deliberate error" } },
						options = { executor = "fake-studio" },
						now = os.clock,
					}
				end, "studio", nil, nil, "logs", native.drain)
				check:expect(report.failed):toBe(1)
				check:expect(report.passed):toBe(2)
				check:expect(report.results[1].failures[1].message):toContain "startup crash"
				check:expect(report.results[2].artifacts[1].content):toContain "plain warning"
				check:expect(#report.results[3].artifacts):toBe(0)
				check:expect(Core.decode(report).failed):toBe(1)
			end
		)

		suite:case("retains cleanup errors, rejects unmatched errors and fails a broken collector", function(check)
			local native = fake()
			native.drain()
			local report = Entry.run(function()
				return {
					cases = {
						{
							id = "case",
							name = "case",
							run = function(context: Core.Context)
								context:defer(function()
									native.emit("Server", "ServerScript:3: unexpected", "MessageError")
									error "cleanup failed"
								end)
							end,
						},
					},
					expectedErrors = { case = { "different" } },
					options = { executor = "fake-studio" },
					now = os.clock,
				}
			end, "studio", nil, nil, "logs", native.drain)
			check:expect(report.failed):toBe(1)
			check:expect(#report.results[1].failures):toBe(2)
			check:expect(report.results[1].artifacts[1].content):toContain "unexpected"
			local broken = Entry.run(
				function()
					return {
						cases = { { id = "broken", name = "broken", run = function() end } },
						options = { executor = "fake-studio" },
						now = os.clock,
					}
				end,
				"studio",
				nil,
				nil,
				"logs",
				function()
					error "collector lost"
				end
			)
			check:expect(broken.failed):toBe(1)
			check:expect(broken.results[1].failures[1].message):toContain "collector lost"
		end)
	end)
end
