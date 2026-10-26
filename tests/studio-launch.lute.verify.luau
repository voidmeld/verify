--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local fs = require "@std/fs"

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
				local text = Lute.encode { studios = self.studios }
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

describe("launched Studio sessions", function()
	it("copies the place, waits for the new Studio, attaches and reaps it on close", function()
		local self = world()
		local launched, problem = Lute.studio.launch {
			place = placeFile(PLACE),
			directory = ".lute/tmp/studio-launch",
			transport = self.transport,
			start = opened(self),
			processes = self.deps,
			launchSeconds = 5,
		}
		expect(problem):toBe(nil)
		local session = assert(launched, "the launch returned no session")
		expect(session.session.studio.id):toBe "launched-1"
		expect(session.pid):toBe(4242)
		expect(string.match(session.name, "^Verify%-%d+%-.+%.rbxlx$") ~= nil):toBe(true)
		expect(fs.readFileToString(session.place)):toBe(PLACE)
		local reply = session.session.execute("Edit", "return 1")
		expect(reply.text):toBe "execute_luau:launched-1"
		local closed = session.close()
		expect(closed.session.acknowledged):toBe(true)
		expect(closed.terminated):toEqual { 4242 }
		expect(closed.survivors):toEqual {}
		expect(self.signals):toEqual { "TERM:4242" }
		expect(self.closes):toBe(1)
		expect(session.close()):toBe(closed)
	end)

	it("never selects or stops a Studio that was open before the launch", function()
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
		expect(session.session.studio.id):toBe "launched-1"
		session.close()
		expect(#self.procs):toBe(1)
		expect(self.procs[1].pid):toBe(10)
	end)

	it("reaps the Studio and reports when it never appears in the list", function()
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
		expect(launched):toBe(nil)
		expect(string.find(problem or "", "did not appear", 1, true) ~= nil):toBe(true)
		expect(self.signals):toEqual { "TERM:77" }
		expect(self.closes >= 1):toBe(true)
	end)

	it("refuses two new Studios with the launched place", function()
		local self = world()
		local launched, problem = Lute.studio.launch {
			place = placeFile(PLACE),
			transport = self.transport,
			start = opened(self, 2),
			processes = self.deps,
			launchSeconds = 5,
		}
		expect(launched):toBe(nil)
		expect(string.find(problem or "", "refusing to choose", 1, true) ~= nil):toBe(true)
		expect(self.signals):toEqual { "TERM:4242" }
	end)

	it("copies binary place bytes with the native extension and preserves cleanup", function()
		local self = world()
		local contents = "<roblox!\137\255\r\n\26\n" .. string.rep("\0", 18)
		local launched, problem = Lute.studio.launch {
			place = placeFile(contents),
			transport = self.transport,
			processes = self.deps,
			start = function(place: string, name: string): number
				expect(fs.readFileToString(place)):toBe(contents)
				expect(string.sub(name, -5)):toBe ".rbxl"
				table.insert(self.procs, { pid = 4242, ppid = 1, command = STUDIO .. " " .. place })
				table.insert(self.studios, { id = "binary", name = name })
				return 4242
			end,
		}
		expect(problem):toBe(nil)
		local session = assert(launched)
		expect(session.session.studio.id):toBe "binary"
		expect(session.close().survivors):toEqual {}
		expect(self.signals):toEqual { "TERM:4242" }
	end)

	it("refuses an invalid place and a missing MCP server before it starts Studio", function()
		local self = world()
		local started = false
		local function start(): number
			started = true
			return 1
		end
		for _, contents in { "<rbxl!\137\255 binary", "<roblox!\137\254\r\n\26\n", "<roblox!" } do
			local invalid, problem = Lute.studio.launch {
				place = placeFile(contents),
				transport = self.transport,
				start = start,
				processes = self.deps,
			}
			expect(invalid):toBe(nil)
			expect(string.find(problem or "", "XML", 1, true) ~= nil):toBe(true)
		end
		self.listing = false
		local silent, silentProblem = Lute.studio.launch {
			place = placeFile(PLACE),
			transport = self.transport,
			start = start,
			processes = self.deps,
		}
		expect(silent):toBe(nil)
		expect(string.find(silentProblem or "", "did not list", 1, true) ~= nil):toBe(true)
		expect(started):toBe(false)
	end)
end)

return nil
