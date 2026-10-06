# Execution contract

A plan is a finite set of units, declared capabilities and policy. Verify executes the plan.
The consumer defines each locator and supplies the authorized host.

`Core.validatePlan(draft)` normalizes IDs, locators, groups, tags, requirements, weights and policy.
Duplicate IDs, duplicate locators and malformed fields fail.

- `selectPlan` narrows a plan by IDs, tags, capabilities, groups or a predicate.
  The predicate sees the same source-bearing subject that harness and session selection use.
- `partitionPlan(plan, count, mode?)` assigns every unit once and keeps fixture groups whole.
  Count batching and weighted batching are deterministic functions of the authored metadata.
- `planDigest` binds the meaning of a plan, not its timing.
- `caseId` composes stable IDs.
- `planFromManifest` accepts a manifest that you validated explicitly. `validateManifest` is the input boundary.

All selection and partitioning use the plan.
Consumers own discovery and changed-file reachability. Verify has no second scheduler.

## Host boundary

`Core.execute(plan, host, options?)` drives these steps:

- Capability negotiation.
- Fixture setup and cleanup.
- Batching.
- Run deadlines.
- Failure accounting and report composition.

A host supplies `runBatch`. Optional parallel dispatch and artifact routing keep the same report semantics.
A batch outcome is `returned`, `faulted`, `timed_out` or `cancelled`. Only a returned valid report carries verdicts.
The host must stop timed-out and cancelled work and account for every dispatched batch.
A clean exit without the expected receipt is a fault.

`execute` derives completeness from the original plan.
Narrowing, missing results, infrastructure faults and contradictory retries stay explicit facts.
A narrowed pass is not the complete gate.

Retries apply only to declared infrastructure outcomes. The report retains every attempt.
Verify never retries an ordinary assertion failure to obtain a pass.
Fixture and cleanup failures stay visible independently.
Artifact sinks return references. A reference is not proof of durability or authenticity.

`src/core` exports the types `Host`, `BatchOutcome`, `ExecutionOptions`, `PlanPolicy` and `ExecutionReport`.
[Behavioral tests](../tests/execution.spec.luau) exercise dropped, reordered, duplicate, forged and disagreeing deliveries with the injected fake host.

## Case lifecycle and waits

