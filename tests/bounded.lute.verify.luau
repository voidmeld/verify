--!strict

local fs = require "@std/fs"
local process = require "@std/process"

local Bounded = require "../src/runtime/bounded"
local Files = require "../src/lute/files"
local Verify = require "../src/core"
local Lute = require "../src/lute"

local function runner(command: { string }): process.ProcessResult
	return process.run(command)
end

local function choose(shell: string, mechanism: Bounded.Mechanism): Bounded.Settings
	return { shell = shell, mechanism = mechanism }
end

local function available(path: string): boolean
	return fs.exists(path) or fs.exists("/usr/bin/" .. path) or fs.exists("/bin/" .. path)
end

return function(suite: Verify.Harness)
	suite:suite("bounded host commands", function()
		suite:case("stops a command and its children at the limit and reports a timeout", function(check)
			local began = os.clock()
			local result = Lute.runBounded({ "/bin/sh", "-c", "sleep 8; echo late" }, 1)
			check:expect(result.ok):toEqual(false)
			check:expect(result.timedOut):toEqual(true)
			check:expect(result.stdout):toEqual ""
			check:expect(os.clock() - began < 4):toEqual(true)
		end)

		suite:case("kills the descendants of a timed out command under each shell and mechanism", function(check)
			local root = Files.claimDirectory "/tmp/verify-bounded-tests"
			check:defer(function()
				fs.removeDirectory(root, { recursive = true })
			end)
			local shells = { "sh" }
			if fs.exists "/bin/dash" then
				table.insert(shells, "/bin/dash")
			end
			local mechanisms: { Bounded.Mechanism } = { "auto", "job" }
			if available "perl" then
				table.insert(mechanisms, "perl")
			end
			if available "setsid" then
				table.insert(mechanisms, "setsid")
			end
			local ran = 0
			for _, shell in shells do
				for _, mechanism in mechanisms do
					ran += 1
					local settings = choose(shell, mechanism :: Bounded.Mechanism)
					local marker = ("%s/marker-%d"):format(root, ran)
					local result = Bounded.run(
						{ "/bin/sh", "-c", ("(sleep 2; echo late > %s) & sleep 8"):format(marker) },
						1,
						runner,
						nil,
						settings
					)
					Lute.runBounded({ "/bin/sh", "-c", "sleep 2.5" }, 6)
					local label = ("%s %s"):format(shell, mechanism)
					check:expect(fs.exists(marker)):toBe(false)
					check:expect(result.ok):toBe(false)
					check:expect(result.timedOut or result.unsupported):toBe(true)
					if mechanism == "perl" or mechanism == "setsid" or (mechanism == "job" and shell == "sh") then
						check
							:expect(label .. " timed out " .. tostring(result.timedOut))
							:toBe(label .. " timed out true")
					end
				end
			end
		end)

		suite:case("fails closed when no mechanism may create a process group", function(check)
			local root = Files.claimDirectory "/tmp/verify-bounded-tests"
			check:defer(function()
				fs.removeDirectory(root, { recursive = true })
			end)
			local marker = root .. "/never"
			local result = Bounded.run(
				{ "/bin/sh", "-c", "echo ran > " .. marker },
				5,
				runner,
				nil,
				{ mechanism = "none" }
			)
			check:expect(result.unsupported):toBe(true)
			check:expect(result.ok):toBe(false)
			check:expect(result.timedOut):toBe(false)
			check:expect(fs.exists(marker)):toBe(false)
		end)

		suite:case("kills a command that ignores termination", function(check)
			local began = os.clock()
			local result = Lute.runBounded({ "/bin/sh", "-c", "trap '' TERM; sleep 8; echo late" }, 1)
			check:expect(result.timedOut):toBe(true)
			check:expect(result.stdout):toBe ""
			check:expect(os.clock() - began < 4):toBe(true)
		end)

		suite:case("passes through output and exit codes of commands that finish in time", function(check)
			local ok = Lute.runBounded({ "/bin/echo", "fast" }, 5)
			check:expect(ok.ok):toEqual(true)
			check:expect(ok.stdout):toEqual "fast\n"
			local failed = Lute.runBounded({ "/bin/sh", "-c", "echo out; echo err >&2; exit 3" }, 5)
			check:expect(failed.ok):toEqual(false)
			check:expect(failed.timedOut):toEqual(false)
			check:expect(failed.exitcode):toEqual(3)
			check:expect(failed.stderr):toEqual "err\n"
		end)

		suite:case("a bounded probe turns an enforced timeout into a wait result naming the last state", function(check)
			local state = { now = 0 }
			local result = Verify.waitUntil({
				name = "host call",
				deadlineSeconds = 2,
				pollSeconds = 1,
				probe = function(remaining: number): (boolean, unknown, string?)
					local ran = Lute.runBounded({ "/bin/sh", "-c", "sleep 8" }, remaining)
					state.now += 3
					return ran.ok,
						if ran.timedOut then "no answer in " .. tostring(math.ceil(remaining)) .. "s" else nil
				end,
			}, {
				now = function(): number
					return state.now
				end,
				sleep = function() end,
			})
			check:expect(result.reason):toEqual "timeout"
			check:expect(result.detail):toContain "last observed: no answer in 2s"
		end)
	end)
end
