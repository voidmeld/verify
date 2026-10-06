# Experience verification

Use the same authored case and the ordinary Verify harness to check application logic, simulated actors and native Roblox observations.
The consumer supplies operations, evidence collectors, reviewers, capabilities and acceptance criteria.

## One case model

Author every host with `harness:case(name, options)` and the ordinary `Core.Context`.
BDD and sessions use that same context.
`Core.runCase(namedCase, host)` runs one case through the harness and returns the ordinary `Report`.
No separate experience case, context, runner or evidence map exists.
Use direct assertions for local functions and typed operations for host interactions in the same case.

### Operations

`Core.operation({kind, name, input, output})` declares an action or a query with input and output decoders.

- `context:perform(actor, operation, input)` keeps the declared Luau input and result types.
- The decoders validate both sides of the wire boundary.
- `Core.bindOperation(operation, handler)` binds a typed handler to a host endpoint.
- Actions and queries use finite plain values. An unsupported engine value needs an explicit codec.
- A query must only read.
- `context:await(actor, query, input, predicate, pollSeconds)` polls a query with the clock and sleep of the host, within the case deadline. It refuses actions.

### Binding a host

A host binds through `harness:run({executor, capabilities, environment, bind, cancelled?})`.

- `bind(context)` runs in setup, only for selected and supported cases. Create a fresh host for each case.
- Register cleanup for a partial resource with `context:defer` before a fallible acquisition or a readiness operation.
- The harness owns the `close` of the returned host.
  Suite setup, body, teardown and cleanup then run through one failure classifier.
- Sessions, BDD surfaces, injected execution hosts and Lute worker options accept the same `bind` and `cancelled` options.
- Use the same monotonic clock for the harness and the host.

Declare required operation capabilities as `action:<name>` or `query:<name>`. Declare `capture` and `judgment` when the case needs them.
A missing capability that preflight finds is `unsupported`.
An undeclared operation that is unavailable during execution fails.

### Deadlines

Case options include `timeoutSeconds` and `cleanupTimeoutSeconds`.
A deadline covers setup and body.
Each teardown and cleanup callback gets a separate cleanup budget, five seconds by default.
The budget includes recovery operations after a failed or cancelled body.
Timeout and cancellation keep their own report statuses.
Checks are cooperative. A blocking call must enforce the deadline that it receives, or the outer worker must interrupt it.
Cleanup runs even after a failure. Its failures stay visible independently.
`context:perform(actor, operation, input, deadlineSeconds?)` and `context:await(actor, query, input, predicate, pollSeconds, deadlineSeconds?)` accept a per-call deadline.
The deadline is positive, finite and bounded by the remaining case time. For `await`, it bounds the whole wait.
The request that reaches the host carries that deadline. A host must stop at it.
If the call fails at or after its deadline, the step is `timed_out` and its message names the actor and operation. The case then runs its cleanup.
A call that fails before its deadline keeps its ordinary failure.

### Progress

`Core.runCases` accepts `progress = Core.progress.create(runId, emit)`. The harness emits `{ runId, sequence, actor, caseId, step, phase, status? }` when each step starts and finishes.
`sequence` is monotonic in the run. A step with no actor reports the actor `case`. A failing listener does not change the run.
`Core.progress.pending(events)` lists the started steps that have not finished.
`Roblox.progressChannel` frames events on the output channel and collects them in order without repeats.
A run with no progress behaves as before. Progress is not evidence and no report field depends on it.

### Observations

`context:checkpoint(actor, name)`, `judge(actor, checkpoint, criterion)` and `measure(actor, name, input, limits)` attach observations to `CaseResult.evidence`.
Each observation binds to the recorded step indices.
Evidence survives standard report decoding, merging and transport.

- A judgment needs the captured checkpoint of that actor and an explicit reviewer verdict with reasoning.
- Capturing media alone establishes no quality judgment.
- An unreviewed judgment and an insufficient measurement are unsupported. An observed defect fails.
- `context:unsupported(requirement)` records a missing runtime capability and still runs cleanup.
- A measurement retains its inputs and limits. Report decoding recomputes the evaluation and checks it.

