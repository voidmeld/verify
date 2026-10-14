--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local system = require "@std/system"

local Binding = require "../src/runtime/binding"
local Bounded = require "../src/runtime/bounded"
local Files = require "../src/lute/files"
local Verify = require "../src/core"
local Lute = require "../src/lute"

local windows = system.win32

local function runner(command: { string }): process.ProcessResult
	return process.run(command)
end

local function choose(shell: string, mechanism: Bounded.Mechanism): Bounded.Settings
	return { shell = shell, mechanism = mechanism }
end

local function available(path: string): boolean
	return fs.exists(path) or fs.exists("/usr/bin/" .. path) or fs.exists("/bin/" .. path)
end

local function sleeper(seconds: number, text: string): { string }
	if windows then
		return { "cmd", "/c", ("ping -n %d 127.0.0.1 >nul & echo %s"):format(seconds + 1, text) }
	end
	return { "/bin/sh", "-c", ("sleep %d; echo %s"):format(seconds, text) }
end

local function lute(): string
	return tostring(process.execPath())
end

local function realTree(): Bounded.Settings
	return { mechanism = "tree", watchdog = { lute(), "run", "src/lute/tree-watchdog.luau" } }
end

local function answered(stdout: string, exitcode: number?): Binding.ProcessResult
	local code = exitcode or 0
	return { ok = code == 0, exitcode = code, stdout = stdout, stderr = "" }
end

