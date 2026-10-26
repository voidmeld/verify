--!strict

local fs = require "@std/fs"
local Core = require "../src/core"
local Lute = require "../src/lute"
local Eval = require "../src/agent-eval"
local Files = require "../src/lute/files"
local fixture = require "../tests/fixtures/script-context"

return function()
	local directory = Files.claimDirectory(Files.temporary "verify-script-context")
	local services = Eval.lute.services()
	local sides: { "Server" | "Client" } = { "Server", "Client" }
	local ok, failure = pcall(function()
		for path, source in fixture.sources do
			fs.writeStringToFile(directory .. "/" .. path, source)
		end
		for _, legacy in { true, false } do
			local project, base = directory .. "/fixture.project.json", directory .. "/fixture.rbxlx"
			fs.writeStringToFile(project, Lute.encode(fixture.project(legacy)))
			local built = services.execute { argv = { "rojo", "build", project, "-o", base }, deadlineSeconds = 60 }
			assert(built.started and built.exitcode == 0 and not built.timedOut, built.stderr)
			local place = directory .. "/bundled.rbxlx"
			Lute.place.build {
				output = place,
				basePlace = base,
				roots = { "src/core", "src/roblox" },
				rootName = "VerifyScriptContext",
			}
			for _, side in sides do
				local body = "local modern = "
					.. tostring(not legacy)
					.. "\nlocal side = "
					.. string.format("%q", side)
					.. "\n"
					.. fixture.assertions
				local result = Lute.studio.run {
					place = place,
					context = if side == "Client" then "Client" else "Server",
					worker = "tools/studio-worker.luau",
					deadlineSeconds = 120,
					code = [[
local root = game:GetService("ReplicatedStorage").VerifyScriptContext
local Core, Roblox = require(root.src.core), require(root.src.roblox)
local harness = Core.createHarness { now = os.clock }
harness:case("native script context", function(check)
    task.wait(0.2)
    check:expect((function()
]] .. body .. [[
    end)()):toBe(true)
end)
return game:GetService("HttpService"):JSONEncode(Roblox.reportChannel.envelope(runId, harness:run {
    executor = "native-script-context", environment = { engineVersion = version() },
}))
]],
				}
				assert(result.status == "returned", result.detail)
				local report = Core.decode(result.report)
				print(Core.format(report))
				assert(report.total == 1 and report.passed == 1, "native script context conformance failed")
			end
		end
	end)
	fs.removeDirectory(directory, { recursive = true })
	assert(ok, failure)
end
