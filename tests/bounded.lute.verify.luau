--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local temporary = require "./temporary"

local fs = require "@std/fs"
local process = require "@std/process"
local system = require "@std/system"

local Runtime = require "../src/lute/runtime"
local Bounded = require "../src/lute/bounded"
local Files = require "../src/lute/files"
local Host = require "../src/lute/host"

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

local function answered(stdout: string, exitcode: number?): Runtime.ProcessResult
	local code = exitcode or 0
	return { ok = code == 0, exitcode = code, stdout = stdout, stderr = "" }
end

describe("bounded host commands", function()
	it("stops a command and its children at the limit and reports a timeout", function()
		local began = os.clock()
		local result = Bounded.run(sleeper(8, "late"), 1)
		expect(result.ok):toEqual(false)
		expect(result.timedOut):toEqual(true)
		expect(result.stdout):toEqual ""
		expect(os.clock() - began < 4):toEqual(true)
	end)

	if windows then
		it("kills the descendants of a timed out command through the tree watchdog", function(own)
			local root = Files.claimDirectory ".lute/tmp/verify-bounded-tests"
			own(function()
				fs.removeDirectory(root, { recursive = true })
			end)
			local marker = root .. "/marker"
			local result = Bounded.run({
				"cmd",
				"/c",
				("start /b lute run tests/programs/late-marker.luau %s 2 & ping -n 9 127.0.0.1 >nul"):format(marker),
			}, 1)
			Bounded.run(sleeper(3, "waited"), 6)
			expect(result.ok):toBe(false)
			expect(result.timedOut):toBe(true)
			expect(fs.exists(marker)):toBe(false)
		end)

		it("the descendant marker is observable when nothing kills it", function(own)
			local root = Files.claimDirectory ".lute/tmp/verify-bounded-tests"
			own(function()
				fs.removeDirectory(root, { recursive = true })
			end)
			local marker = root .. "/marker"
			local result = Bounded.run({
				"cmd",
				"/c",
				("start /b lute run tests/programs/late-marker.luau %s 1"):format(marker),
			}, 20)
			expect(result.ok):toBe(true)
			expect(fs.exists(marker)):toBe(true)
		end)
	else
		it("kills the descendants of a timed out command under each shell and mechanism", function(_, caseContext)
			local root = temporary(caseContext, "verify-bounded-tests")
			local shells = { "sh" }
			if fs.exists "/bin/bash" then
				table.insert(shells, "/bin/bash")
			end
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
				for mechanismIndex = 1, #mechanisms do
					local mechanism: Bounded.Mechanism = mechanisms[mechanismIndex]
					ran += 1
					local settings = choose(shell, mechanism)
					local marker = ("%s/marker-%d"):format(root, ran)
					local result = Bounded.runWith(
						{ "/bin/sh", "-c", ("(sleep 2; echo late > %s) & sleep 8"):format(marker) },
						1,
						runner,
						nil,
						settings
					)
					Bounded.run({ "/bin/sh", "-c", "sleep 2.5" }, 6)
					local label = ("%s %s"):format(shell, mechanism)
					expect(fs.exists(marker)):toBe(false)
					expect(result.ok):toBe(false)
					expect(result.timedOut or result.unsupported):toBe(true)
					if
						mechanism == "perl"
						or mechanism == "setsid"
						or (mechanism == "job" and shell == "/bin/bash")
					then
						expect(label .. " timed out " .. tostring(result.timedOut)):toBe(label .. " timed out true")
					end
				end
			end
		end)

		it("kills a command that ignores termination", function()
			local began = os.clock()
			local result = Bounded.run({ "/bin/sh", "-c", "trap '' TERM; sleep 8; echo late" }, 1)
			expect(result.timedOut):toBe(true)
			expect(result.stdout):toBe ""
			expect(os.clock() - began < 4):toBe(true)
		end)
	end

	it("fails closed when no mechanism may create a process group", function(_, caseContext)
		local calls = 0
		local function counted(command: { string }): Runtime.ProcessResult
			calls += 1
			return process.run(command)
		end
		local absent = Bounded.runWith({ lute(), "--version" }, 5, counted, nil, { mechanism = "tree" })
		expect(absent.unsupported):toBe(true)
		expect(absent.ok):toBe(false)
		expect(absent.timedOut):toBe(false)
		expect(calls):toBe(0)
		local broken = Bounded.runWith(
			{ lute(), "--version" },
			5,
			counted,
			nil,
			{ mechanism = "tree", watchdog = { "verify-no-such-watchdog" } }
		)
		expect(broken.unsupported):toBe(true)
		expect(broken.ok):toBe(false)
		expect(broken.stderr):toContain "could not be started"
		if not windows then
			local root = temporary(caseContext, "verify-bounded-tests")
			local marker = root .. "/never"
			local result = Bounded.runWith(
				{ "/bin/sh", "-c", "echo ran > " .. marker },
				5,
				runner,
				nil,
				{ mechanism = "none" }
			)
			expect(result.unsupported):toBe(true)
			expect(result.ok):toBe(false)
			expect(result.timedOut):toBe(false)
			expect(fs.exists(marker)):toBe(false)
		end
	end)

	it("passes through output and exit codes of commands that finish in time", function()
		if windows then
			local ok = Bounded.run({ "cmd", "/c", "echo fast" }, 5)
			expect(ok.ok):toEqual(true)
			expect(ok.stdout):toEqual "fast\r\n"
			local failed = Bounded.run({ "cmd", "/c", "echo out&(echo err)1>&2&exit 3" }, 5)
			expect(failed.ok):toEqual(false)
			expect(failed.timedOut):toEqual(false)
			expect(failed.exitcode):toEqual(3)
			expect(failed.stdout):toEqual "out\r\n"
			expect(failed.stderr):toEqual "err\r\n"
			return
		end
		local ok = Bounded.run({ "/bin/echo", "fast" }, 5)
		expect(ok.ok):toEqual(true)
		expect(ok.stdout):toEqual "fast\n"
		local failed = Bounded.run({ "/bin/sh", "-c", "echo out; echo err >&2; exit 3" }, 5)
		expect(failed.ok):toEqual(false)
		expect(failed.timedOut):toEqual(false)
		expect(failed.exitcode):toEqual(3)
		expect(failed.stderr):toEqual "err\n"
	end)
end)

