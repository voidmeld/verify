--!strict

local Runtime = require "./runtime"

export type Result = {
	ok: boolean,
	exitcode: number,
	stdout: string,
	stderr: string,
	timedOut: boolean,
	unsupported: boolean,
}

export type Runner = (argv: { string }, options: Runtime.RunOptions?) -> Runtime.ProcessResult

export type Mechanism = Runtime.BoundedMechanism

export type Settings = Runtime.BoundedSettings

local CAPABILITY = "posix-process-groups"

local TREE_CAPABILITY = "process-tree-kill"

local TREE_HEADER = "^verify%-tree%-watchdog (%-?%d+) ([01]) (%d+) (%d+)\n"

local MARKER = "verify_bounded_timeout"

local UNSUPPORTED = "verify_bounded_unsupported"

local WATCHDOG = table.concat({
	"limit=$1; mode=$2; shift 2",
	"spawn() {",
	"  case $1 in",
	'    job) set -m 2>/dev/null; shift; "$@" & child=$! ;;',
	'    setsid) shift; setsid "$@" & child=$! ;;',
	"    perl) shift; perl -MPOSIX -e 'POSIX::setsid(); exec { $ARGV[0] } @ARGV' -- \"$@\" & child=$! ;;",
	"  esac",
	"}",
	"probe() {",
	"  spawn $1 sleep 30",
	"  pr=$child; i=0; ok=1; patience=50",
	'  if [ "$1" = job ]; then patience=10; fi',
	'  while ! kill -0 "-$pr" 2>/dev/null; do',
	"    i=$((i + 1))",
	"    if [ $i -gt $patience ]; then ok=0; break; fi",
	"    sleep 0.02",
	"  done",
	'  kill -KILL "-$pr" 2>/dev/null; kill -KILL "$pr" 2>/dev/null',
	'  { wait "$pr"; } 2>/dev/null',
	"  set +m 2>/dev/null",
	"  [ $ok = 1 ]",
	"}",
	"launch=",
	"for m in job setsid perl; do",
	'  [ "$mode" = auto ] || [ "$mode" = "$m" ] || continue',
	"  case $m in",
	"    setsid) command -v setsid >/dev/null 2>&1 || continue ;;",
	"    perl) command -v perl >/dev/null 2>&1 || continue ;;",
	"  esac",
	"  if probe $m; then launch=$m; break; fi",
	"done",
	'if [ -z "$launch" ]; then echo ' .. UNSUPPORTED .. " >&2; exit 125; fi",
	'spawn "$launch" "$@"',
	'( sleep "$limit" >/dev/null 2>&1; kill -KILL "-$child" 2>/dev/null && echo ' .. MARKER .. " >&2 ) &",
	'dog=$!; { wait "$child"; } 2>/dev/null; status=$?; kill "$dog" 2>/dev/null; exit "$status"',
}, "\n")

local function refused(stderr: string, unsupported: boolean): Result
	return {
		ok = false,
		exitcode = -1,
		stdout = "",
		stderr = stderr,
		timedOut = false,
		unsupported = unsupported,
	}
end

local function tree(
	argv: { string },
	seconds: number,
	runner: Runner,
	options: Runtime.RunOptions?,
	watchdog: { string }?
): Result
	if watchdog == nil or #watchdog == 0 then
		return refused("no tree watchdog is configured, so no process tree can be bounded", true)
	end
	local command = table.clone(watchdog)
	table.insert(command, "watch")
	table.insert(command, tostring(math.ceil(seconds)))
	table.insert(command, "--")
	for _, value in argv do
		table.insert(command, value)
	end
	local called, result = pcall(runner, command, options)
	if not called then
		return refused("the tree watchdog could not be started: " .. tostring(result), true)
	end
	local ran = result
	local code, flag, outBytes, errBytes = string.match(ran.stdout, TREE_HEADER)
	local header = string.find(ran.stdout, "\n", 1, true)
	local outLength = tonumber(outBytes)
	local errLength = tonumber(errBytes)
	if
		code == nil
		or header == nil
		or outLength == nil
		or errLength == nil
		or #ran.stdout ~= header + outLength + errLength
	then
		return {
			ok = false,
			exitcode = if ran.exitcode ~= 0 then ran.exitcode else -1,
			stdout = "",
			stderr = "the tree watchdog returned no complete result: " .. ran.stderr .. ran.stdout,
			timedOut = false,
			unsupported = false,
		}
	end
	local exitcode = tonumber(code)
	assert(exitcode ~= nil)
	local timedOut = flag == "1"
	return {
		ok = exitcode == 0 and not timedOut,
		exitcode = exitcode,
		stdout = string.sub(ran.stdout, header + 1, header + outLength),
		stderr = string.sub(ran.stdout, header + outLength + 1),
		timedOut = timedOut,
		unsupported = false,
	}
end

local function capabilities(settings: Settings?): { string }
	if settings ~= nil and settings.mechanism == "tree" then
		return { TREE_CAPABILITY }
	end
	return { CAPABILITY, TREE_CAPABILITY }
end

local function runWith(
	argv: { string },
	seconds: number,
	runner: Runner,
	options: Runtime.RunOptions?,
	settings: Settings?
): Result
	assert(#argv > 0 and seconds > 0 and seconds < math.huge, "bounded run needs a command and a positive limit")
	local chosen: Settings = settings or {}
	if chosen.mechanism == "tree" then
		return tree(argv, seconds, runner, options, chosen.watchdog)
	end
	local command = {
		chosen.shell or "sh",
		"-c",
		WATCHDOG,
		"verify-bounded",
		tostring(math.ceil(seconds)),
		chosen.mechanism or "auto",
	}
	for _, value in argv do
		table.insert(command, value)
	end
	local called, result = pcall(runner, command, options)
	if not called then
		return refused(tostring(result), false)
	end
	local ran = result
	local stderr = string.gsub(ran.stderr, "%[%d+%][%+%-]?%s+[^\n]*\n?", "")
	local timedOut = string.find(stderr, MARKER, 1, true) ~= nil
	local unsupported = string.find(stderr, UNSUPPORTED, 1, true) ~= nil
	if unsupported then
		return refused("no mechanism could create a process group for the command (job control, setsid or perl)", true)
	end
	return {
		ok = ran.exitcode == 0 and not timedOut,
		exitcode = ran.exitcode,
		stdout = ran.stdout,
		stderr = if timedOut then string.gsub(stderr, MARKER .. "\n?", "") else stderr,
		timedOut = timedOut,
		unsupported = false,
	}
end

local function run(argv: { string }, seconds: number, runner: Runner?, options: Runtime.RunOptions?): Result
	return runWith(argv, seconds, runner or Runtime.process.run, options, Runtime.bounded)
end

return {
	capabilities = capabilities,
	run = run,
	runWith = runWith,
}