Every host uses the [ordinary harness context](experience.md#one-case-model).

1. Acquire actors and resources in `bind(context)`.
2. Register cleanup with `context:defer` before each fallible acquisition.
3. Perform readiness queries with `context:await`.
4. Put actions, assertions and checkpoints in the case.

The harness retains body failures and cleanup failures independently.
Verify has no separate lifecycle, actor runner or transcript verdict model.

These host utilities are not alternative case formats:

- `Core.waitUntil` is the standalone read-only polling primitive.
- `Lute.runBounded(argv, seconds)` enforces an external process-group deadline.
- `Lute.directoryLock(root)` provides cross-process resource ownership.

`Core.accountPlan(plan, execution)` reports what ran, the unsupported units and completeness.
`Core.mediaProbeSummary`, `mediaAudioWindow`, `mediaAudioMeasurement` and `mediaSampleCommands` decode media measurements.
Decoding alone provides no visual or audible judgment.

## Lute workers

`Lute.host({worker, command?, directory, capabilities?, arguments?, ...})` starts one process per batch.
The host appends `arguments` after a `--` that follows the run ID.
`Lute.workerArguments()` returns them with the run ID and with the selection that the worker derives from `--case=`, `--tag=`, `--tier=`, `--name=` (a case-name substring) and `--source=`.

The batch deadline or the host `deadlineSeconds` (default 60) bounds the worker process group.
Use a separate directory for each concurrent run. The batch inputs and reports stay available for failure diagnosis.
The consumer isolates its own output files.

Two worker styles exist:

- `worker` loads a registration function that each module returns.
- `selfRegisteringWorker` calls `load(locator, harness)`. An existing BDD surface can then register against the private harness of each unit.

Both styles use the same session and failure classifier. Importing them creates no global registry.
[The self-registering example](../examples/self-registering-worker.luau) shows the caller seam.

`runWorkerBatch` and `runSelfRegisteringWorkerBatch` expose that lifecycle for injected execution.
An explicit `classifyLoadFailure` can name a recognized prerequisite as skipped or unsupported.
An unrecognized or throwing classifier leaves a hard failure.
A successful load followed by a broken registration is a failure.
Every missing source stays a named case.

`Lute.corpus` supplies these parts:

- Injected discovery rules and require-affinity grouping.
  `discover({ listDir, rules, order?, compare? })` accepts `fs.listDirectory` of the runtime directly.
  `order = "sorted"` (default) sorts the final paths. `order = "walk"` keeps the visit order.
  `compare(left, right)` replaces `<` for entry names and for sorted paths.
- Literal subset matching, worker bounds and stable lock text.

A query that matches nothing selects nothing.
The consumer owns filesystem discovery and the committed complete corpus.
A static require scan cannot infer dynamic edges.
`encodeBatch` and `decodeBatch` transport the existing plan-batch schema.

## Lune workers

`Lune.host({worker, command?, directory?, deadlineSeconds?, ...})` from `src/lune` is the Lute host with a different runtime binding.
It starts one real `lune run` process per batch.
It uses the same plan batches, session, load and registration classification and report schema.
`Lune.worker`, `selfRegisteringWorker`, `runWorkerBatch`, `runSelfRegisteringWorkerBatch`, `runBounded`, `encodeBatch` and `decodeBatch` mirror the Lute names.
Run `lune run examples/lune-run.luau` for a consumer run with three batches: a passing unit, a failing unit and a missing unit.

The logic lives once in `src/runtime`, over a `Runtime` binding `{ name, defaultCommand, defaultDirectory, json, fs, process, time, stdio }`.
`src/lute/runtime.luau` and `src/lune/runtime.luau` supply the services. `Binding.validate` refuses an incomplete binding.
A third runtime needs only a binding. The Lute entry points keep the plain-report protocol.

### Receipts

A Lune host defaults to `receipts = "bound"`.

1. The host passes a unique run ID as the third argument of the worker.
2. The worker writes `{ receiptVersion, runId, batchId, report }` to a per-run file.
3. The host returns a report only when all of these conditions hold:
   - The receipt parses and belongs to this run and batch.
   - The receipt decodes as a valid report.
   - The worker exited with zero.

These cases are faults or timeouts, never a pass:

- A missing, malformed, stale (other run), foreign (other batch) or invalid receipt.
- A nonzero exit beside a receipt.
- An unstartable or absent worker.
- Every timeout.

One exception exists.
A worker can exit nonzero beside a valid receipt that records a failed or unsupported load (`unit:<id>:load`).
The host returns that report and does not fault it, because Lune exits with 1 after a module raised at `require`, even inside `pcall`.
Any other nonzero exit beside a receipt stays a fault.

The host keeps the worker output beside the receipt as `*-worker.log` and names it in the fault detail.
`receipts = "report"` is the Lute default. It accepts a plain report and ignores the exit status.
Load, registration and empty-discovery outcomes are ordinary case results and `Core.execute` facts.

### Limits

The batch deadline kills the POSIX process group of the worker, including grandchildren, through `sh`.
Verify creates the group without a terminal. It tries shell job control, then `setsid`, then `perl` `setsid`, and it proves that the group exists before it starts the command.
If no mechanism works, the run does not start the command. It returns `unsupported = true` and `ok = false`, so the capability `posix-process-groups` is never claimed falsely.

- Lune workers run on macOS and Linux only.
- `lune` must be on `PATH` or named in `command`.
- Each worker resolves its own `require` paths relative to its script.
- `@lune/*` services load dynamically, so static analysis does not type them.
- A pass proves Luau logic under Lune. It does not prove Lute, Studio or Player behavior.

The `lune-specs` producer of the [repository gate](running.md#repository-gate) drives real `lune` subprocesses for these claims.

## Declarative gates

`Gate.define({ id, producers, policy? })` declares what a run must produce.
`Lute.gate.run(gate, options?)` and `Lune.gate.run` execute it through `Core.execute`.
The result is one plan and one `Core.Report`. No second scheduler and no second record exist.
Both are bindings over `src/runtime/gate.luau`.
Another host calls `Gate.run(gate, executor, { runId, ... })` with an injected `{ now, wait, start }`.

| Producer | Fields | Runs |
| --- | --- | --- |
| `tests` | `worker`, `locators`, `command?`, `silent?`, `isolate?`, `workers?`, `sourceDeadlineSeconds?`, `args?`, `cases?` | Ordinary spec modules in one [Lute worker](#lute-workers) process. `command` replaces the worker command of the gate, for example `{ "lune", "run" }` for a [Lune worker](#lune-workers). With `isolate`, one worker process runs per locator, `workers` at a time. The gate accounts them as this one producer. |
| `command`, `build`, `native` | `argv`, `env?`, `cwd?`, `exit?`, `report?` | An argument vector in a bounded process group. `env` adds to the inherited environment. `cwd` is set through the runtime binding. No shell wrapper runs. `native` must name its host in `requires`. |
| `benchmark` | `benchmark` or `collection` | A [benchmark](experience.md#benchmarks) or a benchmark collection in this process, alone by default. A producer names one of the two. |

Fields of the `tests` producer:

- `sourceDeadlineSeconds` bounds each isolated source. The producer deadline also bounds it. One hung source times out alone.
- Every locator must report a case unless `silent` names it.
  A silent module can report no case because another module requires it.
  A consumer declares `silent`. Verify never infers it.
- `cases` declares the exact case census. A missing case or an unexpected case fails the producer.
- `args` go to each worker after `--`.
- A load, registration, hang or fault of one isolated source becomes a failed or timed-out case. The case names the locator of that source and counts once.

`Gate.shard(plan, { prefix, worker, count, mode?, silent?, ... })` turns a plan of the consumer into drafts of `tests` producers.
It uses `partitionPlan`, so fixture groups stay whole and weights balance.
It carries the `silent` names that fall in each shard.
With `policy.concurrency`, the shards run in parallel and keep the structure of the plan.

`Gate.testCases(outcome)` returns the execution report without the producer-level case that each `tests` producer adds.
The counts then show only the cases of the modules. It uses the `without` of the report and does not recount.

### Producer and policy fields

Every producer has a unique `id`. It can also set these fields:

- `why`: one line that `Gate.list` and `Gate.explain` show.
- `after`, `tier`, `tags`, `requires` and `exclusive`.
- `deadlineSeconds`. The default is `policy.commandDeadlineSeconds` (300).

Policy sets `concurrency` (default 1), the whole-run `deadlineSeconds`, `failFast`, `deferrals` and `reuse`.

### Run rules

- **Order and concurrency.** Producers start in declaration order after everything that they run `after` has passed.
  No more than `concurrency` producers run at once. An exclusive producer runs alone.
  A producer after one that did not pass is `blocked`.
- **Deadlines.** Each command is bounded as `runBounded` bounds it. Verify kills its process group at the limit, in whole seconds rounded up.
  The run deadline clamps each start. Producers that the deadline prevents from starting are `timed_out`.
- **Exit and reports.**
  - Exit zero passes, unless `exit` maps the code to `passed`, `failed`, `deferred` or `unsupported`.
  - A producer with `report` must also deliver a report from the current run.
    `{report}`, `{run}`, `{tier}` and `{cases}` in `argv` become the report path and the run ID.
  - The command writes `Lute.gate.writeReport(path, run, report)`. It is the `{ runId, report }` envelope that the Roblox report channel uses.
  - Verify deletes any file at the report path before the run.
  - The producer fails for another run ID, an undecodable report, fewer than `report.minimum` cases or a missing `report.cases` entry.
    `report.exact` also rejects a case that `report.cases` does not name.
  - The exit and the report must agree.
  - Adopted cases are named `<producer>:<case>`.
- **Selection.** `{ ids, tiers, tags, cases, nameContains, sources }` narrows the run.
  All given kinds must match. Any listed value of one kind matches.
  - Verify pulls in dependencies and marks them.
  - An unknown or empty selection raises.
  - Anything short of every producer yields the verdict `selected`, never `release`.
  - `outcome.scope` states what ran: `complete`, a `label`, the requested filters, `selected`, `notSelected`, `skippedByTier` (a declared tier other than the selected tier, with the reason on each record) and `deselected` cases. `Gate.format` prints them.
  - `tiers` and `cases` reach every `tests` worker as `--tier=` and `--case=`. They reach a command as the placeholders `{tier}` and `{cases}`.
  - `nameContains` and `sources` reach every `tests` worker as `--name=` and `--source=`. A command does not receive them.
    Without `ids`, tiers or tags, they select the `tests` producers. A filter that matches no case in any selected producer fails the run.
  - A worker that `Lute.worker` or `Lune.worker` starts runs a case tagged `tier:<name>` only in that tier. It runs untagged cases in every tier.
    It records each other case as `skipped` with a `deselected:` reason (`Selection.account`).
    A deselected case is neither a pass nor a failure. Verify never recounts it, and it keeps the run `selected`.
  - Named `cases` that no selected producer reported fail the run.
    `cases` alone select the producers whose `cases` census declares them.
- **Entry points.**
  - `Gate.rerun(outcome)` returns the selection of the producers that did not pass. It narrows to their failing cases when every one of them reported such cases.
  - `Gate.explain(outcome, id)` says why a producer or case was selected, pulled in, not selected (with the reason), deferred, blocked, failed or reused.
  - `Gate.list(gate)` lists the producers.
  - `Lute.gate.run` and `Lune.gate.run` keep `outcome.json` in the run directory and `latest.json` in the base directory.
    `last(gate)` returns it only for the same gate digest.
  - The `--file` flag narrows the census of a `tests` producer to the case IDs that start with `<spec file>::` for the kept files. It drops the census when an ID names no declared file.
    `--name`, `--case` and `--source` keep the whole census, because the worker accounts for each deselected case.
  - `Lute.gate.cli(draft, args, options?)` and `Lune.gate.cli` parse the flags, run the entry points and return the exit code. See [the gate command line](running.md#gate-command-line).
  - `tools/gate.luau` exposes these entry points as `--tier`, `--case`, `--name`, `--rerun`, `--explain` and `--list`.
- **Acceptance.** `outcome.acceptance.verdict` is `release`, `deferred`, `selected` or `failed`. Only `release` is `releasable`.
  - A missing host capability is `unsupported` and fails.
  - `policy.deferrals[id] = reason` makes an unsupported producer, or an exit code classed `deferred`, `deferred` instead. An unnamed one fails.
  - A deferral is explicit. It is never a release.
- **Reuse.** `options.reuse[id] = { report, reference, validatedBy }` satisfies a producer without running it. It works only for IDs in `policy.reuse`.
  Verify decodes and accounts the report like any other report. It marks the result `reused` and adds a limitation.
  The caller validates that the report matches the current artifact. Verify cannot.
- **Build binding.** `options.build` is an `EvidenceBuild`, the one identity of source, tree and cleanliness. See [evidence provenance](api.md#evidence-provenance).
  Verify records it in the report environment and in the outcome.
  When you set it, a reused report must carry the same build digest, or the producer fails.
- **Outcome.** `{ runId, digest, build?, scope, execution, producers, acceptance }`.
  Every declared producer has a record: status, exit code, bounded log tails, case IDs, reuse and deferral.
  `execution.report` is the report. `Gate.format` renders it.
  Verify writes the full logs under `<directory>/<runId>/`.

Limits:

- A benchmark runs in the process of the gate. It stops only cooperatively between samples.
- The gate digest binds the definition. It does not bind benchmark closures.
- Output is not streamed. Use `observe` for progress.

## Native Studio execution

`Lute.studio.run({place, code, worker, context?, deadlineSeconds?, directory?, studioExecutable?, mcpExecutable?, players?, finalCapture?})` runs code in a disposable Studio.

1. It copies an XML place into an isolated run directory.
2. It starts a disposable Studio and selects its unique document through the official Studio MCP.
3. It starts play and executes `code` in `Server` (default) or `Client`.

Use the provided `tools/studio-worker.luau` as `worker`.
macOS is the reference platform. The launcher uses POSIX process groups.
`run` never attaches unless you give it `attach`. See [attached Studio](#attached-studio).
Studio must already be installed, authenticated and configured for its MCP tools.

The engine code receives `runId`.
Run ordinary cases or a source-bound session, and return `HttpService:JSONEncode(Roblox.reportChannel.envelope(runId, report))`.
The launcher validates the identity and the ordinary report schema.
A missing, malformed or wrong-run report faults.
The result uses the `BatchOutcome` states: returned, faulted or timed_out.
A returned report can contain failed cases.

`Lute.studio.host({place, worker, codeForBatch, capabilities, ...})` implements the standard `Core.Host` for `Core.execute`.
`codeForBatch(batch)` loads and registers the ordinary cases of that batch in the engine.
The consumer owns its mounted test modules and operation bindings. No other case format exists.

Every Studio run is detached.
Verify wraps the code, starts it in the engine and returns at once.
The engine keeps the result in memory and holds the encoded report there.
Verify polls the engine until the code finishes or `deadlineSeconds` ends.
No single request runs long, so the request time limit of the Studio MCP server never ends a run.
Only `deadlineSeconds` bounds the run.

The engine returns the encoded report in segments of at most 24000 bytes.
Each segment carries its index, its count, its own digest, and the length and digest of the whole report.
Verify fetches one segment for each call, rebuilds the report and checks each digest and the total length.
A report of any size arrives, and a small report is one segment.
A missing, repeated, mismatched or corrupted segment fails the run with a `transport:` detail that names the segment.
No partial report is accepted.
Every result that carries engine data from `execute_luau` takes this path, for launched and attached runs and for runs with `players`.

The poll finds one of these states:

| State | Result |
| --- | --- |
| Running | Verify waits and polls again. |
| Done | Verify fetches the segments. |
| Raised | The run faults with the engine error. |
| Gone | The play session ended or Studio closed. The run faults with `session_lost`. |
| No answer until `deadlineSeconds` | The run is `timed_out`. |

Each poll also reads the Studio console for progress when the run has a `progressFile`.
The code must still be valid code for the engine, and it can yield.
The engine keeps the result in the attributes of `ReplicatedStorage`, named `VerifyRun<digest>_*`.
Verify clears them after a fetch.

The default run limit is 90 seconds.
An external watchdog kills the owned worker process group, including Studio and the MCP process, on a timeout.
Normal success and failure also terminate those owned processes.
Case budgets stay cooperative inside the engine. The outer run limit holds even when engine code never yields.
Temporary run directories keep the input, the engine and MCP diagnostics and one report for diagnosis.
They are disposable.

`lute run tools/native-conformance.luau` builds the reference fixture from the current source.
It tests these behaviors:

- Observation parity between the simulator and the server.
- Detection of a native mutation defect.
- The actual jump and landing of a client.
- Termination of a wedged engine.

`lute run tools/gate.luau --native` includes this check.
A missing or unavailable engine fails the native command.
The default portable gate does not run it and cannot establish native parity.
Use the native gate when you change engine behavior or the launcher.

Use `basePlace` to run in your own XML place. Verify copies it, mounts the modules and entry scripts, and leaves the rest untouched. See [mounting](running.md#mounting-and-custom-hosts).
Studio runs report progress through the Studio console. The engine prints one framed `VERIFY_PROGRESS` line for each step event. The frame holds a path-free run token, the length and a checksum of the hex-encoded event, so a rewritten frame is rejected and counted.
The worker reads the console through `get_console_output` while the run executes and appends each new event to `progressFile`. Only the simulator path was run without Studio.
Progress is never evidence. See [watch a run](running.md#watch-a-run).

Set `players = 1..8` to run a server with that many actual Studio clients through `StudioTestService:ExecuteMultiplayerTestAsync`.
The code runs on the server and ends the test with its report.
See the [multiplayer example](../examples/multiplayer.luau). The native gate runs it.

For single-client runs, `finalCapture = true` saves the final active Studio viewport through the supported MCP capture tool before Studio closes.
The last case keeps the image path and media type.
This artifact shows the final state. It is not an earlier checkpoint and not a visual judgment.
Verify does not substitute captures between actors silently.
Multiplayer client capture callbacks need their own durable sink, because temporary `CaptureService` image references expire with the client.
`finalCapture` does not exist for `players`. A final capture for each actor would need these parts:
a client callback that saves the image bytes to a path that the host can read, one capture request for each client in the multiplayer session, and one `Artifact` for each actor in the report.
The screen capture tool saves only the viewport of the active Studio window, so it cannot see the other clients.

## Attached Studio

`Lute.studio.attach(options)` uses a Studio that the developer already has open, through the official Studio MCP.
It returns `session, refusal`.
`options` is `{ authorize, studioId?, match?, transport?, mcpExecutable?, directory?, mode?, callSeconds?, runSeconds?, cleanupSeconds? }`.

Discovery lists the open Studios (`list_roblox_studios`).
It selects the Studio with `studioId`, or the Studio for which `match({ id, name })` is true, or both.
A missing selector, no match (`absent`) or several matches (`ambiguous`) is a refusal that names the candidates.
Verify never picks implicitly.

`authorize(request)` is required. It returns `{ ok, reason? }`.
It receives each request before any bytes leave: `{ tool, argumentsJson, fields, studioId, bytes, digest }`.
`bytes` is `{"name":...,"arguments":...}` exactly as Verify sends it. `digest` is its SHA-256 hex.
A refusal, a raise or a request that targets another Studio sends nothing.
Verify defines no policy. The caller owns the grants, which place is open and whether the run can change it.

A session offers these members. `report` runs detached and fetches in segments. See [native Studio execution](#native-studio-execution).
Each of its start, poll, fetch and clear requests passes through `authorize` as a separate `execute_luau` request.

- `call(tool, argumentsJson)`.
- `execute(datamodel, code)` for `Edit`, `Server` or `Client`.
- `play(start)`.
- `capture({ argumentsJson?, directory?, stem? })`.
- `report(datamodel, code, runId)` for the ordinary run-bound report channel.
- `close()`.

Each response has `ok`, `delivery`, `refused`, `expired`, `detail`, `result` and `text`.
`delivery` has three values:

- `unsent`: nothing left. A retry is safe.
- `possibly_sent`: the call can have taken effect. No answer arrived, the connection was lost or a deadline passed.
- `answered`.

Verify never retries a call that may have been sent. A caller must not repeat a possibly sent mutation blindly.
Before each write, the default transport checks that the MCP child is alive. It writes through a bounded process, so a pipe with no reader cannot block the run.
If the child exited before the write, the call was not sent. The transport reopens the session once and retries it.
If that fails, or the child exits during a call, the response has `sessionLost = true` and a detail that starts with `session_lost`. It is not an expired deadline.

`callSeconds` (default 60) bounds each call. `runSeconds` (default 300) bounds the whole session.
At a deadline, Verify abandons the call and closes the transport. The response is `possibly_sent`.
The session refuses later calls in an expired run as unsent.

`close()` has its own `cleanupSeconds` (default 30).
When the session changed the play mode or lost track of it, `close()` sends the play toggle that returns the Studio to its declared prior `mode`.
The default `mode` is `edit`. It is `play` if the Studio was already playing.
`close()` then closes the transport and returns `{ acknowledged, restored, mode, detail? }`.
It never closes or kills Studio and sends only that toggle.
It reports an unacknowledged cleanup, for example when the consumer refused the stop. It does not hide it.
Verify cannot query the mode of the Studio, so it trusts the declared `mode`.

`transport` replaces the MCP process with `{ call(tool, argumentsJson, deadline) -> exchange, close() }`.
An exchange is `answered`, `unsent` or `unanswered`.
`close` must abort an in-flight call. A later `call` must work again.
Tests use a fake transport. The default starts the Studio MCP executable and reconnects after a deadline.

`Lute.studio.run`, `Lute.studio.host` and `Lute.platform.run({ host = "studio", attach = ... })` accept `attach`.
They run the same engine code and report path as a launched run:

1. Play starts.
2. The code runs in `context`.
3. Verify validates the report against the run ID.
4. An optional final capture is saved.
5. Cleanup runs.

Faults, timeouts and unacknowledged cleanup are never a pass.
The open place must already contain what the code requires, such as the mounted entry.
Verify builds, copies and installs nothing.
Attached runs do not support `players`.
They share the Studio of the developer with no isolation, so the work can see and change the state of the open place.
Use a launched run for isolation.

## Open Cloud execution

`Lute.openCloud.connect({ universeId, placeId, versionId, request, authorize, requestSeconds?, pollSeconds?, pollIntervalSeconds?, logPages?, logBytes?, now?, sleep? })` runs the ordinary entry as a Luau execution task on an exact published place version.
It needs no local Studio and no Player.

Open Cloud is a first-class host beside the simulator, Studio and Player.
`Lute.platform.run({ host = "open-cloud", cloud = ... })` and `tools/run.luau --host open-cloud` use the same entry, case IDs, selection, lifecycle and `Core.Report`.
`Lute.openCloud.host({ connection, codeForBatch, runId?, capabilities?, onOutcome? })` is the `Core.Host` for `Core.execute`.

Verify holds no credentials and reads no environment and no files for this host.
The caller supplies `request(call, deadline) -> exchange` and `authorize(call) -> { ok, reason? }`.

- `call` is `{ purpose = "submit" | "poll" | "logs", method, url, body?, digest, universeId, placeId, versionId, taskPath? }`.
- The request function adds authentication and performs the HTTP call.
- An exchange is `answered` (`httpStatus`, `body`), `unsent` or `unanswered`.
- `authorize` sees every call before Verify sends it.
- `deadline` is an absolute time on the host clock. Verify also abandons a call that exceeds `requestSeconds` (default 30).
- The caller stops caller code that outlives an abandoned call.

`session.run({ code, runId, requires? })` submits once and polls until a terminal state or until `pollSeconds` (default 330) pass.
The code receives `runId`, runs the case lifecycle in the task and returns `HttpService:JSONEncode(Roblox.reportChannel.envelope(runId, report))`.
The outcome is `{ status, passed, delivery, state?, handle?, report?, detail?, logs, diagnostics, timing, runId }`.

- `passed` is true only for a `COMPLETE` task whose single run-bound report has every case passed.
  `COMPLETE` alone is not a pass. Assertion failures return `status = "returned"` with failed cases.
  `FAILED`, `CANCELLED` and a missing, malformed, duplicated or other-run report fault.
- `delivery` is `unsent`, `possibly_sent` or `answered`, as in [attached Studio](#attached-studio).
  - These are `unsent`: 401, 403, 429 and other client errors, an unsent exchange and a refusing `authorize`.
  - These are `possibly_sent`: a 5xx, a 408, an unanswered or malformed 2xx reply and a submit deadline.
  - Verify never retries a submit. The host refuses to submit a batch again when the earlier submit is unknown.
- A local poll deadline gives `timed_out` and cancels nothing. The task can still run or complete.
  The outcome keeps `handle = { path, runId, universeId, placeId, versionId }`.
  `session.reconcile(handle)` polls that task again without a new submit.
  The host does this automatically when you run a batch again that it timed out.
- The task path must match the requested universe, place and version exactly. Another path is a fault.
- After a terminal state, Verify fetches the task logs, bounded by `logPages` and `logBytes`, into `logs`.
  Fetch problems and transient poll failures appear in `diagnostics`.
  `timing` carries the measured `submitSeconds`, `pollSeconds`, `totalSeconds` and `polls`. The output of `tools/run.luau` prints them.

Granular operations sit beside `run`:

- `session.submit(input)` creates the task. It returns `{ status, delivery, handle?, state?, task?, detail? }`. The task path is available before any poll.
- `session.poll(handle)` polls until a terminal state or the deadline. It fetches no logs.
- `session.logs(handle)` fetches the logs separately as `{ ok, text, delivery, diagnostics }`.
- `reconcile` polls and fetches the logs.

All of them use the same authorize hook, deadlines, delivery states and handle ownership checks.

`input.binding = "caller"` submits `code` unchanged, with no run ID prefix.
The caller binds the task to its evidence, for example by the digest of the bytes that it sent.
Outcomes then report `binding = "caller"`, never carry a report and are never `passed`.
A `COMPLETE` task is `returned`. A failed or cancelled task is `faulted`.
Every outcome exposes `results` (the raw task output results) and `task` (the raw decoded terminal task JSON).
The default is `binding = "run"`.

The host declares `open-cloud-server`.
It has no physics simulation, no auto-started place scripts, no joined clients and no input, replication, rendering, audio, capture or judgment.
Verify refuses a unit before it sends anything when the unit requires one of these: `native-physics`, `native-multiplayer`, `native-input`, `native-replication`, `native-rendering`, `native-audio`, `place-scripts`, `joined-clients`, `capture`, `judgment` or `action:input.*`.
Declaring one of them in `capabilities` raises.
The caller declares the operation capabilities of a server instance host.

A passing run proves that the named published version executed that code in a Roblox server task and reported these results under this run ID.
It does not prove any of these:

- Client, input, replication, rendering, audio or physics behavior.
- Player-visible quality.
- That the place version is the version that you intend to release.
- Authenticity. The run ID is correlation.

The place must already contain the mounted framework and entry.

Service limits that the caller faces: a task has a cap of five minutes, and a place can have at most ten incomplete tasks.
The service rejects or ends a task that exceeds either limit.
Verify enforces neither limit and does not cancel tasks.
One measurement on a development place: a task that returns at once completes in about 5 seconds from submit to result.
Your place and the service load change this number. Read the printed `timing` of your own run before you choose this host for a fast loop.

## Published Player execution

Build the authorized test place with `Lute.platform.buildPublished`, then run the same entry through `--host player`.
[Run cases](running.md#published-player) describes the workflow.

The builder supports two modes: server execution with client report relay, or client execution after server authorization.
The server checks the actual joined UserId, the entry identity and the selected case IDs.
Launch data is correlation, not authorization.
Each player can execute only one request per join.

`Lute.player.run { placeId, runId, entry?, caseIds?, logPath?, deadlineSeconds? }` is the lower-level call.
It opens the documented Roblox deep link with the signed-in account.

- The macOS reference backend requires Roblox.app and no existing Player process.
- It reads the log that the new PID holds open, validates the ordinary framed report and the run identity, and stops that owned process.
- `logPath` saves the collected raw log before cleanup.
- The default deadline is 90 seconds.
- A missing, stale, malformed or incomplete report, an exit and a cleanup failure cannot pass.
- Ambiguous process ownership faults.
- A delayed OS launch can finish after the startup deadline. Verify does not kill an unidentified process.

The launcher neither publishes places nor installs scripts into existing experiences.
After you republish, use a new server that runs the intended place version.
Entry and case selection do not identify a deployment revision.
A valid report from an old server is not proof of the new build.

`backend` can supply the typed `now`, `sleep` and `launch` implementation of another platform.
Its session provides `read(remainingSeconds)`, `alive(remainingSeconds)` and `close()`.
Respect deadlines and release partial acquisitions on failure.
[Launcher tests](../tests/player-launcher.spec.luau) exercise this contract.

Real published Player validation has exercised native character motion, generated fixture execution, selected cases, standard report collection and owned-process cleanup.
It does not prove multiple authenticated Players or durable screenshots.
The reference launcher drives one authenticated client per machine and has no durable screenshot export.
Studio multiplayer is separate evidence.

## Report transport

`Roblox.reportChannel.envelope(runId, report)` validates a report and binds its run identity.
`receive(envelope, runId)` rejects other runs.
`publish(runId, report, encode, emit)` writes framed `VERIFY_REPORT` lines.
`collect(bytes, runId, decode)` reassembles and validates them.
Supply the JSON codec and the output sink of the host.

This is the same report for unit and end-to-end cases. It is not a verdict that Verify derives from a log.
Tagged transport rejects missing, mixed, conflicting and multiple complete reports.
A matching ID is correlation, not authentication. Callers own channel access and evidence custody.
