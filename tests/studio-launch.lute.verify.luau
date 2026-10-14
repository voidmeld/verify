--!strict

local fs = require "@std/fs"
local json = require "@std/json"

local Core = require "../src/core"
local Files = require "../src/lute/files"
local Lute = require "../src/lute"
local Mcp = require "../src/lute/studio-mcp"
local Processes = require "../src/lute/studio-processes"
local Wire = require "../src/lute/wire"

local PLACE = '<roblox version="4"><Item class="Workspace" referent="RBX0"></Item></roblox>'
local STUDIO = "C:/Roblox/RobloxStudioBeta.exe"

type World = {
	transport: Lute.StudioTransport,
	deps: Processes.Deps,
	studios: { Lute.StudioInfo },
	procs: { Processes.Proc },
	calls: { string },
	signals: { string },
	closes: number,
	listing: boolean,
}

local function world(): World
	local clock = 0
	local self: World = {
		transport = {
			call = function(): Mcp.Exchange
				return { status = "unsent", detail = "not wired" }
			end,
			close = function() end,
		},
		deps = {
			list = function(): { Processes.Proc }
				return {}
			end,
			signal = function() end,
			wait = function() end,
			now = function(): number
				return 0
			end,
		},
		studios = { { id = "earlier", name = "Mine.rbxlx" } },
		procs = { { pid = 10, ppid = 1, command = STUDIO .. " -task EditFile -localPlaceFile C:\\x\\Mine.rbxlx" } },
		calls = {},
		signals = {},
		closes = 0,
		listing = true,
	}
	self.transport = {
		call = function(tool: string, argumentsJson: string, _deadline: number): Mcp.Exchange
			table.insert(self.calls, tool)
			if tool == "list_roblox_studios" then
				if not self.listing then
					return { status = "unsent", detail = "the server did not start" }
				end
				local text = json.serialize { studios = self.studios :: { json.Value } }
				return { status = "answered", result = { content = { { type = "text", text = text } } } }
			end
			local arguments = Wire.parse(argumentsJson) :: { [string]: unknown }
			return {
				status = "answered",
				result = { content = { { type = "text", text = tool .. ":" .. tostring(arguments.studio_id) } } },
			}
		end,
		close = function()
			self.closes += 1
		end,
	}
	self.deps = {
		list = function(): { Processes.Proc }
			return table.clone(self.procs)
		end,
		signal = function(pid: number, name: "TERM" | "KILL")
			table.insert(self.signals, name .. ":" .. pid)
			for index, proc in self.procs do
				if proc.pid == pid then
					table.remove(self.procs, index)
					break
				end
			end
		end,
		wait = function(seconds: number)
			clock += seconds
		end,
		now = function(): number
			return clock
		end,
	}
	return self
end

local function placeFile(contents: string): string
	local directory = Files.claimDirectory ".lute/tmp/studio-launch-places"
	local path = directory .. "/game.rbxlx"
	fs.writeStringToFile(path, contents)
	return path
end

local function opened(self: World, copies: number?): (place: string, name: string, deadline: number) -> number
	return function(place: string, name: string, _deadline: number): number
		assert(fs.exists(place) and fs.readFileToString(place) == PLACE, "the launcher copies the place")
		table.insert(self.procs, {
			pid = 4242,
			ppid = 1,
			command = STUDIO .. " -task EditFile -localPlaceFile " .. place,
		})
		for index = 1, copies or 1 do
			table.insert(self.studios, { id = "launched-" .. index, name = name })
		end
		return 4242
	end
end

return function(suite: Core.Harness)
	suite:suite("launched Studio sessions", function()
		suite:case("copies the place, waits for the new Studio, attaches and reaps it on close", function(context)
			local self = world()
			local launched, problem = Lute.studio.launch {
				place = placeFile(PLACE),
				directory = ".lute/tmp/studio-launch",
				transport = self.transport,
				start = opened(self),
				processes = self.deps,
				launchSeconds = 5,
			}
			context:expect(problem):toBe(nil)
			local session = assert(launched, "the launch returned no session")
			context:expect(session.session.studio.id):toBe "launched-1"
			context:expect(session.pid):toBe(4242)
			context:expect(string.match(session.name, "^Verify%-%d+%-.+%.rbxlx$") ~= nil):toBe(true)
			context:expect(fs.readFileToString(session.place)):toBe(PLACE)
			local reply = session.session.execute("Edit", "return 1")
			context:expect(reply.text):toBe "execute_luau:launched-1"
			local closed = session.close()
			context:expect(closed.session.acknowledged):toBe(true)
			context:expect(closed.terminated):toEqual { 4242 }
			context:expect(closed.survivors):toEqual {}
			context:expect(self.signals):toEqual { "TERM:4242" }
			context:expect(self.closes):toBe(1)
			context:expect(session.close()):toBe(closed)
		end)

		suite:case("never selects or stops a Studio that was open before the launch", function(context)
			local self = world()
			table.insert(self.studios, { id = "other", name = "Verify-1-run.rbxlx" })
			local launched = Lute.studio.launch {
				place = placeFile(PLACE),
				transport = self.transport,
				start = opened(self),
				processes = self.deps,
				launchSeconds = 5,
			}
			local session = assert(launched, "the launch returned no session")
			context:expect(session.session.studio.id):toBe "launched-1"
			session.close()
			context:expect(#self.procs):toBe(1)
			context:expect(self.procs[1].pid):toBe(10)
		end)

		suite:case("reaps the Studio and reports when it never appears in the list", function(context)
			local self = world()
			local launched, problem = Lute.studio.launch {
				place = placeFile(PLACE),
				transport = self.transport,
				start = function(place: string): number
					table.insert(self.procs, {
						pid = 77,
						ppid = 1,
						command = STUDIO .. " -task EditFile -localPlaceFile " .. place,
					})
					return 77
				end,
				processes = self.deps,
				launchSeconds = 1,
			}
			context:expect(launched):toBe(nil)
			context:expect(string.find(problem or "", "did not appear", 1, true) ~= nil):toBe(true)
			context:expect(self.signals):toEqual { "TERM:77" }
			context:expect(self.closes >= 1):toBe(true)
		end)

		suite:case("refuses two new Studios with the launched place", function(context)
			local self = world()
			local launched, problem = Lute.studio.launch {
				place = placeFile(PLACE),
				transport = self.transport,
				start = opened(self, 2),
				processes = self.deps,
				launchSeconds = 5,
			}
			context:expect(launched):toBe(nil)
			context:expect(string.find(problem or "", "refusing to choose", 1, true) ~= nil):toBe(true)
			context:expect(self.signals):toEqual { "TERM:4242" }
		end)

		suite:case("refuses a binary place and a missing MCP server before it starts Studio", function(context)
			local self = world()
			local started = false
			local function start(): number
				started = true
				return 1
			end
			local binary, binaryProblem = Lute.studio.launch {
				place = placeFile "<rbxl!\137\255 binary",
				transport = self.transport,
				start = start,
				processes = self.deps,
			}
			context:expect(binary):toBe(nil)
			context:expect(string.find(binaryProblem or "", "XML", 1, true) ~= nil):toBe(true)
			self.listing = false
			local silent, silentProblem = Lute.studio.launch {
				place = placeFile(PLACE),
				transport = self.transport,
				start = start,
				processes = self.deps,
			}
			context:expect(silent):toBe(nil)
			context:expect(string.find(silentProblem or "", "did not list", 1, true) ~= nil):toBe(true)
			context:expect(started):toBe(false)
		end)
	end)
end
