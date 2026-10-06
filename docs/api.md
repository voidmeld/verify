# API reference

Verify gives each case an isolated lifecycle and records the result in a report.
Start with cases and assertions.
Use sessions, plans and host adapters when you coordinate several sources or collect observations on another host.

| Task | Start here |
| --- | --- |
| Write and run a case | [Cases and sessions](#cases-and-sessions) |
| Compare values or record calls | [Assertions and spies](#assertions-and-spies) |
| Read, validate or combine results | [Reports and transport](#reports-and-transport) |
| Schedule work across hosts | [Execution plans](#execution-plans) |
| Judge observations that a host collected | [Host observations](#host-observations) |
| Prove that evidence is current, intact, reviewed and complete | [Evidence provenance](#evidence-provenance) |
| Plan captures, classify console output or capture a window | [Host adapters](#host-adapters) |
| Test engine-facing logic without Roblox | [Simulated environment](#simulated-environment) |
| Compose reflection, UI fakes and the engine seam | [Reflection and explicit UI fakes](#reflection-and-explicit-ui-fakes) |

Examples use these package names. Replace the paths with the locations of your mounted packages:

```luau
local Core = require(path.to.verify.core)
local Bdd = require(path.to.verify.bdd)
```

The optional packages are:

- [`Lute`](../src/lute/init.luau), [`Lune`](../src/lune/init.luau) and [`Roblox`](../src/roblox/init.luau).
- [`Gate`](../src/gate/init.luau), [`Evidence`](../src/evidence/init.luau) and [`Benchmark`](../src/benchmark.luau). They run on the host side. A place mounts only core.
- [`Host`](../src/host/init.luau) and [`Consumer`](../src/consumer/init.luau).

Each entry point exports its public functions and types.
The [working example](../examples/basic.luau) is a case and report that you can run directly.
The [laws](laws.md) define the lifecycle and evidence boundaries.

---

## Cases and sessions

### `Core.createHarness`

`createHarness({ now, source?, prefixIds? }) -> Harness`

`Core.createHarness` creates an isolated registry.
Register cases, then call `harness:run` to receive their results.
Importing Verify does not create a shared registry.

`harness:run` returns failed and unsupported results in its report. It does not set the process exit code.
The caller must judge the report and make its command fail when the required claim is unmet.
The [repository gate](running.md#repository-gate) checks that a corpus is nonempty and passes entirely.

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

Supply a monotonic `now` function. This example uses a synthetic clock.
`source` associates the registry with its source.
`prefixIds` controls source prefixes in case IDs. It defaults to true when you supply a source.
Prefixing requires a source and does not change selection visibility.

### Registration and execution

| Method | Purpose |
| --- | --- |
| `harness:suite(name, register)` | Group the cases that a callback registers. |
| `harness:case(name, run)` | Register a callback that receives a case context. |
| `harness:case(name, options)` | Supply `run` and optionally `id`, `requires`, `tags`, `limitations`, `timeoutSeconds` and `cleanupTimeoutSeconds`. |
| `harness:skip(name, reason, run?)` | Register a deliberate omission with its reason. |
| `harness:beforeEach(run)` | Register setup for the cases in the current suite. |
| `harness:afterEach(run)` | Register teardown for the cases in the current suite. |
| `harness:run(options)` | Execute the selected cases and return a report. |

Run options name the `executor`. They can also supply `environment`, `capabilities`, `selection`, `invoke`, `bind` and `cancelled`.
Selection supports IDs, suite prefixes, sources, a case-name substring (`nameContains`, plain text), tags, capabilities and a predicate.
Every field that you set must match.
A focused result records that execution. It does not establish a complete gate.

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

A required capability that the run lacks produces `unsupported`, not a pass.
A deliberate skip produces `skipped`.
The optional invoker owns interruption. It must stop the work before it reports a cancellation or a timeout.
See [execution](execution.md) for host deadlines and policy.

### Case context

The context records assertions, steps and artifact references. It owns case-local cleanup.

| Method | Purpose |
| --- | --- |
| `context:expect(value)` | Create an assertion. |
| `context:step(name, run)` | Record a named step and its outcome. |
| `context:step(name, { run, actor? })` | Associate a step with an actor. |
| `context:artifact(name, reference, mediaType?)` | Attach a reference to evidence. |
| `context:attach(name, mediaType, text)` | Attach text that the case produced. The host stores it. |
| `context:defer(cleanup)` | Register cleanup for the end of the case. |
| `context:own(resource)` | Own a cleanup function or a table with `dispose` or `destroy`. |
| `context:skip(reason)` | Stop the current case with a deliberate skip. |
| `context:perform(actor, operation, input)` | Execute a typed action or query. |
| `context:await(actor, query, input, predicate, pollSeconds)` | Poll a read-only query within the case deadline. |
| `context:checkpoint(actor, name)` | Capture evidence through the bound host. |
| `context:judge(actor, checkpoint, criterion)` | Require an explicit review of captured evidence. |
| `context:measure(actor, name, input, limits)` | Check observed performance against explicit limits. |
| `context:remainingSeconds()` | Read the current body or cleanup budget. |

The [one case model](experience.md#one-case-model) owns typed operations, host binding, deadlines and evidence.
`Core.runCase({name, ...caseOptions}, host)` runs one ordinary case and returns the standard report.
Use `Core.observationParity` to compare the action and query observations of two reports.

`Core.Resource<T>` types a resource for `context:own`. It is a cleanup function or a `T` with a `dispose` or `destroy` member.
Declare the receiver of a disposal callback as the complete resource type.

Cleanup runs once, newest first.
Setup, case, teardown and cleanup failures stay visible independently. A later failure does not erase an earlier one.
Hooks and cleanup use the same invocation contract as the case.
An artifact reference records a location. It does not save or authenticate bytes.

#### Inline attachments

`context:attach(name, mediaType, text)` records text that the case produced in the engine.
The text travels in the report. The host then writes it to a file and replaces it with an ordinary artifact entry.
The entry has `reference`, `mediaType`, `size` and `sha256`. `Evidence.seal` stores it like any other artifact.
Attachments are data. They never prove that a case passed.

The text must be valid UTF-8 and not empty. Binary content is refused.
`name` is a relative path. It must not be empty, start with `/`, contain `\`, a control character, an empty segment or a `.` or `..` segment.
A name is unique within a case.

Limits fail closed. A broken limit raises an error from `attach`, the step fails and cleanup still runs.

| Limit | Default | Option |
| --- | --- | --- |
| Bytes of one attachment | 1048576 | `maxBytes` |
| Attachments in one case | 16 | `maxCount` |
| Bytes in one report | 4194304 | `maxTotalBytes` |

Set the limits with `attachments` in `Core.createHarness` or in the run options. The run options win.
`Core.attachmentDefaults` holds the defaults.

`Lute.attachments.materialize(report, { directory, sink?, limits?, supported?, host? }) -> report, issues` is the host step.
It checks the limits again and writes `<directory>/attachments/<case id>/<name>`.
A `sink(caseId, name, text, meta) -> reference, reason` replaces the file write. `meta` is `{ mediaType, sha256, size }`.
`issues` lists each attachment that was refused, not stored or unsupported. `Lute.platform.run` adds them to the report as a failed case `verify:attachments`.
`Lute.platform.run` accepts `attachments` for the limits and `attachmentSink`.
`Evidence.validate` also hashes again each sealed artifact of a case, so a changed stored attachment fails validation.

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

The surface contains `describe`, `it`, `itSkip`, `beforeEach`, `afterEach`, `expect`, `spy` and `skip`.
Case and hook bodies receive `(own, context)`. `own` registers a cleanup function.
Use `itSkip(name, reason, body?)` during registration and `skip(reason)` during a case or hook.

`it(name, { run, id?, requires?, tags?, limitations? })` passes the same case metadata as `harness:case`:

- `id` fixes the case identity.
- `requires` names capabilities. A missing capability makes the case `unsupported`.
- `tags` select cases.
- `limitations` appear in the report.

`Bdd.surface({executor, environment, capabilities, ambientSource, now?, selection?})` returns one session-backed surface.
It holds the verbs above and these members: `load(source, register)`, `adoptReport`, `sourceReport`, `run`, `setSelection(selection?)`, `reset` and `useHarness`.
`selection` and `setSelection` use the selection of the harness and the session.
`load` opens the source and registers it. It adopts a registration error as a failed source report.
`Bdd.formatResults(report, title?)`, `Bdd.formatFailures` and `Bdd.counts` print a report.
A unit case, an engine-integration case and an end-to-end case use this one vocabulary.
They differ in the capabilities that they require and the evidence that they attach, not in the runner.

### `Core.createSession`

`createSession(options) -> Session`

`Core.createSession` keeps the type of the factory surface in `verbs` and `current()`.
It owns one registry per source. Use it when modules register their cases as they load.
The options require `executor` and `environment`.
Optional fields are `capabilities`, `now`, `surface`, `runtimeVerbs`, `prefixCaseIds` and `selection`.
With solver v2, declare factory options as `Core.SessionProvidedOptions<YourSurface>` before you call the overloaded constructor.

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
| `open(source)` / `close()` | Enter and leave the registration scope of a source. |
| `harness()` / `current()` | Access the harness or the supplied surface of the active source. |
| `verbs` | Route calls through the surface of the active source. |
| `adoptReport(source, report)` | Include an existing source report. |
| `sourceReport(id, source, status, detail)` | Construct a source-level failed or skipped report. |
| `setSelection(selection?)` | Set which cases to run. |
| `run()` / `reset()` | Execute the queued sources or reset the session state. |

Call session methods with `:`.
A `surface` factory maps registration verbs to each harness.
`runtimeVerbs` routes verbs such as `skip` while cases run.
A reset or a reentry during a run fails and keeps the queued sources.
The [worker examples](execution.md#lute-workers) show module-loading integration.

---

## Assertions and spies

### `Core.expect`

`expect(value) -> Expectation`

Use `expect` directly, through a case context or through the BDD surface.
Chain `.never` before a matcher to negate it.

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
| `toBeNil`, `toBeOk` | Nil and non-nil checks. `false` is non-nil. |
| `toBeTruthy`, `toBeFalsy` | Truthiness checks. |
| `toBeTrueWith(detail)` | A true value, with a supplied failure detail. |
| `toBeCloseTo`, `toBeNear`, `toBeFloat32` | Numeric tolerance or single-precision representation. |
| `toBeLessThan`, `toBeGreaterThan`, `toBeLessThanOrEqual`, `toBeGreaterThanOrEqual` | Numeric ordering. |
| `toContain`, `toContainExactly`, `toHaveLength` | Containment and length. |
| `toThrow(contains?)`, `toThrowMatching(pattern)` | A thrown error, with optional plain text or a Luau pattern. |

`toThrow` uses plain text containment. Use `toThrowMatching` for patterns.
`Core.float32(value)` returns the single-precision value.
The exact matcher signatures are in [`matchers.luau`](../src/core/matchers.luau).

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

Inspect `calls`, `called()`, `lastArgs()` and `lastReturn()`.
Use `reset()` to clear the recorded calls.
Use `returnValue(value)` to supply a fixed return and `implementation(fn)` to replace the callback.

---

## Reports and transport

A schema-v1 report retains the executor, environment, capabilities, sources and case results.
Each case result retains status, timing, failures, steps, artifacts, limitations and origin.
The counts must agree with the result rows.

| Status | Meaning |
| --- | --- |
| `passed` | The executed case passed. |
| `failed` | An assertion, a lifecycle phase or an execution recorded a failure. |
| `skipped` | The case was deliberately omitted, with a reason. |
| `unsupported` | A required capability was unavailable. |
| `timed_out` | The invoker reported that it stopped the timed-out work. |
| `cancelled` | The invoker reported that it stopped the cancelled work. |

### Validate and combine

| API | Use it to… |
| --- | --- |
| `Core.decode(value)` | Validate a foreign report and its schema. |
| `Core.merge(reports, executor, environment)` | Combine trusted reports. |
| `Core.compose(payloads, executor, environment)` | Account for every expected shard, including missing, malformed and duplicate outcomes. |
| `Core.syntheticReport(options)` | Record work that a host could not reach. |
| `Core.format(report)` | Produce readable output. Each case that carries measurements adds one line for each measurement: name, unit, sample count, `p50`, `p95`, declared extra percentiles and the evaluation reason. |
| `Core.canonical(value)` | Produce a deterministic representation. |
| `Core.verdictDigest(report)` / `Core.verdictDifferences(left, right)` | Compare verdicts without treating timings as deterministic. |

```luau
local combined = Core.compose({
    { id = "worker-1", report = report },
    { id = "worker-2", error = "worker exited before returning a report" },
}, "local-workers", { revision = "working-tree" })

print(Core.format(combined))
```

Supply every launched shard, including errors.
If you omit an unsuccessful worker from the input, the result cannot establish that all expected work passed.

### Move reports between hosts

| Surface | Transport |
| --- | --- |
| `Core.frame`, `extract`, `reassemble`, `receipt` | Tagged log lines. |
| `Core.segment`, `reassembleSegments` | Bounded payload arrays. |
| `Lute.encode`, `parse` | Any JSON value to text, and JSON text to a plain value. |
| `Lute.decode` | JSON text to a validated report. |
| `Lute.segmentReport`, `reassembleReport` | Reports carried in bounded segments. |

Missing, conflicting and mixed chunks fail.
**JSON decoding is not report validation.** Validate each received report with `Core.decode`.
The consumer binds executor identity and owns authenticity.
[Report transport](execution.md#report-transport) describes the run-bound channel.

## Execution plans

A plan names a finite set of work and its requirements.
The consumer supplies discovery, the meaning of each locator and an authorized host.

| API | Responsibility |
| --- | --- |
| `Core.validateManifest`, `planFromManifest` | Validate a manifest, then derive a plan from it. |
| `Core.validatePlan`, `selectPlan`, `partitionPlan` | Normalize, select and divide planned work deterministically. |
| `Core.planDigest`, `caseId` | Bind the meaning of a plan and compose case identities. |
| `Core.negotiate`, `explainCapabilities` | Determine and explain capability support. |
| `Core.execute(plan, host, options?)` | Execute batches with lifecycle and failure accounting. |
| `Gate.define`, `run`, `format`, `shard`, `testCases`, `rerun`, `explain`, `list` (package `src/gate`); `Lute.gate` and `Lune.gate` (`run`, `last`, `cli`, `writeReport`) | Declare producers and execute them as one accounted plan with an acceptance verdict. See [declarative gates](execution.md#declarative-gates). |
| `Benchmark.case`, `run`, `collection`, `collect`, `store`, `storeReport`, `decode`, `compare`, `spread` (`src/benchmark.luau`) | Warm up, sample and check baselines and stability. Report the result as an ordinary case. Store, compare and summarize runs. See [benchmarks](experience.md#benchmarks). |

[Execution](execution.md) describes fixtures, deadlines, retries and Lute workers.
[`Host.fake`](../src/host/init.luau) injects missing, duplicate, reordered, failed and cancelled deliveries without external effects.

---

## Host observations

Use typed operations, `context:perform`, `await`, `checkpoint`, `judge` and `measure` in the ordinary case.
Evidence lives in `CaseResult.evidence` and uses the standard report transport.
The [experience contract](experience.md) describes binding. The [execution contract](execution.md) describes hosts.

## Evidence provenance

Evidence travels on the report.
An `Artifact` can carry `sha256`, `size` and a typed `provenance`. Provenance holds:

- The run, case, actor and checkpoint.
- The build (`commit`, `tree`, `clean`, `digest`).
- The executing host and its capabilities, taken from the case origin.
- The `device` class that the caller declares, and `capturedAt`.

A `Review` can carry `kind` (`visual` or `audio`) and `judged`, the content hashes that the reviewer saw.
The report decoder keeps both. The report is the only record. No second record exists.

### Seal, bind and validate

- `Evidence.seal(report, { from, device, now, hash, read, sink })` reads each artifact and stores its bytes in `sink`.
  It returns `{ report, issues }`.
  `from` is any `{ runId, build }`, such as a gate outcome. It replaces `runId` and `build`.
  An artifact that is unreadable, unstorable or unconfirmed stays unsealed and appears in `issues`.
- `Lute.evidenceStore.seal` binds the Lute hash, file reader, clock and a local directory store.
  The whole call is `seal(outcome.execution.report, { from = outcome, device })`.
- `Evidence.bindReview(report, { caseId, actor, checkpoint, kind, judged })` binds a recorded review to the content hashes that the reviewer judged.
  Hash what the reviewer saw, not what you store later.
- `Evidence.validate(report, policy)` returns `{ ok, issues, verified }`. It hashes every artifact again through `policy.store`.
- `Evidence.explain(result)` formats a validation result.

The validation policy declares these fields:

- The expected build, from `from` or from `build`. `requireClean` refuses dirty builds. It defaults to true with `from`.
- `now`, `maxAgeSeconds` (default 3600) and `maxSkewSeconds` (default 5).
- Optional `runId`, `hosts` and `capabilities`.
- `required` coverage, a list of `{ caseId, actors, checkpoints, devices, mediaType?, reviews? }`.
  `Evidence.expand` expands each entry as a cross product.

Validation rejects these conditions:

- A mismatched build, or a stale or future capture.
- Missing coverage, or a wrong run, host, actor, checkpoint or device.
- A duplicate or conflicting observation, or a missing identity.
- A changed or unavailable artifact.
- A missing, unbound, failed or wrong-artifact review.

An empty policy or an invalid clock raises. It never passes.

### Sinks

A sink is `{ put(content, meta) -> reference, get(reference) -> bytes, stat(reference) -> { size } }`.
The caller supplies it.

- `Lute.evidenceStore.localDirectory(path)` is the content-addressed reference sink.
- `Core.memorySink(hash)` is a portable sink.
- `Lute.evidenceStore.validate(report, { from, required })` fills in the store, hash and clock.
- Lune has no local store binding. Pass `hash`, `read` and a sink to `Evidence`.

Validation needs only `get`, `stat`, a hasher and a clock, so it runs unchanged under Lute and Lune:

```sh
lute run examples/evidence-provenance/lute.luau
lune run examples/evidence-provenance/lune.luau
```

Metadata and a saved screenshot do not establish visual quality, audio quality or physical-device use.
A review records that a named reviewer judged specific content. `device` is a claim.
The class `physical` is accepted only when `policy.attest.physical(artifact, provenance)` returns true from the caller's own evidence.

---

## Host adapters

Adapters use host operations that you inject.
The consumer owns authorization, destinations, artifact custody and release acceptance.
Load only the package that the observation needs.

For Studio, Player and Open Cloud, see [execution](execution.md):
[native Studio](execution.md#native-studio-execution), [attached Studio](execution.md#attached-studio),
[published Player](execution.md#published-player-execution) and [Open Cloud](execution.md#open-cloud-execution).

### Capture coverage

Coverage lives in the ordinary case and in evidence.

1. Record each tool call with `context:step`. A step keeps its order, status and duration in the case result.
2. Record each saved output with `context:checkpoint`.
3. Call `Evidence.expand(required)`. It expands the `required` coverage of a policy into one cell per case, actor, checkpoint and device class.
   A cell is `{ caseId, actor, checkpoint, device, mediaType?, reviews? }`.
4. Drive your capture from the cells.
5. Call `Evidence.seal` to hash each artifact and bind its provenance.
6. Call `Evidence.validate`. It rejects any cell without an observation.

The consumer owns tool execution, request digests, storage paths, authorization and the meaning of each checkpoint.

### Console classification

`Core.classifyConsole(lines, options)` and `classifyConsoleText(text, options)` return the lines that match `options.errorPatterns`.
`splitConsoleLines(text)` splits text into lines.
The caller must supply the error patterns. Core has no default patterns.

Options also accept `ignorePatterns`, `ignore`, `caseInsensitive` and a pair of `blockBeginPatterns` and `blockEndPatterns`.
An ignored line removes a block that follows it.
`Roblox.consolePatterns` holds `errors`, `blockBegin` and `blockEnd` for the Roblox output log.

### Window capture (macOS reference)

`Lute.windowCapture` is the reference adapter that captures a Studio or Player window on macOS.
It runs no command. It decides from facts that you inject.

- `parseWindowRows` reads rows of `pid`, `id`, `layer`, `width`, `height` and `owner`, separated by tabs.
- `selectWindow` and `documentWindowSize` choose the largest document window of one process.
- `captureFrame` captures that window with your `deps` and crops it to a viewport.
  It checks that the file is a PNG of sufficient size.
- `checkpointFrames` checks that each checkpoint has one distinct frame that is not the whole window.
- `recordCapture` returns a capture record. The record binds kind, target, source commit, console hash, console error lines, image hash and byte count.
- `decodeCapture` accepts only a record of the expected kind and target.
- `checkCapture` accepts a record only when the source is unchanged or an ancestor, the image is not empty and the console has no error line.

A capture record is not the run-bound worker receipt. It claims no judgment.
The consumer owns run freshness, image custody and clean-image coverage.

### Observation sinks and place fixtures

`Roblox.observationSink` provides these parts:

- Escaped and chunked wire data, and bounded values.
- Markers, tallies and reference pooling.
- Owned observation seams, arming, and publication into an injected node tree.

It must not replace or destroy state that the host owns.
In-engine adapters can import this leaf directly.

`placeBoot`, `bootPlace`, `buildPlaceTree`, `createPlaceCache` and `createPlaceRuntime` build and run injected place fixtures over an engine that the consumer supplies.
Their reports test the declared boot phases and ownership.
They do not simulate all engine behavior.

---

## Simulated environment

`Roblox.testEnvironment(options?)` is the optional simulated engine for headless tests.
It is plain Luau. It depends on no consumer and reads no generated paths. Do not mount it in a released place.

### What the simulator proves

The simulator proves Luau logic over the declared surface, ordering and disposal.
It does not prove rendering, physics, replication, animation, audio, input devices or player capacity.
Check a supported behavior against the real engine before you rely on it.

| Layer | Behavior comes from | Engine parity |
| --- | --- | --- |
| `Roblox.testEnvironment` | Built-in and declared classes, and the explicit fakes that you supply. | None. A method that is declared but not implemented raises `unsupported_method`. |
| `Roblox.reflection` and `Roblox.fixtureBridge` | Class defaults and property types from a reflection database. Events, methods, layout, rendering, input and physics exist only where you declare or inject them. | None. The database supplies metadata only. |
| `Lute.fixture.bridge` | A serialized reflection snapshot. It needs no Lune runtime. | None. A Lune test compares it with the native bridge. |
| `Lune.fixture` | The real database and datatypes of `@lune/roblox`. | Metadata from the engine. Behavior stays simulated. |
| Native Studio or Player host | The engine. | The engine. See [execution](execution.md#native-studio-execution). |

### Defaults and opt-in conveniences

| Behavior | Default | Option |
| --- | --- | --- |
| A handler error only prints, so the environment collects it | Engine-true. | `handlerErrors = "raise"` is a test convenience. |
| A signal count for any signal | Added metering. | None. |
| An unknown member raises | Engine-true. | `fakeOn` and `functionDoubles = true` are test doubles. |
| A write that targets a rejected selection is ignored | `"raise"` is a test convenience. | `ui.selection = "ignore"` is engine-true. |
| A selection outside a `PlayerGui` is allowed | Engine-true. | `ui.requirePlayerGui = true` is a test convenience. |
| `TweenInfo`, `FloatCurveKey` and `Path2DControlPoint` fields | Engine-true values and defaults. | None. |
| A property with no stored default reads `nil` | Engine metadata only. | `defaultProperty` and the `Lune.fixture` native read give the engine value. |
| A derived property such as `TextBounds` | Reads as stored. | `computed` is a test convenience. A computed property is read-only unless it declares `writable = true`. |
| An undeclared write raises | Engine-true. | `undeclaredWrites = true` is a test convenience. |
| An undeclared read raises | Engine-true. | `undeclaredReads = "nil"` is a test convenience. |
| `GetStyled` and `GetStyledPropertyChangedSignal` | Plain property fakes. | None. |

### Options and result

`options` has these fields:

- `classes`: a table of `{super?, creatable?, properties = {name = default}, events = {names}, methods = {name = function | true}}`.
  The built-in classes are `Instance`, `Folder`, `Model`, parts, `GuiObject` (size, position, color, anchor), `Frame`, `CanvasGroup`, `ScrollingFrame`, `TextLabel`, `TextBox`, buttons, `UIListLayout`, `UIPadding`, `ScreenGui`, `Humanoid`, `Animation`, `Animator` and `AnimationTrack`.
- `builtins = false` omits `Roblox.BASIC_ENVIRONMENT_CLASSES`.
- `fakes`.
- `limits`: `attributeNameLength` (default 100) and `attributeStringLength` (unbounded unless set).
- `handlerErrors`: `"collect"` (default) or `"raise"`. See [handler errors](#handler-errors).
- `computed`: a table of `["Class.Property"] = function(object) -> value`. See [computed reads](#computed-reads).
- `undeclaredWrites = true` accepts a write to a property that the class does not declare. See [undeclared writes](#undeclared-writes).
- `functionDoubles = true` lets a function assignment install a method double. See [method doubles](#method-doubles).

The result has these members:

- `root`, `createInstance(className, props?)`, `defineClass`, `newSignal`, `heartbeat`.
- `task` with `spawn`, `defer`, `delay`, `wait` and `cancel` on virtual time. Also `scheduler`, `step(seconds)` and `now`.
- Inspection: `childrenOf`, `parentOf`, `propertyOf`, `attributeOf`, `isAlive`, `liveObjects` and `liveConnections`.
- `poke` and `fire`, which apply an engine-side change and an engine-side event.
- `failNext(operation)` and `clearFailures`.
- `errors`, the handler errors that the engine would only print.
- `snapshot(object)`, which returns class, name, set properties, attributes and children as a table for debugging.
- `fake(member, handler)` and `fakeOn(object, name, handler)`.
- `connectionsOf(signal)`, `firesOf(signal)` and `connectionsOfInstance(object)`.

`createInstance` takes children in the array part: `createInstance("Model", {Name = "m", childA, childB, Parent = root})`.
`Roblox.isInstance(value)` and `Roblox.typeName(value)` identify instances and datatypes.
`Roblox.virtualScheduler()` is the scheduler alone.

The package exports the types `Environment`, `EnvironmentOptions`, `EnvironmentDefineOptions`, `EnvironmentSnapshot`, `EnvironmentMethod`, `Signal`, `Connection`, `VirtualScheduler`, `VirtualTask` and `VirtualCallback`.
Instance properties and per-class methods are dynamic schema boundaries.
Their values still need the class contract of the consumer.
Assigning a method dictionary does not prove its signatures.

### Datatypes

`Roblox.datatypes` holds these members:

- Constructors for `Vector2`, `Vector3`, `Color3`, `UDim`, `UDim2` and `CFrame`, with value equality.
- `TweenInfo.new(time, style, direction, repeatCount, reverses, delay)`.
  It has the fields `Time`, `EasingStyle`, `EasingDirection`, `RepeatCount`, `Reverses` and `DelayTime`.
  The defaults are 1, `Enum.EasingStyle.Quad`, `Enum.EasingDirection.Out`, 0, false and 0.
  It is an attribute value. Two values with equal fields are equal.
- `FloatCurveKey.new(time, value, interpolation)` has the fields `Time`, `Value` and `Interpolation`.
- `Path2DControlPoint.new(position, leftTangent?, rightTangent?)` has the fields `Position`, `LeftTangent` and `RightTangent`.
  Each tangent defaults to `UDim2.new(0, 0, 0, 0)`.
  `FloatCurveKey` and `Path2DControlPoint` are not attribute values, as in the engine.
  Both have value equality.
- The other constructor shells, each typed by `typeName`.
- A permissive `Enum`, `typeName(value)` and `readCFrame(cframe) -> (x, y, z, {nine rotation numbers})`.

`Animator:LoadAnimation` returns a track.
`Play`, `Stop` and `AdjustSpeed` change `IsPlaying` and `Speed` and fire `Stopped` and `Ended`. The simulator blends no frames.
The package exports `DatatypeVector2`, `DatatypeVector3`, `DatatypeCFrame`, `DatatypeColor3`, `DatatypeUDim`, `DatatypeUDim2` and `DatatypeEnum` for supported values.
These types describe the simulated surface, not every native Roblox member.

### Instance behavior

- Instances support `Parent`, `Name`, children events, find and ancestor lookups and `GetFullName`.
- `Destroy` locks the parent, destroys the descendants and disconnects the signals of the instance.
- Attributes have change signals. Property change signals fire only on change.
- Signals fire in connect order. A connection that disconnects during a fire is skipped.
- `signalOf(object, event)` returns `{ fire, connections, fires }` for one event.
  A test can fire the event and count its live connections and fires.
- `connectionsOf(signal)` and `firesOf(signal)` count any signal that the environment made.
  That includes `GetPropertyChangedSignal` and `GetAttributeChangedSignal` results, `heartbeat` and `newSignal()` results.
  A signal from another source raises.
  `connectionsOfInstance(object)` totals the live connections on the event, property and attribute signals of one instance.
  These counts are test conveniences. They change no engine behavior.
- `onCreate(hook)` sees every new instance, including clone copies.
- Attributes accept string, number, boolean, nil, BrickColor, CFrame, Color3, ColorSequence, EnumItem, Font, Instance, NumberRange, NumberSequence, Rect, TweenInfo, UDim, UDim2, Vector2 and Vector3.
  The simulator refuses every other value, including tables, functions and buffers, by type name.
  It judges native userdata by its `typeof` name against the same list.
- A read of a name that is not a property, event or method returns the first child with that `Name`, as the engine does.
  A property, event or method of that name wins.
- Any other unknown read and every unknown write raises the engine error "is not a valid member".
- `defineClass` refuses an existing class, including a built-in class. Call `defineClass(name, spec, {replace = true})` to replace it.
  The new spec replaces the old spec for instances that you create afterward. It is not merged.
- A method declared as `true` has no behavior.
  A call raises `unsupported_method: Class.Method ...` unless a function is given in `methods`, in `options.fakes` or through `fake("Class.Method", handler)`.
  A schema that describes an API is never an implementation. A test that needs a result supplies it explicitly.
- `Clone()` remaps instance references inside the clone, and copies attributes and tags.
  It omits nonarchivable descendants and leaves external references external. It does not copy signals.
- The environment includes recursive `FindFirstChildWhichIsA`, exact and inherited ancestor lookup and instance tag methods.

### Reflection and behavior adapters

The built-in schemas are a small declared test surface. They are not a complete reflection database.
Use the [reflection and UI adapters](#reflection-and-explicit-ui-fakes) for standard integration.

A custom environment can supply two functions:

- `defaultProperty(className, property, fallback)`. A returned `false` is a real default. Return `fallback` for an unmapped property.
- `validateProperty(className, property, value, operation)`. `operation` is `set` for an authored assignment and `poke` for a simulated engine change.

A class property that you declare as `false` has no default and reads `nil`.
Reflection declares every database property that way.
A property for which the database stores no default reads `nil`, unless the consumer overlay declares a value.
A stored `false` stays `false`.
Validation runs before mutation.
Explicit fakes do not establish native rendering or input fidelity.

### Handler errors

The engine prints an error that a handler raises. It does not raise the error to the caller.
The default `handlerErrors = "collect"` matches the engine. The environment appends each message to `errors`.

`handlerErrors = "raise"` is an opt-in test convenience.
After a property write, `poke`, `Parent` change, attribute change, method call, `fire` or `Signal:Fire`, the environment rethrows.
It joins every message that the operation collected with a newline, removes them from `errors` and raises the result.
Every handler still runs first. A nested operation inside a handler does not raise on its own.
An error from the operation itself wins and leaves the handler messages in `errors`.
Any other value of `handlerErrors` raises when you create the environment.

### Method doubles

A class declares each member that an instance has. A read of any other member raises.
A test sometimes needs a member that the schema omits, such as `GetFocusedTextBox` or `IsKeyDown`.

- `fakeOn(object, name, handler)` installs `handler` for that instance only.
  The call passes the instance as `self`. A second call replaces the first.
  It raises for a property, an event, `ClassName` and `Parent`. It never reaches another instance or a clone.
- `functionDoubles = true` lets `object.Name = function(self, ...) end` do the same.
  A function written to a declared property still goes through validation.
  Without the option, a function assignment to an undeclared member raises "is not a valid member".

Both forms are test doubles, not engine behavior. The engine has no such assignment.
The option is off by default because it would turn a mistyped assignment into a silent member.
`fakeOn` is explicit and always available.
A double wins over a declared method of the same name.
A reference that you read before a replacement keeps the earlier handler.

### Computed reads

`computed = { ["TextLabel.TextBounds"] = function(object) return value end }` answers a read of a derived property.
The key is a class name and a property name. A getter on a class also applies to its subclasses.
It also makes an undeclared name readable, and `GetPropertyChangedSignal` accepts it.
A write or a `poke` to a computed property raises.
Declare `{ get = fn, writable = true }` instead of the function to opt in to writes.
A write or a `poke` then stores the value and notifies as a normal write does.
A read returns the getter result, or the stored value when the getter returns nil.
`Clone` copies the stored value of a writable computed property.
The getter runs on every read. Fire the changed signal with `poke` on a stored property that it depends on.
`propertyOf` and `snapshot` return stored values only.
This is a test convenience. It does not compute layout or text metrics. The getter you supply does.

### Undeclared writes

The engine refuses a write to a property that the class does not have. The default matches.
`undeclaredWrites = true` is an opt-in test convenience.
`undeclaredReads = "nil"` is also opt-in. A read of a key that is not a property, an event, a method, a child or a method double then returns `nil`. This includes a key that is not a string. Writes still follow `undeclaredWrites`.
A write or `poke` then stores the value, fires the property signals and makes the name readable and cloneable.
A read of a name that nobody wrote still raises.
Events, methods and `ClassName` still refuse a write.
Validators still run. The reflection adapter still checks every declared property.

### Hierarchy events

- The events are `AncestryChanged`, `DescendantRemoving` and, for a subtree, `DescendantAdded`.
- Moving a subtree notifies the ancestors that it leaves or enters. A common ancestor receives neither event.
- Removal runs before detachment, with the root before its descendants.
- An ancestry callback on the moved instance or its descendants receives the moved instance and its new parent.
- A same-parent assignment emits no events.
- Reparenting the removing instance from its removal callback fails.
- The simulator dispatches immediately. A native deferred signal mode can expose different callback timing and observed state.
- The order across events beyond these guarantees is not a contract.

---

## Reflection and explicit UI fakes

### Reflection

`Roblox.reflection.create { database, typeName, enumType?, classes?, referenceClass?, validateProperty? }` builds an environment from a Lune-compatible reflection database.
Pass `roblox.getReflectionDatabase()` and the `typeof` function of the runtime.

- `enumType(value)` returns the enum family name, with or without the `Enum.` prefix.
- The adapter inherits class defaults, rejects unknown and read-only writes, and validates native datatypes.
- `referenceClass(className, property)` narrows reference properties. The `Ref` metadata of Lune does not include the target class.
- `classes` overlays explicit events and methods.
- `validateProperty` adds fixture restrictions.

The portable package imports no Lune runtime.
`lune run tools/check-reflection.luau` checks the real integration.

### Fixture bridge

`Roblox.fixtureBridge { database, typeName, enumType?, library?, classes?, referenceClass?, validateProperty?, defaultProperty?, handlerErrors?, computed?, undeclaredWrites?, functionDoubles?, ui? }` composes reflection, the event metadata of the simulator, UI fakes and the engine seam over one environment.

- UI fake classes that the database lacks appear in `unavailable`. The bridge does not invent them.
- `ui = false` omits the UI fakes. Entries in `classes` replace the defaults.
- `ui.validate(className, property)` keeps UI property validation for the pairs that it accepts. It relaxes the rest while every fake stays installed.
- `ui = { validate = false }` installs no UI validator.
- UI validation acts only on `SelectedObject`. Every other write makes no extra call.
- `ui.selection` is `"raise"` (default) or `"ignore"`. See [rejected selection](#rejected-selection).
- `ui.requirePlayerGui = true` requires the target to descend from a `PlayerGui`.

The options `defaultProperty`, `computed`, `handlerErrors`, `undeclaredWrites` and `functionDoubles` pass to the environment.
`Lute.fixture.bridge` and `Lune.fixture` accept the same options.

The bridge returns `{ environment, engine, ui, unavailable, faults, hasClass, observe, track, record, instanceHost, accounting, close }`.

- `track()` lists created instances and cloned `{ source, copy }` pairs until `stop()`.
- `faults` wraps `failNext`. `assertConsumed` refuses an injection that never fired.
- `observe` and `record` report each create, property, attribute, parent and destroy operation. They mark injected failures. Each event also carries the `object` and, for property, attribute and parent operations, the new `value`.
- `accounting` and `close` return the live objects, the live connections and the pending faults.
- `instanceHost(actor)` reuses the same environment.

`Lune.fixture(options?)` in `src/lune` binds the real database and datatypes of `@lune/roblox` to the bridge.
`lune run examples/lune-fixture.luau` shows a consumer.
Application-specific UI expectations stay with the consumer.

This is simulated behavior that is validated against engine metadata. It is not engine parity.
Instances are Luau tables. Defaults and property types come from the database.
Events, methods, layout, rendering, input and physics exist only where you declare or inject them.

### Defaults that the database does not store

`defaultProperty(className, property)` is a bridge option. The bridge calls it for a declared property that has no stored default and no overlay value.
The order is the database default, then an overlay value, then the hook, then `nil`.
Return `nil` for no default.
A declaration is never a default. Without a hook such a property reads `nil`.
`ResetPropertyToDefault(property)` restores the same value and fires the changed signals when the value differs.
It does not validate, because the value comes from the environment. It raises for an undeclared property.
It also works on `Roblox.testEnvironment`, where the default is the declared value.

`Lune.fixture` and `Lune.fixtureFrom` supply this hook from a real `Instance.new(className)` of `@lune/roblox`.
The database omits some properties of a class that you cannot create, such as `FormFactor` on a `Part`. The native instance supplies them.
They read the property from that instance and return `nil` for a class that `Instance.new` refuses, an unreadable property or an instance value.
Pass your own `defaultProperty` to replace it.
`fixtureFrom` uses the hook only when its native table has an `Instance` constructor.
This is engine metadata.

### Reflection snapshots

Under Lute, a serialized reflection snapshot replaces the Lune database at test time.

`lune run tools/export-reflection.luau <out.json> [--classes=A,B,...]` writes a deterministic, compact snapshot.
The snapshot holds the named classes and their superclasses. It records property types, scriptability, tags and defaults.
It records defaults only for Vector3, Vector2, Color3, UDim, UDim2, CFrame, EnumItem, string, number and boolean values.
It omits other default types. Without `--classes`, it exports every class.

- `Lute.fixture.bridge(path | snapshot, options?)` builds the same bridge from that file with no Lune runtime.
- `Roblox.reflectionSnapshot.database(snapshot)` and `.bridge(snapshot, options?)` are the portable forms.
- Values are Verify datatypes. Enum items carry their family (`Enum.Material.Plastic`). Verify checks them against the enum of the property.

A Lune test compares the snapshot path with the native bridge for classes, properties, defaults and accepted and refused writes.
After a Roblox API update, regenerate a committed snapshot. The Lune test fails when a fixture is stale.

### UI fakes

`Roblox.uiFakes.classes` declares optional UI methods.
Supply it as a class overlay.
Pass `uiFakes.validateProperty` as the property validator to reject the selection of hidden or unselectable controls.
`Instance:GetStyled(property)` reads the plain property.
`Instance:GetStyledPropertyChangedSignal(property)` returns the property changed signal.
Both are test fakes. They apply no style rules.

#### Rejected selection

When the real engine gets `GuiService.SelectedObject = target` for a hidden, disabled or unselectable control, it ignores the write.
The default `ui.selection = "raise"` raises instead, so a test finds the mistake.
`ui = { selection = "ignore" }` is the engine-true mode.
It drops the write with no error, no signal and no change.
`controller.rejectedSelections()` lists each `{ target, reason }` in order.
A hidden ancestor, a disabled `ScreenGui` and `Selectable == false` reject.
A value that is not a `GuiObject` still raises in both modes.

`ui.requirePlayerGui = true` makes a target outside a `PlayerGui` raise in both modes. It is an opt-in test convenience.

A `validateProperty` function that returns `false` vetoes the write or `poke` silently, with no change and no signal.
Any other return value accepts it. This applies to `Parent` too.

`uiFakes.attach(environment, { measureText?, measureBounds?, methods? })` installs fakes for these behaviors:

- Focus.
- Style maps.
- Video state.
- Path-point storage.
- Instant page navigation.

Measurement providers are required for measurement claims.
Keep the controller and call `close()` to release focus resources.
The simulator does not simulate curve evaluation, rendered text, animated navigation, playback quality or style rendering.
A declared method that is unsupported needs an explicit injected implementation.
`attach` registers `environment.onClone`.
`Clone()` then copies style, transition, derive and path state, and remaps in-tree derive references. Focus is never copied.
`environment.observe` and `pendingFailures` expose operation observation and unfired fault injection.

### Engine seam

`Roblox.environmentEngine(environment, library?)` exposes the environment as a structural scene engine.
The engine has creation, heartbeat, clock, datatype constructors, destruction and property observation.
Objects and signals keep their identity.
The default uses Verify datatypes. Supply the typed factory library when you use native datatypes.
This adapter adds no renderer and no native engine claim.

---

## Consumer diagnostics

`Consumer.scan(contents, path, ruleset)`, `scanTree` and `scanProductionPaths` inspect portable specifications and production graphs.
Choose a ruleset: `Consumer.generic` or `Consumer.roblox`.
[Consumer diagnostics](lint.md) describes the rules and their limits.

## Named case collections

`Core.runCases(cases, options, now, ids?)` executes ordinary named cases with exact selection.
The [run guide](running.md) describes selection, entry modules and host execution.
