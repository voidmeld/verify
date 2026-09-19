# Public API

Root `init.luau` modules export the public names and types. Portable leaf modules use relative
requires and directory roots use `@self/child`, so the same core mounts in an engine tree.
The [laws](laws.md) constrain every API. [Execution](execution.md) covers plans and hosts.

## Cases and sessions

`Core.createHarness({now?, source?, prefixCaseIds?})` creates an isolated registry. Register
`suite(name, callback)`, `case(name, callbackOrOptions)`, `beforeEach(callback)`, and
`afterEach(callback)`. `case` options carry requirements, tags, limits and deliberate skips.
`harness:run({executor, environment, capabilities?, selection?, invoke?})` returns a report.
See [the executable example](../examples/basic.luau).

A case receives `context:expect(value)`, `step(name, callback)`, `artifact(name, reference,
mediaType?)`, `defer(cleanup)`, `own(disposable)`, and `skip(reason)`. Ownership accepts a function
or a table with `dispose`/`destroy`. Hooks and cleanup share the invocation contract; an executor
must actually stop work before claiming cancellation or timeout. Failures never erase earlier
failures. `expect`, `float32` and `spy` are also exported directly from core.

`Bdd.create(harness)` returns `describe`, `it`, `itSkip`, `beforeEach`, `afterEach` and `skip`, all
backed by that harness. Matchers and their negation live in `src/core/matchers.luau`; plain throw
containment and pattern throw matching are separate operations.

`Core.createSession(options)` provides one registry per source. `open(source)`, `close()`,
`harness()`, `adoptReport(source, report)`, `sourceReport(...)`, `run()` and `reset()` support
self-registering modules. A supplied `surface` maps verbs to the active source; `runtimeVerbs`
route verbs such as `skip` during case execution. Mid-run reset and reentry fail without losing
queued sources. Source id prefixing changes identity spelling, never selection visibility.

## Reports and transport

Schema-v1 reports retain executor, environment, capabilities, sources and case results. Each case
retains status, timing, failures, steps, artifacts, limitations and origin. The six statuses are
`passed`, `failed`, `skipped`, `unsupported`, `timed_out`, `cancelled`. Counts must agree with rows.

`Core.decode(value)` validates a foreign report. `merge(reports, executor, environment)` combines
trusted reports; `compose(payloads, executor, environment)` turns missing, malformed or duplicate
shard outcomes into named failures. Supply every launched shard, including errors. `format` is
human readable; `canonical`, `verdictDigest`, and `verdictDifferences` compare verdicts without
pretending timings are deterministic. `syntheticReport` accounts for work a host could not reach.

`frame`, `extract`, `reassemble`, and `receipt` handle tagged log lines. `segment` and
`reassembleSegments` handle bounded payload arrays. Missing, conflicting or mixed chunks fail.
Lute exports JSON `encode`/`decode` plus `segmentReport`/`reassembleReport`; encoding is transport,
not validation or authenticity. Consumers validate on receipt and bind executor identity themselves.

## Remote observations

`Core.sealObservations(draft)` creates an immutable snapshot with contract, run, environment,
capabilities, actors, artifacts, timeline and observations. `isSealedBundle` checks the snapshot.
`evaluateObservations(bundle, source, register, now?)` runs a real harness over it;
`observationVerdict(report, clearReason)` accepts only nonempty all-passing results with coherent
counts. `observationStringMap` normalizes supplied environment fields. No observation carries an
acceptance decision before its cases run.

## Required host adapters

`Roblox.observeScenario(deps, predicates, options)` captures the baseline census before starting
an authorized driver, selects a new/grown transcript, refuses ambiguous sources, and returns
bounded readback or a named failure. Consumer predicates own what source, completion and bindings
mean. This function gathers observations; core owns evaluation.

`Roblox.tierLadder` supplies shared session/client/journey judgment and receipt mechanics. Exact
predicate rows, run identity, source and environment must agree. Unsupported applies only when the
specified capability was unreached and no real defect was observed. `judge`, `receipt`,
`sessionObservations`, `chunkedCallPlan`, `clientObservations` and `journeySpec` retain their typed
options in `src/roblox/tier-ladder.luau`.

`Roblox.witnessHost` supplies window parsing/selection, viewport capture, checkpoint frames and
`recordReceipt`/`decodeReceipt`/`checkReceipt`. Root aliases remain available. Capture uses injected
operations and current window/scale facts. Receipts bind contract, target, source, console hash,
image hash and byte count. Source changes must pass injected ancestry/path policy; a missing image
or red console holds. Duplicate labels cannot overwrite a checkpoint. `Core.classifyConsoleText`
and related console functions preserve narrow caller exclusions, blocks and line ordering.

`Lute.detectViewportCorners` is an explicitly supplied native inspection capability backed by the
adjacent Swift helper. Missing capability is unsupported. It rejects absent/ambiguous marker
rectangles; consumers still own run freshness, image custody and final clean image coverage.

`Roblox.observationSink` provides escaped/chunked wire data, bounded values, markers, tallies,
reference pooling, owned observation seams, arming and publication into an injected node tree.
It must not replace or destroy host-owned state. In-engine adapters can import this leaf directly.

`Roblox.instanceLayer` models only members of a supplied API dump. `placeBoot`, `bootPlace`,
`buildPlaceTree`, `createPlaceCache` and `createPlaceRuntime` build and run injected place fixtures.
Their reports test declared boot phases and ownership; they do not simulate all engine behavior.

`Host.fake` is the deterministic executor used to inject missing, duplicate, reordered, failed and
cancelled deliveries. It performs no external effects. `Consumer.scan`, `scanTree` and
`scanProductionPaths` implement the [consumer diagnostics](lint.md).
