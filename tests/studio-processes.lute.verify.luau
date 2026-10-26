--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local process = require "@std/process"
local system = require "@std/system"

local Files = require "../src/lute/files"
local Processes = require "../src/lute/studio-processes"
local Powershell = require "../src/lute/powershell"

type Fake = {
	deps: Processes.Deps,
	alive: { [number]: boolean },
	signals: { string },
}

local function fake(procs: { Processes.Proc }, stubborn: { [number]: boolean }, immortal: { [number]: boolean }): Fake
	local clock = 0
	local alive: { [number]: boolean } = {}
	for _, proc in procs do
		alive[proc.pid] = true
	end
	local signals: { string } = {}
	local deps: Processes.Deps = {
		list = function(): { Processes.Proc }
			local out: { Processes.Proc } = {}
			for _, proc in procs do
				if alive[proc.pid] then
					table.insert(out, proc)
				end
			end
			return out
		end,
		signal = function(pid: number, name: "TERM" | "KILL")
			table.insert(signals, name .. ":" .. pid)
			if name == "KILL" and not immortal[pid] then
				alive[pid] = false
			elseif name == "TERM" and not stubborn[pid] then
				alive[pid] = false
			end
		end,
		wait = function(seconds: number)
			clock += seconds
		end,
		now = function(): number
			return clock
		end,
	}
	return { deps = deps, alive = alive, signals = signals }
end

local STUDIO = "/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio"

