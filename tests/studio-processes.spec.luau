--!strict

local Core = require "../src/core"
local Processes = require "../src/lute/studio-processes"

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

return function(suite: Core.Harness)
	suite:suite("launched Studio process ownership", function()
		suite:case("ends the launched Studio and its multiplayer children and never an earlier Studio", function(check)
			local procs: { Processes.Proc } = {
				{ pid = 10, ppid = 1, command = STUDIO .. " -task EditFile -localPlaceFile /x/Mine.rbxlx" },
				{ pid = 20, ppid = 1, command = STUDIO .. " -task EditFile -localPlaceFile /x/Verify-1.rbxlx" },
				{ pid = 21, ppid = 1, command = STUDIO .. " -task StartServer -placeId 1" },
				{ pid = 22, ppid = 1, command = STUDIO .. " -rbxTransportToken abc" },
				{ pid = 30, ppid = 1, command = "/usr/bin/other" },
			}
			local env = fake({ procs[1] }, {}, {})
			local before = Processes.snapshot(env.deps)
			check:expect(before[10]):toBe(true)
			local later = fake(procs, { [21] = true }, {})
			local cleanup = Processes.reap(before, { root = 20, markers = { "Verify-1" } }, later.deps)
			check:expect(#cleanup.survivors):toBe(0)
			check:expect(later.alive[10]):toBe(true)
			check:expect(later.alive[20]):toBe(false)
			check:expect(later.alive[21]):toBe(false)
			check:expect(later.alive[22]):toBe(false)
			check:expect(table.find(later.signals, "KILL:21") ~= nil):toBe(true)
			check:expect(table.find(later.signals, "TERM:10")):toBeNil()
		end)

		suite:case("reports a process that survives both signals", function(check)
			local procs: { Processes.Proc } = {
				{ pid = 21, ppid = 1, command = STUDIO .. " -task StartServer -placeId 1" },
			}
			local env = fake(procs, { [21] = true }, { [21] = true })
			local cleanup = Processes.reap({}, nil, env.deps)
			check:expect(cleanup.survivors):toEqual { 21 }
			check:expect(table.find(env.signals, "TERM:21") ~= nil):toBe(true)
			check:expect(table.find(env.signals, "KILL:21") ~= nil):toBe(true)
		end)

		suite:case("finds descendants of the launched Studio", function(check)
			local procs: { Processes.Proc } = {
				{ pid = 20, ppid = 1, command = STUDIO .. " -task EditFile" },
				{ pid = 25, ppid = 20, command = STUDIO .. " -helper" },
			}
			check:expect(Processes.owned(procs, {}, 20, nil)):toEqual { 20, 25 }
		end)
	end)
end
