# API reference

Verify gives each case an isolated lifecycle and records what happened in a report. Start with
cases and assertions; use sessions, execution plans and host adapters when you need to coordinate
multiple sources or collect observations elsewhere.

| I want to… | Start here |
| --- | --- |
| Write and run a case | [Cases and sessions](#cases-and-sessions) |
| Compare values or record calls | [Assertions and spies](#assertions-and-spies) |
| Read, validate or combine results | [Reports and transport](#reports-and-transport) |
| Schedule work across executors | [Execution plans](#execution-plans) |
| Judge observations collected by a host | [Remote observations](#remote-observations) |
| Capture a scenario, window or place fixture | [Host adapters](#host-adapters) |

Examples use these package names. Replace the paths with your mounted package locations:

```luau
local Core = require(path.to.verify.core)
local Bdd = require(path.to.verify.bdd)
```

Optional packages are [`Lute`](../src/lute/init.luau), [`Roblox`](../src/roblox/init.luau),
[`Host`](../src/host/init.luau) and [`Consumer`](../src/consumer/init.luau).
The entry points export their public functions and types. See the
[working example](../examples/basic.luau) for a directly executable case and report.
The [verification laws](laws.md) define lifecycle and evidence boundaries.

---

## Cases and sessions

### `Core.createHarness`

`createHarness({ now, source?, prefixIds? }) -> Harness`

`Core.createHarness` creates an isolated registry. Register cases. Call `harness:run` to receive their results.
Importing Verify does not create a shared registry.

`harness:run` returns failed and unsupported results in its report; it does not set the process exit code.
The caller must judge the report and make its command fail when the required claim is unmet.
See the [repository runner](../tools/test.luau) for a nonempty, all-passing corpus check.

```luau
local tick = 0
local harness = Core.createHarness {
    now = function()
        tick += 0.001
        return tick
    end,
}

harness:suite("inventory", function()
    harness:case("counts the available slots", function(context)
        local slots = { "first", "second", "third" }
        context:expect(slots):toHaveLength(3)
    end)
end)

local report = harness:run {
    executor = "local",
    environment = { revision = "working-tree" },
}

print(Core.format(report))
```

Supply a monotonic `now` function. This example uses a synthetic clock. `source` associates the
registry with its source. `prefixIds` controls source prefixes in case IDs and defaults to true
when a source is supplied. Prefixing requires a source and does not change selection visibility.

### Registration and execution

| Method | Purpose |
| --- | --- |
| `harness:suite(name, register)` | Group the cases registered by a callback. |
| `harness:case(name, run)` | Register a callback receiving a case context. |
| `harness:case(name, options)` | Supply `run` plus optional `id`, `requires`, `tags` and `limitations`. |
| `harness:skip(name, reason, run?)` | Register a deliberate omission with its reason. |
| `harness:beforeEach(run)` | Register setup for cases in the current suite. |
| `harness:afterEach(run)` | Register teardown for cases in the current suite. |
| `harness:run(options)` | Execute selected cases and return a report. |

Run options name the `executor` and may supply `environment`, `capabilities`, `selection` and
`invoke`. Selection supports IDs, suite prefixes, tags, capabilities and a predicate.
A focused result records that execution; it does not establish a complete gate.

```luau
harness:case("adds two values", {
    requires = { "arithmetic" },
    tags = { "calculation" },
    limitations = { "fixed inputs" },
    run = function(context)
        context:expect(2 + 2):toBe(4)
    end,
})
```

A required capability absent from the run produces `unsupported`, not a pass. A deliberate skip
produces `skipped`. The optional invoker owns actual interruption: it must stop work before
reporting cancellation or timeout. See [execution](execution.md) for host deadlines and policy.

### Case context

The context records assertions, steps and artifact references, and owns case-local cleanup.

| Method | Purpose |
| --- | --- |
| `context:expect(value)` | Create an assertion. |
| `context:step(name, run)` | Record a named step and its outcome. |
| `context:step(name, { run, actor? })` | Associate a step with an actor. |
| `context:artifact(name, reference, mediaType?)` | Attach a reference to evidence. |
| `context:defer(cleanup)` | Register cleanup for the end of the case. |
| `context:own(resource)` | Own a cleanup function or a table with `dispose`/`destroy`. |
| `context:skip(reason)` | Stop the current case with a deliberate skip. |

Cleanup runs once, newest first. Setup, case, teardown and cleanup failures remain independently
visible; a later failure does not erase an earlier one. Hooks and cleanup use the same invocation
contract as the case. Artifact references record locations; they do not save or authenticate bytes.

### `Bdd.create`

`create(harness) -> Bdd`

`Bdd.create` provides registration verbs over the same harness and report model.

```luau
local test = Bdd.create(harness)

test.describe("selection", function()
    test.it("starts empty", function(own, context)
        local selection = {}
        own(function()
            table.clear(selection)
        end)
        context:expect(selection):toHaveLength(0)
    end)
end)
```

The surface contains `describe`, `it`, `itSkip`, `beforeEach`, `afterEach`, `expect`, `spy` and
`skip`. Case and hook bodies receive `(own, context)`; `own` registers a cleanup function.
Use `itSkip(name, reason, body?)` during registration and `skip(reason)` during a case or hook.

### `Core.createSession`

`createSession(options) -> Session`

`Core.createSession` owns one registry per source. Use it when modules register their cases as they load. Options
require `executor` and `environment`; optional fields include `capabilities`, `now`, `surface`,
`runtimeVerbs`, `prefixCaseIds` and `selection`.

```luau
local session = Core.createSession {
    executor = "local",
    environment = { revision = "working-tree" },
}

session:open("specs/inventory")
session:harness():case("starts empty", function(context)
    context:expect({}):toHaveLength(0)
end)
session:close()

local report = session:run()
```

| Method or field | Purpose |
| --- | --- |
| `open(source)` / `close()` | Enter and leave a source's registration scope. |
| `harness()` / `current()` | Access the active source's harness or supplied surface. |
| `verbs` | Route calls through the active source's surface. |
| `adoptReport(source, report)` | Include an existing source report. |
| `sourceReport(id, source, status, detail)` | Construct a source-level failed or skipped report. |
| `setSelection(selection?)` | Set which cases to run. |
| `run()` / `reset()` | Execute queued sources or reset session state. |

Call session methods with `:`. A `surface` factory maps registration verbs to each harness;
`runtimeVerbs` routes verbs such as `skip` while cases run. Mid-run reset and reentry fail without
losing queued sources. [Worker examples](execution.md#lute-workers) show module-loading integration.

---

## Assertions and spies

### `Core.expect`

`expect(value) -> Expectation`

Available directly, through a case context, or through the BDD surface. Chain `.never` before a
matcher to negate it.

```luau
Core.expect(4):toBe(4)
Core.expect({ count = 2 }):toEqual({ count = 2 })
Core.expect("ready").never:toBe("waiting")
Core.expect(function()
    error("missing entry", 0)
end):toThrow("missing entry")
```

| Matchers | Compare |
| --- | --- |
| `toBe`, `toEqual` | Equality and deep equality. |
| `toBeNil`, `toBeOk` | Nil and non-nil checks; `false` is non-nil. |
| `toBeTruthy`, `toBeFalsy` | Truthiness checks. |
| `toBeTrueWith(detail)` | A true value, with a supplied failure detail. |
| `toBeCloseTo`, `toBeNear`, `toBeFloat32` | Numeric tolerance or single-precision representation. |
| `toBeLessThan`, `toBeGreaterThan`, `toBeLessThanOrEqual`, `toBeGreaterThanOrEqual` | Numeric ordering. |
| `toContain`, `toContainExactly`, `toHaveLength` | Containment and length. |
| `toThrow(contains?)`, `toThrowMatching(pattern)` | A thrown error, with optional plain text or a Luau pattern. |

`toThrow` uses plain text containment; use `toThrowMatching` for patterns. `Core.float32(value)`
returns the single-precision value. Exact matcher signatures are in
[`matchers.luau`](../src/core/matchers.luau).

### `Core.spy`

`spy(implementation?) -> Spy`

`Core.spy` records calls to its `fn` and optionally delegates to your implementation.

```luau
local callback = Core.spy(function(value)
    return value * 2
end)

Core.expect(callback.fn(3)):toBe(6)
Core.expect(callback.callCount()):toBe(1)
Core.expect(callback.lastArgs()):toEqual({ 3 })
```

Inspect `calls`, `called()`, `lastArgs()` and `lastReturn()`. Use `reset()` to clear recorded calls,
`returnValue(value)` to supply a fixed return, or `implementation(fn)` to replace the callback.

---

## Reports and transport

A schema-v1 report retains executor, environment, capabilities, sources and case results. Each
case retains status, timing, failures, steps, artifacts, limitations and origin. Counts must agree
with the result rows.

| Status | Meaning |
| --- | --- |
| `passed` | The executed case passed. |
| `failed` | An assertion, lifecycle phase or execution failure was recorded. |
| `skipped` | The case was deliberately omitted with a reason. |
| `unsupported` | A required capability was unavailable. |
| `timed_out` | The invoker reported that timed-out work was stopped. |
| `cancelled` | The invoker reported that cancelled work was stopped. |

### Validate and combine

| API | Use it to… |
| --- | --- |
| `Core.decode(value)` | Validate a foreign report and its schema. |
| `Core.merge(reports, executor, environment)` | Combine trusted reports. |
| `Core.compose(payloads, executor, environment)` | Account for every expected shard, including missing, malformed or duplicate outcomes. |
| `Core.syntheticReport(options)` | Record work a host could not reach. |
| `Core.format(report)` | Produce readable output. |
| `Core.canonical(value)` | Produce a deterministic representation. |
| `Core.verdictDigest(report)` / `Core.verdictDifferences(left, right)` | Compare verdicts without treating timings as deterministic. |

```luau
local combined = Core.compose({
    { id = "worker-1", report = report },
    { id = "worker-2", error = "worker exited before returning a report" },
}, "local-pool", { revision = "working-tree" })

print(Core.format(combined))
```

Supply every launched shard, including errors. Omitting an unsuccessful worker from the input
cannot establish that all expected work passed.

### Move reports between hosts

| Surface | Transport |
| --- | --- |
| `Core.frame`, `extract`, `reassemble`, `receipt` | Tagged log lines. |
| `Core.segment`, `reassembleSegments` | Bounded payload arrays. |
| `Lute.encode`, `decode` | JSON values. |
| `Lute.segmentReport`, `reassembleReport` | Reports carried in bounded segments. |

Missing, conflicting or mixed chunks fail. **JSON decoding is not report validation.** Validate
received reports with `Core.decode`; consumers bind executor identity and own authenticity.

## Execution plans

A plan names a finite set of work and its requirements. The consumer supplies discovery,
locator meaning and an authorized host.

| API | Responsibility |
| --- | --- |
| `Core.validateManifest`, `planFromManifest` | Validate a manifest, then derive a plan from it. |
| `Core.validatePlan`, `selectPlan`, `partitionPlan` | Normalize, select and deterministically divide planned work. |
| `Core.planDigest`, `caseId` | Bind plan meaning and compose case identities. |
| `Core.negotiate`, `explainCapabilities` | Determine and explain capability support. |
| `Core.execute(plan, host, options?)` | Execute batches with lifecycle and failure accounting. |

See [the execution contract](execution.md) for fixtures, deadlines, retries, Lute workers and
pools. [`Host.fake`](../src/host/init.luau) injects missing, duplicate, reordered, failed and
cancelled deliveries without external effects.

---

## Remote observations

### `Core.sealObservations`

`sealObservations(draft) -> Bundle`

`Core.sealObservations` freezes a snapshot of supplied observations and their executor, environment, capabilities,
actors, artifacts and timeline. Sealing preserves the input. It does not judge or authenticate it.

### `Core.evaluateObservations`

`evaluateObservations(bundle, source, register, now?, selection?) -> Report`

`Core.evaluateObservations` runs a real harness against a sealed bundle. Registration receives the harness and observations.
An optional `selection` uses the harness selection contract. Only selected case bodies run.
Registration failures still fail, and a selection with no matches cannot produce a clear verdict.
A focused report proves only its selected claims; consumers must distinguish it from complete acceptance.

```luau
local bundle = Core.sealObservations {
    executor = "local-observer",
    environment = { revision = "working-tree", run = "sample-1" },
    observations = { visibleRows = 3 },
}

local report = Core.evaluateObservations(bundle, "viewport", function(harness, observations)
    harness:case("shows three rows", function(context)
        context:expect(observations.visibleRows):toBe(3)
    end)
end)

local verdict = Core.observationVerdict(report, "viewport checks passed")
```

`observationVerdict(report, clearReason)` returns `clear` only for nonempty, all-passing results
with coherent counts; otherwise it returns `held`. `isSealedBundle` checks the sealed snapshot,
and `observationStringMap` normalizes supplied environment fields. An observation is not an
acceptance decision before its cases run.

## Host adapters

Adapters use injected host operations. Consumers own authorization, actual destinations,
artifact custody and release acceptance. Load only the package needed for the observation.

### Scenarios and journeys

`Roblox.observeScenario(deps, predicates, options)` captures the baseline census before starting
an authorized driver. It selects a new or grown transcript, refuses ambiguous sources, and
returns bounded readback or a named failure. Consumer predicates define source, completion and
bindings; core evaluates the collected observations.

`Roblox.tierLadder` provides session, client and journey judgment and receipts. Exact predicate
rows, run identity, source and environment must agree. `unsupported` applies only when the
specified capability was unreached and no real defect was observed. See the typed options for
`judge`, `receipt`, `sessionObservations`, `chunkedCallPlan`, `clientObservations` and `journeySpec`
in [`tier-ladder.luau`](../src/roblox/tier-ladder.luau).

### Windows, captures and receipts

`Roblox.witnessHost` provides window parsing and selection, viewport capture, checkpoint frames,
and `recordReceipt` / `decodeReceipt` / `checkReceipt`. These functions are also exported at the
Roblox package root.

Captures use injected operations and current window/scale facts. Receipts bind contract, target,
source, console hash, image hash and byte count. Source changes must pass injected ancestry/path
policy; a missing image or red console holds. Duplicate labels cannot overwrite a checkpoint.

`Core.classifyConsoleText`, `classifyConsole` and `splitConsoleLines` preserve narrow caller
exclusions, blocks and line ordering. `Lute.detectViewportCorners` uses the adjacent Swift helper
as an explicitly supplied native inspection capability. It rejects absent or ambiguous marker
rectangles; a missing capability is unsupported. Consumers still own run freshness, image custody
and final clean-image coverage.

### Observation sinks and place fixtures

`Roblox.observationSink` provides escaped/chunked wire data, bounded values, markers, tallies,
reference pooling, owned observation seams, arming and publication into an injected node tree.
It must not replace or destroy host-owned state. In-engine adapters can import this leaf directly.

`Roblox.instanceLayer` models only members of a supplied API dump. `placeBoot`, `bootPlace`,
`buildPlaceTree`, `createPlaceCache` and `createPlaceRuntime` build and run injected place fixtures.
Their reports test declared boot phases and ownership; they do not simulate all engine behavior.

### Consumer diagnostics

`Consumer.scan`, `scanTree` and `scanProductionPaths` inspect portable specifications and
production graphs. See [consumer diagnostics](lint.md) for the rules and their limits.
