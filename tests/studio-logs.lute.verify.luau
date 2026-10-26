--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

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
	local native = factory()
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

describe("Studio engine log capture", function()
	it("captures both startup histories once and filters only internal source roots", function()
		local native = fake()
		native.emit("Server", "CorePackages.Internal:1: engine noise", "MessageError")
		native.emit("Client", "CoreGui.Internal:2: engine noise", "MessageWarning")
		native.emit(
			"Client",
			"[Roblox][CoreGui.RobloxGui.Modules.PlayerPermissionsModule] Invalid value for enum CreatorType\nCoreGui.Internal:25: stack",
			"MessageError"
		)
		native.emit("Server", "[Roblox][CorePackages.Internal] engine noise", "MessageError")
		native.emit("Client", "[Roblox][ScriptContext] engine noise", "MessageError")
		native.emit(
			"Client",
			"[Roblox][Script Context.StarterScript] Script Context.StarterScript:507: engine noise",
			"MessageError"
		)
		native.emit(
			"Server",
			"ServerScriptService.Game:45: [Roblox][CoreGui.Internal] CorePackages in payload",
			"MessageError"
		)
		native.emit("Server", "[Roblox][ServerScriptService.Game] CoreGui in payload", "MessageError")
		native.emit("Client", "Players.Player.Client:9: warning", "MessageWarning")
		native.emit("Server", "ordinary output", "MessageOutput")
		local rows = native.drain()
		expect(#rows):toBe(5)
		expect(rows[1].source):toBe "ServerScript"
		expect(rows[1].line):toBe(12)
		expect(rows[2].source):toBe "ServerScriptService.Game"
		expect(rows[3].source):toBe "ServerScriptService.Game"
		expect(rows[3].line):toBeNil()
		expect(rows[5].actor):toBe "client-42"
		expect(rows[5].line):toBe(9)
		expect(#native.drain()):toBe(0)
	end)

	it("fails the first case on startup crashes and isolates later warnings and expected errors", function()
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
		expect(report.failed):toBe(1)
		expect(report.passed):toBe(2)
		expect(report.results[1].failures[1].message):toContain "startup crash"
		expect(report.results[2].artifacts[1].content):toContain "plain warning"
		expect(#report.results[3].artifacts):toBe(0)
		expect(Core.decode(report).failed):toBe(1)
	end)

	it("retains cleanup errors, rejects unmatched errors and fails a broken collector", function()
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
		expect(report.failed):toBe(1)
		expect(#report.results[1].failures):toBe(2)
		expect(report.results[1].artifacts[1].content):toContain "unexpected"
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
		expect(broken.failed):toBe(1)
		expect(broken.results[1].failures[1].message):toContain "collector lost"
	end)
end)

return nil