describe("bounded process trees", function()
	it("starts the tree watchdog with the limit and decodes its framed result", function()
		local seen: { string } = {}
		local passed: Runtime.RunOptions? = nil
		local function fake(command: { string }, options: Runtime.RunOptions?): Runtime.ProcessResult
			seen = command
			passed = options
			return answered "verify-tree-watchdog 3 0 3 4\noutERR\n"
		end
		local settings: Bounded.Settings = { mechanism = "tree", watchdog = { "lute", "run", "watchdog.luau" } }
		local result = Bounded.runWith({ "tool", "a b" }, 1.5, fake, { cwd = "work" }, settings)
		expect(seen):toEqual { "lute", "run", "watchdog.luau", "watch", "2", "--", "tool", "a b" }
		expect(passed):toEqual { cwd = "work" }
		expect(result):toEqual {
			ok = false,
			exitcode = 3,
			stdout = "out",
			stderr = "ERR\n",
			timedOut = false,
			unsupported = false,
		}
		local timedOut = Bounded.runWith({ "tool" }, 1, function(): Runtime.ProcessResult
			return answered "verify-tree-watchdog 137 1 0 0\n"
		end, nil, settings)
		expect(timedOut.timedOut):toBe(true)
		expect(timedOut.ok):toBe(false)
		expect(timedOut.exitcode):toBe(137)
		local passing = Bounded.runWith({ "tool" }, 1, function(): Runtime.ProcessResult
			return answered "verify-tree-watchdog 0 0 2 0\nok"
		end, nil, settings)
		expect(passing.ok):toBe(true)
		expect(passing.stdout):toBe "ok"
	end)

	it("faults a missing, truncated or malformed tree watchdog result", function()
		local settings: Bounded.Settings = { mechanism = "tree", watchdog = { "watchdog" } }
		for _, stdout in { "", "verify-tree-watchdog 0 0 10 0\nshort", "verify-tree-watchdog zero\n", "late\n" } do
			local result = Bounded.runWith({ "tool" }, 1, function(): Runtime.ProcessResult
				return answered(stdout, 1)
			end, nil, settings)
			expect(result.ok):toBe(false)
			expect(result.timedOut):toBe(false)
			expect(result.unsupported):toBe(false)
			expect(result.stdout):toBe ""
			expect(result.stderr):toContain "no complete result"
		end
	end)

	it("declares process tree kill for both mechanisms and process groups only for POSIX", function()
		expect(Bounded.capabilities(nil)):toEqual { "posix-process-groups", "process-tree-kill" }
		expect(Bounded.capabilities { mechanism = "auto" }):toEqual {
			"posix-process-groups",
			"process-tree-kill",
		}
		expect(Bounded.capabilities { mechanism = "tree" }):toEqual { "process-tree-kill" }
		local declared: { [string]: boolean } = {}
		for _, capability in Host.capabilities(Runtime) do
			declared[capability] = true
		end
		expect(declared["process-tree-kill"]):toBe(true)
		expect(declared["posix-process-groups"] == true):toBe(not windows)
	end)

	it("the tree watchdog passes output, exit codes, arguments and start refusals through", function()
		local result = Bounded.runWith(
			{ lute(), "run", "tests/programs/exit-with.luau", "4", "a b", 'q"uote', "back\\slash\\", "" },
			30,
			runner,
			nil,
			realTree()
		)
		expect(result.exitcode):toBe(4)
		expect(result.ok):toBe(false)
		expect(result.timedOut):toBe(false)
		expect(result.stdout):toBe '[a b][q"uote][back\\slash\\][]'
		local passing =
			Bounded.runWith({ lute(), "run", "tests/programs/exit-with.luau", "0" }, 30, runner, nil, realTree())
		expect(passing.ok):toBe(true)
		local refused = Bounded.runWith({ "verify-no-such-program" }, 30, runner, nil, realTree())
		expect(refused.ok):toBe(false)
		expect(refused.unsupported):toBe(false)
		expect(refused.exitcode):toBe(-1)
		expect(refused.stderr):toContain "the command could not be started"
	end)
end)

return nil
