--!strict

local fs = require "@std/fs"
local json = require "@std/json"
local Core = require "../src/core"
local Lute = require "../src/lute"
local Files = require "../src/lute/files"
local Logs = require "../src/lute/studio-logs"
local Place = require "../src/lute/place"
local ProgressFile = require "../src/lute/progress-file"

return function()
	for _, side in { "Server", "Client" } do
		local directory = Files.claimDirectory(Files.temporary "verify-native-logs")
		local place = directory .. "/fixture.rbxlx"
		local startup = "warn('native startup warning'); error('native " .. side .. " startup crash')"
		Place.build {
			output = place,
			roots = { "src/core", "src/roblox" },
			serverSource = if side == "Server" then startup else nil,
			clientSource = if side == "Client" then startup else nil,
		}
		local progressPath = directory .. "/progress.jsonl"
		local outcome = Lute.studio.run {
			place = place,
			worker = "tools/studio-worker.luau",
			progressFile = progressPath,
			code = [==[
local root = game:GetService('ReplicatedStorage').VerifyModules
local Entry = require(root.src.roblox['case-entry'])
local Channel = require(root.src.roblox['report-channel'])
local Progress = require(root.src.roblox['progress-channel'])
local logger = game:GetService('LogService'):GetLogger(Progress.LOGGER)
local progress = Progress.publisher(runId, progressToken, function(message, context) logger:Info(message, context) end)
task.wait(1)
local function emit(message)
    task.spawn(function() error(message) end)
    task.wait(0.1)
end
local report = Entry.run(function()
    return {
        cases = {
            {id = 'startup', name = 'startup', run = function(context)
                context:step('native/path', function() end)
            end},
            {id = 'expected', name = 'expected', run = function()
                warn('native expected warning')
                emit('native expected error')
            end},
            {id = 'unmatched', name = 'unmatched', run = function()
                emit('native unmatched error')
            end},
            {id = 'clean', name = 'clean', run = function() end},
        },
        expectedErrors = {expected = {'native expected error'}, unmatched = {'different error'}},
        options = {executor = 'native-log-conformance'},
        now = os.clock,
    }
end, 'studio', nil, progress, runId, ]==]
				.. Logs.drain
				.. [==[)
return game:GetService('HttpService'):JSONEncode(Channel.envelope(runId, report))
]==],
		}
		assert(outcome.status == "returned", outcome.detail)
		local report = Core.decode(outcome.report)
		fs.writeStringToFile(directory .. "/report.json", json.serialize((report :: unknown) :: json.Value))
		assert(report.failed == 2 and report.passed == 2, Core.format(report))
		local first, expected, unmatched, clean = unpack(report.results)
		assert(
			first.status == "failed"
				and expected.status == "passed"
				and unmatched.status == "failed"
				and clean.status == "passed",
			Core.format(report)
		)
		local startupLog = first.artifacts[1].content or ""
		assert(string.find(startupLog, "native " .. side .. " startup crash", 1, true), startupLog)
		assert(string.find(startupLog, "native startup warning", 1, true), startupLog)
		assert(
			string.find(
				startupLog,
				if side == "Server" then "ServerScriptService.VerifyServer:" else "PlayerScripts.VerifyClient:",
				1,
				true
			),
			startupLog
		)
		assert(string.find(expected.artifacts[1].content or "", "native expected warning", 1, true), "warning lost")
		assert(#clean.artifacts == 0, "logs leaked between cases")
		local firstEvent = (
			json.deserialize(string.match(fs.readFileToString(progressPath), "[^\n]+") :: string) :: unknown
		) :: { [string]: unknown }
		local events = ProgressFile.read(progressPath, firstEvent.runId :: string)
		assert(
			#events == 2 and events[1].step == "native/path" and events[2].phase == "finished",
			"structured native progress lost"
		)
		assert(not fs.exists(progressPath .. ".diagnostics"), "native progress degraded")
		print(
			"native logs: "
				.. side
				.. " startup, warning, location, expected/unmatched errors, isolation and structured progress passed; "
				.. directory
		)
	end
end
