--!strict

local process = require "@std/process"
local Lute = require "../src/lute"
local Platform = Lute.platform
local Core = require "../src/core"
local host = process.args[2] or "studio"
assert(host == "simulator" or host == "studio", "choose simulator or studio")
local result = Platform.run {
	host = host,
	entry = "examples/multiplayer/entry.luau",
	players = 2,
	clientEntry = "examples/multiplayer/client.luau",
	deadlineSeconds = 90,
	output = "/tmp/verify-multiplayer",
}
print(Core.format(result.report))
assert(result.report.total == 1 and result.report.passed == 1, "multiplayer case failed")
