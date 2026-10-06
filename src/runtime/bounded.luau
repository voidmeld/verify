--!strict

local Binding = require "./binding"

export type Result = {
	ok: boolean,
	exitcode: number,
	stdout: string,
	stderr: string,
	timedOut: boolean,
	unsupported: boolean,
}

export type Runner = (argv: { string }, options: Binding.RunOptions?) -> Binding.ProcessResult

local CAPABILITY = "posix-process-groups"

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

export type Mechanism = "auto" | "job" | "setsid" | "perl" | "none"

export type Settings = {
	shell: string?,
	mechanism: Mechanism?,
}

local function run(
	argv: { string },
	seconds: number,
	runner: Runner,
	options: Binding.RunOptions?,
	settings: Settings?
): Result
	assert(#argv > 0 and seconds > 0 and seconds < math.huge, "bounded run needs a command and a positive limit")
	local chosen: Settings = settings or {}
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
		return {
			ok = false,
			exitcode = -1,
			stdout = "",
			stderr = tostring(result),
			timedOut = false,
			unsupported = false,
		}
	end
	local ran = result :: Binding.ProcessResult
	local stderr = string.gsub(ran.stderr, "%[%d+%][%+%-]?%s+[^\n]*\n?", "")
	local timedOut = string.find(stderr, MARKER, 1, true) ~= nil
	local unsupported = string.find(stderr, UNSUPPORTED, 1, true) ~= nil
	if unsupported then
		return {
			ok = false,
			exitcode = -1,
			stdout = "",
			stderr = "no mechanism could create a process group for the command (job control, setsid or perl)",
			timedOut = false,
			unsupported = true,
		}
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

return {
	CAPABILITY = CAPABILITY,
	run = run,
}
