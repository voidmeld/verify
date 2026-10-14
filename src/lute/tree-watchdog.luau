--!strict

local fs = require "@std/fs"
local io = require "@std/io"
local process = require "@std/process"
local system = require "@std/system"
local task = require "@std/task"

local KILLED = 137

local function command(from: number): { string }
	assert(process.args[from] == "--", "the tree watchdog needs -- before the command")
	local argv: { string } = {}
	for index = from + 1, #process.args do
		table.insert(argv, process.args[index])
	end
	assert(#argv > 0, "the tree watchdog needs a command")
	return argv
end

local function emit(exitcode: number, timedOut: boolean, stdout: string, stderr: string)
	io.write(
		("verify-tree-watchdog %d %d %d %d\n"):format(exitcode, if timedOut then 1 else 0, #stdout, #stderr),
		stdout,
		stderr
	)
end

local function readIfPresent(path: string): string?
	local read, contents = pcall(fs.readFileToString, path)
	return if read then contents else nil
end

local function removeIfPresent(path: string)
	pcall(fs.remove, path)
end

local function report(path: string, argv: { string })
	fs.writeStringToFile(path, tostring(process.pid()))
	local inherited: process.ProcessRunOptions = { stdio = "inherit" }
	local started, result = pcall(process.run, argv, inherited)
	if not started then
		fs.writeStringToFile(path .. ".refused", tostring(result))
		process.exit(127)
	end
	process.exit((result :: process.ProcessResult).exitcode)
end

local function watch(seconds: number, argv: { string })
	local pidPath = ("%s/verify-tree-%d-%d.pid"):format(
		(string.gsub(tostring(system.tmpdir()), "\\", "/")),
		process.pid(),
		math.floor(os.clock() * 1000000)
	)
	local reporter = { tostring(process.execPath()), "run", process.args[1], "report", pidPath, "--" }
	for _, value in argv do
		table.insert(reporter, value)
	end
	local finished: process.ProcessResult? = nil
	local failure: string? = nil
	task.spawn(function()
		local ran, value = pcall(process.run, reporter)
		if ran then
			finished = value :: process.ProcessResult
		else
			failure = tostring(value)
		end
	end)
	local deadline = os.clock() + seconds
	while finished == nil and failure == nil and os.clock() < deadline do
		task.wait(0.02)
	end
	local done = finished
	if done ~= nil or failure ~= nil then
		local refusal = readIfPresent(pidPath .. ".refused")
		removeIfPresent(pidPath)
		removeIfPresent(pidPath .. ".refused")
		if failure ~= nil then
			emit(-1, false, "", "the tree watchdog could not start its reporter: " .. failure)
		elseif refusal ~= nil then
			emit(-1, false, "", "the command could not be started: " .. refusal)
		else
			local result = done :: process.ProcessResult
			emit(result.exitcode, false, result.stdout, result.stderr)
		end
		process.exit(0)
	end
	local detail = ""
	local pid = readIfPresent(pidPath)
	if pid ~= nil and string.match(pid, "^%d+$") ~= nil then
		local killed, result = pcall(process.run, { "taskkill", "/T", "/F", "/PID", pid })
		if not killed then
			detail = "taskkill could not be started: " .. tostring(result)
		elseif (result :: process.ProcessResult).exitcode ~= 0 then
			local ran = result :: process.ProcessResult
			detail = ("taskkill exited %d: %s%s"):format(ran.exitcode, ran.stdout, ran.stderr)
		end
	end
	removeIfPresent(pidPath)
	removeIfPresent(pidPath .. ".refused")
	emit(KILLED, true, "", detail)
	process.exit(0)
end

local role = process.args[2]
if role == "watch" then
	local seconds = tonumber(process.args[3])
	assert(seconds ~= nil and seconds > 0 and seconds < math.huge, "the tree watchdog needs a positive limit")
	watch(seconds, command(4))
elseif role == "report" then
	local path = process.args[3]
	assert(type(path) == "string" and path ~= "", "the tree reporter needs a process id path")
	report(path, command(4))
end

return nil