`Core.observationParity(leftReport, rightReport)` compares case verdicts and the inputs and observations of actions and queries.
Both reports must pass.
It does not certify native physics, replication timing, visual quality, sound or performance.
Those claims need their own observations and assertions.

Start with [typed local operations](../examples/experience.luau), the [shared instance case](../examples/instance-case.luau) and the [failure and cleanup tests](../tests/semantic-execution.spec.luau).

## Reusable instance adapter

`Roblox.instanceHost` owns instance-operation binding and fixture cleanup.
Its operations `create`, `parent`, `destroy`, `setProperty`, `setAttribute` and `inspect` use stable instance IDs that the caller selects.
`property(decoder)` and `attribute(decoder)` provide typed reads.

The exact same case runs with `instanceHost.simulated(actor).host` or `instanceHost.native(actor).host`.
Native execution needs an already running, authorized Studio or Player context.
The [native launcher](execution.md#native-studio-execution) provides isolated Studio startup and report retrieval.

`simulated(actor, environment?)` accepts a configured `Roblox.testEnvironment()`.
Reuse its class, default, validation, explicit fake, virtual time and hierarchy behavior. Do not build a second engine.
`Roblox.reflection.create` supplies class definitions and defaults from an injected database.
It implies no reflection database and no UI or physics behavior that is not implemented.
Supply explicit fakes for unsupported methods.

`registry({actor, createInstance, borrowed?, codec?})` exposes the same endpoints for a custom native or simulated host, including `experienceHost` remote routing.
`native(actor, borrowed?, codec?)` provides the native factory and clock.
A codec translates property and attribute values that are not portable. The default transport accepts only finite plain values.

Rules for instances:

- Verify does not destroy borrowed instances.
- Verify restores borrowed descendants that you moved under owned fixtures to their original parent before cleanup.
  A failed restoration prevents the destruction of their owner.
- Other changes to borrowed instances need explicit caller cleanup.
- Verify releases owned fixtures on success and on failure.
- Unknown IDs, wrong actors and invalid values fail.

## Native Roblox hosts

`Roblox.experienceHost.nativeEngine()` needs a running Roblox simulation.
It reads the Studio or Player, server or client, place and engine identity.

`create(options)` binds that engine, a local actor, actor contexts, an operation registry and an optional transport, capture and judge.
Injected engine records remain fixture evidence.
Registered operations and supplied collectors and reviewers advertise their capabilities automatically.
Declare extra capabilities in `options.capabilities`.
`endpoint(decode, body, requires?)` validates payloads before the handler runs.
Local registry operations and remote responses keep their actor and operation bindings.

`remoteTransport(context, remote, actors, playerFor?)` wraps a RemoteFunction that the caller supplies.
Server routing needs a player resolver.
Bind native callbacks with `remoteResponder(registry, capabilities, now, actor, authorize)`.
The required authorization callback checks the caller before dispatch.

Opt in to these test endpoints only in an authorized development or staging session.
The caller owns endpoint installation, actor membership, authorization policy and cleanup.
Capability names and response correlation do not authenticate a remote caller.
Wire requests carry `remainingSeconds`. The receiving actor applies that budget to its own clock.
The originating deadline still bounds the returned completion cooperatively.

The [native visibility example](../examples/roblox-experience.luau) binds an injected target and optional collectors.
The [hierarchy conformance example](../examples/hierarchy-experience.luau) accepts a native Folder factory or the simulated environment and checks the same authored observations.

## Player actions

`Roblox.playerHost` declares the typed operations `move`, `jump`, `equip` and `inspect`.
`native(actor)` binds the Humanoid, backpack and character of the live local player.

- `move` accepts a unit direction.
- `equip` requires one uniquely named backpack Tool.
- `inspect` returns position, velocity, health and the equipped tool.
- Cleanup stops movement.

These operations are semantic character controls.
They do not prove the behavior of keyboard, touch, gamepad or UI input. Those need input-specific host operations and tests.

`registry(backend)` binds the same vocabulary to injected functions for deterministic tests.
Such a fixture does not advertise native physics.
The [player example](../examples/player-case.luau) requires `native-physics` and observes an actual jump and landing.
It is unsupported on a host that only simulates.

## Simulated networking

`Roblox.network.create({ clients, latency?, environment? })` gives each declared client and the server a separate simulated environment.

- `send` queues cloned plain-data messages. `onMessage` receives them.
- `advance(seconds)` delivers the ready snapshot in due-time and sequence order.
- A message that is sent during delivery waits for another advance.
- Payloads refuse nonfinite numbers, cycles, metatables, sparse arrays and mixed array and dictionary keys. Outcomes name refusals explicitly.
- The network clock advances independently of the scheduler of each environment.
- `disconnect(client)` drops queued messages in both directions and disconnects its receiving handlers.

This tests authored message handling and isolation.
It supplies no native replication, physics or rendering parity.
See the [network tests](../tests/network.spec.luau).

## Performance observations

`Core.performance.summarize({ samples, unit, context, threshold?, percentiles?, series? })` validates dense samples that are finite and nonnegative.
It retains the environment, the signal and the timing label (`observed` or `simulated`).
It computes count, mean, extrema and nearest-rank p50, p95 and p99 in the supplied unit.
An empty observation retains absent metrics.
An optional threshold counts the samples that are strictly above it.

- `percentiles` lists more nearest-rank percentiles, for example `{ 75, 90 }`. Each is above 0 and at most 100. None repeats.
  The summary lists them in ascending order as `{ percentile, value }`. The report decoder recomputes them.
- `series` is `{ [name]: { { number } } }`. Each name holds arrays of finite numbers.
  The input keeps them raw. Verify does not interpret them. `Core.performance.checkSeries(series)` validates the shape.

`evaluate(summary, limits)` requires matching units, a positive `minimumSamples` and explicit caller limits.
Ratio limits also require the matching threshold.

- An exceeded limit fails.
- Missing, insufficient, simulated or mismatched evidence is unsupported.
- Verify has no built-in budget and no built-in environment attribution.
- Caller labels do not authenticate timing. A real frame-performance claim needs samples from the actual consumer surface.

[Performance tests](../tests/performance.spec.luau) prove the calculations and refusals.
`context.measure(actor, name, input, limits)` records the evaluation in the case evidence and requires a passed result through the shared harness.

`Roblox.performance.collect({ connect, environment, signal, maximumSamples })` bounds collection from an injected interval signal.
Supply the current `environmentLabel` and a caller-owned `sampleLimit`:

```luau
local collector = Roblox.performance.collect {
    environment = environmentLabel,
    signal = "RenderStepped",
    maximumSamples = sampleLimit,
    connect = function(sample)
        local connection = game:GetService("RunService").RenderStepped:Connect(sample)
        return function() connection:Disconnect() end
    end,
}
```

Exercise the consumer, then call `collector.finish()` during cleanup.
`finish` disconnects once and returns cloned `Performance.Input` samples in `ms`, labeled `observed`.
An invalid interval refuses after cleanup.
The cap stops the retention of new samples. `finish` still releases the connection.
The caller must connect the actual signal and bind the run and source identity.
Injected callback tests establish fixture coverage. They do not establish an observed native frame-performance result.

## Coordinated native clients

`Roblox.multiplayer.server(context, options)` binds a server and one to eight clients to one ordinary case.

- The options supply the `RemoteEvent`, a unique `runId`, the client count, an authorization callback, the server registry, the native engine, sleep and the readiness deadline.
- `armed` can announce that the server listener is connected.
- Clients wait for that announcement. Each then calls `multiplayer.client` with the same remote and run ID, its registry, capabilities, clock and spawn function.
- The optional `capture` and `close` callbacks collect client evidence and release client resources.

The server assigns `client-1` through `client-N` in join order.
These are run-local identities, not account IDs.
Cases use `context:perform`, `await` and `checkpoint` against these actors or against `server`.
The coordinator checks the actual sender identity, the run and request identity, deadlines and disconnects.
Cleanup waits for connected clients to acknowledge the release. Missing or failed cleanup fails the case.

The [runnable example](../examples/multiplayer.luau) clicks UI in one client and observes the replicated counter on the server and on the second client.
Its native client images are temporary and explicitly limited evidence.
Use a durable capture callback to retain per-client images.

`Roblox.inputHost` declares the operations `key`, `pointer` and `text`.

- `native()` uses `UserInputService:CreateVirtualInput()`. It returns nil when that is unavailable.
- Register only the available capabilities. Unavailable input is not a pass.
- `registry(backend)` binds the operations. `backend.close()` releases held keys and mouse buttons.
- `screenCenter(guiObject)` converts the rendered GUI bounds to screen coordinates, including the top-bar inset.
- Pointer coordinates are screen pixels.
- Roblox still rejects reserved keys and interactions with protected CoreGui.

This is real virtual input. It is distinct from the character motion operations in `playerHost`.

## Benchmarks

`Benchmark.case(spec)` (`src/benchmark.luau`, host side) is an ordinary case.
`Benchmark.run(spec)` returns the raw result.

A spec supplies these fields:

- `name`, `unit` (`seconds`, `milliseconds` or `microseconds`), `warmup`, `samples` and `iterations?`.
- Either `workload` or `phases`. See [phases](#phases).
- `budget?` with `p50`, `p95`, `p99` and `maximum`.
  Without a budget, the case passes as measured only. It carries that limitation and the evaluation reason `measured`. Acceptance policy then decides.
- `percentiles?`: more nearest-rank percentiles for every summary, for example `{ 75, 90 }`.
- `environment = { observed, accepted? }`.
- `maxSpread`, `yardstick` and `baseline`, all optional.
  A `baseline` is a `value` or recorded `samples`. It can include the `yardstick` that was recorded with it, which normalizes the comparison across machines.
- `acceptedBaselines`.
- `judge`: a callback over the raw samples, the series and the summary. It returns a refusal message.
- `setup` and `teardown`: run once, untimed.
- `beforeSample`, `finalize` and `afterSample`: see [the sample lifecycle](#the-sample-lifecycle).
- `warmupScope?`: `workload` (default) or `sample`.
- `heap`: `{ probe, unit, maximumGrowth? }`.
- `deadlineSeconds`.
- `clock`: an injectable clock. The default is `os.clock`. A gate supplies its own.

The consumer owns identities, budgets and units. No machine is a universal baseline.

`Benchmark.collection({ name, yardstick, benchmarks })` is one case whose members share a yardstick.
A gate declares it as `{ kind = "benchmark", collection = collection }`.
The collection measures the yardstick before and after the whole collection. `Benchmark.collect` returns the raw result.

- After the second reading, each member runs its baseline comparison, including `baseline.yardstick` normalization, and its `judge`.
  They use the yardstick samples from before and after the collection.
- The judge view carries these samples raw (`yardstickBefore`, `yardstickAfter`) and summarized (`yardstickBeforeSummary`, `yardstickAfterSummary`).
  A caller can apply its own normalization and rules.
- A drifting yardstick marks the members unsupported and skips their judges.

Warmup runs are untimed. Exactly `samples` timed samples follow, and each sample averages `iterations` runs.
Verify never retries the run.
The measurement evidence of the case keeps all raw samples.

### The sample lifecycle

One sample runs these steps in order:

1. `beforeSample()` runs untimed. Its first return value is the sample state. Build a fresh environment here.
2. The timed region runs the `workload` for `iterations` runs. Then it runs `finalize(state, sampler)` once, for example a drain.
   `finalize` needs `iterations` of 1. A drain that you want timed belongs here, not in `afterSample`.
3. `afterSample(state, sampler)` runs untimed. Release the environment here.
   It runs after a failed sample too. The first failure stays the reported failure.

`workload` and phases receive `(state, sampler)`. `state` is nil when no `beforeSample` ran.
`warmupScope = "workload"` runs only the timed steps in each warmup run, with no hooks and a nil state.
`warmupScope = "sample"` runs the whole lifecycle in each warmup run. Nothing from a warmup run is recorded.
A spec with phases and a `beforeSample` needs `warmupScope = "sample"` when it warms up.

### Phases

`phases = { { name, run, budget?, maxSpread?, baseline?, judge? }, ... }` replaces `workload`.
One sample runs the phases in order on the state from `beforeSample`.
Each phase has its own timing.
Declare the list with its type, `local phases: { Benchmark.Phase } = { ... }`.
Then each `run` takes only the parameters that it uses.

- Each phase has its own raw samples, summary, budget, baseline comparison, `maxSpread` and judge.
  The judge view names the phase in `phase`.
- Each phase is one measurement of the one case. Its name is `<spec name>/<phase name>`.
  The same holds for each member of a collection.
- The spec-level `budget`, `baseline`, `judge`, `maxSpread`, `finalize` and `iterations` are not allowed with phases.
- `Result.samples` holds the sum of the phases of each sample. `Result.phases` holds one `PhaseResult` for each phase.
- A phase that raises fails the sample. Verify records no partial sample.
- An unbudgeted phase carries the limitation `measured only: no budget declared for phase <name>`.

### Auxiliary series

`sampler.series(name, values)` keeps an array of finite numbers for the sample, for example per-frame durations or counters.
Each call adds one array to the series `name`.
The series stays raw in the measurement input and in `judge` (`view.series`). Verify does not interpret it.
A series recorded in a phase belongs to that phase. A series recorded in `afterSample` belongs to the case,
or to the last phase of a phased case. A series from a warmup run is discarded.
A series with a blank name or a value that is not finite fails the sample.

### Compare stored runs

`Benchmark.store(name, results)` returns a stored run: `{ schemaVersion, name, measurements }`.
Each measurement is `{ name, unit, environment, samples }`. A phase is its own measurement.
`Benchmark.storeReport(name, report)` returns the same stored run from a report.
Use it for a benchmark that a gate ran. It reads the measurement evidence of every case, so phases are included.
It stores the samples, the unit and the environment. It raises when the report has no measurement evidence.
Write it with `Lute.encode`. Read it with `Benchmark.decode(Lute.parse(text))`, which validates it.

`Benchmark.compare(baseline, candidate, { rule, rules?, minimumSamples?, executor?, now? })` returns an ordinary `Core.Report`.
Each measurement of the baseline is one case. A rule is `{ ratio, floor, metric? }`.
`metric` is `p50` (default), `p95`, `p99` or `maximum`. `rules[name]` replaces `rule` for one measurement.

- A case fails when the candidate metric is above both `baseline * ratio` and `baseline + floor`.
  `ratio` is at least 1. `floor` is in the unit of the measurement.
- A measurement that only one run has fails. So does a different unit or environment.
- The measurement evidence holds the candidate samples and the limit.

`Benchmark.spread(runs, { metric? }?)` summarizes N stored runs of the same benchmarks.
It needs at least two runs. For each measurement in every run, it lists the metric value of each run
and their `minimum`, `maximum`, `median`, `mean`, `deviation` and `relativeRange` (`(maximum - minimum) / median`).
A measurement that some run lacks is in `incomplete`. A different unit or environment fails.

The verdict follows these rules:

- A run within budget passes.
- A run over budget, or a baseline regression beyond `tolerance`, fails.
- Anything that makes the numbers untrustworthy is reported as the missing `measurement:<reason>`.
  The status is unsupported unless the budget also failed.
- Environment or baseline mismatch skips the workload.
- A raising workload or an invalid clock fails.

| Reason | Meaning |
| --- | --- |
| `environment_mismatch` | The observed environment is not an accepted environment. |
| `baseline_mismatch` | The baseline identity, environment or unit does not match. |
| `unstable` | `(p95 - p50) / p50` exceeds `maxSpread`. |
| `yardstick_unstable` | The yardstick spread exceeds `yardstick.maxSpread`. |
| `yardstick_drift` | A fixed CPU workload sampled before and after moves more than `maxDrift`. |
| `heap_unsupported` | The probe returned no reading. |
| `deadline_exceeded` | The benchmark passed its deadline. |

`Benchmark.luauHeap` reads `collectgarbage('count')` where the runtime exposes it.
Lune exposes it. Lute 1.0 does not, so it reports `heap_unsupported`.
It never forces a collection.
A summary also carries `total` and `deviation`.