return function(suite: Verify.Harness)
	suite:suite("bounded host commands", function()
		suite:case("stops a command and its children at the limit and reports a timeout", function(check)
			local began = os.clock()
			local result = Lute.runBounded(sleeper(8, "late"), 1)
			check:expect(result.ok):toEqual(false)
			check:expect(result.timedOut):toEqual(true)
			check:expect(result.stdout):toEqual ""
			check:expect(os.clock() - began < 4):toEqual(true)
		end)

		if windows then
			suite:case("kills the descendants of a timed out command through the tree watchdog", function(check)
				local root = Files.claimDirectory ".lute/tmp/verify-bounded-tests"
				check:defer(function()
					fs.removeDirectory(root, { recursive = true })
				end)
				local marker = root .. "/marker"
				local result = Lute.runBounded({
					"cmd",
					"/c",
					("start /b lute run tests/programs/late-marker.luau %s 2 & ping -n 9 127.0.0.1 >nul"):format(
						marker
					),
				}, 1)
				Lute.runBounded(sleeper(3, "waited"), 6)
				check:expect(result.ok):toBe(false)
				check:expect(result.timedOut):toBe(true)
				check:expect(fs.exists(marker)):toBe(false)
			end)

			suite:case("the descendant marker is observable when nothing kills it", function(check)
				local root = Files.claimDirectory ".lute/tmp/verify-bounded-tests"
				check:defer(function()
					fs.removeDirectory(root, { recursive = true })
				end)
				local marker = root .. "/marker"
				local result = Lute.runBounded({
					"cmd",
					"/c",
					("start /b lute run tests/programs/late-marker.luau %s 1"):format(marker),
				}, 20)
				check:expect(result.ok):toBe(true)
				check:expect(fs.exists(marker)):toBe(true)
			end)
		else
			suite:case("kills the descendants of a timed out command under each shell and mechanism", function(check)
				local root = Files.claimDirectory(Files.temporary "verify-bounded-tests")
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

			suite:case("kills a command that ignores termination", function(check)
				local began = os.clock()
				local result = Lute.runBounded({ "/bin/sh", "-c", "trap '' TERM; sleep 8; echo late" }, 1)
				check:expect(result.timedOut):toBe(true)
				check:expect(result.stdout):toBe ""
				check:expect(os.clock() - began < 4):toBe(true)
			end)
		end

		suite:case("fails closed when no mechanism may create a process group", function(check)
			local calls = 0
			local function counted(command: { string }): Binding.ProcessResult
				calls += 1
				return process.run(command)
			end
			local absent = Bounded.run({ lute(), "--version" }, 5, counted, nil, { mechanism = "tree" })
			check:expect(absent.unsupported):toBe(true)
			check:expect(absent.ok):toBe(false)
			check:expect(absent.timedOut):toBe(false)
			check:expect(calls):toBe(0)
			local broken = Bounded.run(
				{ lute(), "--version" },
				5,
				counted,
				nil,
				{ mechanism = "tree", watchdog = { "verify-no-such-watchdog" } }
			)
			check:expect(broken.unsupported):toBe(true)
			check:expect(broken.ok):toBe(false)
			check:expect(broken.stderr):toContain "could not be started"
			if not windows then
				local root = Files.claimDirectory(Files.temporary "verify-bounded-tests")
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
			end
		end)

		suite:case("passes through output and exit codes of commands that finish in time", function(check)
			if windows then
				local ok = Lute.runBounded({ "cmd", "/c", "echo fast" }, 5)
				check:expect(ok.ok):toEqual(true)
				check:expect(ok.stdout):toEqual "fast\r\n"
				local failed = Lute.runBounded({ "cmd", "/c", "echo out&(echo err)1>&2&exit 3" }, 5)
				check:expect(failed.ok):toEqual(false)
				check:expect(failed.timedOut):toEqual(false)
				check:expect(failed.exitcode):toEqual(3)
				check:expect(failed.stdout):toEqual "out\r\n"
				check:expect(failed.stderr):toEqual "err\r\n"
				return
			end
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
					local ran = Lute.runBounded(sleeper(8, "late"), remaining)
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

	suite:suite("bounded process trees", function()
		suite:case("starts the tree watchdog with the limit and decodes its framed result", function(check)
			local seen: { string } = {}
			local passed: Binding.RunOptions? = nil
			local function fake(command: { string }, options: Binding.RunOptions?): Binding.ProcessResult
				seen = command
				passed = options
				return answered "verify-tree-watchdog 3 0 3 4\noutERR\n"
			end
			local settings: Bounded.Settings = { mechanism = "tree", watchdog = { "lute", "run", "watchdog.luau" } }
			local result = Bounded.run({ "tool", "a b" }, 1.5, fake, { cwd = "work" }, settings)
			check:expect(seen):toEqual { "lute", "run", "watchdog.luau", "watch", "2", "--", "tool", "a b" }
			check:expect(passed):toEqual { cwd = "work" }
			check:expect(result):toEqual {
				ok = false,
				exitcode = 3,
				stdout = "out",
				stderr = "ERR\n",
				timedOut = false,
				unsupported = false,
			}
			local timedOut = Bounded.run({ "tool" }, 1, function(): Binding.ProcessResult
				return answered "verify-tree-watchdog 137 1 0 0\n"
			end, nil, settings)
			check:expect(timedOut.timedOut):toBe(true)
			check:expect(timedOut.ok):toBe(false)
			check:expect(timedOut.exitcode):toBe(137)
			local passing = Bounded.run({ "tool" }, 1, function(): Binding.ProcessResult
				return answered "verify-tree-watchdog 0 0 2 0\nok"
			end, nil, settings)
			check:expect(passing.ok):toBe(true)
			check:expect(passing.stdout):toBe "ok"
		end)

		suite:case("faults a missing, truncated or malformed tree watchdog result", function(check)
			local settings: Bounded.Settings = { mechanism = "tree", watchdog = { "watchdog" } }
			for _, stdout in { "", "verify-tree-watchdog 0 0 10 0\nshort", "verify-tree-watchdog zero\n", "late\n" } do
				local result = Bounded.run({ "tool" }, 1, function(): Binding.ProcessResult
					return answered(stdout, 1)
				end, nil, settings)
				check:expect(result.ok):toBe(false)
				check:expect(result.timedOut):toBe(false)
				check:expect(result.unsupported):toBe(false)
				check:expect(result.stdout):toBe ""
				check:expect(result.stderr):toContain "no complete result"
			end
		end)

		suite:case("declares process tree kill for both mechanisms and process groups only for POSIX", function(check)
			check:expect(Bounded.capabilities(nil)):toEqual { "posix-process-groups", "process-tree-kill" }
			check:expect(Bounded.capabilities { mechanism = "auto" }):toEqual {
				"posix-process-groups",
				"process-tree-kill",
			}
			check:expect(Bounded.capabilities { mechanism = "tree" }):toEqual { "process-tree-kill" }
			local declared: { [string]: boolean } = {}
			for _, capability in Lute.HOST_CAPABILITIES do
				declared[capability] = true
			end
			check:expect(declared["process-tree-kill"]):toBe(true)
			check:expect(declared["posix-process-groups"] == true):toBe(not windows)
		end)

		suite:case("the tree watchdog passes output, exit codes, arguments and start refusals through", function(check)
			local result = Bounded.run(
				{ lute(), "run", "tests/programs/exit-with.luau", "4", "a b", 'q"uote', "back\\slash\\", "" },
				30,
				runner,
				nil,
				realTree()
			)
			check:expect(result.exitcode):toBe(4)
			check:expect(result.ok):toBe(false)
			check:expect(result.timedOut):toBe(false)
			check:expect(result.stdout):toBe '[a b][q"uote][back\\slash\\][]'
			local passing =
				Bounded.run({ lute(), "run", "tests/programs/exit-with.luau", "0" }, 30, runner, nil, realTree())
			check:expect(passing.ok):toBe(true)
			local refused = Bounded.run({ "verify-no-such-program" }, 30, runner, nil, realTree())
			check:expect(refused.ok):toBe(false)
			check:expect(refused.unsupported):toBe(false)
			check:expect(refused.exitcode):toBe(-1)
			check:expect(refused.stderr):toContain "the command could not be started"
		end)
	end)
end
