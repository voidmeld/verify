--!strict

local process = require "@std/process"
local Core = require "../src/core"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"
local case = require "../examples/instance-case"

local Place = require "../src/lute/place"
local place = process.args[2] or "/tmp/Verify-Conformance.rbxlx"
Place.build {
	output = place,
	roots = { "src/core", "src/roblox" },
	modules = { "examples/instance-case.luau", "examples/player-case.luau" },
	rootName = "VerifySemanticFixture",
}
local result = Lute.studio.run {
	place = place,
	worker = "tools/studio-worker.luau",
	code = [[
local root = game:GetService('ReplicatedStorage').VerifySemanticFixture
local Core = require(root.src.core)
local Roblox = require(root.src.roblox)
local case = require(root.examples['instance-case'])
local report = Core.runCase(case, Roblox.instanceHost.native('server').host)
local broken = Roblox.instanceHost.native('server')
broken.registry.operations.actions['instance.setProperty'] = {run = function() return nil end}
local failed = Core.runCase(case, broken.host)
assert(failed.failed == 1, 'native mutation defect escaped the case')
return game:GetService('HttpService'):JSONEncode(Roblox.reportChannel.envelope(runId, report))
]],
}
assert(result.status == "returned", result.detail)
local report = Core.decode(result.report)
local simulated = Core.runCase(case, Roblox.instanceHost.simulated("server").host)
local parity = Core.observationParity(simulated, report)
print(Core.format(report))
assert(parity.status == "passed", "native observation parity failed")

local player = Lute.studio.run {
	finalCapture = true,
	place = place,
	context = "Client",
	worker = "tools/studio-worker.luau",
	code = [[
local root = game:GetService('ReplicatedStorage'):WaitForChild('VerifySemanticFixture')
local Core = require(root.src.core)
local Roblox = require(root.src.roblox)
local player = game:GetService('Players').LocalPlayer
local rig = player.Character or player.CharacterAdded:Wait()
rig:WaitForChild('HumanoidRootPart')
task.wait(2)
local report = Core.runCase(require(root.examples['player-case']), Roblox.playerHost.native('client'))
return game:GetService('HttpService'):JSONEncode(Roblox.reportChannel.envelope(runId, report))
]],
}
assert(player.status == "returned", player.detail)
local playerReport = Core.decode(player.report)
print(Core.format(playerReport))
assert(playerReport.total == 1 and playerReport.passed == 1, "native player motion failed")
assert(#playerReport.results[1].artifacts > 0, "native final capture missing")

local timeout = Lute.studio.run {
	place = place,
	worker = "tools/studio-worker.luau",
	deadlineSeconds = 35,
	code = "while true do end",
}
assert(timeout.status == "timed_out", "wedged engine must time out: " .. tostring(timeout.detail))
print "native conformance: server parity, defect detection, client physics and enforced timeout passed"
