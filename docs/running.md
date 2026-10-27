# Run cases

Start with `lute run tools/run.luau --entry examples/platform-entry.luau`. Each host runs the same named cases and returns the same report format.

## Hosts

Select a host that can observe the required behavior. A pass proves only the observations that the host can make.

| Host | Selection | Requirements and limits |
| --- | --- | --- |
| Simulator | `--host simulator`, the default | Needs Lute. Checks the declared simulation. Proves no native rendering, physics, replication or input. |
| Lute worker | `Lute.host` | Runs one process per batch. See [workers](execution.md#lute-workers). |
| Launched Studio | `--host studio` | Needs installed, authenticated Studio and MCP tools. Uses a place copy. Supports 1 to 8 clients. |
| Attached Studio | `Lute.platform.run` with `attach` | Needs an open Studio and `authorize`. Shares its state. Rejects `players`. The CLI cannot attach. |
| Player | `--host player` | Needs a published test place and a closed Player. The reference launcher supports macOS and one client per machine. |
| Open Cloud | `--host open-cloud` | Needs caller functions for `request` and `authorize`. Runs server code on an exact published version. Has no input, physics, replication, rendering, audio or capture. |

A capability describes a host operation. It grants no permission. A missing required capability gives `unsupported`. See [host execution](execution.md#native-studio-execution) for Studio details.

## Run a case

Use a working directory that contains Verify and the test modules. Lute cannot load test modules outside its loading root. Use the common parent directory. Paths are relative to the working directory.

```sh
lute run tools/run.luau --entry examples/platform-entry.luau
lute run tools/run.luau --entry examples/platform-entry.luau --host studio --capture
lute run tools/run.luau --entry examples/platform-entry.luau --case instance-state
```

The [entry factory](../examples/platform-entry.luau) receives the host name and returns `{ cases, options, now }`. The host name is `simulator`, `studio` or `player`. Open Cloud uses the Studio binding. Studio and Open Cloud also give the full run ID as a second argument. Other hosts give nil. `cases` contains `Core.NamedCase` values with unique explicit IDs. `options` is `Core.RunOptions`. `now` is the clock. Use `options.bind` for resources that the harness must release after each case.

Studio sets `ReplicatedStorage.VerifyRun` to a short token from the run ID. Attribute strings have a 50-character limit. A multiplayer server sets the token before the entry runs. Clients receive it through replication. The server entry also receives the full run ID.

`Core.runCases(cases, options, now, ids?)` validates the collection and selection before execution. Unknown IDs, duplicate IDs and empty selections fail. Without `ids`, all cases run. Do not also set `options.selection`. Give each case a finite timeout and its required capabilities. Reports record the selection mode and available case count.

## Commands and evidence

| Option | Meaning |
| --- | --- |
| `--entry module.luau` | Required portable factory module. |
| `--host simulator\|studio\|player\|open-cloud` | Host. Default: simulator. |
| `--case id` | Exact case ID. Repeat for several IDs. |
| `--deadline seconds` | Host budget. Default: 90. Excludes preparation. |
| `--output directory` | Parent of unique evidence directories. Default: `.verify`. |
| `--framework directory` | Verify checkout. Default: inferred from this command. |
| `--root directory` | Extra mounted module directory. Repeat as necessary. Literal imports are followed automatically. |
| `--place file` | Binary `.rbxl` or XML `.rbxlx` Studio fixture with the mounted entry. Without it, Verify builds a floor and spawn. |
| `--base-place file.rbxlx` | Merge modules and entry scripts into a copy of this XML place. Do not combine with `--place`. |
| `--context Server\|Client` | Studio execution side. Default: Server. |
| `--players count` | Studio server with 1 to 8 clients. |
| `--client file`, `--server file` | Portable bootstrap modules that return functions. Verify mounts and calls them. |
| `--capture` | Save the final Studio view. Supports one client only. |
| `--require-media type` | Require a saved artifact with this exact MIME type for each returned case. |
| `--place-id number` | Published Player or Open Cloud place. |
| `--cloud module.luau` | Open Cloud module that returns `{ request, authorize }`. |
| `--universe-id id`, `--place-version n` | Open Cloud universe and exact place version. |

Exit zero requires a nonempty report in which every selected case passed. Skips, unsupported requirements, timeouts, partial reports and cleanup failures give a nonzero exit. A selected pass does not prove acceptance of the whole project.

Each run saves `report.json`, `summary.txt` and available artifacts together. Simulator output is in `host.log`. Studio diagnostics are under `studio/`, including after a failed launch. Captures keep their case, actor and checkpoint IDs. Temporary Roblox URIs, remote links, missing files and empty files do not satisfy durable media requirements. A final image proves only the final view. It does not prove an earlier checkpoint or visual quality.

`Lute.platform.run(options)` returns `{ report, directory, reportPath }`. `requiredEvidence` accepts `{ caseId, actor?, checkpoint?, mediaType }` entries. Require each actor separately when a claim needs both views. Missing evidence adds a failed case. Custom hosts can use `Lute.evidence.write` and `Lute.evidence.finish` with the same rules.

### Engine logs

Studio runs collect `MessageError` and `MessageWarning` from the server and every joined client. After other cleanup, each case drains the collectors into `engine.log`. Logs include the actor and any source path and line that Roblox gives. Unexpected errors fail the case. Warnings remain evidence. An entry factory can set `expectedErrors = { [caseId] = { "literal error text" } }`. Only errors that contain a declared literal are expected. Other errors fail, including cleanup errors.

Collectors exclude engine sources rooted at `CorePackages`, `CoreGui`, `ScriptContext` and `Script Context`. This includes bracketed Logger prefixes. Matching words in an application message remain. Launched fixtures install collectors before Play. They replay available history so the first case receives startup crashes. Attached runs connect in Play and include available session history. Roblox can discard earlier history. A warning without a source stays without a source. Collector installation or drain failures fail the run or case. A simulated-host pass does not prove native log delivery.

To inspect structured logging in an open Studio:

1. In Edit, run `lute run tools/logservice-spike.luau <studio-id> install`.
2. Start Play.
3. Wait five seconds.
4. Run `lute run tools/logservice-spike.luau <studio-id> read`.
5. Stop Play.
6. Before another installation, remove `VerifyLogSpike` from ReplicatedStorage.
7. Remove `VerifyLogSpikeServer` and `VerifyLogSpikeClient`.

The probe tests Server and Client scripts, plus Server and Client plugin commands. `roundTrips` records Logger context delivery through `MessageOut` and `GetLogHistory`. Output keeps the raw dictionaries. `Error` can throw after it emits. A thrown call alone does not prove failed delivery. Studio 0.743.0.7431133 on Windows kept the token, side, sequence and nested payload in all four contexts. This applied to Info, Warn, Error, Output and Log through both channels. A server flood kept the newest 512 entries in ascending order. Progress uses these Logger contexts.

## Watch a run

For the simulator or Studio, give `Lute.platform.run` a `progressFile` or `onProgress`. With only `onProgress`, the file is `<output>/progress.jsonl`. Each line is `{ runId, sequence, actor, caseId, step, phase, status? }`. `phase` is `started` or `finished`. Sequence numbers increase in each run. The default actor is `case`. A started step without a finish identifies work still in progress. A file without new lines can indicate a stalled run.

Studio reads newer VerifyProgress Logger events for the run token during detached polling. It validates context and run identity, orders events and removes repeats. `Roblox.progressChannel.readPage(token, afterSequence)` creates a page read. A response must fit within 32 KiB. Larger events fail. Sequence gaps, invalid contexts and read failures add `<progressFile>.diagnostics` and a first-case limitation. The attached host also uses this process. See [native execution](execution.md#native-studio-execution) and [attach](execution.md#attached-studio). `onProgress` receives the events in order after the worker returns. The worker blocks the caller. Progress does not prove a pass. Without a listener or file, the report stays the same.

## Attachments

Use `context:attach(name, mediaType, text)` to attach text. `Lute.platform.run` writes it to `<output>/attachments/<case id>/<name>`. It replaces inline content with an artifact that contains `size` and `sha256`. Give `attachmentSink` to change storage. Give `attachments = { maxBytes?, maxCount?, maxTotalBytes? }` to change limits. The simulator and both Studio modes support attachments. Player and Open Cloud fail `verify:attachments`. See the [example](../examples/attachments.luau) and [attachment contract](api.md#inline-attachments).

## Gates and benchmarks

Run `lute run examples/gate.luau` for a combined gate. Append producer IDs to select work. A selected run prints `selected`. Run `lute run examples/benchmark.luau` for a benchmark case. See [gates](execution.md#declarative-gates) and [benchmarks](experience.md#benchmarks).

## Repository gate

`tools/gate.luau` checks this repository. It runs static checks, the `tests/manifest.luau` corpus, examples and boundary checks. The full gate needs a clean committed HEAD. It checks a fresh clone of that HEAD. After a specification is added or removed, run `lute run tools/check-test-manifest.luau --write`. The `specs` producer runs the shared corpus. The `memory` producer runs heap checks in isolation. Verify uses first-party source and `rokit.toml`. It needs no `dependencies.lock.luau`.

```sh
lute run tools/gate.luau --tier fast
```

The fast tier selects `static` and `behavior`. It accepts an uncommitted tree and excludes fresh-clone and native checks. Run `lute run tools/gate.luau` for the full portable gate. Add `--native` to include Studio checks on the reference host.

## Gate command line

`Lute.gate.cli(draft, args, options?)` defines and runs a gate. It returns an exit code. Give flags without the script name. A script must handle its own flags, such as `--native`, before this call. `options.options` contains `Lute.gate.run` options. `options.usage` replaces the usage line.

| Flag | Action |
| --- | --- |
| `--only producer` | Select a producer. Repeat for several producers. |
| `--file spec` | Keep this file in each tests producer. Repeat for several files. Unknown files exit 2. Case census and silent entries follow the selection. |
| `--case id` | Select an exact case ID. |
| `--name text` | Select names that contain this plain text. No match fails. |
| `--tier name` | Select a tier. Repeat for several tiers. |
| `--rerun` | Repeat work that the last run did not pass. |
| `--explain id` | Explain the last outcome for a producer or case. |
| `--list` | List producers. |
| `--shard index/count` | Run one shard. Dependencies stay together. Each producer and spec file belongs to one shard. An empty shard exits zero. |
| `--weights path` | Balance shards with measured seconds. Unknown work uses the median weight. |
| `--record-weights path` | Save times for passed producers and spec files. Keep earlier values that this run did not measure. |

A case ID has the form `<spec file>::<suite> > <case>`. A narrowed run prints `NARROWED`. It does not prove the complete gate. Rerun and explain use the last outcome of the same producer set. After `--file`, use the same file selection again. Native producers remain deferred without `--native` and the reference Studio host. Exit codes are 0 for pass, narrowed pass or deferral; 1 for failure or missing earlier outcome; 2 for invalid flags.

To divide a gate across N machines, run shards `1/N` through `N/N` with the same weights file. Every shard must pass. Refresh weights from a recent complete run with `--record-weights`.

## Multiplayer

Run `lute run examples/multiplayer.luau simulator` or `lute run examples/multiplayer.luau studio`. The [same case](../examples/multiplayer/case.luau) clicks in client one, observes the server, then observes client two. The simulator uses explicit application fakes. Studio uses two clients, virtual input and replication. Simulation does not prove native input, rendering, physics or replication. Native CaptureService references are temporary. This example claims no retained screenshots or visual judgment. Give a durable capture adapter and separate actor requirements when necessary.

## Published Player

Build a test fixture with `Lute.platform.buildPublished`. Give `{ output, entry, authorizedUserIds, context = "Server" | "Client" }`. Publish that output through the publishing workflow that you authorize. Run `lute run tools/run.luau --entry examples/platform-entry.luau --host player --place-id YOUR_TEST_PLACE_ID`.

The server authorizes the actual player. It validates entry and selection from join data and permits one run per connection. `Client` runs the entry on that client. The default is `Server`. Both modes print the framed report in the owning client. Keep account IDs in consumer configuration. Launch data grants no authority or experience access. After mounted source changes, rebuild and publish again. Player uses published code. See [Player execution](execution.md#published-player-execution).

## Open Cloud

```sh
lute run tools/run.luau --entry examples/platform-entry.luau --host open-cloud \
  --cloud examples/open-cloud-transport.luau --universe-id U --place-id P --place-version V
```

The caller module owns credentials and policy. The example reads a process key and permits only the Open Cloud origin. Verify does not read credentials. The published version must contain the framework and entry. `--case` selects work. `--deadline` bounds polling. Output includes task path, delivery, state and measured times. A timeout does not cancel the task. Use `session.reconcile(handle)` to poll it again. Do not submit it again. See [Open Cloud execution](execution.md#open-cloud-execution).

## Launch or attach

`--host studio` launches a disposable Studio on a place copy. Use `Lute.studio.launch` for several engine calls in one disposable Studio. Give `attach` to `Lute.platform.run({ host = "studio", ... })` to use an open Studio. Attach needs a `studioId` and `authorize` hook. The caller controls the open place and mounted entry. Attach has no isolation, builds no place and rejects `players`. It returns Studio to its previous mode and never closes it. The CLI does not attach. See [attached Studio](execution.md#attached-studio) and [launched sessions](execution.md#launched-studio-session).

## Mounting and custom hosts

Use `Lute.place.bundle({ roots, modules?, rootName? })` for an XML module tree. Use `Lute.place.build({ output, roots, modules?, clientSource?, serverSource?, rootName?, basePlace? })` for a fixture. The builder follows literal relative and `@self` imports. Dynamic and external imports fail. A bundle installs no instances and starts no Studio. The caller must give any required client bootstrap. See [place mounting](api.md#host-adapters) for host APIs and the builder types in [source](../src/lute/place.luau).

An ordinary `a/b.luau` resolves `./c` to `a/c`, `../c` to `c` and `@self/c` to `a/b/c`. In `a/b/init.luau`, `./c` resolves to `a/c`, `../c` to a sibling of `a`, and `@self/c` to `a/b/c`. This builder does not compile arbitrary package systems or replace application builds. `moduleExpression(path, rootName?)` references a mounted module. Existing fixtures normally use `ReplicatedStorage.VerifyModules`.

With `basePlace`, Verify copies the XML base to output and adds the module root and entry scripts. The root is in ReplicatedStorage. VerifyClient is in StarterPlayerScripts. VerifyServer is in ServerScriptService. It adds missing services and preserves other instances. It never changes the base file. Existing names that conflict with new roots or scripts fail. Binary bases fail. Save them as `.rbxlx` first. The merge scans Item tags and does not parse other XML. `Lute.platform.run({ basePlace })` uses this merge. The `place` option keeps its existing meaning. Lower-level hosts and workers support custom discovery and launch systems.

## Platform support

Core, gate, evidence, benchmark and simulator layers assume no operating system. The Lute layer supports macOS, Linux and Windows.

| Platform | Process bound | Capability |
| --- | --- | --- |
| macOS, Linux | `sh` creates and kills a process group. It needs job control, `setsid` or `perl`. Dash without a terminal has no job control. | `posix-process-groups`, `process-tree-kill` |
| Windows | A Lute watchdog starts a reporter and kills its tree with `taskkill /T /F`. | `process-tree-kill` |

Gate commands and workers use these bounds. A missing group or watchdog gives `unsupported = true` before the command starts. Require `process-tree-kill` for work that must run on all platforms. On Windows, taskkill cannot find descendants whose parents already exited. The watchdog does not wait for those descendants. A timed-out Windows command returns no output.

Studio launch and attach support macOS and Windows. On Windows, the newest `%LOCALAPPDATA%/Roblox/Versions` directory with `RobloxStudioBeta.exe` determines the Studio path. StudioMCP.exe is in that directory. A PowerShell bridge writes to MCP standard input. Verify lists processes with `Get-CimInstance Win32_Process` and stops them with `taskkill`. Windows 11 native conformance, multiplayer and launched-session checks have passed on the reference host.

The reference Player launcher supports macOS only. Windows launches several processes without a reliable log-to-process binding. Windows Player reports `verify:execution` as unsupported, with missing `roblox-player-launcher`. Give `Lute.player.run` a `backend` to support another platform.

| Default | macOS | Windows | Override |
| --- | --- | --- | --- |
| Studio | `/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio` | Newest Studio version executable | `studioExecutable` |
| Studio MCP | `/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP` | StudioMCP.exe beside Studio | `mcpExecutable` |
| Player | Roblox.app, `open`, `pgrep`, `ps`, `lsof` | No reference backend | `backend` |
| Run directories | `/tmp/verify-studio`, `/tmp/verify-studio-attach`, `/tmp/verify-studio-launch` | Same directory names under the system temporary root | `directory` |

## Capture native text metrics

Run `lute run tools/capture-text-metrics.luau <out.json> <font-family> [weight] [style]` with a native Studio host. Give a full family URL, such as `rbxasset://fonts/families/BuilderSans.json`. The command records supported sizes and checks unseen text against the native service. It writes `<out.json>.report.json`. It writes font facts only when comparisons pass. Keep font sources out of `src/lute/fixtures/text`. The default fixture reads committed facts there. The native gate compares each face with the current service and runs shared text layout assertions. These checks cover only the declared text grammar and layout cases.

The capture measures `pixelScale` from the smallest positive token width at size 1. It converts native widths to raster pixels before it computes advances, pair adjustments and boundary corrections. The model rounds the raster width up, multiplies by `pixelScale` and returns a float32 value. Earlier facts without `pixelScale` use 1. Each size keeps its measured native line height. Validation compares the returned width with the original native value, with no tolerance. A failed comparison leaves the report and its complete attachment manifest; it does not write font facts.
