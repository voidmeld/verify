# Run cases

Use one command to run cases on the simulator, Studio, a published Player or Open Cloud.
Each entry returns ordinary named cases and harness options. Each host produces the standard report.
Verify has no separate end-to-end case language.

## Hosts

A host runs cases and returns a report. Choose the host by what the claim needs to observe.
A passing run proves only what the host can observe.

| Host | Start it with | Runs | Needs | Limits |
| --- | --- | --- | --- | --- |
| Simulator | `--host simulator` (default) | The case in the Lute process, over the [simulated environment](api.md#simulated-environment). | Lute. | Proves Luau logic over the declared surface. It proves no rendering, physics, replication or input. |
| Lute worker | `Lute.host` | One Lute process per batch. | Lute. See [platform support](#platform-support). | Proves Luau logic under Lute. See [Lute workers](execution.md#lute-workers). |
| Studio, launched | `--host studio` | A disposable Studio on a copy of an XML place. | Installed, authenticated Studio with its MCP tools. macOS reference. See [platform support](#platform-support) for Windows. | One Studio per run. Supports 1 to 8 clients. Saves a final view for one client. See [native Studio execution](execution.md#native-studio-execution). |
| Studio, attached | `attach` option of `Lute.platform.run` | The case in a Studio that the developer already has open. | An open Studio and an `authorize` function. | No isolation. No `players`. The command line cannot attach. See [attached Studio](execution.md#attached-studio). |
| Player | `--host player` | The case in a published place, through the signed-in Player. | A published test place and a closed Player. macOS only. | One client per machine. No durable screenshots. See [published Player execution](execution.md#published-player-execution). |
| Open Cloud | `--host open-cloud` | The case as a Luau execution task on an exact place version. | A caller module for `request` and `authorize`. | Server only. No input, physics, replication, rendering, audio or capture. See [Open Cloud execution](execution.md#open-cloud-execution). |

A capability states what a host can observe. It grants no permission.
A case that requires a capability that the host lacks reports `unsupported`.

## Run a case

Run these commands from a workspace that contains both the framework and the test modules.
Paths are relative to the working directory.
Lute cannot resolve a test module outside its loading root, so use their common parent as the working directory.
Do not pass an entry that is outside the workspace, such as a file in the temporary directory.

From this repository:

```sh
lute run tools/run.luau --entry examples/platform-entry.luau
lute run tools/run.luau --entry examples/platform-entry.luau --host studio --capture
lute run tools/run.luau --entry examples/platform-entry.luau --case instance-state
```

The first two commands run the same assertions against simulated and native instances.
[The entry](../examples/platform-entry.luau) chooses the host binding.
It exports a function that receives `simulator`, `studio` or `player` and returns `{ cases, options, now }`.
On Studio and Open Cloud runs the function also receives the run ID as a second argument. It is nil on the simulator and the Player.
During a Studio run, `ReplicatedStorage` holds the attribute `VerifyRun` with the run ID. A multiplayer run sets it on the test server before the entry runs, so clients read it by replication. Prefer the second argument on the server.

- `cases` holds `Core.NamedCase` values with explicit unique IDs.
- `options` is `Core.RunOptions`.
- `now` is the clock.

Bind per-case resources through `options.bind`. The harness cleans them up.

`Core.runCases(cases, options, now, ids?)` validates the collection and the exact selection before it runs.
Reports record whether the selection was explicit and how many cases were available.
An unknown, duplicate or empty selection fails. If you omit the selection, every case runs.
Do not also set `options.selection`. Each case declares a finite timeout and the capabilities that its observations need.

## Commands and evidence

| Option | Meaning |
| --- | --- |
| `--entry module.luau` | Portable factory module. Required. |
| `--host simulator\|studio\|player\|open-cloud` | The host. Defaults to simulator. |
| `--case id` | Exact case ID. Repeat to select several. |
| `--deadline seconds` | Host execution budget. Defaults to 90. Preparation is outside this budget. |
| `--output directory` | Parent for unique evidence directories. Defaults to `.verify`. |
| `--framework directory` | Framework checkout. Inferred from the path of this command. |
| `--root directory` | Additional mounted module directory. Repeat as needed. Verify follows literal imports automatically. |
| `--place fixture.rbxlx` | Existing Studio fixture that contains the mounted entry. Without it, the command builds an isolated floor and spawn fixture. |
| `--base-place place.rbxlx` | Merge the mounted modules and entry scripts into a copy of this XML place. Do not combine it with `--place`. |
| `--context Server\|Client` | Studio execution side. Defaults to Server. |
| `--players count` | Studio server with 1 to 8 clients. |
| `--client file`, `--server file` | Portable bootstrap modules that return functions. Verify mounts and calls them automatically. |
| `--capture` | Durable final Studio view. Single-client runs only. |
| `--require-media type` | Require a saved artifact with this exact MIME type for each returned case. |
| `--place-id number` | Published Player or Open Cloud place. |
| `--cloud module.luau` | Open Cloud: caller module that returns `{ request, authorize }`. |
| `--universe-id id`, `--place-version n` | Open Cloud universe and exact place version. |

Exit zero means that the report is nonempty and every selected case passed.
Skips, unsupported requirements, timeouts, partial reports and failed cleanup exit nonzero.
A selected pass is not whole-project acceptance.

Studio platform runs collect `MessageError` and `MessageWarning` entries from the server and every joined client.
Each case drains the collectors after its other cleanup and attaches `engine.log`, including actor and any source path and line supplied by Roblox.
An unexpected error fails the case; warnings remain evidence. An entry factory can declare `expectedErrors = { [caseId] = { "literal error text" } }`.
Only errors containing a declared literal are expected. Other errors still fail, including errors during cleanup.
Engine sources rooted at `CorePackages`, `CoreGui`, `ScriptContext` and `Script Context` are filtered, including bracketed Logger prefixes; matching words in an application message are retained.
Collectors start before Play in launched fixtures and replay available log history when connecting, so startup crashes reach the first executed case.
Attached runs connect in Play and include the available history of that Play session. Roblox bounds that history; earlier entries may already be gone.
A plain warning may carry no location. Verify retains the message and does not invent a source or line.
Failure to install or drain a collector fails the run or case. A fake-host pass proves no native log delivery.

To probe structured logging on an already open Studio, run this in Edit:

```sh
lute run tools/logservice-spike.luau <studio-id> install
```

Start Play yourself, wait five seconds, and run:

```sh
lute run tools/logservice-spike.luau <studio-id> read
```

The read probes four contexts: Server and Client scripts installed before Play, and plugin commands in Server and Client. `roundTrips` records whether each Logger method preserves context through `MessageOut` and `GetLogHistory`; the raw dictionaries remain in the output.
`Error` can throw even when it emits successfully, so its call failure alone does not disprove delivery.
Stop Play yourself afterward. Remove `VerifyLogSpike` from ReplicatedStorage and the two `VerifyLogSpikeServer` and `VerifyLogSpikeClient` scripts before reinstalling.
Studio 0.743.0.7431133 on Windows preserved the token, side, sequence and nested payload through both MessageOut and GetLogHistory for Info, Warn, Error, Output and Log in all four contexts. The server flood retained the newest 512 entries in ascending order. Progress uses Logger contexts.

Each run keeps `report.json`, `summary.txt` and the available artifacts together.
Simulator output is in `host.log`. Studio process and MCP diagnostics are below `studio/`.
A failed native launch keeps its diagnostics.

Captures keep case, actor and checkpoint identity.
Verify lists these as missing durable evidence: temporary Roblox URIs, remote links, missing files and empty files.
They do not satisfy media requirements.
A final Studio image proves only the final view. It does not prove an earlier checkpoint or visual quality.

For programmatic use, `Lute.platform.run(options)` returns `{ report, directory, reportPath }`.
It accepts the corresponding typed options and `requiredEvidence`.
`requiredEvidence` is a list of `{ caseId, actor?, checkpoint?, mediaType }`.
Require each actor separately when a multiplayer claim needs both views.
Missing required evidence adds a failed case to the same report.
`Lute.evidence.write` and `Lute.evidence.finish` persist reports from custom hosts with the same rules.

## Watch a run

`Lute.platform.run` accepts `progressFile` and `onProgress` for the simulator and Studio hosts.
The run appends one JSON line per step event to `progressFile`. If you give only `onProgress`, the file is `<output>/progress.jsonl`.
An event is `{ runId, sequence, actor, caseId, step, phase, status? }`. `phase` is `started` or `finished`.
`sequence` rises by one in each run. A step with no actor reports the actor `case`.
A watchdog process reads the file. A `started` event with no `finished` event names the actor and step that is still running.
A file with no new line for too long means a stalled run.
A launched Studio run reads Logger history on every poll of the detached run. See [native Studio execution](execution.md#native-studio-execution).
An attached Studio run reports progress the same way. Pass `progressFile` or `onProgress`. See [attached Studio](execution.md#attached-studio).
A Studio run emits each event in the context of the VerifyProgress Logger, with a run token. The host reads GetLogHistory directly through execute_luau, validates the context and run identity, orders events and ignores repeats. Roblox bounds the history; sequence gaps, invalid contexts and failed reads produce `<progressFile>.diagnostics` and a limitation on the first case.
`onProgress` receives the same events in order after the run returns, because a worker process blocks the caller.
A run with no listener and no file behaves as before. The report is the same, and progress never proves a pass.

## Attachments

A case can attach text with `context:attach(name, mediaType, text)`.
`Lute.platform.run` writes each attachment to `<output>/attachments/<case id>/<name>` and replaces it in the report with an artifact entry that has `size` and `sha256`.
Pass `attachmentSink` to store it elsewhere, and `attachments = { maxBytes?, maxCount?, maxTotalBytes? }` to change the limits.
The simulator and the launched and attached Studio hosts support attachments. Player and Open Cloud runs fail the case `verify:attachments`.
The [attachment example](../examples/attachments.luau) shows the result. See [inline attachments](api.md#inline-attachments).

## Gates and benchmarks

```sh
lute run examples/gate.luau [producer-id ...]
lute run examples/benchmark.luau
```

[The gate example](../examples/gate.luau) runs build, test-module, benchmark and deferred native producers as one plan.
It prints the verdict. If you name producer IDs, it runs only those and prints `selected`.
See [declarative gates](execution.md#declarative-gates) and [benchmarks](experience.md#benchmarks).

## Repository gate

`tools/gate.luau` is the one command that checks this repository.
It runs the static checks, the specs in `tests`, the examples and the boundary checks.
The spec corpus runs through the `specs` producer of kind `tests`.

```sh
lute run tools/gate.luau [--native] [--only producer]... [--tier name]... [--case id]... [--file spec]... [--name text] [--rerun] [--explain id] [--list]
```

| Goal | Command |
| --- | --- |
| Run the whole gate | `lute run tools/gate.luau` |
| Run one spec file | `lute run tools/gate.luau --file tests/shape.verify.luau` |
| Run one case | `lute run tools/gate.luau --only specs --case "<case id>"` |
| Run the cases whose name contains a text | `lute run tools/gate.luau --only specs --name "door"` |
| Run one tier (`static` or `behavior`) | `lute run tools/gate.luau --tier behavior` |
| Run one producer | `lute run tools/gate.luau --only lint` |
| Repeat what the last run did not pass | `lute run tools/gate.luau --rerun` |
| Explain why a producer or case ran, failed or was skipped | `lute run tools/gate.luau --explain specs` |
| List the producers | `lute run tools/gate.luau --list` |
| Include the native Studio checks | `lute run tools/gate.luau --native` |

A case ID has the form `<spec file>::<suite> > <case>`.
`--file` takes a spec file and selects its producer.
`--name` matches a plain substring of the case name. A name that matches no case fails the run.
A narrowed run prints `NARROWED`. It is not the gate.
Deferred native producers need `--native` and the reference Studio host.
`--rerun` and `--explain` read the last outcome of the same producer set.
After a `--file` run, the producer set changes. Use the same `--file` again.

## Gate command line

`Lute.gate.cli(draft, args, options?)` is the command line of `tools/gate.luau`. It defines the gate, runs it and returns the exit code.
`args` holds the flags without the script name. The output is the output of `tools/gate.luau`.

A consumer gate script defines the gate and calls the command line:

```luau
local Lute = require "../src/lute"
local process = require "@std/process"

local flags: { string } = {}
for index = 2, #process.args do
    table.insert(flags, process.args[index])
end
local code = Lute.gate.cli(myGateDraft, flags, { options = { directory = ".lute/tmp/gate" } })
if code ~= 0 then
    process.exit(code)
end
```

| Flag | Meaning |
| --- | --- |
| `--only producer` | Select a producer. Repeat to select several. |
| `--file spec` | Keep only this spec file in each `tests` producer. Repeat to keep several. An unknown file exits with 2. The declared `cases` census and the `silent` list keep only the entries of the kept files. |
| `--case id` | Select an exact case. |
| `--name text` | Select the cases whose name contains the text. |
| `--tier name` | Select a tier. |
| `--rerun` | Repeat what the last run did not pass. |
| `--explain id` | Explain the last run for a producer or case. |
| `--list` | List the producers. |

`options.options` is the `Lute.gate.run` options. `options.usage` replaces the usage line.
The exit code is 0 for a pass, a narrowed pass or a deferral, 1 for a failed gate or a missing earlier outcome and 2 for a bad flag.
The command line adds no flag. A script handles its own flags, such as `--native`, before it calls the function.

## Multiplayer

```sh
lute run examples/multiplayer.luau simulator
lute run examples/multiplayer.luau studio
```

These commands run [one case](../examples/multiplayer/case.luau).
The case clicks in the first client, observes the server, then observes the second client.
The simulator supplies explicit application fakes. Studio uses two actual clients, virtual input and replication.
Both hosts use the same context operations and verdicts.

Simulation supplies no native input, rendering, physics or replication proof.
Native per-client `CaptureService` references stay temporary.
This example claims no retained screenshots and no visual judgment.
Supply a durable capture adapter and actor-specific requirements when you need them.

## Published Player

Build an isolated test fixture once with `Lute.platform.buildPublished`:

```luau
Lute.platform.buildPublished {
    output = testPlacePath,
    entry = "examples/platform-entry.luau",
    authorizedUserIds = testAccountIds,
    context = "Server",
}
```

Publish that file to your test experience with your authorized publishing workflow. Then run:

```sh
lute run tools/run.luau --entry examples/platform-entry.luau --host player --place-id YOUR_TEST_PLACE_ID
```

The generated bootstrap authorizes the actual player on the server.
It validates the requested entry and selection from the join data.
It permits one run per player connection.
With `context = "Client"`, the entry runs on the authorized client. By default it runs on the server.
Both contexts print the standard framed report in the owning client.

Keep test account IDs in consumer configuration.
The fixture does not grant access to the experience and does not change publication settings.
Launch data identifies a run. It grants no authority.

The [reference Player launcher](execution.md#published-player-execution) uses the signed-in account.
It supports one client per machine and needs an otherwise closed Player.
Publishing stays explicit. After you change the mounted source, rebuild the fixture and publish again.
A Player run uses the published code, not files that changed locally afterward.

## Open Cloud

```sh
lute run tools/run.luau --entry examples/platform-entry.luau --host open-cloud \
  --cloud examples/open-cloud-transport.luau --universe-id U --place-id P --place-version V
```

The caller module owns credentials and policy.
The example reads one key from its process environment and allows only the Open Cloud origin.
Verify never reads credentials.
`--case` and `--deadline` behave as for other hosts. The deadline bounds polling.
The published place version must already contain the mounted framework and entry.
The report, exit status and evidence are the ordinary ones.
The command prints the task path, delivery, state and measured timing.
A timeout prints the task path and does not cancel the task.
Reconcile a timed-out task with `session.reconcile(handle)`. Do not submit it again.
See [Open Cloud execution](execution.md#open-cloud-execution) for guarantees and limits.

## Launch or attach

By default, `--host studio` launches a disposable Studio on a copy of an XML place and closes it.
A programmatic caller that needs several engine calls in one disposable Studio uses `Lute.studio.launch`. See [launched Studio session](execution.md#launched-studio-session).
A programmatic caller can pass `attach` to `Lute.platform.run` with `host = "studio"`.
The run then uses a Studio that is already open:

```luau
Lute.platform.run {
	host = "studio",
	entry = "examples/platform-entry.luau",
	context = "Client",
	attach = {
		studioId = openStudioId,
		authorize = function(request) return { ok = true } end,
	},
}
```

Attach shares the developer's open Studio. It gives no isolation, rejects `players` and builds or copies no place.
The caller owns these decisions:

- The `authorize` hook, which sees every request before Verify sends it.
- Which place is open.
- Whether the entry is mounted in that place.

A Studio run is detached and its report returns in segments. A long run or a large report does not reach a request limit of the Studio MCP server. Only `deadlineSeconds` bounds the run.
Verify starts play, runs, captures if you ask and returns the Studio to its prior mode.
Verify never closes the Studio. The command line does not attach.
See [attached Studio](execution.md#attached-studio).

## Mounting and custom hosts

`Lute.place.build({ output, roots, modules?, clientSource?, serverSource?, rootName? })` builds an XML fixture with a floor and a spawn.
It follows literal relative imports and `@self` imports, mounts the dependency closure and rejects dynamic and external imports.
It resolves them as Luau does. An ordinary file `a/b.luau` resolves `./c` as `a/c`, `../c` as `c` and `@self/c` as `a/b/c`.
An `init.luau` stands for its directory. In `a/b/init.luau`, `./c` is `a/c`, `../c` is the sibling of `a` and `@self/c` is `a/b/c`.
It does not compile arbitrary package systems and does not replace the place build of an application.
Use `moduleExpression(path, rootName?)` to reference a mounted module.

`basePlace` merges into an existing place instead of building a floor.
`Lute.place.build({ output, basePlace, roots, modules?, clientSource?, serverSource?, rootName? })` copies the base file to `output`.
It adds the module tree as `ReplicatedStorage.<rootName>`, `VerifyClient` in `StarterPlayerScripts` and `VerifyServer` in `ServerScriptService`.
It adds a missing service and leaves every other instance of the base untouched. It never edits the base file.
It fails when the base already holds an instance with the module root name or with a script name that it adds.
It reads and writes XML only. A binary `.rbxl` base fails with a message. Save the base as `.rbxlx` first.
The merge scans `Item` tags. It does not parse the other XML. `Lute.platform.run({ basePlace })` uses it and the option `place` keeps its meaning.

For an existing place fixture, mount under `ReplicatedStorage.VerifyModules`.
You can also use the lower-level [Studio host](execution.md#native-studio-execution) with your own bootstrap.
Lower-level workers and hosts support custom discovery, scheduling and launch environments.
They produce the same cases and reports.

## Platform support

The portable layers assume no operating system. They are core, gate, evidence, benchmark and the simulator.
The Lute layer supports macOS, Linux and Windows. The mechanism that bounds a process differs by platform:

| Platform | Mechanism | Capabilities |
| --- | --- | --- |
| macOS, Linux | `sh` from `PATH` puts the command in a process group and kills the group at the limit. It needs one way to create the group: shell job control, `setsid` or `perl`. A dash shell without a terminal has no job control. | `posix-process-groups`, `process-tree-kill` |
| Windows | A Lute watchdog runs the command under a reporter process and kills the tree of the reporter with `taskkill /T /F` at the limit. | `process-tree-kill` |

Gate commands and worker hosts run bounded.
A run that cannot create its group or start its watchdog does not start the command. It returns `unsupported = true`.
Require `process-tree-kill` when a case must run on every platform.
On Windows, a descendant whose parent exited before the limit is not in the tree, so `taskkill` cannot find it.
The watchdog does not wait for such a descendant, so the limit still holds.
A command that reaches the limit on Windows returns no output.

The Studio launcher and the attached Studio support macOS and Windows.
On Windows, Verify finds Studio in the newest directory under `%LOCALAPPDATA%/Roblox/Versions` that holds `RobloxStudioBeta.exe`.
It drives the standard input of the Studio MCP server through a Windows PowerShell bridge, because Windows has no `mkfifo` and Lute cannot write to the standard input of a running process.
It lists processes with `Get-CimInstance Win32_Process` and stops them with `taskkill`.
On Windows 11 the native conformance check and the native multiplayer check passed, and `Lute.studio.launch` started, drove and stopped a Studio.

The reference Player launcher supports macOS only.
On Windows, one launch starts more than one Player process, and no open-file query binds the report log to one process.
`--host player` then reports the case `verify:execution` as `unsupported` with the missing capability `roblox-player-launcher`.
`Lute.player.run` accepts a `backend` for another platform.

These defaults depend on the platform:

| Default | macOS | Windows | Override |
| --- | --- | --- | --- |
| Studio executable | `/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio` | `RobloxStudioBeta.exe` in the newest Studio version directory | `studioExecutable` |
| Studio MCP executable | `/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP` | `StudioMCP.exe` in the same directory | `mcpExecutable` |
| Player launcher | `/Applications/Roblox.app`, `/usr/bin/open`, `/usr/bin/pgrep`, `/bin/ps`, `/usr/sbin/lsof` | None | `backend` |
| Run directories | `/tmp/verify-studio`, `/tmp/verify-studio-attach`, `/tmp/verify-studio-launch` | `verify-studio`, `verify-studio-attach` and `verify-studio-launch` in the system temporary directory | `directory` |
