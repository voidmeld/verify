--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local Lute = require "../src/lute"
local fixture = require "./fixtures/script-context"

for _, mode in { "default", "legacy", "modern" } do
	it("boots " .. mode .. " scripts only in their native contexts and locations", function(own)
		local legacy = mode ~= "modern"
		local project = fixture.project(if mode == "default" then nil else legacy)
		local sources = table.clone(fixture.sources)
		sources["fixture.project.json"] = Lute.encode(project)
		local host = table.clone(Lute.fixture.host)
		host.readFile = function(path: string): string
			return assert(sources[path], path)
		end
		local bridge = Lute.fixture.bridge()
		own(bridge.close)
		local report = Roblox.bootPlace({
			projectPath = "fixture.project.json",
			identity = { universeId = 1, placeId = 2, placeVersion = 3 },
			subject = { name = "Context", userId = 4, jobId = "context" },
			aliases = {},
			firstViewport = { x = 800, y = 600 },
			finalViewport = { x = 800, y = 600 },
			frames = 1,
			engineProvidedInput = false,
			observe = function(stage, view)
				if stage == "server" or stage == "client" then
					local source = "local modern = "
						.. tostring(not legacy)
						.. "\nlocal side = "
						.. string.format("%q", if stage == "server" then "Server" else "Client")
						.. "\n"
						.. fixture.assertions
					expect(Lute.chunk.load(source, { environment = view.runtime.globals })()):toBe(true)
				end
			end,
		}, {
			newEngine = bridge.placeEngine,
			host = host,
			cache = Roblox.createPlaceCache(host),
			files = {
				exists = function(path: string): boolean
					return sources[path] ~= nil
				end,
				fileType = function(): string
					return "file"
				end,
				listDirectory = function()
					return {}
				end,
			},
		})
		own(function()
			for index = #report.runtime.closeHandlers, 1, -1 do
				report.runtime.closeHandlers[index]()
			end
		end)
		expect(report.diagnostics):toEqual {}
		expect(#report.serverScripts):toBe(if legacy then 2 else 5)
		expect(#report.clientScripts):toBe(if legacy then 4 else 6)
	end)
end

return nil