describe("launched Studio process ownership", function()
	it("Windows launches maximize Studio and preserve literal paths and its actual PID", function()
		local script =
			Processes.windowsStart("C:/O'Brien/$(unused)/RobloxStudioBeta.exe", "C:/Game files/玩家's place.rbxlx")
		expect(script):toContain "-WindowStyle Maximized -PassThru"
		if system.win32 then
			local stub = [[
function Start-Process {
  param($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru)
  if ($FilePath -ne 'C:/O''Brien/$(unused)/RobloxStudioBeta.exe') { throw 'executable changed' }
  if ($ArgumentList -ne '-task EditFile -localPlaceFile "C:\Game files\玩家''s place.rbxlx"') { throw 'arguments changed' }
  if ($WindowStyle -ne 'Maximized' -or -not $PassThru) { throw 'startup options changed' }
  [pscustomobject]@{ Id = 418 }
}
]]
			local ran = process.run(Powershell.command(stub .. script))
			expect(ran.exitcode):toBe(0)
			expect(ran.stdout):toBe "418\r\n"
		end
	end)
	it("Windows launch failure does not return a wrapper PID", function()
		if system.win32 then
			local ok, failure = pcall(
				Processes.start,
				"C:/verify-missing-studio.exe",
				"C:/Verify-test.rbxlx",
				"Verify-test",
				os.clock() + 5,
				"unused"
			)
			expect(ok):toBe(false)
			expect(tostring(failure)):toContain "Start-Process"
		end
	end)
	it("ends the launched Studio and its multiplayer children and never an earlier Studio", function()
		local procs: { Processes.Proc } = {
			{ pid = 10, ppid = 1, command = STUDIO .. " -task EditFile -localPlaceFile /x/Mine.rbxlx" },
			{ pid = 20, ppid = 1, command = STUDIO .. " -task EditFile -localPlaceFile /x/Verify-1.rbxlx" },
			{ pid = 21, ppid = 20, command = STUDIO .. " -task StartServer -placeId 1" },
			{ pid = 22, ppid = 21, command = STUDIO .. " -rbxTransportToken abc" },
			{ pid = 30, ppid = 1, command = "/usr/bin/other" },
		}
		local env = fake({ procs[1] }, {}, {})
		local before = Processes.snapshot(env.deps)
		expect(before[10]):toBe(true)
		local later = fake(procs, { [21] = true }, {})
		local cleanup = Processes.reap(before, { root = 20, markers = { "Verify-1" } }, later.deps)
		expect(#cleanup.survivors):toBe(0)
		expect(later.alive[10]):toBe(true)
		expect(later.alive[20]):toBe(false)
		expect(later.alive[21]):toBe(false)
		expect(later.alive[22]):toBe(false)
		expect(table.find(later.signals, "KILL:21") ~= nil):toBe(true)
		expect(table.find(later.signals, "TERM:10")):toBeNil()
	end)

	it("reports a process that survives both signals", function()
		local procs: { Processes.Proc } = {
			{ pid = 21, ppid = 20, command = STUDIO .. " -task StartServer -placeId 1" },
		}
		local env = fake(procs, { [21] = true }, { [21] = true })
		local cleanup = Processes.reap({}, { root = 21 }, env.deps)
		expect(cleanup.survivors):toEqual { 21 }
		expect(table.find(env.signals, "TERM:21") ~= nil):toBe(true)
		expect(table.find(env.signals, "KILL:21") ~= nil):toBe(true)
	end)

	it("finds descendants of the launched Studio", function()
		local procs: { Processes.Proc } = {
			{ pid = 20, ppid = 1, command = STUDIO .. " -task EditFile" },
			{ pid = 25, ppid = 20, command = STUDIO .. " -helper" },
		}
		expect(Processes.owned(procs, {}, 20, nil)):toEqual { 20, 25 }
	end)

	it("never claims another concurrent run by multiplayer flags alone", function()
		local procs: { Processes.Proc } = {
			{ pid = 20, ppid = 1, command = STUDIO .. " -localPlaceFile Verify-A.rbxlx" },
			{ pid = 21, ppid = 20, command = STUDIO .. " -task StartServer" },
			{ pid = 30, ppid = 1, command = STUDIO .. " -localPlaceFile Verify-B.rbxlx" },
			{ pid = 31, ppid = 30, command = STUDIO .. " -task StartServer" },
			{ pid = 32, ppid = 31, command = STUDIO .. " -rbxTransportToken other" },
			{ pid = 40, ppid = 1, command = STUDIO .. " -rbxTransportToken orphan" },
		}
		local env = fake(procs, {}, {})
		local cleanup = Processes.reap({}, { root = 20, markers = { "Verify-A.rbxlx" } }, env.deps)
		expect(cleanup.terminated):toEqual { 20, 21 }
		expect(env.alive[30] and env.alive[31] and env.alive[32] and env.alive[40]):toBe(true)
		expect(Processes.owned(procs, {}, nil, { "Verify-A.rbxlx" })):toEqual { 20, 21 }
	end)

	it("owns Windows Studio processes by the same names, flags and descent", function()
		local studio = '"C:\\Users\\a\\AppData\\Local\\Roblox\\Versions\\version-1\\RobloxStudioBeta.exe"'
		local procs: { Processes.Proc } = {
			{ pid = 10, ppid = 1, command = studio },
			{ pid = 20, ppid = 2, command = studio .. " -task EditFile -localPlaceFile C:/t/Verify-1.rbxlx" },
			{ pid = 21, ppid = 20, command = studio .. " -task StartServer -placeId 1" },
			{ pid = 25, ppid = 20, command = "C:\\x\\RobloxCrashHandler.exe --crashCounter Win-ROBLOXStudio" },
			{ pid = 26, ppid = 20, command = studio .. " -helper" },
		}
		expect(Processes.owned(procs, { [10] = true }, 20, { "Verify-1" })):toEqual { 20, 21, 26 }
	end)

	it("reads process rows from ps and from the Windows process listing", function()
		expect(Processes.parse "  10     1 /usr/bin/a -x\n 11 10 b\n"):toEqual {
			{ pid = 10, ppid = 1, command = "/usr/bin/a -x" },
			{ pid = 11, ppid = 10, command = "b" },
		}
		expect(Processes.parse '4 0 \r\n20 4 "C:\\a b\\x.exe" -flag\r\nnot a row\r\n'):toEqual {
			{ pid = 4, ppid = 0, command = "" },
			{ pid = 20, ppid = 4, command = '"C:\\a b\\x.exe" -flag' },
		}
	end)

	it("observes a launched child by its parent and marker and refuses one that is never seen", function()
		local lute = tostring(process.execPath())
		local marker = Files.temporary(("verify-spawn-%d-%d"):format(process.pid(), os.time()))
		local argv = if system.win32
			then { lute, "run", "tests/programs/late-marker.luau", marker, "20" }
			else { "/bin/sleep", "20" }
		local pid = Processes.spawn(argv, if system.win32 then marker else "/bin/sleep 20", os.clock() + 20)
		local seen = false
		for _, proc in Processes.defaults().list() do
			seen = seen or (proc.pid == pid and proc.ppid == process.pid())
		end
		Processes.defaults().signal(pid, "KILL")
		expect(seen):toBe(true)
		local missing, refusal = pcall(Processes.spawn, { "verify-no-such-program" }, "x", os.clock() + 5)
		expect(missing):toBe(false)
		expect(tostring(refusal)):toContain "was not observed"
		local quick, early = pcall(
			Processes.spawn,
			{ lute, "run", "tests/programs/exit-with.luau", "0" },
			"verify-never-listed",
			os.clock() + 20
		)
		expect(quick):toBe(false)
		expect(tostring(early)):toContain "it exited first"
	end)
end)

return nil
