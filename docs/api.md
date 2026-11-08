# API reference

Verify gives each case an isolated lifecycle and records its result in a report.
Start with cases and assertions.
Use sessions, plans and host adapters to coordinate sources or collect observations on another host.

| Task | Start here |
| --- | --- |
| Write and run a case | [Cases and sessions](#cases-and-sessions) |
| Compare values or record calls | [Assertions and spies](#assertions-and-spies) |
| Read, validate or combine results | [Reports and transport](#reports-and-transport) |
| Schedule work across hosts | [Execution plans](#execution-plans) |
| Boot a mounted project | [Mounted place sources](#mounted-place-sources) |
| Load Luau modules and fixtures | [Lute loader](#luteloader) |
| Encode bytes or read XML | [Codecs](#codecs) |
| Judge observations that a host collected | [Host observations](#host-observations) |
| Prove that evidence is current, intact, reviewed and complete | [Evidence provenance](#evidence-provenance) |
| Plan captures or move reports from a native host | [Host adapters](#host-adapters) |
| Test engine-facing logic without Roblox | [Simulated environment](#simulated-environment) |
| Compose reflection, UI fakes and the engine seam | [Reflection and explicit UI fakes](#reflection-and-explicit-ui-fakes) |
| Capture native models, meshes and animations for the engine double | [Native content facts](#native-content-facts) |
| Score a Roblox interface or evaluate coding agents | [Agent evaluation](#agent-evaluation) |
| Measure benchmark samples and regressions | [Benchmarks](#benchmarks) |
| Inspect consumer specifications | [Consumer diagnostics](#consumer-diagnostics) |
| Check a repository | [Repository checks](#repository-checks) |

## Shared setup

Require a public root from your pinned Verify copy.
Do not require private implementation modules for runtime operations.
Types not aliased by a root remain in their defining modules.

| Name | Entry | Host |
| --- | --- | --- |
| `Core` | `src/core` | Any |
| `Bdd` | `src/bdd.luau` | Any |
| `Roblox` | `src/roblox` | Any |
| `Lute` | `src/lute` | Lute |
| `Codec` | `src/codec` | Any |
| `Gate` | `src/gate` | Host side |
| `Evidence` | `src/evidence` | Host side |
| `Benchmark` | `src/benchmark.luau` | Host side |
| `Consumer` | `src/consumer` | Any |
| `AgentEval` | `src/agent-eval` | Lute |
| `Checks` | `src/checks` | Lute |

Examples use the package names in this table. Bind the packages that each example uses.
For a file under this checkout's `examples` directory, use:

```luau
local Core = require "../src/core"
local Bdd = require "../src/bdd"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"
local Codec = require "../src/codec"
local Gate = require "../src/gate"
local Evidence = require "../src/evidence"
local Benchmark = require "../src/benchmark"
local Consumer = require "../src/consumer"
local AgentEval = require "../src/agent-eval"
local Checks = require "../src/checks"
```

These are fragments unless the text says otherwise.
A name such as `host`, `benchmarkSpec` or `outputDirectory` is a caller-supplied input of the stated type.
Short type names refer to the defining module linked in each entry.
Use the root aliases when available.
Examples in one entry do not share local variables with another entry.
Transport examples use `lines`, `records` and `segments` from the preceding transport entries.
`report` is a standard report from a harness run.
`harness` is an open harness. `now` is a monotonic clock.
`waitOps` supplies `now` and `sleep`.
The [quickstart](quickstart.md) and [examples](../examples) provide complete programs.
The [laws](laws.md) own lifecycle and evidence requirements.

This page owns public signatures, return values and failure behavior.
`tools/check-public-surface.luau` checks each root export heading for missing or stale entries.
It checks coverage, not the correctness of prose or examples.

---

## Cases and sessions

### `Core.createHarness`

Source: [src/core/harness.luau](../src/core/harness.luau).

`createHarness({ now, source?, prefixIds?, attachments? }) -> Harness`

Returns: A new isolated `Harness`.

Failures: Missing clock or invalid source-prefix options raise. Registration errors raise; execution failures stay in the report.

`Core.createHarness` creates an isolated registry. Register cases, then call `harness:run` to receive their results. Importing Verify does not create a shared registry.

`harness:run` returns failed and unsupported results in its report. It does not set the process exit code. The caller must judge the report and make its command fail when the required claim is not met. The [repository gate](running.md#repository-gate) checks that a corpus is nonempty and passes entirely.

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

Give a monotonic `now` function. This example uses a synthetic clock. `source` associates the registry with its source. `prefixIds` controls source prefixes in case IDs. It defaults to true when you give a source. Prefixing requires a source and does not change selection visibility.

### Registration and execution

| Method | Purpose |
| --- | --- |
| `harness:suite(name, register)` | Group the cases that a callback registers. |
| `harness:case(name, run)` | Register a callback that receives a case context. |
| `harness:case(name, options)` | Give `run` and optionally `id`, `requires`, `tags`, `limitations`, `timeoutSeconds` and `cleanupTimeoutSeconds`. |
| `harness:skip(name, reason, run?)` | Register a deliberate omission with its reason. |
| `harness:beforeEach(run)` | Register setup for the cases in the current suite. |
| `harness:afterEach(run)` | Register teardown for the cases in the current suite. |
| `harness:run(options)` | Execute the selected cases and return a report. |

Run options name the `executor`. They can also give `environment`, `capabilities`, `selection`, `invoke`, `bind` and `cancelled`. Selection accepts IDs, suite prefixes, sources, tags, capabilities and a predicate. `nameContains` matches plain text in the case name. `shard = { index, count }` selects every `count`th matching case, starting at `index`. The shards include each matching case once. `index` and `count` must be whole numbers, with `1 <= index <= count`. Every field that you set must match. A focused result records that execution. It does not establish a complete gate.

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

A required capability that the run lacks produces `unsupported`, not a pass. A deliberate skip produces `skipped`. The optional invoker owns interruption. It must stop the work before it reports a cancellation or a timeout. See [execution](execution.md) for host deadlines and policy.

### Case context

The context records assertions, steps and artifact references. It owns case cleanup.
`context.id` is the registered case ID.

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

The [one case model](experience.md#one-case-model) owns typed operations, host binding, deadlines and evidence. `Core.runCase({name, ...caseOptions}, host)` runs one ordinary case and returns the standard report. Use `Core.observationParity` to compare the action and query observations of two reports.

`Core.Resource<T>` types a resource for `context:own`. It is a cleanup function or a `T` with a `dispose` or `destroy` member. Declare the receiver of a disposal callback as the complete resource type.

Cleanup runs once, newest first. Setup, case, teardown and cleanup failures stay visible independently. A later failure does not erase an earlier one. Hooks and cleanup use the same invocation contract as the case. An artifact reference records a location. It does not save or authenticate bytes.

`Artifact` and `Judgment` fields are read-only. Checkpoints retain frozen copies of captured artifacts and judgments. Report processing replaces an artifact or judgment when its data changes.

#### Inline attachments

`context:attach(name, mediaType, text)` records text that the case produced in the engine. The text travels in the report. The host then writes it to a file and replaces it with an ordinary artifact entry. The entry has `reference`, `mediaType`, `size` and `sha256`. `Evidence.seal` stores it like any other artifact. Attachments are data. They never prove that a case passed.

The text must be valid UTF-8 and not empty. Binary content is refused. `name` is a relative path. It must not be empty, start with `/`, contain `\`, a control character, an empty segment or a `.` or `..` segment. A name is unique within a case.

Limits fail closed. A broken limit raises an error from `attach`, the step fails and cleanup still runs.

| Limit | Default | Option |
| --- | --- | --- |
| Bytes of one attachment | 1048576 | `maxBytes` |
| Attachments in one case | 16 | `maxCount` |
| Bytes in one report | 4194304 | `maxTotalBytes` |

Set the limits with `attachments` in `Core.createHarness` or in the run options. The run options win.


`Lute.attachments.materialize(report, { directory, sink?, limits?, supported?, host? }) -> report, issues` is the host step. It checks the limits again and writes `<directory>/attachments/<case id>/<name>`. A `sink(caseId, name, text, meta) -> reference, reason` replaces the file write. `meta` is `{ mediaType, sha256, size }`. `issues` lists each attachment that was refused, not stored or unsupported. `Lute.platform.run` adds them to the report as a failed case `verify:attachments`. `Lute.platform.run` accepts `attachments` for the limits and `attachmentSink`. `Evidence.validate` also hashes again each sealed artifact of a case, so a changed stored attachment fails validation.

### `Bdd.create`

Source: [src/bdd.luau](../src/bdd.luau).

`create(harness) -> Bdd`

Returns: Registration and assertion verbs over the supplied harness.

Failures: Invalid registration follows the harness contract. `skip` outside a running case or hook raises.

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

The surface contains `describe`, `it`, `itSkip`, `beforeEach`, `afterEach`, `expect`, `spy` and `skip`. Case and hook bodies receive `(own, context)`. `own` registers a cleanup function. Use `itSkip(name, reason, body?)` during registration and `skip(reason)` during a case or hook.

`it(name, { run, id?, requires?, tags?, limitations? })` passes the same case metadata as `harness:case`:

- `id` fixes the case identity.
- `requires` names capabilities. A missing capability makes the case `unsupported`.
- `tags` select cases.
- `limitations` appear in the report.

`Bdd.surface({executor, environment, capabilities, ambientSource, now?, selection?})` returns one session-backed surface. It holds the verbs above and these members: `load(source, register)`, `adoptReport`, `sourceReport`, `run`, `setSelection(selection?)`, `reset` and `useHarness`. `selection` and `setSelection` use the selection of the harness and the session. `load` opens the source and registers it. It adopts a registration error as a failed source report. `Bdd.formatResults(report, title?)`, `Bdd.formatFailures` and `Bdd.counts` print a report. A unit case, an engine-integration case and an end-to-end case use this one vocabulary. They differ in the capabilities that they require and the evidence that they attach, not in the runner.

### `Core.createSession`

Source: [src/core/session.luau](../src/core/session.luau).

`createSession(options) -> Session`

Returns: A session with one harness per source.

Failures: Invalid options and closing without an open source raise. Reentry and reset during execution raise.

`Core.createSession` owns one harness per source. Use it when modules register their cases as they load. The options require `executor` and `environment`. Optional fields are `capabilities`, `now`, `bind`, `cancelled`, `prefixCaseIds` and `selection`.

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
| `harness()` / `current()` | Access the harness or the given surface of the active source. |
| `active()` | Access the running surface, or the registering surface outside a run. |
| `adoptReport(source, report)` | Include an existing source report. |
| `sourceReport(id, source, status, detail)` | Construct a source-level failed or skipped report. |
| `setSelection(selection?)` | Set which cases to run. |
| `run()` / `reset()` | Execute the queued sources or reset the session state. |

Call session methods with `:`. A `surface` factory maps registration functions to each harness. Use `current()` for registration and `active()` for operations such as `skip` that also run inside cases. A reset or a reentry during a run fails and keeps the queued sources. The [worker examples](execution.md#lute-workers) show module-loading integration.

### `Core.createSurfaceSession`

Source: [src/core/session.luau](../src/core/session.luau).

`createSurfaceSession(options) -> Session`

Returns: A session whose registration surface retains the factory result type.

Failures: A missing factory and invalid session transitions raise. Factory failures propagate.

```luau
local session = Core.createSurfaceSession {
    executor = "local", environment = {},
    surface = function(sourceHarness) return Bdd.create(sourceHarness) end,
}
```

`Core.createSurfaceSession` takes the options of `Core.createSession` and also requires a `surface` factory. It preserves the return type of the factory. Declare its options as `Core.SessionProvidedOptions<YourSurface>` when needed.

---

### `Core.runCase`

Source: [src/core/harness.luau](../src/core/harness.luau).

`runCase(spec: NamedCase, host: CaseHost) -> Report`

Returns: A report for one case. The host supplies time, capabilities and typed operations.

Failures: Case and cleanup failures become result rows. Invalid registration raises.

```luau
local single = Core.runCase(caseSpec, caseHost)
print(Core.format(single))
```

### `Core.runCases`

Source: [src/core/harness.luau](../src/core/harness.luau).

`runCases(cases: { NamedCase }, options: RunOptions, now: () -> number, ids: { string }?) -> Report`

Returns: A report with exact IDs and selection metadata. Without `ids`, it runs all cases.

Failures: Empty collections or selections, duplicate or unknown IDs, and `options.selection` raise.

```luau
local selected = Core.runCases(namedCases, runOptions, now, { "first" })
```

### `Core.waitUntil`

Source: [src/core/wait.luau](../src/core/wait.luau).

`waitUntil(spec: Spec, ops: Ops) -> Result`

Returns: `{ ok, reason, name, waitedSeconds, polls, observed, detail? }`. Reasons include `satisfied`, `timeout`, `cancelled`, `refused` and `probe_threw`.

Failures: Invalid bounds raise. Probe errors become `probe_threw`; clock and sleep errors propagate.

```luau
local waited = Core.waitUntil({
    name = "ready", deadlineSeconds = 1, pollSeconds = 0.1,
    probe = function() return true, "ready", nil end,
}, waitOps)
assert(waited.ok)
```

### `Core.awaitValue`

Source: [src/core/wait.luau](../src/core/wait.luau).

`awaitValue<T>(predicate: () -> T?, seconds: number, poll: number, ops: Ops, truthy: boolean?) -> T?`

Returns: The first non-nil value. False is a value unless `truthy` is true. Timeout and cancellation return nil.

Failures: Invalid bounds and probe failures raise.

```luau
local value = Core.awaitValue(function() return false end, 1, 0.1, waitOps)
assert(value == false)
```

### `Bdd.surface`

Source: [src/bdd.luau](../src/bdd.luau).

`surface(options: SurfaceOptions) -> Surface`

Returns: A session-backed BDD surface with registration, report adoption, selection, execution and reset.

Failures: Registration errors in `load` become failed source reports. Session reentry and invalid state raise.

```luau
local surface = Bdd.surface { executor = "local", environment = {}, capabilities = {}, ambientSource = "inline" }
surface.it("passes", function() surface.expect(true):toBe(true) end)
local result = surface.run()
```

### `Bdd.counts`

Source: [src/bdd.luau](../src/bdd.luau).

`counts(report: Report) -> (number, number, number)`

Returns: Passed, failed and skipped counts. The failed count includes unsupported, timed-out and cancelled results.

Failures: It expects a valid report.

```luau
local passed, failed, skipped = Bdd.counts(report)
```

### `Bdd.formatResults`

Source: [src/bdd.luau](../src/bdd.luau).

`formatResults(report: Report, title: string?) -> string`

Returns: Readable results with an optional title.

Failures: It expects a valid report.

```luau
print(Bdd.formatResults(report, "local cases"))
```

### `Bdd.formatFailures`

Source: [src/bdd.luau](../src/bdd.luau).

`formatFailures(report: Report, title: string?) -> string`

Returns: Formatted failure details.

Failures: It expects a valid report.

```luau
print(Bdd.formatFailures(report))
```

## Assertions and spies

### `Core.expect`

Source: [src/core/matchers.luau](../src/core/matchers.luau).

`expect(value) -> Expectation`

Returns: An expectation with matchers and `.never` negation.

Failures: A failed matcher raises an assertion failure. The harness records it when the assertion runs in a case.

Use `expect` directly, through a case context or through the BDD surface. Chain `.never` before a matcher to negate it.

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
| `toBeTrueWith(detail)` | A true value, with a given failure detail. |
| `toBeCloseTo`, `toBeNear`, `toBeFloat32` | Numeric tolerance or single-precision representation. |
| `toBeLessThan`, `toBeGreaterThan`, `toBeLessThanOrEqual`, `toBeGreaterThanOrEqual` | Numeric ordering. |
| `toContain`, `toContainExactly`, `toHaveLength` | Containment and length. |
| `toThrow(contains?)`, `toThrowMatching(pattern)` | A thrown error, with optional plain text or a Luau pattern. |

`toThrow` uses plain text containment. Use `toThrowMatching` for patterns. `Core.float32(value)` returns the single-precision value. The exact matcher signatures are in [`matchers.luau`](../src/core/matchers.luau).

### `Core.spy`

Source: [src/core/spy.luau](../src/core/spy.luau).

`spy(implementation?) -> Spy`

Returns: A spy with a callable `fn` and call-history controls.

Failures: Implementation errors propagate after the call is recorded.

`Core.spy` records calls to its `fn` and optionally delegates to your implementation.

```luau
local callback = Core.spy(function(value)
    return value * 2
end)

Core.expect(callback.fn(3)):toBe(6)
Core.expect(callback.callCount()):toBe(1)
Core.expect(callback.lastArgs()):toEqual({ 3 })
```

Inspect `calls`, `called()`, `lastArgs()` and `lastReturn()`. Use `reset()` to clear the recorded calls. Use `returnValue(value)` to give a fixed return and `implementation(fn)` to replace the callback.

---

### `Core.float32`

Source: [src/core/matchers.luau](../src/core/matchers.luau).

`float32(value: number) -> number`

Returns: The value rounded through a four-byte float buffer.

Failures: Invalid argument types raise through the buffer operation.

```luau
Core.expect(Core.float32(0.1)):toBeFloat32(0.1)
```

## Reports and transport

A schema-v1 report keeps the executor, environment, capabilities, sources and case results. Each case result keeps status, timing, failures, steps, artifacts, limitations and origin. The counts must agree with the result rows.

| Status | Meaning |
| --- | --- |
| `passed` | The executed case passed. |
| `failed` | An assertion, a lifecycle phase or an execution recorded a failure. |
| `skipped` | The case was deliberately omitted, with a reason. |
| `unsupported` | A required capability was unavailable. |
| `timed_out` | The invoker reported that it stopped the timed-out work. |
| `cancelled` | The invoker reported that it stopped the cancelled work. |

### Validate and combine

Give `compose` every expected shard, including errors.
Use `merge` only for trusted reports with distinct case IDs.

### `Core.SCHEMA_VERSION`

Source: [src/core/report.luau](../src/core/report.luau).

`SCHEMA_VERSION: number`

Returns: `1`, the report schema version.

Failures: Reading the constant cannot fail. Decoders reject other versions.

```luau
assert(report.schemaVersion == Core.SCHEMA_VERSION)
```

### `Core.decode`

Source: [src/core/report.luau](../src/core/report.luau).

`decode(value: unknown) -> Report`

Returns: A validated report copy with schema, counts, results and evidence checked.

Failures: Invalid versions, fields, counts or result records raise. JSON parsing alone does not validate a report.

```luau
local decoded = Core.decode(report)
assert(decoded.total == report.total)
```

### `Core.merge`

Source: [src/core/report.luau](../src/core/report.luau).

`merge(reports: { Report }, executor: string, environment: { [string]: string }) -> Report`

Returns: One combined trusted report with source and origin accounting.

Failures: Duplicate case IDs raise. Use `compose` for untrusted shard outcomes.

```luau
local merged = Core.merge({ report }, "combined", {})
```

### `Core.compose`

Source: [src/core/report.luau](../src/core/report.luau).

`compose(payloads: { ShardPayload }, executor: string, environment: { [string]: string }) -> Report`

Returns: A report that accounts for valid, invalid, missing and conflicting shard deliveries.

Failures: Bad shard outcomes become failed synthetic results. Do not omit an expected shard from `payloads`.

```luau
local combined = Core.compose({ { id = "one", report = report }, { id = "two", error = "no delivery" } }, "workers", {})
```

### `Core.syntheticReport`

Source: [src/core/harness.luau](../src/core/harness.luau).

`syntheticReport(options: SyntheticOptions) -> Report`

Returns: A one-result report for unreachable or refused work. Options include `id`, `name`, `status`, `executor`, `environment` and `message`.

Failures: Empty IDs, names and executor names raise. Unsupported results need missing capabilities; skipped results need a reason.

```luau
local missing = Core.syntheticReport {
    id = "missing", name = "missing worker", status = "failed",
    executor = "local", environment = {}, message = "no report",
}
```

### `Core.format`

Source: [src/core/format.luau](../src/core/format.luau).

`format(report: Report) -> string`

Returns: Readable counts, result details and measurement summaries. It writes no file.

Failures: It expects a valid report. Decode foreign data first.

```luau
print(Core.format(report))
```


### Move reports between hosts

Validate each received report with `Core.decode`.
The consumer binds executor identity and owns authenticity.
See the [report transport procedure](execution.md#report-transport) for run-bound channels.

### `Core.frame`

Source: [src/core/transport.luau](../src/core/transport.luau).

`frame(tag: string, payload: string, maxPayloadBytes: number?) -> { string }`

Returns: Tagged transport lines. The optional size bounds the payload in each line.

Failures: Invalid tags or chunk sizes raise.

```luau
local lines = Core.frame("result", "hello", 3)
```

### `Core.extract`

Source: [src/core/transport.luau](../src/core/transport.luau).

`extract(bytes: string, tag: string) -> { Record }`

Returns: Parsed chunk records for the tag. Unrelated log text is ignored.

Failures: An invalid tag raises. Incomplete or conflicting records need reassembly checks.

```luau
local records = Core.extract(table.concat(lines, "\n"), "result")
```

### `Core.reassemble`

Source: [src/core/transport.luau](../src/core/transport.luau).

`reassemble(records: { Record }) -> (string?, string?)`

Returns: The complete payload, or nil and a reason.

Failures: Missing, duplicate-conflicting or mixed records return a reason.

```luau
local payload, reason = Core.reassemble(records)
assert(payload, reason)
```

### `Core.receipt`

Source: [src/core/transport.luau](../src/core/transport.luau).

`receipt(bytes: string, tag: string) -> (string?, string?)`

Returns: The result of extraction and reassembly in one call.

Failures: Invalid tags raise. Incomplete or conflicting delivery returns nil and a reason.

```luau
local payload, reason = Core.receipt(table.concat(lines, "\n"), "result")
assert(payload, reason)
```

### `Core.segment`

Source: [src/core/transport.luau](../src/core/transport.luau).

`segment(payload: string, maxBytes: number) -> { Segment }`

Returns: Ordered payload records with identity and digest fields.

Failures: A nonpositive or nonintegral size raises.

```luau
local segments = Core.segment("hello", 3)
```

### `Core.reassembleSegments`

Source: [src/core/transport.luau](../src/core/transport.luau).

`reassembleSegments(segments: { unknown }) -> (string?, string?)`

Returns: The complete payload, or nil and a reason. It leaves the input rows unchanged.

Failures: Invalid fields, missing segments and digest conflicts return a reason.

```luau
local payload, reason = Core.reassembleSegments(segments)
assert(payload == "hello", reason)
```

### `Lute.encode`

Source: [src/lute/wire.luau](../src/lute/wire.luau).

`encode(value: unknown) -> string`

Returns: JSON text for a portable value.

Failures: Cycles, unsupported types and invalid JSON values raise.

```luau
local text = Lute.encode({ status = "ready" })
```

### `Lute.parse`

Source: [src/lute/wire.luau](../src/lute/wire.luau).

`parse(encoded: string) -> unknown`

Returns: Plain decoded JSON tables and primitive values.

Failures: Invalid JSON raises. The result has no report validation.

```luau
local value = Lute.parse('{"ready":true}')
```

### `Lute.decode`

Source: [src/lute/wire.luau](../src/lute/wire.luau).

`decode(encoded: string) -> Report`

Returns: A parsed and validated report.

Failures: Invalid JSON or report schema raises.

```luau
local decoded = Lute.decode(Lute.encode(report))
```

### `Lute.decodeBatch`

Source: [src/lute/batch.luau](../src/lute/batch.luau).

`decodeBatch(encoded: string) -> PlanBatch`

Returns: A validated worker input batch with its ID, index, units and optional deadline.

Failures: Invalid JSON, missing fields or invalid batch values raise. It does not decode a result report.

```luau
local batch = Lute.decodeBatch(encodedBatch)
```


## Execution plans

A plan names a finite set of work and its requirements. The consumer provides discovery, the meaning of each locator and an authorized host.

### `Core.execute`

Source: [src/core/execution.luau](../src/core/execution.luau).

`execute(plan: PlanDraft | Plan, host: Host, options: ExecutionOptions?) -> ExecutionReport`

Returns: The validated plan, batches, outcomes and standard report.

Failures: Invalid plans raise. Host failures, missing deliveries and unsupported requirements remain accounted outcomes.

```luau
local execution = Core.execute(plan, host)
print(Core.format(execution.report))
```


## Declarative gates

A gate accounts for its declared producers and returns an acceptance verdict.
The [execution guide](execution.md#declarative-gates) describes the procedure.

### `Gate.SCHEMA_VERSION`

Source: [src/gate/gate-define.luau](../src/gate/gate-define.luau).

`SCHEMA_VERSION: number`

Returns: `1`, the gate definition schema version.

Failures: Reading the constant cannot fail.

```luau
assert(Gate.SCHEMA_VERSION == 1)
```

### `Gate.define`

Source: [src/gate/gate-define.luau](../src/gate/gate-define.luau).

`define(draft: Draft) -> Definition`

Returns: A normalized gate with ordered producers, validated dependencies, policy and digest.

Failures: Invalid producers, cycles, duplicate IDs and invalid policy bounds raise.

```luau
local gate = Gate.define { id = "checks", producers = { { id = "unit", kind = "command", argv = { "lute", "run", "check.luau" } } } }
```

### `Gate.run`

Source: [src/gate/gate.luau](../src/gate/gate.luau).

`run(gate: Definition, executor: Executor, options: RunOptions) -> Outcome`

Returns: Execution records, report, build identity, scope and acceptance verdict.

Failures: Invalid selection raises. Producer failures stay in the outcome and affect acceptance.

```luau
local outcome = Gate.run(gate, gateExecutor, gateOptions)
```

### `Gate.format`

Source: [src/gate/gate-format.luau](../src/gate/gate-format.luau).

`format(outcome: Outcome) -> string`

Returns: A readable gate verdict and producer results.

Failures: It expects a valid outcome.

```luau
print(Gate.format(outcome))
```

### `Gate.explain`

Source: [src/gate/gate-format.luau](../src/gate/gate-format.luau).

`explain(outcome: Outcome, id: string) -> string?`

Returns: The producer or case explanation, or nil for an unknown ID.

Failures: It expects a valid outcome.

```luau
local explanation = Gate.explain(outcome, "unit")
```

### `Gate.list`

Source: [src/gate/gate-format.luau](../src/gate/gate-format.luau).

`list(gate: Definition) -> string`

Returns: A readable producer list with kinds, tiers and dependencies.

Failures: It expects a defined gate.

```luau
print(Gate.list(gate))
```

### `Gate.rerun`

Source: [src/gate/gate.luau](../src/gate/gate.luau).

`rerun(outcome: Outcome) -> Selection?`

Returns: Selection for unsuccessful work, or nil when there is none.

Failures: It expects a valid outcome.

```luau
local selection = Gate.rerun(outcome)
```

### `Gate.testCases`

Source: [src/gate/gate.luau](../src/gate/gate.luau).

`testCases(outcome: Outcome) -> Report`

Returns: The execution report without test-producer summary rows. Individual case results remain.

Failures: It expects a valid gate outcome. It removes test-producer summary rows from the execution report.

```luau
print(Core.format(Gate.testCases(outcome)))
```


## Benchmarks

A benchmark warms up work, records samples and evaluates explicit limits or a baseline.
The [benchmark guide](experience.md#benchmarks) describes setup and measurement limits.

### `Benchmark.check`

Source: [src/benchmark-check.luau](../src/benchmark-check.luau).

`check(spec: Spec, owned: boolean?) -> ()`

Returns: No value after validating a benchmark specification. `owned` permits collection-owned calibration.

Failures: Invalid samples, budgets, phases, baselines or calibration raise.

```luau
Benchmark.check(benchmarkSpec)
```

### `Benchmark.checkCollection`

Source: [src/benchmark-check.luau](../src/benchmark-check.luau).

`checkCollection(collection: Collection) -> ()`

Returns: No value after validating the collection and its members.

Failures: Invalid calibration, duplicate member names or invalid member specifications raise.

```luau
Benchmark.checkCollection(benchmarkCollection)
```

### `Benchmark.run`

Source: [src/benchmark.luau](../src/benchmark.luau).

`run(spec: Spec) -> Result`

Returns: Samples, summaries, phases, invalidity, comparisons and any failure.

Failures: Invalid specifications raise. Work failures become `failure`; calibration refusals remain in `invalid`.

```luau
local measured = Benchmark.run(benchmarkSpec)
```

### `Benchmark.case`

Source: [src/benchmark.luau](../src/benchmark.luau).

`case(spec: Spec) -> CaseOptions`

Returns: A case definition that records benchmark measurements in the standard report.

Failures: Invalid specifications raise at construction. Measurement failures or regressions fail the running case.

```luau
harness:case("measures work", Benchmark.case(benchmarkSpec))
```

### `Benchmark.collect`

Source: [src/benchmark.luau](../src/benchmark.luau).

`collect(collection: Collection) -> CollectionResult`

Returns: Ordered member results with collection calibration and attempt evidence.

Failures: Invalid collections raise. Execution and calibration failures remain in the result.

```luau
local collected = Benchmark.collect(benchmarkCollection)
```

### `Benchmark.collection`

Source: [src/benchmark.luau](../src/benchmark.luau).

`collection(collection: Collection) -> CaseOptions`

Returns: One case definition that records all member measurements and calibration attempts.

Failures: Invalid collections raise. Member failures and invalid measurements remain visible in the case.

```luau
harness:case("measures collection", Benchmark.collection(benchmarkCollection))
```

### `Benchmark.limits`

Source: [src/benchmark.luau](../src/benchmark.luau).

`limits(spec: Spec) -> Performance.Limits`

Returns: Limits derived from unit, sample count and budget. With no thresholds, it sets `measureOnly`.

Failures: It expects a valid specification. Validate with `check` first.

```luau
local limits = Benchmark.limits(benchmarkSpec)
```

### `Benchmark.store`

Source: [src/benchmark-store.luau](../src/benchmark-store.luau).

`store(name: string, results: { Result }) -> Stored`

Returns: A portable stored measurement record. It writes no file.

Failures: An empty name or invalid encoded measurements raise.

```luau
local stored = Benchmark.store("candidate", { measured })
```

### `Benchmark.storeReport`

Source: [src/benchmark-store.luau](../src/benchmark-store.luau).

`storeReport(name: string, report: Report) -> Stored`

Returns: A portable record of the report measurements. The report must contain at least one measurement.

Failures: An empty name or malformed measurements raise.

```luau
local stored = Benchmark.storeReport("candidate", report)
```

### `Benchmark.decode`

Source: [src/benchmark-store.luau](../src/benchmark-store.luau).

`decode(value: unknown) -> Stored`

Returns: A validated stored record.

Failures: Invalid schema, names, measurements, samples or series raise.

```luau
local baseline = Benchmark.decode(savedBaseline)
```

### `Benchmark.compare`

Source: [src/benchmark-store.luau](../src/benchmark-store.luau).

`compare(baseline: Stored, candidate: Stored, options: CompareOptions) -> Report`

Returns: An ordinary report for declared comparison rules.

Failures: Invalid rules raise. Missing, incompatible or regressed measurements do not pass.

```luau
local comparison = Benchmark.compare(baseline, stored, comparisonOptions)
```

### `Benchmark.spread`

Source: [src/benchmark-store.luau](../src/benchmark-store.luau).

`spread(runs: { Stored }, options: SpreadOptions?) -> SpreadSummary`

Returns: Per-measurement spread and noise summaries across stored runs.

Failures: Malformed records or invalid spread options raise.

```luau
local spread = Benchmark.spread({ baseline, stored })
```



---

## Mounted place sources

`Roblox.createPlaceCache(host)` shares source and compiled bytes. Each load uses its own environment. `Roblox.buildPlaceTree(engine, projectPath, dependencies)` mounts a project with the given engine and file host. `Roblox.createPlaceRuntime(engine, mounted, options)` runs source modules in separate client and server contexts. `Roblox.bootPlace(config, dependencies)` controls the bounded boot stages. These checks do not prove native rendering, input, asset access or release acceptance.

Project properties accept implicit Color3, Vector2, Vector3 and flat CFrame components. They also accept explicit datatype values. Primitive properties accept explicit type wrappers. `$attributes` sets attributes on the root, services and child instances. The environment validates each attribute value.

Project `emitLegacyScripts` defaults to true. Set it to false to mount client and server sources as Scripts with `RunContext`. An explicit `RunContext` property overrides this choice. Boot uses each script context and disabled state. Modern server Scripts run in Workspace, ServerScriptService, ReplicatedStorage, ReplicatedFirst and ServerStorage. Modern client Scripts run in Workspace, ReplicatedStorage, ReplicatedFirst and PlayerScripts. Legacy server Scripts run in Workspace and ServerScriptService. Legacy LocalScripts run in ReplicatedFirst and PlayerScripts. The shared Studio and simulator assertions check both modes, context overrides and disabled sources in the five services.

The place runtime accepts `debug.profilebegin`, `debug.profileend` and `debug.setmemorycategory`. These calls collect no performance or memory measurements. The debug table keeps the host inspection functions. It does not change the host table.

The runtime's `HttpService.JSONEncode` writes engine datatypes, Instances, functions and threads as JSON null. Tables with an array part encode that part and ignore dictionary entries. Holes inside the array part become null. Empty tables become empty arrays. Numeric dictionary keys become integer strings. Cyclic tables fail. The host still encodes strings and numbers. The default host does not model buffer and nonfinite-number encodings, and dictionary keys other than strings and numbers remain unsupported.

`ReplicatedFirst:RemoveDefaultLoadingScreen()` is accepted without rendering a loading screen. Arrival logic can continue, but native loading-screen visibility requires a Studio or Player observation.

The scheduler applies explicit Humanoid state changes. It then emits `StateChanged`. A detached Humanoid reports `None`. A Humanoid in a Model in Workspace starts in `Running`. This behavior does not simulate automatic movement, state physics or network ownership.

Humanoid state-enable flags default to true and reset on cloning. `SetStateEnabled` emits `StateEnabledChanged` even for repeated writes; `None` remains enabled and ignores writes. Flags describe configured state-machine policy; the simulator has no automatic state machine.

The reflected environment gives Workspace and WorldModel these `WorldRoot` methods. Queries read current descendants of that world. A nested WorldModel is a separate world. Queries do not advance physics or move the source part.

| Method | Geometry and result |
| --- | --- |
| `Raycast(origin, direction, params?)` | Finite segment against oriented boxes and uniform balls; nearest hit or nil. Origins inside a target do not hit that target. Direction magnitude is at most 15000 studs. |
| `Blockcast(cframe, size, direction, params?)` | Translates an oriented box against boxes and balls; nearest hit or nil. |
| `Spherecast(position, radius, direction, params?)` | Sweeps a sphere against boxes and balls, including rounded edge and corner contacts; nearest hit or nil. |
| `Shapecast(part, direction, params?)` | Sweeps the source part's supported geometry and excludes that part. Terrain cannot be a source. Optional frame/size overrides refuse as unsupported. |
| `GetPartBoundsInBox(cframe, size, params?)` | Returns parts whose oriented bounding boxes overlap the oriented query box, including contact. |
| `GetPartBoundsInRadius(position, radius, params?)` | Returns parts whose oriented bounding boxes intersect the query sphere, including contact. |
| `GetPartsInPart(part, params?)` | Returns parts intersecting the source's supported volume, excluding the source. The source must belong to the queried WorldRoot. |

Casts return a read-only `RaycastResult`. It contains `Instance`, contact `Position` in world coordinates, outward unit `Normal`, traveled `Distance` and target `Material`. Shape casts skip targets that intersect or touch the initial shape. Direction length must not exceed 1024 studs. Each size must not exceed 512 studs. Sphere radius must not exceed 256 studs. A zero direction misses. Sizes must be positive. An overlap radius can be zero. Nonfinite inputs and CFrames without orthonormal axes fail. Simultaneous hits and overlap arrays use descendant order. Roblox does not guarantee this order. A box contact can have several valid points. Verify returns a point in that contact region.

Both parameter types use `FilterType` and `FilterDescendantsInstances`. Filters include the listed roots and their descendants. `IncludeInstances=nil` adds no restriction. An empty table includes nothing. `ExcludeInstances` takes priority over inclusion. Legacy and modern filters combine. With default flags, a part is eligible when `CanCollide` or `CanQuery` is true. Set `CanCollide=false` before you use `CanQuery=false` to exclude a part. `RespectCanCollide=true` uses only `CanCollide`. `CanTouch` has no effect. `BruteForceAllSlow` bypasses part collision flags and group masks. Instance filters still apply.

Collision groups use symmetric masks. Configure them with `PhysicsService.RegisterCollisionGroup`, `UnregisterCollisionGroup`, `IsCollisionGroupRegistered`, `CollisionGroupSetCollidable` and `CollisionGroupsAreCollidable`. PhysicsService and Workspace share the environment workspace rules. The corresponding WorldRoot methods keep separate WorldModel rules when the snapshot declares them. Unregistered groups use the default collidable mask. Group IDs, renaming and other unimplemented methods raise the usual unsupported-method error. `MaxParts=0` gives unlimited results. Positive values limit overlap results. Negative values fail. Verify validates every eligible candidate, even after it reaches the limit. A partial result cannot hide unsupported content.

Block Parts use box geometry. Uniform Ball Parts use sphere geometry. Cylinders, MeshParts, PartOperations, seats, spawn locations and trusses use their oriented `CFrame` and `Size` box. PartOperations include unions. Bounds queries use boxes for every BasePart. This model has no mesh triangles, concavity, union decomposition or cylinder curvature. Other collision shapes raise `unsupported_content`. These include wedges and nonuniform balls. Bounds queries can inspect their boxes.

Terrain ray geometry comes from `FillBlock`, `FillBall`, `FillCylinder`, `WriteVoxels`, `ReplaceMaterial` and `Clear`. Fills overwrite earlier occupied volumes, including carving with Air. Blocks and cylinders follow their CFrame; cylinders use local Y as their axis. Later fills survive earlier replacements. Replacements affect matching occupied material within the region, including replacement with Air; replacing Air does not create terrain. Clear removes all edits. WriteVoxels and ReplaceMaterial require resolution 4 and grid-aligned Region3 bounds of at most 4,194,304 voxels. Voxel arrays must match all three dimensions, with finite occupancy in `[0, 1]`. Validation finishes before edits apply. Input tables are copied into geometry. Each occupied voxel is a box filled upward from its bottom by its occupancy fraction. This analytic model preserves disconnected layers and supports rays in any direction; it does not implement native smooth-terrain meshing or voxelization of fill boundaries.

Terrain rays share ordinary instance filters, the Default collision group and nearest-part selection. IgnoreWater excludes water volumes. Authored terrain shape casts raise `unsupported_content`; overlap queries still need an explicit box proxy. For a uniform terrain proxy without edits, use `environment.poke` to provide `CFrame`, `Size` and `Material`. Queries use that box. Missing proxy facts raise `unsupported_content`. `Shapecast` cannot cast a Terrain source.

Nonzero `OverlapParams.Tolerance`, `RaycastParams.Margin` and `RaycastParams.SizeGradient` raise `unsupported`. Verify does not silently change the requested volume. Margin and SizeGradient accept validated values, then fail explicitly during a query. Spatial results prove only this geometry model. They do not prove native physics or floating-point parity. The query fails when it cannot resolve a box contact numerically.

AudioEmitter distance curves copy inputs, outputs and cloned state. Negative finite distances become zero. Finite volumes stay within `[0, 1]`. These rules match the native setters. Invalid keys or values fail before the curve changes. The simulator accepts at most 400 points. It does not simulate audibility or audio output.

The ParticleEmitter method double accepts finite nonnegative integer Emit counts, defaulting to 16, and Clear requests. These produce `effect` diagnostics recording the request only. No particles, visibility, lighting or rendering are simulated or proved.

Fixture engines compute Attachment.WorldCFrame and WorldPosition from local CFrame and the nearest ancestral PVInstance or Attachment, through intervening folders. BasePart ancestors use CFrame rather than PivotOffset; other PVInstances use their pivot. Detached attachments use their local frame. Parent movement and reparenting affect subsequent reads. World-space writes convert to local coordinates, and Position/CFrame writes stay coupled. Position writes preserve rotation. This covers static attachment transforms, not animated bone transforms, constraint solving or native property-change event parity.

`Model:ScaleTo` scales about the current pivot and keeps nested model factors and cloned scale state. Supported geometry includes part sizes and pivot offsets, attachment frames, joint C0/C1, mesh offsets and file-mesh scale. It includes sound rolloff distances and particle size, speed and acceleration. It also includes beam widths and curves, trail minimum and maximum length, and rope length and thickness. Supported Humanoid properties are hip height, speed, jump height and jump power. AnimationConstraint translation scales linearly and its maximum force and torque scale cubically; strength and damping remain unchanged. Motor6D/Bone animated transforms and light range remain unchanged. Edited properties become the new basis for later scaling; unchanged property sizes keep their original basis. Part positions use floating-point transformations. Constraints other than ropes and animation constraints refuse before geometry changes; constraint dynamics and other geometric properties require an explicit host or native execution.

Lute consumers use `Lute.fixture.host` for filesystem reads, compilation, environment-bound loading and JSON, and `Lute.fixture.files` for project traversal. Both tables are frozen; clone the host when injecting fixture sources. `Lute.FixturePlaceHost` is its exported type. Consumers keep project paths and game-specific setup rather than copying this platform wiring.

Project `$path` values resolve relative to the project file's directory. Absolute paths remain absolute. Project properties decode Rojo's tagged Color3, Vector3, CFrame and enum values through the engine's datatype library. Malformed components and unknown enum values fail before assignment.

The modeled `ContentProvider.PreloadAsync` accepts an empty request without callbacks. It rejects nonempty requests as `unsupported_place_asset`; it does not fetch assets or report a fabricated asset status.

`PlaceRuntimeEngine.environment` owns the simulated environment. The binding gives the runtime its DataModel, instance constructor, service lookup, datatypes and source diagnostics. Runtime and boot use public environment operations for properties, events and method doubles. The engine contract has no mutable `stateOf` or `serviceMethods` table.

Construct it with `Lute.fixture.bridge().placeEngine()`. Use `engine.environment.scheduler` for time, `environment.fire(instance, event, ...)` for events and `environment.fake` or `fakeOn` for explicit method doubles. BasePart position/CFrame writes remain coupled. The reflected environment models pivots, descendant placement and oriented model bounds; it does not simulate joints, collisions or physics. Set a model's primary part or world pivot when its orientation matters; an unset pivot uses the largest descendant part as its basis.

Runtime options are `{ aliases, cache, host, methodDoubles?, client?, beforeRender? }`. `methodDoubles` selects classes for the existing runtime method doubles. Omit it to use the standard simulation. Give an explicit list to restrict the methods. An empty list installs none. The runtime applies this selection to existing and new instances. Call each function in `runtime.closeHandlers` when the host closes. This stops registration. Unselected media and physics methods get no behavior.

Runtime defaults preserve methods configured before runtime creation. `environment.hasFake(instance, member)` finds object overrides, inherited class fakes and class handlers. Closing removes only runtime overrides and listeners. It keeps caller methods.

`MemoryStoreService:GetHashMap()` gives cached handles with native structure when the game ID is positive. Reads, writes, expiry, contention and sharing across servers need explicit injected behavior. Handle creation proves none of these operations.

`Workspace:GetServerTimeNow()` follows the virtual scheduler clock, starting at simulated epoch zero. `UserInputService:GetLastInputType()` starts at `None` and follows dispatched input events; close handlers disconnect its listeners. These are controlled simulation inputs, not OS input or wall-clock synchronization. The mesh-part double keeps URI-backed `Content` and refuses empty or object-backed content; it performs no asset load and proves no asset access or appearance.

`bridge.placeEngine()` returns one cached engine for runtime and boot. The engine uses the bridge environment and reflection metadata. It owns a DataModel. Its service lookup creates only reflected services. Script construction restrictions still apply. The boot report keeps source diagnostics and observed roots. No separate diagnostic adapter is necessary.

The optional `client = { name, userId, viewport = { x, y } }` creates a Player, PlayerGui and camera. Viewport dimensions must be positive and finite. This sets `runtime.localPlayer` and `Players.LocalPlayer`. It does not start scripts or create a character. `runtime.step(seconds)` advances the scheduler and simulated RunService frame events. It calls `beforeRender()` before render events. Hosts can use `bridge.layout.step` there. Reader errors stop execution before render publication. These frames do not prove native rendering or physics. `StudioDeviceSimulatorService:SetDeviceAsync(id)` applies captured Studio facts for `iphone_14`, `xbox`, `hd_1080` and `generic_handheld_720`. `runtime.device()` returns current device facts. `runtime.screenArea(screenGui)` returns the device area for that ScreenGui and its `ScreenInsets`. `IgnoreGuiInset` selects `DeviceSafeInsets` or `CoreUISafeInsets`, as in Studio.

ModuleScript results are cached by instance and execution context. Relative requires use the mounted source tree. Runtime and compile failures stay in the cache. Another require raises the same failure.

### `Roblox.buildPlaceTree`

Source: [src/roblox/place-boot.luau](../src/roblox/place-boot.luau).

`buildPlaceTree<B>(engine: PlaceRuntimeEngine, projectPath: string, dependencies: TreeDeps<B>) -> Mounted`

Returns: The mounted project tree and source facts.

Failures: Invalid projects, unsupported values and file host failures raise.

```luau
local mounted = Roblox.buildPlaceTree(placeEngine, projectPath, treeDependencies)
```

### `Roblox.createPlaceCache`

Source: [src/roblox/place-boot.luau](../src/roblox/place-boot.luau).

`createPlaceCache<B, C>(host: PlaceBootHost<B, C>) -> Cache<B, C>`

Returns: A shared source and compilation cache. Module execution environments remain separate.

Failures: Read and compilation failures propagate through the cache operations.

```luau
local cache = Roblox.createPlaceCache(Lute.fixture.host)
```

### `Roblox.createPlaceRuntime`

Source: [src/roblox/place-boot.luau](../src/roblox/place-boot.luau).

`createPlaceRuntime(engine, mounted, options) -> PlaceRuntime`

Returns: A runtime with separate client/server module caches, stepping, device facts and close handlers.

Failures: Invalid bindings or unsupported operations raise. Module and compile failures stay cached.

```luau
local runtime = Roblox.createPlaceRuntime(placeEngine, mounted, runtimeOptions)
runtime.step(1 / 60)
for _, close in runtime.closeHandlers do
    close()
end
```

### `Roblox.bootPlace`

Source: [src/roblox/place-boot.luau](../src/roblox/place-boot.luau).

`bootPlace<B>(config: Config, dependencies: Deps<B>) -> Report`

Returns: A bounded boot report with stages, diagnostics and observed roots.

Failures: Invalid configuration raises. Boot operation errors propagate. The returned report retains recorded source diagnostics.

```luau
local boot = Roblox.bootPlace(bootConfig, bootDependencies)
```

## Host observations

Use typed operations, `context:perform`, `await`, `checkpoint`, `judge` and `measure` in the ordinary case. Evidence lives in `CaseResult.evidence` and uses the standard report transport. The [experience contract](experience.md) describes binding. The [execution contract](execution.md) describes hosts.

### `Core.operation`

Source: [src/core/operations.luau](../src/core/operations.luau).

`operation<I, O>(definition: Operation<I, O>) -> Operation<I, O>`

Returns: A frozen copy with `kind`, `name`, `input` and `output` decoders.

Failures: An empty name or a kind other than `action` or `query` raises.

```luau
local query = Core.operation {
    kind = "query", name = "ready",
    input = function(value: unknown): unknown return value end,
    output = function(value: unknown): boolean
        assert(type(value) == "boolean")
        return value
    end,
}
```

### `Core.bindOperation`

Source: [src/core/operations.luau](../src/core/operations.luau).

`bindOperation<I, O>(definition: Operation<I, O>, body: (I, OperationRequest) -> O) -> Endpoint`

Returns: An endpoint whose `run(payload, request)` validates input and output around `body`.

Failures: A request name or kind mismatch raises. Decoder and body failures propagate.

```luau
local endpoint = Core.bindOperation(query, function() return true end)
```

### `Core.observationParity`

Source: [src/core/report.luau](../src/core/report.luau).

`observationParity(left: Report, right: Report) -> Parity`

Returns: `{ status, differences }` for action and query observations.

Failures: Missing evidence gives `unsupported`; different observations give `failed`. It proves no native rendering parity.

```luau
local parity = Core.observationParity(simulatedReport, nativeReport)
print(parity.status)
```

### `Core.progress`

Source: [src/core/progress.luau](../src/core/progress.luau).

`create(runId: string, emit: (Event) -> ()) -> Progress`; `valid(value: unknown, runId: string) -> Event`; `pending(events: { Event }) -> { Event }`

Returns: A publisher, a validated event copy, or unmatched started events. Publication adds increasing sequence numbers.

Failures: Invalid identity or event fields raise. The publisher suppresses errors from `emit`.

```luau
local progress = Core.progress.create("run-1", function(event) print(event.sequence) end)
progress.publish("case-1", "case", "setup", "started", nil)
```

### `Core.performance`

Source: [src/core/performance.luau](../src/core/performance.luau).

`summarize(input: Input) -> Summary`; `evaluate(summary: Summary, limits: Limits) -> Evaluation`; `checkSeries(series: Series?) -> ()`

Returns: Statistics, a `passed`/`failed`/`unsupported` evaluation, or no value after series validation.

Failures: Malformed samples, context, percentiles, series or limits raise. Simulated or insufficient observations cannot satisfy observed limits.

```luau
local summary = Core.performance.summarize {
    samples = { 1, 2, 3 }, unit = "ms",
    context = { environment = "lute", signal = "work", timing = "observed" },
}
local evaluation = Core.performance.evaluate(summary, { unit = "ms", minimumSamples = 3, p95 = 4 })
```

### `Core.shape`

Source: [src/core/init.luau](../src/core/init.luau).

`finite(value) -> boolean`; `finiteNonnegative(value) -> boolean`; `nonnegativeInteger(value) -> boolean`; `denseRows(value, count: number) -> boolean`

Returns: A predicate result without coercion. `denseRows` checks an exact dense array and permits JSON marker keys.

Failures: Invalid values return false. These predicates do not validate consumer field names.

```luau
assert(Core.shape.finite(1))
assert(not Core.shape.nonnegativeInteger(-1))
assert(Core.shape.denseRows({ "first" }, 1))
```

## Evidence provenance

Evidence travels on the report. An `Artifact` can carry `sha256`, `size` and a typed `provenance`. Provenance holds:

- The run, case, actor and checkpoint.
- The build (`commit`, `tree`, `clean`, `digest`).
- The executing host and its capabilities, taken from the case origin.
- The `device` class that the caller declares, and `capturedAt`.

A `Review` can carry `kind` (`visual` or `audio`) and `judged`, the content hashes that the reviewer saw. The report decoder keeps both. The report is the only record. No second record exists.

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

### `Evidence.seal`

Source: [src/evidence/seal.luau](../src/evidence/seal.luau).

`seal(report: Report, options: SealOptions) -> Sealed`

Returns: `{ report, issues }`, with stored artifacts bound to the run, build, host, device and capture time.

Failures: Invalid options raise. Unreadable, unstorable or unconfirmed artifacts stay unsealed and produce issues.

```luau
local sealed = Evidence.seal(report, sealOptions)
assert(#sealed.issues == 0)
```

### `Evidence.bindReview`

Source: [src/evidence/seal.luau](../src/evidence/seal.luau).

`bindReview(report: Report, binding: ReviewBinding) -> Report`

Returns: A report copy whose matching review names the hashes that the reviewer judged.

Failures: A missing review raises. This call does not perform or approve a review.

```luau
local reviewed = Evidence.bindReview(report, reviewBinding)
```

### `Evidence.validate`

Source: [src/evidence/validation.luau](../src/evidence/validation.luau).

`validate(report: Report, policy: Policy) -> Result`

Returns: `{ ok, issues, verified }` after coverage, identity, time, bytes and review checks.

Failures: An empty coverage policy or invalid clock raises. Evidence mismatches produce issues and `ok = false`.

```luau
local result = Evidence.validate(report, evidencePolicy)
assert(result.ok, Evidence.explain(result))
```

### `Evidence.expand`

Source: [src/evidence/validation.luau](../src/evidence/validation.luau).

`expand(required: { Requirement }) -> { Cell }`

Returns: The cross product of case, actor, checkpoint and device requirements.

Failures: Empty coverage and empty or repeated names in a requirement raise.

```luau
local cells = Evidence.expand { { caseId = "first", actors = { "client" }, checkpoints = { "ready" }, devices = { "desktop" } } }
```

### `Evidence.explain`

Source: [src/evidence/validation.luau](../src/evidence/validation.luau).

`explain(result: Result) -> string`

Returns: A readable validation result.

Failures: It expects a validation result.

```luau
print(Evidence.explain(result))
```

### `Core.memorySink`

Source: [src/core/provenance.luau](../src/core/provenance.luau).

`memorySink(hash: (string) -> string) -> EvidenceSink`

Returns: An in-memory sink with `put`, `get` and `stat`.

Failures: Unknown references return no bytes or metadata. Hasher failures propagate.

```luau
local sink = Core.memorySink(Lute.sha256)
```

Metadata and a saved screenshot do not establish visual quality, audio quality or physical-device use. A review records that a named reviewer judged specific content. `device` is a claim. The class `physical` is accepted only when `policy.attest.physical(artifact, provenance)` returns true from the caller's own evidence.

---

## Host adapters

Adapters use host operations that you inject. The consumer owns authorization, destinations, artifact custody and release acceptance. Load only the package that the observation needs.

For Studio, Player and Open Cloud, see [execution](execution.md): [native Studio](execution.md#native-studio-execution), [attached Studio](execution.md#attached-studio), [published Player](execution.md#published-player-execution) and [Open Cloud](execution.md#open-cloud-execution).

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

### `Lute.attachments`

Source: [src/lute/attachments.luau](../src/lute/attachments.luau).

`materialize(report: Report, options: Options) -> (Report, { string })`; `directorySink(directory: string) -> Sink`

Returns: A report with stored attachment references and refusal issues, or a filesystem sink.

Failures: Invalid or unsupported attachments produce issues. Sink errors are accounted per attachment.

```luau
local storedReport, issues = Lute.attachments.materialize(report, { directory = outputDirectory })
```

### `Lute.bounded`

Source: [src/lute/bounded.luau](../src/lute/bounded.luau).

`run(argv, seconds, runner?, options?) -> Result`; `runWith(argv, seconds, runner, options?, settings?) -> Result`; `capabilities(settings?) -> { string }`

Returns: A bounded process result, or available process-control capabilities.

Failures: Invalid bounds and unavailable tree control refuse execution. A timeout reports termination rather than success.

```luau
local processResult = Lute.bounded.run({ "lute", "--version" }, 5)
assert(processResult.ok)
```

### `Lute.chunk`

Source: [src/lute/chunk.luau](../src/lute/chunk.luau).

`load(source: string, options: Options?) -> (...unknown) -> ...Value`; `check(source: string, name: string?) -> (boolean, string?)`

Returns: A compiled function, or syntax-check success and an optional error.

Failures: `load` raises on compilation failure. `check` returns false and an error without executing the source.

```luau
local chunk = Lute.chunk.load("return 2 + 2")
local ok = Lute.chunk.check("return 4")
assert(ok)
```

### `Lute.corpus`

Source: [src/lute/corpus.luau](../src/lute/corpus.luau).

`discover(spec: Discovery) -> { string }`; `groupByRequire(files, readFile, aliasPattern) -> { { string } }`; `workers(threadCount, override, fileCount, margin, cap) -> number`; `selection(files, query?) -> PlanSelection`; `literal(text) -> string`; `lockText(sections) -> string`

Returns: Discovered paths, dependency groups, worker count, selection, escaped pattern or lock text.

Failures: Malformed discovery and queries raise. File host errors propagate.

```luau
local escaped = Lute.corpus.literal("case.verify.luau")
assert(string.match("case.verify.luau", "^" .. escaped .. "$") ~= nil)
```

### `Lute.evidence`

Source: [src/lute/evidence.luau](../src/lute/evidence.luau).

`write(report: Report, directory: string, required: { Requirement }?) -> Result`; `finish(report: Report, directory: string) -> string`

Returns: A report and stored evidence results, or the path to the saved report.
`finish` updates the report and summary after `write` has created them.

Failures: Missing required durable evidence becomes a report failure. Filesystem errors can raise.

```luau
local saved = Lute.evidence.write(report, outputDirectory)
assert(#saved.issues == 0)
local reportPath = Lute.evidence.finish(saved.report, outputDirectory)
```

### `Lute.evidenceStore`

Source: [src/lute/evidence-store.luau](../src/lute/evidence-store.luau).

`localDirectory(directory: string) -> EvidenceSink`; `readFile(reference: string) -> (string?, string?)`; `sha256(bytes: string) -> string`; `seal(report: Report, options: SealOptions) -> Sealed`; `validate(report: Report, options: ValidateOptions) -> Result`; `DEFAULT_DIRECTORY: string`

Returns: Filesystem bindings for the portable Evidence operations. `seal` and `validate` fill the store, hash and clock.

Failures: File failures return reasons or sealing issues. Invalid evidence policy raises; validation mismatches produce issues.

```luau
local sink = Lute.evidenceStore.localDirectory(outputDirectory)
```

### `Lute.fixture`

Source: [src/lute/fixture.luau](../src/lute/fixture.luau).

`load(source: string?) -> Snapshot`; `bridge(snapshot: (string | Snapshot)?, options: Options?) -> Bridge`

Returns: Snapshot or bridge. `host` and `files` provide frozen filesystem, compilation and project traversal operations.

Failures: Invalid snapshots, missing files and unsupported reflected behavior raise.

```luau
local bridge = Lute.fixture.bridge()
local frame = bridge.environment.createInstance("Frame")
frame:Destroy()
bridge.close()
```


`bridge(snapshot?, options?)` accepts `content` providers in addition to the reflection and UI options:

- `content.assetVersion(versionId)` returns a live, archivable Model template created in this bridge's environment, or nil for unavailable content. `InsertService:LoadAssetVersion` validates the version ID, clones the template on each call and parents the result to InsertService. Missing providers, unavailable versions and invalid templates raise. The provider owns fixture acquisition and version mapping; the double performs no network fetch and invents no geometry.
- `content.terrainMaterialColor(material)` provides a captured Color3 for an unset terrain material. `Terrain:SetMaterialColor` stores per-terrain overrides and `GetMaterialColor` returns them before consulting the provider. Air, Water, other enum families and invalid colors raise. An unset material without a provider raises rather than inventing a default palette.

`placeEngine().record` keeps diagnostics and sends virtual timestamps and message types to LogService history and MessageOut. History returns independent tables. It keeps the newest 512 entries in order. ClearOutput clears history but keeps diagnostics. Structured Logger context is outside this simulation.

Sound Play, Pause, Resume and Stop update playback state and emit the corresponding events. Virtual time advances TimePosition at PlaybackSpeed. A positive TimeLength permits completion and loops. The simulator does not load sound media, find durations or prove audible playback. AudioPlayer Play sets IsPlaying (including planned playback before readiness), and Stop clears it while preserving TimePosition. AudioTextToSpeech Play sets IsPlaying only when IsLoaded; Pause clears it and preserves TimePosition. Readiness remains a host-supplied fact. Scheduled audio timestamps raise before state changes. Modern audio controls do not advance TimePosition, synthesize media or emit completion; use explicit duration/event facts for those observations. AudioPlayer has no Pause method and AudioTextToSpeech has no Stop method in the engine reference.

`TweenService:Create(instance, tweenInfo, goals)` returns a Tween with `Instance`, `TweenInfo` and `PlaybackState`. Play, Pause and Cancel follow the engine states Begin, Delayed, Playing, Paused, Cancelled and Completed. Virtual time advances a playing tween. When `DelayTime` plus `Time` elapses, the tween writes each goal value once and fires `Completed` with `Enum.PlaybackState.Completed`. A tween that is within 1e-6 seconds of its end is complete. The tween writes no intermediate values, because the engine interpolates natively. Cancel resets progress, writes no goal and fires `Completed` with `Enum.PlaybackState.Cancelled`. Destroying a playing tween stops it. `RepeatCount` other than 0 and `Reverses` raise. The simulator does not prove easing curves or rendered motion.

TextChatService.OnIncomingMessage uses write-only callback storage. A host can inspect and invoke it through propertyOf. This does not prove filtered chat delivery.

Font faces without captured facts still raise errors. Give measured `ui.measureBounds`, `ui.truncateBounds` and `ui.measureText` adapters for the required operations. You can also capture facts with the [native text tool](running.md#capture-native-text-metrics). Verify never substitutes an unrelated face.

Exact measured strings can supplement a face's token grammar. Their native bounds use their captured pixel grid. Their characters do not become composable tokens: an uncaptured combination containing a character outside the original grammar still raises `unsupported_text_metrics`.

Uniform RichText weights use the captured face selected by `<b>` or `<font weight="...">`. Weight names are case insensitive; quoted numeric weights use 100 through 900. Native captures establish that Heavy selects Bold for BuilderSans and Regular for Fondamento and Michroma. Other weights need their own captured facts. Text that changes effective weights between runs still raises `unsupported_text_metrics`.

`measureBounds`, `truncateBounds` and `measureLineHeight` receive `Gui = true` for GUI observations. Service parameters omit it. For the captured missing family `rbxasset://fonts/families/DoesNotExist.json`, service measurement raises `Temp read failed.` while GUI measurement uses SourceSansPro. Its Heavy GUI weight selects Bold. Other uncaptured families still raise `unsupported_text_metrics`.

Truncation compares the rendered prefix and ellipsis with the available width, including fractional widths. An exact fit is accepted. The combined raster width is converted to a float32 result once. The shared Studio case checks widths on both sides of these boundaries.

When `SplitWord` ends at a space boundary, its bounds include the trailing space instead of an ellipsis. Wrapped truncation also retains the natural width of the last visible line. The shared boundary fixture checks both rules with wrapped and unwrapped labels at several widths and heights.

`AtEnd` keeps a word boundary when the prefix and ellipsis fill at least half the available width. Otherwise it cuts within the word. A cut within a word keeps the glyph spacing from the following character in the original text. The shared truncation fixture checks the threshold and the spacing with repeated letters.

Wrapping splits an oversized word across measured characters while retaining kerning and the rounding of cumulative run positions. A fragment keeps an unavoidable rounded glyph advance even when it exceeds the constraint or that glyph's isolated width. Without trailing whitespace, its width is bounded by the larger of the constraint and the largest required rounded advance. Retained trailing spaces can extend this bound. Wrapping prefers whitespace between words and preserves independent paragraph bounds. TextScaled selects a font size at which whole words fit before it checks the wrapped height.

TextScaled supports AutomaticSize. An automatic X axis measures without a width constraint; an automatic Y axis permits the measured height to grow. Automatic XY selects the largest permitted size. Authored dimensions remain minimum bounds, and UITextSizeConstraint still limits the selected size.

### `Lute.gate`

Source: [src/lute/gate.luau](../src/lute/gate.luau).

`run(gate: Definition, options: Options?) -> Outcome`; `last(gate, options?) -> (Outcome?, string?)`; `writeReport(path, runId, report) -> ()`; `cli(draft, args, options?) -> number`; `create(runtime) -> Gate`; `DEFAULT_DIRECTORY: string`

Returns: A bounded gate outcome, its saved predecessor, a CLI exit code, or an injected runtime.

Failures: Invalid flags return code 2. Failed work returns code 1. Invalid definitions and infrastructure failures can raise.

```luau
local outcome = Lute.gate.run(gate, { directory = outputDirectory })
```

### `Lute.host`

Source: [src/lute/host.luau](../src/lute/host.luau).

`host(options: Options, runtime: Runtime?) -> Host`

Returns: A worker host that starts one bounded process per batch.

Failures: Invalid host options raise. Worker launch, delivery and termination failures become batch outcomes.

```luau
local host = Lute.host(workerHostOptions)
```

### `Lute.loader`

Source: [src/lute/loader.luau](../src/lute/loader.luau).

`new(options: LoaderOptions?) -> Loader`

Returns: A cached module loader with `require(path)` and `reference(path)`.

Failures: Missing modules, unknown aliases, cycles and module failures raise with the module path.

```luau
local loader = Lute.loader.new { aliases = { verify = "src" } }
local LoadedCore = loader.require("src/core")
```

### `Lute.memory`

Source: [src/lute/memory.luau](../src/lute/memory.luau).

`create(host: Host) -> Memory`; `settle(options?) -> Reading`; `measure<T>(spec: Spec<T>, options?) -> Result`; `METHOD: string`

Returns: Bounded heap observations using collection witnesses, or a memory helper bound to an explicit host.

Failures: Invalid bounds, collection deadlines and allocation limits raise. Body failures still trigger teardown; cleanup failures stay visible.

```luau
local reading = Lute.memory.settle()
print(reading.heapKb)
```

### `Lute.model`

Source: [src/lute/model.luau](../src/lute/model.luau).

`read(text: string) -> { ModelInstance }`; `descendants(roots) -> { ModelInstance }`; `find(roots, path: string) -> ModelInstance?`

Returns: Parsed XML instances, all descendants or the first path match.

Failures: Invalid XML, binary input or a root other than `roblox` raises. A missing path returns nil.

```luau
local roots = Lute.model.read('<roblox><Item class="Folder"><Properties/></Item></roblox>')
assert(#Lute.model.descendants(roots) == 1)
```

### `Lute.openCloud`

Source: [src/lute/open-cloud.luau](../src/lute/open-cloud.luau).

`connect(options: OpenCloudOptions) -> OpenCloudSession`; `host(options: OpenCloudHostOptions) -> Host`; `describe(outcome) -> string`; `refusedCapabilities(required?) -> { string }`; `UNSUPPORTED: { string }`

Returns: An authorized execution session, a plan host, a readable outcome or unsupported capability names.

Failures: Invalid configuration raises. Refusal, ambiguous submission and polling timeout remain distinct outcomes. Reconcile a handle before another submission.

```luau
local session = Lute.openCloud.connect(openCloudOptions)
local outcome = session.run(cloudInput)
print(Lute.openCloud.describe(outcome))
```

### `Lute.place`

Source: [src/lute/place.luau](../src/lute/place.luau).

`bundle(options: BundleOptions) -> string`; `build(options: Options) -> ()`; `moduleExpression(path: string, rootName: string?) -> string`

Returns: XML module bytes, a written fixture, or a module reference expression.

Failures: Unresolved dynamic or external imports, conflicting names and invalid base XML raise.

```luau
local expression = Lute.place.moduleExpression("src/core")
```

### `Lute.platform`

Source: [src/lute/platform.luau](../src/lute/platform.luau).

`run(options: PlatformOptions) -> { report, directory, reportPath }`

Returns: A standard host report and saved paths.

Failures: Invalid options raise. Host, evidence and attachment failures become failed or unsupported results.

```luau
local result = Lute.platform.run { entry = "examples/platform-entry.luau", host = "simulator", output = outputDirectory }
print(Core.format(result.report))
```

### `Lute.player`

Source: [src/lute/player.luau](../src/lute/player.luau).

`run(options: Options) -> BatchOutcome`; `url(placeId: number, runId: string, selection: Selection?) -> string`; `supported() -> (boolean, string?)`

Returns: A bounded Player outcome, launch URL, or reference-launcher availability and reason.

Failures: Invalid options raise. Unsupported platforms and launch/report failures do not pass.

```luau
local available, reason = Lute.player.supported()
print(available, reason)
```

### `Lute.studio`

Source: [src/lute/studio.luau](../src/lute/studio.luau).

`run(options: Options) -> BatchOutcome`; `worker(path: string) -> ()`; `host(options: HostOptions) -> Host`; `attach(options) -> (Session?, Refusal?)`; `launch(options) -> (Launched?, string?)`

Returns: A Studio outcome, worker execution, host, attached session or disposable launched session.

Failures: Invalid options and unavailable Studio operations raise or return failed outcomes. Attach and launch return nil with a refusal or reason when they cannot open a session.
Attach requires authorization and preserves the caller Studio.

```luau
local host = Lute.studio.host(studioHostOptions)
```

### `Lute.worker`

Source: [src/lute/worker.luau](../src/lute/worker.luau).

`worker(operations: Operations, options: Options?) -> ()`

Returns: No value. It reads a worker batch, loads cases and writes the wire report.

Failures: Bad arguments and batch input raise. Registration failures become source failures.

```luau
Lute.worker(workerOperations)
```

### `Lute.selfRegisteringWorker`

Source: [src/lute/worker.luau](../src/lute/worker.luau).

`selfRegisteringWorker(operations: SelfRegisteringOperations, options: Options?) -> ()`

Returns: No value. It runs modules that register their own cases.

Failures: Bad arguments raise. Source-load failures become source reports.

```luau
Lute.selfRegisteringWorker(registrationOperations)
```

### `Lute.sha256`

Source: [src/lute/hash.luau](../src/lute/hash.luau).

`sha256(bytes: string) -> string`

Returns: The lowercase hexadecimal SHA-256 digest.

Failures: It expects byte text. It grants no source authenticity.

```luau
assert(#Lute.sha256("hello") == 64)
```

### `Lute.typePolicy`

Source: [src/lute/type-policy.luau](../src/lute/type-policy.luau).

`explicitAny(source: string) -> { number }`; `casts(source: string) -> { number }`; `nonStrict(source: string) -> { number }`

Returns: Source offsets for explicit `any`, type assertions, or weakened/missing strict directives.

Failures: Malformed syntax fails closed in the syntax policy. Quoted identifiers do not become annotations.

```luau
assert(#Lute.typePolicy.casts("--!strict\nlocal x = 1") == 0)
```

## Codecs

Portable codecs use no host services.

### `Codec.base64`

Source: [src/codec/base64.luau](../src/codec/base64.luau).

`encode(bytes: string) -> string`; `decode(text: string) -> string?`

Returns: Padded base64 text, or decoded bytes.

Failures: `decode` returns nil for invalid padded base64.

```luau
assert(Codec.base64.decode(Codec.base64.encode("hello")) == "hello")
```

### `Codec.image`

Source: [src/codec/image.luau](../src/codec/image.luau).

`mediaType(bytes: string) -> string?`; `pngSize(bytes: string) -> (number?, number?)`

Returns: A recognized image MIME type, or PNG width and height.

Failures: Unrecognized bytes return nil. This module does not render or fully validate an image.

```luau
assert(Codec.image.mediaType("plain text") == nil)
```

### `Codec.xml`

Source: [src/codec/xml.luau](../src/codec/xml.luau).

`parse(text: string) -> Element`; `children(element: Element, tag: string) -> { Element }`; `first(element: Element, tag: string) -> Element?`

Returns: A parsed root or matching children. `first` returns nil if no child matches.

Failures: Malformed XML raises.

```luau
local root = Codec.xml.parse("<root><item/></root>")
assert(Codec.xml.first(root, "item") ~= nil)
```

## Simulated environment

`Roblox.testEnvironment(options?)` is the optional simulated engine for headless tests. It is plain Luau. It depends on no consumer and reads no generated paths. Do not mount it in a released place.

### What the simulator proves

The simulator proves Luau logic over the declared surface, ordering and disposal. It does not prove rendering, physics, replication, animation, audio, input devices or player capacity. Check a supported behavior against the real engine before you rely on it.

| Layer | Behavior comes from | Engine parity |
| --- | --- | --- |
| `Roblox.testEnvironment` | Built-in and declared classes, and the explicit fakes that you supply. | None. A method that is declared but not implemented raises `unsupported_method`. |
| `Roblox.reflection` and `Roblox.fixtureBridge` | Class defaults and property types from a reflection database. Events, methods, layout, rendering, input and physics exist only where you declare or inject them. | None. The database provides metadata only. |
| `Lute.fixture.bridge` | A serialized reflection snapshot, exported from Studio, and the datatype library bound to it. | Metadata, defaults, enums, brick colors and fonts from the engine that exported it. Behavior stays simulated. |
| Native Studio or Player host | The engine. | The engine. See [execution](execution.md#native-studio-execution). |

### Defaults and opt-in conveniences

| Behavior | Default | Option |
| --- | --- | --- |
| A handler error only prints, so the environment collects it | Engine-true. | `handlerErrors = "raise"` is a test convenience. |
| A signal count for any signal | Added metering. | None. |
| An unknown member raises | Engine-true. | `fakeOn` and `functionDoubles = true` are test doubles. |
| Selection of a hidden or unselectable control | `"raise"` is a test convenience; `"ignore"` drops the write. | `ui.selection = "native"` accepts the write, as Studio does. |
| Selection outside a `PlayerGui` | Allowed as a test convenience. | `ui.selection = "native"` or `ui.requirePlayerGui = true` rejects the write. |
| `TweenInfo`, `FloatCurveKey` and `Path2DControlPoint` fields | Engine-true values and defaults. | None. |
| A property with no stored default reads `nil` | Engine metadata only. | `defaultProperty` gives the engine value. |
| A derived property such as `TextBounds` | Reads as stored. | `computed` is a test convenience. A computed property is read-only unless it declares `writable = true`. |
| An undeclared write raises | Engine-true. | `undeclaredWrites = true` is a test convenience. |
| An undeclared read raises | Engine-true. | `undeclaredReads = "nil"` is a test convenience. |
| `GetStyled` and `GetStyledPropertyChangedSignal` | Bounded flat style cascade, virtual-time transitions and style notifications. | No native rendering. |

### Options and result

`options` has these fields:

- `classes`: a table of `{super?, creatable?, properties = {name = default}, events = {names}, methods = {name = function | true}}`.
  The built-in classes are `Instance`, `Folder`, `Model`, parts, `GuiObject` (size, position, color, anchor), `Frame`, `CanvasGroup`, `ScrollingFrame`, `TextLabel`, `TextBox`, buttons, `UIListLayout`, `UIPadding`, `ScreenGui`, `Humanoid`, `Animation`, `Animator` and `AnimationTrack`.
- `builtins = false` omits the built-in classes.
- `fakes`.
- `limits`: `attributeNameLength` (default 100) and `attributeStringLength` (unbounded unless set).
- `handlerErrors`: `"collect"` (default) or `"raise"`. See [handler errors](#handler-errors).
- `computed`: a table of `["Class.Property"] = function(object) -> value`. See [computed reads](#computed-reads).
- `undeclaredWrites = true` accepts a write to a property that the class does not declare. See [undeclared writes](#undeclared-writes).
- `functionDoubles = true` lets a function assignment install a method double. See [method doubles](#method-doubles).

The result has these members:

- `root`, `createInstance(className, props?)`, `defineClass`, `newSignal`, `heartbeat`.
- `createEngineInstance(className, props?)` creates a known engine-owned Instance class, including a class whose metadata forbids script construction. It bypasses only creatability; defaults, property validation, creation hooks and lifetime accounting remain active. Script constructors still use `createInstance` and keep their restrictions. Use `poke` for engine-owned read-only properties.
- `createEngineObject(className, props?)` uses the same allocation path for a known Object class. An Object that does not inherit Instance has no Instance hierarchy, name, attributes or destruction methods. `releaseObject(object)` releases an owned Object or Instance and its signal connections. It is an environment cleanup operation, not a simulated native Object method or garbage collector. Creation hooks and fixture tracking receive Objects.
- `task` with `spawn`, `defer`, `delay`, `wait` and `cancel` on virtual time. Also `scheduler`, `step(seconds)` and `now`.
- `scheduler.block(register)` suspends the current task. The registration may return a cleanup function. The scheduler calls it once when the task resumes or is canceled, then releases it. Cleanup failures enter `scheduler.failures`; cancellation still closes the task.
- Inspection: `childrenOf`, `parentOf`, `descendantOrderOf`, `propertyOf`, `attributeOf`, `isAlive`, `liveObjects` and `liveConnections`.
- `descendantOrderOf(ancestor, object)` returns the registration order within that ancestor, or nil when the object is not its descendant. Moving within the ancestor preserves the order. Leaving and reentering gives a later order. ScreenGui hit testing uses this order to resolve equal DisplayOrder values.
- `propertyOf` can inspect a declared callback. The script-side instance getter still rejects callback reads. Method doubles and undeclared callback names are not exposed by `propertyOf`.
- `poke` and `fire`, which apply an engine-side change and an engine-side event.
- `failNext(operation)` and `clearFailures`.
- `errors`, the handler errors that the engine would only print.
- `snapshot(object)`, which returns class, name, set properties, attributes and children as a table for debugging.
- `fake(member, handler)` and `fakeOn(object, name, handler)`.
- `connectionsOf(signal)`, `firesOf(signal)` and `connectionsOfInstance(object)`.

`createInstance` takes children in the array part: `createInstance("Model", {Name = "m", childA, childB, Parent = root})`. `Roblox.isInstance(value)` and `Roblox.typeName(value)` identify instances and datatypes. `Roblox.assertInstance(value: unknown)` returns the registered simulated `Instance`. It raises an error for other values. Use it when an unknown or native type contains a simulated instance. It keeps identity after destruction. It rejects lookalike tables, native instances and Object-only values. The weak registry does not keep instances. `isInstance` rejects Objects that do not inherit Instance. `typeName` returns `Object` for those Objects. A Studio Client capture on 2026-10-22, version `0.744.0.7441077`, confirmed this identity for VirtualInput, its distinct factory objects and its Object-only members.

The package exports the types `Environment`, `EnvironmentOptions`, `EnvironmentDefineOptions`, `EnvironmentSnapshot`, `EnvironmentMethod`, `Signal`, `Connection`, `VirtualScheduler`, `VirtualTask` and `VirtualCallback`. Instance properties and per-class methods are dynamic schema boundaries. Their values still need the class contract of the consumer. Assigning a method dictionary does not prove its signatures.

### Datatypes

`Roblox.datatypes` is a pure Luau copy of the Roblox datatypes. It needs no engine. Each value is a userdata, as in the engine. `type(value)` is `"userdata"`, and table functions refuse it. Values are read-only, compare by value and print with the engine format. Components are rounded to 32-bit floats, and `UDim` offsets are truncated to 32-bit integers, as in the engine. Arithmetic and member errors use the engine messages.

| Datatype | Members |
| --- | --- |
| `Vector2`, `Vector3` | `new`, `zero`, `one`, the axis constants, `X`, `Y`, `Z`, `Magnitude`, `Unit`, `Lerp`, `Dot`, `Cross`, `Abs`, `Ceil`, `Floor`, `Sign`, `Max`, `Min`, `Angle`, `FuzzyEq`, `+`, `-`, `*`, `/`, `//` and unary `-`. `Vector3.FromNormalId` and `Vector3.FromAxis`. |
| `Vector2int16`, `Vector3int16` | `new`, `X`, `Y`, `Z`, `+`, `-`, `*`, `/` and unary `-`. Components wrap to 16 bits. |
| `CFrame` | `new` (position, look-at, quaternion and 12-number forms), `identity`, `Angles`, `fromEulerAnglesXYZ`, `fromEulerAnglesYXZ`, `fromOrientation`, `fromAxisAngle`, `fromMatrix`, `lookAt`, `lookAlong`, the position and vector members, `Rotation`, `GetComponents`, `Inverse`, `Lerp`, `Orthonormalize`, the `ToWorldSpace`, `ToObjectSpace`, `PointTo...` and `VectorTo...` methods, `ToEulerAnglesXYZ`, `ToEulerAnglesYXZ`, `ToOrientation`, `ToAxisAngle`, `FuzzyEq`, `*`, `+` and `-`. |
| `Color3` | `new`, `fromRGB`, `fromHSV`, `fromHex`, `toHSV`, `R`, `G`, `B`, `Lerp`, `ToHSV` and `ToHex`. |
| `UDim`, `UDim2` | `new`, `fromScale`, `fromOffset`, `Scale`, `Offset`, `X`, `Y`, `Width`, `Height`, `UDim2:Lerp`, `+`, `-` and unary `-`. |
| `Rect` | `new` with four numbers or two `Vector2` values, `Min`, `Max`, `Width` and `Height`. |
| `Ray`, `Region3` | Ray origin, direction, unit ray, closest point and distance; region center, size and grid expansion. |
| `Random` | `new`, `NextNumber`, `NextInteger`, `NextUnitVector`, `Shuffle` and `Clone`. Seeded streams are reproducible and clones advance independently. The generator reuses Verify's agent-evaluation stream; sequences do not match Roblox's generator. `Shuffle` operates on a dense array without invoking metamethods and keeps hash entries. |
| `RaycastParams`, `OverlapParams` | Mutable filters, include/exclude arrays, collision group and collision flags; ray water filtering; overlap limit and tolerance. Filter arrays copy on assignment and read. These values configure the WorldRoot query double described above; they do not give a physics engine. |
| `NumberRange`, `NumberSequence`, `ColorSequence` and their keypoints | `new` in each engine form, `Min`, `Max`, `Keypoints`, `Time`, `Value` and `Envelope`. The engine rules for keypoints apply. |
| `BrickColor` | `new` with a number, a name, a `Color3` or three numbers, `palette` (0 to 127), `random`, the named constructors, `Number`, `Name`, `Color`, `r`, `g` and `b`. |
| `Font` | `new`, `fromName`, `fromId`, `fromEnum`, `Family`, `Weight`, `Style` and `Bold`. `Family`, `Weight`, `Style` and `Bold` are writable, as in the engine. |
| `TweenInfo`, `Content`, `FloatCurveKey`, `Path2DControlPoint` | The engine constructors and fields. `Content` has `fromUri`, `fromAssetId`, `fromObject` and `none`. |
| `Enum` | Families, items, `Name`, `Value`, `EnumType`, `IsA`, `GetEnumItems`, `FromName`, `FromValue` and `Enum:GetEnums()`. |

The library also has these functions:

- `typeName(value)` returns the datatype name, or nil for other values.
- `typeof(value)` returns the datatype name, or the result of the builtin `typeof`.
  Luau gives no other way to name a userdata, so code under test must call this function instead of the builtin.
  `Roblox.typeName(value)` also names simulated instances.
- `enumType(item)` returns the family name of an enum item.
- `readCFrame(cframe)` returns `x, y, z` and the nine rotation numbers.
- `create(catalog)` returns a new library bound to `{ enums?, brickColors?, fonts? }`.

The default library has no catalog. Its `Enum` is permissive: any family and any item name exist, and items have no `Value`. `BrickColor`, `Font.fromEnum` and `Font.Bold` need a catalog. A library from `create` or from a [reflection snapshot](#reflection-snapshots) is strict. An unknown family or item raises the engine error. Values from different libraries interoperate. Enum items of the same family and name are equal.

`TweenInfo.new` defaults to 1, `Enum.EasingStyle.Quad`, `Enum.EasingDirection.Out`, 0, false and 0. `FloatCurveKey` tangents default to nil and are writable. `Path2DControlPoint` tangents default to `UDim2.new(0, 0, 0, 0)`.

`tests/datatypes.lute.verify.luau` compares more than 100 probes with results that Studio recorded. A probe that declares a tolerance compares its numbers with that relative tolerance. Floating-point geometry probes declare their tolerances; other probes match exactly.

`Animator:LoadAnimation` returns a track. `Play`, `Stop` and `AdjustSpeed` change `IsPlaying` and `Speed` and fire `Stopped` and `Ended`. The simulator blends no frames. The package exports selected `Datatype...` aliases, plus `DatatypeLibrary` and `DatatypeCatalog`. The defining datatype module declares the other types. These types describe the values for the type checker. At run time each value is a userdata.

### Instance behavior

- Instances support `Parent`, `Name`, children events, find and ancestor lookups and `GetFullName`.
- `WaitForChild(name, timeout?)` returns an existing direct child without yielding. Otherwise it waits on the virtual scheduler until a child is added or renamed to `name`. A positive timeout returns nil when it expires; nil waits indefinitely. Nonpositive timeouts raise before the existing-child lookup. The simulator does not print the engine's infinite-yield warning.
- `Destroy` locks the parent, destroys the descendants and disconnects the signals of the instance.
- Attributes have change signals. Property change signals fire only on change.
- Signals start listeners in connect order on separate scheduler coroutines. A yielding listener does not suspend the emitter or other listeners. A connection that disconnects before its listener starts is skipped; a started listener may finish after disconnection.
- `signal:Wait()` yields through the existing scheduler until the next fire and returns its complete argument tuple. It ignores previous fires. Resumption and task cancellation release the wait listener.
- `signal:Once(handler)` connects a listener that disconnects before its first run and returns the connection. Disconnecting it earlier skips the listener.
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
  A schema that describes an API is never an implementation. A test that needs a result provides it explicitly.
- `Clone()` remaps instance references inside the clone, and copies attributes and tags.
  It omits nonarchivable descendants and leaves external references external. It does not copy signals.
- The environment includes recursive `FindFirstChildWhichIsA`, exact and inherited ancestor lookup and instance tag methods.

### Reflection and behavior adapters

The built-in schemas are a small declared test surface. They are not a complete reflection database. Use the [reflection and UI adapters](#reflection-and-explicit-ui-fakes) for standard integration.

A custom environment can give two functions:

- `defaultProperty(className, property, fallback)`. A returned `false` is a real default. Return `fallback` for an unmapped property.
- `validateProperty(className, property, value, operation)`. `operation` is `set` for an authored assignment and `poke` for a simulated engine change.

A class property that you declare as `false` has no default and reads `nil`. Reflection declares every database property that way. A property for which the database stores no default reads `nil`, unless the consumer overlay declares a value. A stored `false` stays `false`. Validation runs before mutation. Explicit fakes do not establish native rendering or input fidelity.

`environment.defaultClassProperty(className, property)` reads the same default without allocating an object. It includes inherited properties and the configured default provider. An unknown class or property raises.

### Handler errors

The engine prints an error that a handler raises. It does not raise the error to the caller. The default `handlerErrors = "collect"` matches the engine. The environment appends each message to `errors`.

`handlerErrors = "raise"` is an opt-in test convenience. After a property write, `poke`, `Parent` change, attribute change, method call, `fire` or `Signal:Fire`, the environment rethrows. It joins every message that the operation collected with a newline, removes them from `errors` and raises the result. Every handler still runs first. A nested operation inside a handler does not raise on its own. An error from the operation itself wins and leaves the handler messages in `errors`. Any other value of `handlerErrors` raises when you create the environment.

### Method doubles

A class declares each member that an instance has. A read of any other member raises. A test sometimes needs a member that the schema omits, such as `GetFocusedTextBox` or `IsKeyDown`.

- `fakeOn(object, name, handler)` installs `handler` for that instance only. It returns idempotent cleanup that restores the previous active override. Out-of-order cleanup does not restore an already disposed handler. Later explicit method assignments remain in place. Overrides use the instance's existing method-double storage.
  The call passes the instance as `self`. A second call replaces the first.
  It raises for a property, an event, `ClassName` and `Parent`. It never reaches another instance or a clone.
- `functionDoubles = true` lets `object.Name = function(self, ...) end` do the same.
  A function written to a declared property still goes through validation.
  Without the option, a function assignment to an undeclared member raises "is not a valid member".

Both forms are test doubles, not engine behavior. The engine has no such assignment.

Callback members are `OnInvoke`, `OnServerInvoke`, `OnClientInvoke` and `ShouldDeliverCallback`. They accept assignments but always raise errors on reads. Assignment does not check callability. Use a function for a callable handler. Use nil to clear it. `propertyOf` inspects the stored value without a native member read. Reflected Write and None members also reject reads. This includes computed getters and method doubles. Class specifications can declare inherited restrictions with `access = { Member = "read" | "write" | "none" | "callback" }`. The option is off by default because it would turn a mistyped assignment into a silent member. `fakeOn` is explicit and always available. A double wins over a declared method of the same name. A reference that you read before a replacement keeps the earlier handler.

### Computed reads

`computed = { ["TextLabel.TextBounds"] = function(object) return value end }` answers a read of a derived property. The key is a class name and a property name. A getter on a class also applies to its subclasses. It also makes an undeclared name readable, and `GetPropertyChangedSignal` accepts it. A write or a `poke` to a computed property raises. Declare `{ get = fn, writable = true }` instead of the function to opt in to writes. A write or a `poke` then stores the value and notifies as a normal write does. A read returns the getter result, or the stored value when the getter returns nil. `Clone` copies the stored value of a writable computed property. The getter runs on every read. Fire the changed signal with `poke` on a stored property that it depends on. `propertyOf` and `snapshot` return stored values only. This is a test convenience. It does not compute layout or text metrics. The getter you give does.

### Undeclared writes

The engine refuses a write to a property that the class does not have. The default matches. `undeclaredWrites = true` is an opt-in test convenience. Set `undeclaredReads = "nil"` to return `nil` for unknown keys. A known key can name a property, event, method, child or method double. Unknown keys include values that are not strings. `undeclaredWrites` still controls writes. A write or `poke` then stores the value, fires the property signals and makes the name readable and cloneable. A read of a name that nobody wrote still raises. Events, methods and `ClassName` still refuse a write. Validators still run. The reflection adapter still checks every declared property.

### Hierarchy events

- The events are `AncestryChanged`, `DescendantRemoving` and, for a subtree, `DescendantAdded`.
- Moving a subtree notifies the ancestors that it leaves or enters. A common ancestor receives neither event.
- Removal runs before detachment, with the root before its descendants.
- An ancestry callback on the moved instance or its descendants receives the moved instance and its new parent.
- A same-parent assignment emits no events.
- Reparenting the removing instance from its removal callback fails.
- The simulator dispatches immediately. A native deferred signal mode can expose different callback timing and observed state.
- `task.defer` keeps the engine re-entrancy limit. A thread deferred from a deferred thread is one level deeper. Deferring past 80 levels in one resumption raises `Maximum re-entrancy depth (80) exceeded calling task.defer`.
- The order across events beyond these guarantees is not a contract.

### Held selection navigation

`GuiService:Select(parent)` chooses the eligible descendant with the lowest SelectionOrder inside the input host's PlayerGui. It excludes hidden, nonselectable, noninteractable and off-screen objects. Active does not affect eligibility. A parent with no eligible descendants leaves SelectedObject unchanged. A parent outside the PlayerGui raises an error.

The simulated input host repeats held arrow-key selection after 0.5 seconds, then at intervals of at least 0.12 seconds. Release stops the repeats. A repeat moves the current selection without another `InputBegan` event. A focused TextBox prevents selection movement. The shared Studio case checks the initial delay, repeat movement, release, key events and the end of a collection.

`UserInputService:GetGamepadState()` returns the 24 idle controls for each Gamepad1–Gamepad8 slot, including disconnected slots. Each InputObject identifies its slot and key, with End state and zero position. Other UserInputType values return an empty array. Each call returns a separate array. This initial-state model does not inject gamepad input.

### Input action state

`InputAction:Fire(value)` and `GetState()` share state with simulated keyboard dispatch. The value must match the action type: boolean, number, Vector2 or Vector3. Repeated values emit no event. Boolean transitions emit `Pressed` or `Released` before `StateChanged`. Other types emit only `StateChanged`.
`InputBinding:Fire(value)` on a Scriptable binding feeds its parent InputAction with the same type and enabled rules as `InputAction:Fire`. It raises for any other binding type.
An enabled automatic `InputBinding` whose `UIButton` is a clicked GuiButton fires its Bool action true on the pointer press and false on release. A non-Bool action raises `unsupported_simulated_input`. Touch dispatch to UIButton bindings is not simulated.

An action must belong to a DataModel and be enabled. Its nearest InputContext must also be enabled. Disabling either resets the state. A parent change resets affected actions, and a type change publishes the new zero state. Clones start at zero. The shared Studio sequence checks these transitions, duplicate suppression and destruction. This model does not establish physical input delivery.

### Haptic requests without motor hardware

The default environment has no haptic motors. `HapticService:IsVibrationSupported()` and `IsMotorSupported()` return false. `HapticEffect:Play()` and `Stop()` accept requests but produce no motor output or `Ended` event. This matches the observed Studio host without haptic hardware. `SetWaveformKeys()` accepts FloatCurveKey arrays only when the effect type is Custom. Native request validation also accepts empty arrays, negative key times, repeated times and values outside 0–1. This model does not simulate waveform playback on supported hardware.

---

### `Roblox.testEnvironment`

Source: [src/roblox/environment.luau](../src/roblox/environment.luau).

`testEnvironment(options: EnvironmentOptions?) -> Environment`

Returns: An isolated engine double with virtual time, declared classes and resource accounting.

Failures: Invalid schemas and options raise. Undeclared or unsupported operations raise when used.

```luau
local environment = Roblox.testEnvironment()
local folder = environment.createInstance("Folder", { Name = "Example" })
folder:Destroy()
assert(environment.liveConnections() == 0)
```

### `Roblox.isInstance`

Source: [src/roblox/environment.luau](../src/roblox/environment.luau).

`isInstance(value: unknown) -> boolean`

Returns: True for a registered simulated Instance, including a destroyed one.

Failures: Other values return false.

```luau
assert(Roblox.isInstance(environment.root))
```

### `Roblox.assertInstance`

Source: [src/roblox/environment.luau](../src/roblox/environment.luau).

`assertInstance(value: unknown) -> Instance`

Returns: The same registered simulated Instance.

Failures: Native instances, lookalikes and Object-only values raise.

```luau
local instance = Roblox.assertInstance(environment.root)
```

### `Roblox.typeName`

Source: [src/roblox/environment.luau](../src/roblox/environment.luau).

`typeName(value: unknown) -> string`

Returns: A simulated datatype or instance type name, or the host type name.

Failures: It does not validate a class contract.

```luau
assert(Roblox.typeName(environment.root) == "Instance")
```

### `Roblox.datatypes`

Source: [src/roblox/datatypes/init.luau](../src/roblox/datatypes/init.luau).

`create(catalog: Catalog) -> Library`; `typeName(value) -> string?`; `typeof(value) -> string`; `enumType(item) -> string?`; `readCFrame(value) -> twelve numbers`

Returns: A catalog-bound datatype library or type/component observations. Constructors listed above return simulated datatype values.

Failures: Invalid components and unknown strict catalog members raise. Catalog-dependent operations fail without a catalog.

```luau
local vector = Roblox.datatypes.Vector3.new(1, 2, 3)
assert(Roblox.datatypes.typeof(vector) == "Vector3")
```

### `Roblox.value`

Source: [src/roblox/value.luau](../src/roblox/value.luau).

`value(item: unknown) -> Value`; `read(value: Value, key: unknown) -> Value`; `write(value: Value, key: unknown, item: Value) -> ()`; `invoke(value: Value, ...unknown) -> ...Value`

Returns: VM values and the results of table reads or function invocation.

Failures: Invalid VM operations and invoked function errors propagate.

```luau
local wrapped = Roblox.value.value({ count = 1 })
Roblox.value.write(wrapped, "count", Roblox.value.value(2))
local count = Roblox.value.read(wrapped, "count")
```

## Reflection and explicit UI fakes

### Reflection

`Roblox.reflection.create { database, typeName, enumType?, classes?, referenceClass?, validateProperty? }` builds an environment from a reflection database. Pass `Roblox.reflectionSnapshot.database(snapshot)` and `Roblox.typeName`.

- `enumType(value)` returns the enum family name, with or without the `Enum.` prefix.
- The adapter inherits class defaults, rejects unknown and read-only writes, and validates native datatypes.
- `referenceClass(className, property)` narrows reference properties. The `Ref` metadata of the database does not include the target class.
- `classes` overlays explicit events and methods.
- `validateProperty` adds fixture restrictions.


### Fixture bridge

`Roblox.fixtureBridge { database, typeName, enumType?, library?, classes?, referenceClass?, validateProperty?, defaultProperty?, handlerErrors?, computed?, undeclaredWrites?, functionDoubles?, ui?, layout? }` composes reflection, the event metadata of the simulator, UI fakes and the engine seam over one environment.

- UI fake classes that the database lacks appear in `unavailable`. The bridge does not invent them.
- `ui = false` omits the UI fakes. Entries in `classes` replace the defaults.
- `ui.validate(className, property)` keeps UI property validation for the pairs that it accepts. It relaxes the rest while every fake stays installed.
- `ui = { validate = false }` installs no UI validator.
- UI validation acts only on `SelectedObject`. Every other write makes no extra call.
- `ui.selection` is `"raise"` (default), `"ignore"` or `"native"`. See [rejected selection](#rejected-selection).
- `ui.requirePlayerGui = true` requires the target to descend from a `PlayerGui`.
- `GuiService.GetGuiInset` requires an explicit `ui.methods["GuiService.GetGuiInset"]` handler that returns both current inset vectors. There is no inferred inset or relationship to `TopbarInset`. A provider provides representative host state; it does not establish native inset or safe-area coverage.

The options `defaultProperty`, `computed`, `handlerErrors`, `undeclaredWrites` and `functionDoubles` pass to the environment. `Lute.fixture.bridge` accepts the same options.

The bridge returns `{ environment, engine, ui, layout, unavailable, faults, hasClass, observe, track, record, instanceHost, accounting, close }`.

`layout = { roots, viewport, origin?, screenArea?, projection?, read?, component?, vector?, measureBounds? }` enables simulated layout. `roots()` returns mounted roots. `viewport()` returns `{ X, Y }`. `screenArea(screenGui)` returns `{ x, y, width, height }` for each ScreenGui. Give `runtime.screenArea` to use the current device inset area. Computed geometry reads flush pending layout, including inside render callbacks. Reads within the same mounted root reuse the flush while its inputs stay unchanged. `bridge.layout.step()` explicitly publishes a layout pass without advancing time or connecting frame handlers. Call `bridge.layout.flush(object)` to flush only mounted roots containing that object. Computed geometry reads use this path; other roots retain pending changes until their own read or a full step. Unchanged subtrees reuse validation and measurements, and style steps refresh only dirty observations and active transitions. `environment.propertyOf` inspects stored geometry without flushing it.

BillboardGuis below a mounted root establish independent canvas spaces. Their native `AbsolutePosition` is `(0, 0)`. Their `Size` scale components specify studs; offsets specify pixels. Layout projects the stud components at the offset camera depth and rounds the canvas dimensions to pixels. Screen ancestry contributes no origin, rotation or scale. Descendants use the existing layout and text measurement rules within that canvas. `SizeOffset`, `AlwaysOnTop` and `LightInfluence` do not change local canvas geometry. This models no lighting, occlusion or screen hit testing.

`layout.ignoreDecorativeWorldGui = true` explicitly excludes noninteractive world layers from layout and hit testing without changing their instances. Hidden controls do not make a layer interactive. Visible buttons, active or selectable GUI objects, and enabled drag detectors still require supported projection and input behavior. The default continues to refuse unsupported enabled world layers. An excluded decoration establishes no native geometry or rendering evidence.

`Roblox.UiProjectionHost` is `{ revision, camera, adornee }`. `revision()` returns a number that changes whenever host projection inputs change. `camera()` returns `{ basis, viewport = { X, Y }, fieldOfView }` or nil. `adornee(instance)` returns `{ basis, size }` or nil. A basis contains `position`, `right`, `up` and `back`, each a numeric `{ X, Y, Z }`; its axes describe an orthonormal frame. Adornee sizes are full dimensions in studs. The field of view is vertical, in degrees. The fixture bridge supplies this contract from Workspace.CurrentCamera and BasePart CFrame and Size. An explicit Adornee takes precedence over the parent part. Custom hosts can provide other adornee geometry. Missing camera, target, bounds or required properties raise `unsupported_ui_layout` before geometry publication.

StudsOffset and ExtentsOffset use the camera axes; extents use half the camera-aligned adornee bounds. World-space variants use the world axes and bounds. Positive depth offsets bring the canvas toward the camera. On the reference host, MaxDistance culls at the offset camera depth; zero and infinity remove the limit. Out-of-range and behind-camera canvases become zero-sized, while descendant pixel offsets remain authored. Disabled BillboardGuis retain their last published geometry and are excluded from hit testing. Enabled world GUI input remains unsupported. The shared native fixture checks text and descendants at two camera distances, transformed screen ancestry, offsets, lighting flags, parent-part movement, camera rotation, disabled retention and culling boundaries. Nondefault deprecated DistanceLowerLimit and DistanceUpperLimit remain unsupported. Projected input and arbitrary text rendering remain outside this geometry claim.

Layout clamps `ScrollingFrame.CanvasPosition` when it owns the measured bounds. Poked `AbsoluteSize`, `AbsoluteWindowSize` or `AbsoluteCanvasSize` that differ from its last publication make those bounds stale. Before the first pass, nonzero bounds count as supplied geometry. If stale bounds would cause a clamp, layout raises `unsupported_ui_layout` before publishing geometry. The error names the instance and shows supplied and computed bounds. This includes poked bounds with an unmeasured zero canvas. Author `Size` and `CanvasSize`, or keep the poked frame outside layout roots.

`CanvasPosition` uses screen pixels, including under `UIScale`. Setting `GuiService.SelectedObject` scrolls its measured, enabled `ScrollingFrame` ancestors immediately. Selection scrolling can move both axes regardless of `ScrollingDirection`. A control that fits the window moves only far enough to fit. An oversized control that lies outside the window advances by its own extent; a partial overlap stays in place. Nested ancestors use the geometry from before the selection change. The shared native fixture checks scaling, disabled scrolling, oversized controls and nested frames. The layout controller's `close()` disconnects its selection observers; closing a fixture bridge calls it automatically.

`layout.objectsAtPosition(root, x, y)` queries published rectangles in GUI coordinates. It returns visible objects from front to back, including objects that cannot receive input. It supports Global and Sibling ordering, ancestor clipping and enabled ScreenGuis. Rotation turns descendant positions and hit regions. Clipping is ignored when the clipping object or any ancestor is rotated, as observed on the reference host; rotation of the clipped child alone does not disable clipping. Right and bottom edges are inclusive, as in the native fixture. Coordinates must be finite integers. Equal DisplayOrder values put later-registered ScreenGuis in front. This includes ScreenGuis inside folders. Moving a screen within the same root preserves its registration order; removing it from the root and adding it again changes the order. Unsupported geometry raises errors. The input backend separately checks input eligibility and routes presses and releases. The geometry query dispatches no events.

Layout supports UDim2 dimensions, anchors, scale, fixed padding, size constraints, single-line lists and wrapped lists. Lists support parent Fill, individual UIFlexItem modes, weighted growth and shrink, size limits, cross-axis flex and line alignment. Shrink weights include each item basis. Items at a size limit release remaining space to other flexible items. The same 58 flex configurations run in the simulator and Studio. Main-axis SpaceBetween, SpaceAround and SpaceEvenly distribute free space independently of ordinary alignment. Fitting spacing replaces list padding, while AbsoluteContentSize still includes the authored padding. Overflow retains authored gaps: SpaceBetween starts at the leading edge; SpaceAround and SpaceEvenly center the group. Shared fixtures check both axes and all three ordinary alignments. Fixed ScrollingFrame axes reserve their UIPadding during flex distribution. Automatically sized scroller axes retain unpadded flex growth. Intrinsic AutomaticSize supports fixed child bounds, simple lists and grids, including growth and shrink.

UIGridLayout supports both fill directions, start corners, sorting, alignment, cell padding and maximum cells per row or column. It publishes AbsoluteCellSize, AbsoluteCellCount and AbsoluteContentSize. A layout aspect constraint controls cell size with both aspect types and dominant axes. Cell dimensions use native float precision before the fit calculation. Both hosts run the same 37 configurations observed on native Studio. Individual size constraints can reserve multiple cells. The visible cell is centered within its reserved cells. Maximum sizes, child scales and child aspect constraints change the visible rectangle. Nine additional native configurations check these rules. Nonpositive sizes, negative padding and cells that depend on an automatic parent axis also fail before changes.

Wrapped lists form lines in either fill direction. Each line distributes its flexible items separately. Cross-axis flex distributes or stretches lines. Scaled padding uses the corresponding parent axis. Fixed-child lists support automatic sizing on either axis. They handle resize, visibility, sorting, removal and wrapping changes. Individual GUI aspect constraints support both aspect types, dominant axes, scaling, size limits and list flex. Both hosts run the same 1,164 wrapping and aspect configurations observed on native Studio. They also run reflow mutations.

Relative children under automatic parents support bounded measurement. Lists require the authored minimum to contain the children under both ancestor and final bounds. Free layouts measure natural child bounds first, then relative dimensions, then final padded bounds. Unpadded relative positions and anchors are supported when the final children fit. The same 444 configurations and a resize, minimum-size, visibility, insertion, removal and padding mutation sequence run under Studio and the double.

Unresolved relative growth and padded relative positions remain unsupported. Relative children under constrained automatic parents also remain unsupported. The same applies to relative intrinsic child sizes with their own automatic axis or aspect constraint. Unwrapped lists reject non-leading or overflowing distributed spacing. Table layouts, page layouts and LayerCollectors other than ScreenGui and BillboardGui also fail. Aspect constraints on automatic-size GUI objects fail. These cases raise `unsupported_ui_layout` before geometry publication. A `StyleLink` requires an effective-property `read(instance, property)` provider; the bridge provides its UI style reader by default. Supplied reader errors propagate. `vector(x, y)` selects the output datatype constructor. These mechanisms are simulated and do not establish native rendering or input coverage.

`Lute.fixture.bridge` installs captured text measurements by default. TextService.GetTextBoundsAsync and GetTextSize use font advances, pair adjustments and boundary corrections observed on native Studio. The facts record engine version, font face and supported tokens at integer sizes 1-100. Committed families are Builder Sans, Nunito, Fondamento and Michroma, each with Regular, Medium, SemiBold and Bold weights. The fixtures also include Gotham SSm Medium and Bold; Source Sans Pro Regular, SemiBold and Bold; RobotoMono Regular; Guru Regular; and Legacy Arial Regular. All use Normal style. Unknown faces or tokens raise `unsupported_text_metrics`. The simulator does not estimate those inputs. GetTextSize limits height to whole lines within frameSize.Y, with at least one line. Width includes all lines.

Rich text supports underline, strikethrough, stroke, mark, comments, entities, line breaks, uppercase, font color and font transparency. Bold tags select the captured Bold face when all text has the same effective weight. Mixed font weights and other tags that change font metrics remain unsupported. Token coverage belongs to each captured face. Builder Sans Regular includes the Latin extensions and Japanese characters exercised by its committed service cases; this does not establish support for all Unicode text.

With UI behavior enabled, `TextLabel`, `TextButton` and `TextBox` compute `ContentText` from their current `Text` and `RichText` values. Plain text stays unchanged. Rich text removes tags and comments, decodes the five named XML entities and converts line-break tags to newlines. Content preserves letter case inside uppercase tags. Reads update immediately, including before parenting and after cloning. The shared native case checks these reads; it does not establish property-change signal or automatic localization behavior.

A given `ui.measureBounds` or `ui.measureText` replaces the default for that method. Set the field to false to leave the method unsupported. Portable Roblox.fixtureBridge and Roblox.reflectionSnapshot.bridge still need explicit measurement providers.

Layout passes an optional second argument, `unwrappedWidth`, to `measureBounds` for an unwrapped GUI observation. The default provider uses this width to test the final space gap. Plain text can omit that gap from its bounds when this makes the line fit. It preserves the original glyph spacing and does not join the words for kerning. Rich text keeps the gap. Service measurements receive no second argument and keep their original wrapping rules. Plain unwrapped text without automatic sizing tests horizontal fit; rich text, wrapped text and automatic sizing also test the available height.

The flexed text fixture allows 0.00001 pixels of error in relative child positions. Native float rounding can change these positions when the screen origin changes, including a small nonzero position for the first child. The fixture still compares text bounds, sizes and fit results exactly.

The optional `measureLineHeight(parameters, lines, spacing)` provider returns a block height for GUI layout. The default provider adds each line in float32 raster coordinates before converting to GUI coordinates. This preserves native rounding for scaled fonts and fractional `LineHeight`. A custom bounds provider without this callback uses its returned line height in GUI coordinates. The bridge forwards the UI callback unless layout supplies one.

Text service measurements use the same raster accumulation. `GetTextSize` compares complete block heights with the supplied height limit. It includes a block that fits exactly, even when dividing the limit by a rounded single-line height would lose a line. Shared native cases cover 120 height limits across Builder Sans and Legacy Arial sizes.

Rich text converts raster bounds with the reciprocal of the float32 raster scale. It trims a line's trailing space before splitting an oversized word. Wrapped rich text with `TextTruncate.None` reports the full text height, including lines outside the control. `TextFits` still checks the available height. Shared native cases check these rules against the text service and GUI bounds.

Layout uses measureBounds to publish TextBounds and TextFits and measure automatic text size. The bridge forwards its UI provider unless layout has its own. Line height and UI scale use line metrics observed on native Studio. These include Legacy Arial strut sizes. Fractional rendered font sizes are floored and must remain in the range 1-100. Text supports automatic axes and size constraints. Lists measure wrapped automatic height at the assigned flex width. Plain wrapped bounds limit visible height to complete lines and keep full wrapped width. TextFits is false when lines do not fit. Unwrapped multiline text beyond the available height remains unsupported. TextScaled fits whole words before checking height; TextTruncate supports AtEnd and SplitWord. Both hosts run 36 constraint, 180 clipping, 36 flex and 36 Legacy Arial configurations, plus shared line-height, rich-text and truncation cases. Legacy Arial geometry allows 0.001 pixel error for native float rounding. Service bounds compare exactly. A native pass covers only the committed font faces and text grammar. It does not prove arbitrary text rendering.

- `track()` lists created instances and cloned `{ source, copy }` pairs until `stop()`.
- `faults` wraps `failNext`. `assertConsumed` refuses an injection that never fired.
- `observe` and `record` report each create, property, attribute, parent and destroy operation. They mark injected failures. Each event also carries the `object` and, for property, attribute and parent operations, the new `value`.
- `accounting` and `close` return the live objects, the live connections and the pending faults.
- `instanceHost(actor)` reuses the same environment.

Application-specific UI expectations stay with the consumer.

This is simulated behavior that is validated against engine metadata. It is not engine parity. Instances are Luau tables. Defaults and property types come from the database. Events, methods, layout, rendering, input and physics exist only where you declare or inject them.

### Defaults that the database does not store

`defaultProperty(className, property)` is a bridge option. The bridge calls it for a declared property that has no stored default and no overlay value. The order is the database default, then an overlay value, then the hook, then `nil`. Return `nil` for no default. A declaration is never a default. Without a hook such a property reads `nil`. `ResetPropertyToDefault(property)` restores the same value and fires the changed signals when the value differs. It does not validate, because the value comes from the environment. It raises for an undeclared property. It also works on `Roblox.testEnvironment`, where the default is the declared value.


### Reflection snapshots

Under Lute, a serialized reflection snapshot provides the reflection database at test time. A snapshot is a JSON file with schema version 2. A loader refuses every other version.

| Field | Content |
| --- | --- |
| `classes` | For each class: `superclass`, `tags`, `properties` with `datatype`, `scriptability` and `tags`, tagged `defaults`, and the `events` that the class declares. An instance has the events of its class and of each superclass. |
| `enums` | For each family: the items in engine order, each `{ name, value }`. |
| `brickColors` | `colors`, each `{ number, name, color }`, and the 128 `palette` numbers. |
| `fonts` | For each `Enum.Font` item that `Font.fromEnum` accepts: `{ family, weight, style }`. |
| `engineVersion` | The Studio version that wrote the file. |

#### Use a snapshot

- `Lute.fixture.load(path?)` reads a snapshot file. Without a path, it loads the bundled Studio 0.744.0.7441077 capture from 2026-10-22. This capture contains 933 classes and 652 enums from ReflectionService, with instance defaults and no place-specific service values.
- `Roblox.reflectionSnapshot.library(snapshot)` returns the [datatype library](#datatypes) bound to the enums, brick colors and fonts of the snapshot. It returns the same library for the same snapshot table.
- `Roblox.reflectionSnapshot.database(snapshot)` returns `{ GetClassNames, GetClass }`, the database shape that `Roblox.fixtureBridge` and `Roblox.reflection.create` take. Its defaults are values of the bound library.
- `Roblox.reflectionSnapshot.engineLibrary(library)` returns the `library` option of `Roblox.fixtureBridge`, so the engine seam constructs values of that library.
- `Roblox.reflectionSnapshot.bridge(snapshot, options?)` and `Lute.fixture.bridge(path | snapshot | nil, options?)` compose these parts. `Lute.fixture.bridge()` uses the bundled capture. Its resource path is relative to the installed Verify package, independent of the working directory.

Captured methods declare members without implementations. Calls without simulation or an explicit fake fail as unsupported. Class metadata uses all capabilities to keep the hierarchy. Creation and member access use the current or Plugin scope. Events require a Listen permit. Methods require a Call permit.

```luau
local snapshot = Lute.fixture.load()
local types = Roblox.reflectionSnapshot.library(snapshot)
local bridge = Lute.fixture.bridge(snapshot)
local label = bridge.environment.createInstance "TextLabel"
label.Size = types.UDim2.fromOffset(10, 20) + types.UDim2.fromScale(0.5, 0)
label.TextXAlignment = types.Enum.TextXAlignment.Left
```

`tests/reflection-snapshot.lute.verify.luau` builds bridges from both committed fixture files. Their recorded engine versions bound the captured metadata.

#### Run code under test with the library

`Lute.chunk.load(source, { name?, environment?, injectGlobals? })` compiles `source` and returns the chunk function. A global read looks in `environment` first and then in the Lute globals. `injectGlobals = false` uses `environment` alone. A global write stays in the chunk. `environment` does not change. `Lute.chunk.check(source, name?)` returns `true`, or `false` and the syntax error, and runs nothing. Put the library members and `typeof = types.typeof` in `environment`, so the code under test sees datatype globals with engine names.

#### Load a module tree under the library

`Lute.loader.new(options?)` returns `{ require(path) }`. It loads Roblox-targeted modules under Lute. `require(path)` takes a path relative to the working directory, with or without `.luau`. A directory path loads its `init.luau`.

Each module runs in its own environment:

- `typeof` is the datatype `typeof`, so a datatype value reports its engine name.
- `warn(...)` prints the arguments with the prefix `[warn]`.
- `getfenv(0)` returns the environment of the module. `getfenv(f)` returns the environment of a function that a module returned.
- `require` resolves `./` and `../` paths, `@self/` children and the aliases in `options.aliases`. `@std/` and `@lute/` load from the runtime.
- Alias names can contain path segments. The longest matching alias wins at a path boundary. An exact alias loads its root module. Aliases and relative paths to the same file share one module instance.
- Each name in `options.globals` is a global, for example `game`, `Instance` or `Enum` from an engine fixture. A name in `options.globals` replaces `typeof` and `warn`.
- `options.transform(path, source)` returns the source to load for a file. Use it to change one module in a test.
- `options.files = { exists(path), readFile(path) }` provides the module files. Without this option, the loader uses the host filesystem. Use an in-memory file table when module loads must complete without filesystem waits. Both functions receive normalized paths relative to the working directory.
- `require` also takes a reference from `loader.reference(path)`. A reference gives a child reference for each indexed name, so `require(game.ReplicatedStorage.shared.rules)` loads `<path>/rules` when `game.ReplicatedStorage.shared` is `loader.reference("<path>")`. The loader reads `options.globals` on each access, so a global can hold references that the loader makes.

The loader loads each file once and keeps the resolved paths. A require cycle, a missing module and an unknown alias raise with the module named. A file under a prefix in `options.hostPaths` loads with `options.requireHost(module)` instead, as an ordinary host module. `module` is the path without `.luau` or `/init.luau`.

```luau
local loader = Lute.loader.new { aliases = { verify = "src" } }
local Package = loader.require "src/core"
```

### UI fakes

`Roblox.uiFakes.classes` declares optional UI methods. Give it as a class overlay. Pass `uiFakes.validateProperty` as the property validator to reject the selection of hidden or unselectable controls. `Instance:GetStyled(property)` resolves the nearest linked StyleSheet. It supports class, tag, name and compound selectors, child (`>`) and descendant (`>>`) combinators. It also supports comma-separated alternatives, rule priorities and attribute tokens. For example, `.Container > Frame#Card.Hot` requires the parent tag, child class, child name and child tag. Relevant branches must use supported syntax. A nondefault raw property overrides the style. Writing the default or resetting it exposes the style again. Empty links do not replace an ancestor scope.

`ScrollingFrame:GetScrollVelocity()` returns `Vector2.zero`. Canvas writes and virtual time create no momentum. `ResetScrollVelocity()` keeps the canvas position. The double does not simulate inertial scrolling, release velocity or deceleration.

`Instance:GetStyled(property, "::ClassName")` reads a phantom `UIPadding`, `UICorner`, `UIStroke` or `UIGradient`. Missing phantoms raise. These components do not appear in the physical hierarchy, change resource counts or fire child events. A physical component has its own styled properties and takes precedence for layout. The shared fixtures check this distinction with physical and phantom padding, raw overrides, default values, token changes and removal.

`Instance:GetStyledPropertyChangedSignal(property)` observes the underlying style value and linked scope. Raw writes do not fire this signal. Style changes can fire it while a raw override masks the returned value. Call `controller.step()` to refresh observations; fixture layout does this before layout. `controller.styled(object, property)` exposes the effective read. `controller.component(object, className, property)` reads a physical component first, then a supported phantom, or returns nil when neither exists. Supply this as `layout.component` beside `layout.read` for phantom padding geometry. The fixture bridge provides both readers when it provides styled reads. Closing the controller disconnects its observations.

`Instance.StyledPropertiesChanged` fires on a GuiObject at `controller.step()` when a rule value it read through `GetStyled` changes and the GuiObject has a listener. It compares the rule value, so a transition fires the event once, not on each interpolation frame. Non-GuiObject instances such as UIPadding do not fire it yet.

Style transitions accept `TweenInfo` values or attribute tokens through `SetPropertyTransition`, `SetPropertyTransitions` and `SetDefaultPropertyTransition`. The `"*"` entry is the default. An explicit property entry overrides the default in its rule. Transition settings cascade separately from property targets, as in [StyleRule](https://create.roblox.com/docs/reference/engine/classes/StyleRule).

The first styled read sets the initial value. Later target changes interpolate on `environment.now`. `GetStyled`, `controller.styled` and phantom reads return the current value. Raw property reads keep their default or explicit value. Retargeting starts from the current value. `DelayTime` holds the value before interpolation. `RepeatCount` and `Reverses` are ignored, as `StyleRule` specifies. `controller.step()` publishes intermediate values; fixture layout calls it before layout.

The double interpolates numbers, `Color3`, `UDim`, `UDim2`, `Vector2`, `Vector2int16`, `Vector3`, `Rect` and `CFrame`. Booleans and enum items switch at eased progress 0.5. Other types snap. All easing styles and directions are supported. Removing a rule, tag or sheet uses the transition left in the cascade, or snaps when none is left. Invalid transitions and unresolved tokens raise `unsupported_ui_style`. Retargeting, discrete switching and removal timing are model choices until native conformance covers them.

Relevant nested rules, state selectors and query selectors raise `unsupported_ui_style`. Implicit space combinators, named or nested phantoms and derived sheets also raise this error. The same applies to multiple links at one scope, equal-priority conflicts and other selector arguments. Unsupported selectors do not block properties that their rules cannot affect. This is bounded model coverage. Shared Studio Client and double assertions check hierarchy selectors, name/tag/parent mutations, compound selectors and phantom modifiers. Native conformance does not prove rendering.


#### Rejected selection

`ui = { selection = "native" }` accepts explicit `GuiService.SelectedObject` writes to hidden, inactive and unselectable controls, including controls under a disabled `ScreenGui`. It raises if the target is outside a `PlayerGui`. Shared Studio and double cases check immediate and settled selection. This contract concerns explicit assignment; input navigation chooses eligible controls separately.

The default `ui.selection = "raise"` is a test convenience that rejects hidden and unselectable targets. `ui.selection = "ignore"` drops those writes with no error, no signal and no change. `controller.rejectedSelections()` lists each ignored `{ target, reason }` in order. A hidden ancestor, a disabled `ScreenGui` and `Selectable == false` reject in these two modes. Neither mode represents native explicit assignment. A value that is not a `GuiObject` raises in all modes.

`ui.requirePlayerGui = true` also requires `PlayerGui` ancestry in the `"raise"` and `"ignore"` modes. Native mode always requires this ancestry.

A `validateProperty` function that returns `false` vetoes the write or `poke` silently, with no change and no signal. Any other return value accepts it. This applies to `Parent` too.

`uiFakes.attach(environment, { measureText?, measureBounds?, methods? })` installs fakes for these behaviors:

- Focus.
- Style maps.
- Video state.
- Path-point storage.
- Instant page navigation.

TextBox focus changes emit the corresponding UserInputService events after the TextBox events. Capturing an already focused box has no effect. During a direct transfer, the old box remains focused while its FocusLost handlers run; the new box then gains focus without a TextBoxFocusReleased event. Releasing or destroying the focused box clears focus before FocusLost and TextBoxFocusReleased. A shared Studio case verifies event order and the focus state visible to handlers.

Measurement providers are required for measurement claims. Keep the controller and call `close()` to release focus resources. The simulator does not simulate curve evaluation, rendered text, animated navigation, playback quality or style rendering. A declared method that is unsupported needs an explicit injected implementation. `attach` registers `environment.onClone`. `Clone()` then copies style, transition, derive and path state, and remaps in-tree derive references. Focus is never copied. `environment.observe` and `pendingFailures` expose operation observation and unfired fault injection. `environment.observe(listener, filter)` takes an optional filter with `operations` and `members` lists. A filtered observer receives only events whose operation is in `operations` and whose member is in `members`. An event without a member does not match a `members` filter. When no observer matches, the environment builds no event.

### Engine seam

`Roblox.environmentEngine(environment, library?)` exposes the environment as a structural scene engine. The engine has creation, heartbeat, clock, datatype constructors, destruction and property observation. Objects and signals keep their identity. The default uses Verify datatypes. Give the typed factory library when you use native datatypes. This adapter adds no renderer and no native engine claim.

---

### `Roblox.environmentEngine`

Source: [src/roblox/environment-engine.luau](../src/roblox/environment-engine.luau).

`environmentEngine(environment: Environment, library: Library?) -> Engine`

Returns: A structural engine over the same instances, signals, virtual clock and datatype library.

Failures: Unsupported environment operations still raise. It supplies no renderer.

```luau
local engine = Roblox.environmentEngine(environment)
```

### `Roblox.reflection`

Source: [src/roblox/reflection.luau](../src/roblox/reflection.luau).

`create(options: Options) -> Environment`

Returns: A simulated environment with reflection defaults, member restrictions and datatype validation.

Failures: Invalid metadata or unsupported member use raises. Reflection supplies no method implementation.

```luau
local environment = Roblox.reflection.create { database = database, typeName = Roblox.typeName }
```

### `Roblox.reflectionSnapshot`

Source: [src/roblox/reflection-snapshot.luau](../src/roblox/reflection-snapshot.luau).

`decode(value: unknown) -> Snapshot`; `library(snapshot) -> Library`; `database(snapshot) -> Database`; `engineLibrary(library) -> Library`; `bridge(snapshot, options?) -> Bridge`; `SCHEMA_VERSION: number`

Returns: Validated snapshot data, bound constructors, reflection metadata or a fixture bridge.

Failures: Invalid snapshots, tagged defaults and unknown enum values raise.

```luau
local snapshot = Lute.fixture.load()
local types = Roblox.reflectionSnapshot.library(snapshot)
local database = Roblox.reflectionSnapshot.database(snapshot)
```

### `Roblox.fixtureBridge`

Source: [src/roblox/fixture-bridge.luau](../src/roblox/fixture-bridge.luau).

`fixtureBridge(options: Options) -> FixtureBridge`

Returns: One environment with reflection, UI and layout controllers, engine binding and accounting.

Failures: Invalid options and unsupported metadata or geometry raise. Call `close()` to release controllers.

```luau
local bridge = Roblox.fixtureBridge { database = database, typeName = Roblox.typeName }
bridge.close()
```

### `Roblox.uiFakes`

Source: [src/roblox/ui-fakes.luau](../src/roblox/ui-fakes.luau).

`attach(environment, options?, selection?) -> Controller`; `selection(options?) -> Selection`; `validateProperty(className, property, value, operation) -> ()`; `classes: { [string]: ClassSpec }`

Returns: A UI controller or selection policy. `classes` supplies optional class overlays.

Failures: Unsupported style, focus or measurement operations raise. Selection behavior follows the selected policy.

```luau
local controller = Roblox.uiFakes.attach(environment)
controller.close()
```

### `Roblox.teleportFakes`

Source: [src/roblox/init.luau](../src/roblox/init.luau).

`setJoinData(environment, player, dictionary) -> ()`; `setLocalPlayerTeleportData(environment, teleportService, value) -> ()`

Returns: No value. Each setter installs independent arrival facts. Nil clears local arrival data.

Failures: Invalid players, services and nonportable payloads raise before state changes.

```luau
Roblox.teleportFakes.setJoinData(environment, player, { TeleportData = { stage = "ready" } })
```

TeleportOptions SetTeleportData/GetTeleportData, Player GetJoinData and TeleportService GetLocalPlayerTeleportData are registered automatically in the engine double. Options start with nil data; players start with an empty join dictionary and client arrival data starts nil. Options store independent copies, return copies, and retain data on Clone. False is data; nil clears it. Payloads accept finite primitives, value datatypes supported by the double and nested arrays or dictionaries. Cycles, mixed keys, sparse arrays and engine-state references raise before state changes. No teleport operation, transport, credential or source-authentication guarantee is simulated.

`setJoinData(environment, player, dictionary)` supplies independent server arrival facts for a live Player. `setLocalPlayerTeleportData(environment, teleportService, value)` supplies client arrival data separately; nil clears it. Both copy their inputs, and reads return fresh copies. These fixtures do not enforce server/client execution context or derive arrivals from TeleportOptions. Consumers choose which facts each actor receives.

### `Roblox.deviceFakes`

Source: [src/roblox/device-fakes.luau](../src/roblox/device-fakes.luau).

`configure(engine: Engine, options: Options) -> ()`

Returns: No value. It applies validated capabilities, preferred input and inset facts.

Failures: Invalid capabilities, enum families or geometry raise before publication.

```luau
Roblox.deviceFakes.configure(placeEngine, deviceOptions)
```

`configure(engine, { preferredInput, touch, keyboard, mouse, gamepad, topLeft, bottomRight, topbar })` applies a device preset to the place engine's UserInputService and GuiService instances. PreferredInput is an Enum.PreferredInput item; capability flags are booleans. Its preferred input must have an enabled capability. Insets are finite nonnegative Vector2 values; topbar is a finite Rect. Validation precedes publication. Property changes publish ordinary changed signals, including PreferredBinding updates on InputActions. GetGuiInset returns the supplied corners, so camera screen projection uses the same inset. TopbarInset publishes the supplied Rect. Mutating the options table afterward does not change installed state.

The preset installs an all-buttons-up baseline for GetKeysPressed, GetMouseButtonsPressed, IsKeyDown, IsMouseButtonPressed and IsGamepadButtonDown. Input-host operations can override it with live simulated state. This helper invents no device dimensions and does not advance physical input. For captured Studio device profiles, viewport changes and ScreenGui layout areas, use createPlaceRuntime and StudioDeviceSimulatorService as documented above.

### `Roblox.instanceHost`

Source: [src/roblox/instance-host.luau](../src/roblox/instance-host.luau).

`simulated(actor, environment?) -> Simulated`; `native(actor, borrowed?, codec?) -> Host`; `registry(options) -> Registry`; `property(decode) -> Operation`; `attribute(decode) -> Operation`

Returns: Instance operations and host bindings. `create`, `parent`, `destroy`, `setProperty`, `setAttribute` and `inspect` are typed operations.

Failures: Unknown handles, invalid values and unavailable members raise. Native access requires a Roblox engine.

```luau
local instanceHost = Roblox.instanceHost.simulated("client", environment)
instanceHost.host.close()
```

### `Roblox.controllerHost`

Source: [src/roblox/controller-host.luau](../src/roblox/controller-host.luau).

`Roblox.controllerHost.simulated(engine)` opts a place engine into kinematic controller motion.
It integrates `ControllerManager.MovingDirection`, `BaseMoveSpeed` and the active controller's `MoveSpeedFactor`.
Ground sensors use the configured `Workspace.Raycast` host and `GroundOffset`. Manual sensors remain caller-owned.
Disconnect the returned connection to stop motion and release the instance observer.
This host proves controller wiring and game logic. It simulates no wall collision, gravity, native physics or rendering.

Place runtimes simulate `Player.LoadCharacterAsync` for connected players, including replacement events,
`StarterCharacter` cloning and selected spawn placement. Place boot retains a character loaded during admission.
Character-added and appearance-ready events precede workspace parenting. R15 part replacement retains placement
and retargets existing joints. Avatar scaling and mesh deformation remain native-only.
`RunService.BindToSimulation` requires fixed simulation and supports the declared frequencies, priorities and disconnect.
It supplies fixed deltas to callbacks. It does not model rollback or native property synchronization restrictions.
`Stats.FrameTime` reports the supplied virtual frame duration, never native performance.

### `Roblox.pathfindingHost`

`Roblox.pathfindingHost.install(engine, compute)` opts into configured `CreatePath`, `ComputeAsync` and `GetWaypoints` behavior. `compute(origin, destination, parameters)` receives finite Vector3 endpoints and a copy of the path parameters. Return a list of finite positions including both endpoints, or nil for `NoPath`. Successful results expose copied Walk waypoints; a later miss clears them. The consumer supplies routing topology. This host does not build a native navmesh or simulate collision avoidance or jumps.

### `Roblox.promptHost`

`Roblox.promptHost.simulated(engine, { player, visible })` opts into distance-gated prompt events and holds. `visible(prompt, origin, target)` supplies visibility and selection policy; this host does not infer native camera visibility, line of sight or exclusivity. Prompts must be enabled under Workspace, within `MaxActivationDistance` of the player's HumanoidRootPart, and parented to a BasePart, Attachment or Model with a PrimaryPart. The service must be enabled. Heartbeats emit prompt and service shown/hidden events. Public keyboard events and `InputHoldBegin`/`InputHoldEnd` share cancellable holds; a completed hold emits Triggered once. Removal, range loss, disabling and disconnect cancel pending holds. The returned connection disconnects the host. No rendering or native input acceptance is proved. Fixture services start with ProximityPromptService.Enabled true. Prompt defaults include Enabled and RequiresLineOfSight true, HoldDuration zero, MaxActivationDistance ten, keyboard E and gamepad ButtonX.

### `Roblox.inputHost`

Source: [src/roblox/input-host.luau](../src/roblox/input-host.luau).

`simulated(environment, options: SimulatedOptions) -> Simulated`; `native() -> Backend?`; `registry(backend) -> Registry`; `screenCenter(target: GuiTarget) -> { x, y }`

Returns: An input binding, native backend when available, operation registry or screen point. `key`, `pointer` and `text` are typed operations.

Failures: Unsupported native input returns nil. Invalid input or unsupported simulated geometry raises.
Virtual mouse-button input uses its explicit coordinates without requiring a preceding pointer move.
`screenCenter` needs native `GuiService:GetGuiInset()` and a positive rendered target area.

```luau
local point = Roblox.inputHost.screenCenter(guiTarget)
```


When `TouchEnabled` is true and `MouseEnabled` is false, virtual mouse input creates touch contacts. Each press creates one InputObject that persists through movement and release. The host emits GUI contact events, the general input events, and TouchStarted, TouchMoved and TouchEnded. It uses the device's `GetInsetArea(None)` origin for touch coordinates. Shared native cases check entry, movement, exit, release, button activation and UIDragDetector capture with TranslatePlane and CustomOffset. Long press begins after 0.5 virtual seconds; movement of five pixels or more before recognition cancels it. Recognized movement emits Change and release emits End. GUI long-press positions include the GUI inset; service positions match the InputObject. Other gestures, simultaneous contacts and native touch scrolling remain unmodeled.

Pointer focus passes through Frames and TextLabels, stops at buttons, and can focus a read-only TextBox. ClearTextOnFocus clears before caret placement. Trailing caret placement supports alignment and physical padding; an existing edit also supports a leading click. Interior, wrapped and rotated placement remains unsupported. Cursor positions use byte offsets. Text input replaces the selection in either direction; Backspace removes the selection or one complete UTF-8 codepoint. IsMouseButtonPressed reports the modeled left button state.

Directional selection prioritizes overlapping perpendicular rectangle spans. The shared geometry fixture checks wide controls, span boundaries and group escape/stop. Selection between overlapping targets along the travel axis remains uncalibrated. Destroying an InputAction or its context retains its last PreferredBinding without a replacement notification; live binding unparenting and reparenting still notify.

`simulated` accepts `virtualController = true` to route keyboard keys through the default Studio controller mappings. Button, trigger and stick events update the same objects returned by `GetGamepadState`. Trigger changes precede button transitions. Opposing stick keys cancel an axis. Unmapped keys produce no keyboard events in this mode. The default keeps keyboard input.

With a selected GuiObject, D-pad input moves selection and repeats while held. Button A activates the selected button on release. These inputs report `gameProcessedEvent = true`; activation precedes the release event. Button B leaves selection unchanged and reports an unprocessed event. The left thumbstick moves selection once per cardinal direction until released. The right thumbstick leaves selection unchanged and reports an unprocessed event. Diagonal thumbstick selection remains unsupported. The shared `tests/fixtures/input-controller-selection.luau` case checks these events in the double and in Studio with Controller Emulator enabled.

Controller emulation sets `GamepadEnabled` and `PreferredInput` to gamepad. It preserves the viewport and keyboard and mouse availability. Closing the input host restores the previous gamepad and preferred-input values.

`connectGamepad()` starts controller emulation on an open host, as when a player connects a pad. It sets `GamepadEnabled`, fires `GamepadConnected` with `Gamepad1` and answers `GetConnectedGamepads` and `GetGamepadConnected`. It does not change `PreferredInput`. `disconnectGamepad()` stops emulation, restores the values from before the connection and fires `GamepadDisconnected`. Keys then reach the keyboard again. A second connection or a disconnection without a pad is unsupported. In either mode, gamepad input sets `PreferredInput` to gamepad. Keyboard and mouse input do not change `PreferredInput` back.

Repeated thumbstick key presses accumulate axis values, including values outside -1 to 1. Each release subtracts one press. The system menu remains unsupported. The mode supports raw input and boolean action bindings. It does not model the character controller or its processed-input flags.

### `Roblox.experienceHost`

Source: [src/roblox/experience-host.luau](../src/roblox/experience-host.luau).

`create(options: Options) -> CaseHost`; `endpoint(decode, body, requires?) -> Endpoint`; `respond(registry, capabilities, now, actor, value) -> Response`; `remoteTransport(context, remote, actors, playerFor?) -> Transport`; `remoteResponder(registry, capabilities, now, actor, authorize) -> handler`; `nativeEngine() -> Engine`

Returns: A case host, endpoint, response or transport over explicit operations.

Failures: Invalid requests, missing capabilities and authorization refusals remain failed responses or raise at the host boundary.

```luau
local host = Roblox.experienceHost.create(experienceOptions)
```

### `Roblox.multiplayer`

Source: [src/roblox/multiplayer.luau](../src/roblox/multiplayer.luau).

`server(context: Context, options: ServerOptions) -> CaseHost`; `client(options: ClientOptions) -> () -> ()`; `undeliverable(storage: DeliveryStorage, reason: DeliveryReason, detail: string) -> boolean`; `DELIVERY_CHANNEL: string`

Returns: A coordinated server host, a client disconnect function, or whether a delivery report was sent.

Failures: Missing roles, refused requests and expired deadlines fail. The caller supplies role authorization.

`undeliverable` fires `reason` (`request_missing`, `run_id_mismatch` or `remote_missing`) and `detail` through the `VerifyDelivery` channel that the server runner creates for a `players` run. It returns `false` when the channel is absent. The server runner ends the run with the first report. `ClientOptions.undeliverable` is called once when the client receives a message for a different run, with `run_id_mismatch`.

```luau
local disconnect = Roblox.multiplayer.client(multiplayerClientOptions)
disconnect()
if not remote then
	Roblox.multiplayer.undeliverable(game:GetService("ReplicatedStorage"), "remote_missing", "no session remote")
end
```

### `Roblox.reportChannel`

Source: [src/roblox/report-channel.luau](../src/roblox/report-channel.luau).

`envelope(runId, report) -> Envelope`; `receive(value, runId) -> Report`; `publish(runId, report, encode, emit) -> ()`; `collect(bytes, runId, decode) -> Report`

Returns: Run-bound report envelopes, emitted lines or validated received reports.

Failures: Wrong run identity, invalid reports and incomplete/conflicting chunks raise.

```luau
local envelope = Roblox.reportChannel.envelope("run-1", report)
local received = Roblox.reportChannel.receive(envelope, "run-1")
```

### `Roblox.progressChannel`

Source: [src/roblox/progress-channel.luau](../src/roblox/progress-channel.luau).

`publisher(runId, token, emit) -> RunProgress`; `collect(rows, token, runId) -> Collected`; `read: string`; `readPage(token, afterSequence) -> string`; `LOGGER: string`

Returns: A publisher, validated log events, or Studio source for a log read.

Failures: Invalid run tokens and log fields fail validation. Collection preserves diagnostics for refused events.

```luau
local source = Roblox.progressChannel.readPage("token", 0)
```

### `Roblox.uiAudit`

Source: [src/roblox/init.luau](../src/roblox/init.luau).

`collect(options?) -> Dump`; `decode(value: unknown) -> Dump`; `analyze(dump, options?) -> Report`; `contrastRatio(left, right) -> number`; `isAbove(dump, left, right) -> boolean`; `SCHEMA_VERSION: number`; `RULES: { [string]: Severity }`

Returns: UI facts, a validated dump, rule findings, contrast or ordering observations.

CanvasGroup elements record styled `groupTransparency` and cumulative `opacity`. Roots record opacity inherited from the selected root and its ancestors. Decoding derives descendant opacity and rejects contradictory projections. Missing opacity fields default to opaque. Contrast flattens each group's contents before applying its transparency; unknown image paint remains unproved. Fully transparent groups contribute no text findings, but their input targets remain active.

Failures: Invalid dumps and options raise. Collection needs native or explicitly supplied UI facts. Findings do not replace visual review.

```luau
local contrast = Roblox.uiAudit.contrastRatio({ r = 0, g = 0, b = 0 }, { r = 1, g = 1, b = 1 })
assert(contrast == 21)
```

## Native content facts

### `Roblox.contentFacts`

Source: [src/roblox/content-facts.luau](../src/roblox/content-facts.luau).

`requests(value: unknown) -> { Request }`; `validate(value: unknown) -> Capture`; `attach(environment: Environment, capture: unknown, library: DatatypeLibrary?) -> ()`

Returns: Validated requests, a validated capture, or no value after installing captured-content fakes.

Failures: Invalid IDs, schemas and captured fields raise. Missing IDs and captured refusals raise during a load.
Partial reconstruction destroys its objects before it raises.

```luau
local requests = Roblox.contentFacts.requests { { kind = "model", key = "item", version = 123 } }
assert(#requests == 1)
```

`Roblox.contentFacts.requests(value)` checks a nonempty request array. Each request has a unique `key` and a `kind`. Use `{ kind = "model", key = "item", version = 123 }` for a pinned asset version. Use `{ kind = "mesh", key = "item", id = 123 }` for a mesh. Use `{ kind = "animation", key = "item", id = 123 }` for an animation or keyframe sequence. IDs must be positive safe integers. A model request cannot use an asset ID.

Load caller-supplied captures with the schema below. Verify retains captured facts and reconstruction; capture generation belongs to the caller.

`Roblox.contentFacts.validate(value)` checks a decoded capture and returns it. Use `Lute.fixture.host.decodeJson(text)` to decode a file into plain tables. Schema version 1 has `schemaVersion`, `engineVersion`, `placeId`, `placeVersion`, `gameId` and `rows`. Each row has `request`, `ok` and either `facts` or `refusal`. Successful facts are an array of nodes. A node has `className`, `name` and an optional `parent` index. The root has no parent. Each parent precedes its children. Reference indices point into the same array.

| Class | Captured fields |
| --- | --- |
| Model | `pivot`, `box`, `size`, optional `primaryPart` |
| BasePart | `cframe`, `pivotOffset`, `size`, `canCollide`, `canQuery`, `material`, `materialVariant` |
| MeshPart | `meshId`, `textureId`, `meshSize`, `collisionFidelity`, optional `hasSkinnedMesh` |
| SurfaceAppearance | `colorMap`, `normalMap`, `metalnessMap`, `roughnessMap`, `alphaMode` |
| SpecialMesh | `meshId`, `textureId`, `scale`, `offset` |
| Attachment | `cframe` |
| Bone | `transform` in addition to attachment fields |
| Motor6D | `c0`, `c1`, `transform`, optional `part0`, `part1` |
| AnimationConstraint | `transform`, optional `attachment0`, `attachment1` |
| KeyframeSequence | `loop`, `priority` |
| Keyframe | `time` |
| Pose | `cframe`, `weight`, `easingStyle`, `easingDirection` |

An optional `hasSkinnedMesh` boolean on a MeshPart sets its read-only `HasSkinnedMesh`. A capture without it leaves `HasSkinnedMesh` false; Verify never infers it from bones.

Vectors have three finite components. Frames have the twelve components from `CFrame:GetComponents()`. Enum fields use member names. Map fields contain durable URI strings. An empty string means no map. Mesh capture uses Box collision fidelity. It records native Size and MeshSize. Its part frame and Size define its bounds. Model `box` and `size` record the native bounding box. Animation parent indices retain nested poses. The capture loads sequences through KeyframeSequenceProvider. It does not sample playback.

Pass `{ content = { facts = decodedCapture } }` to `Lute.fixture.bridge` to use the capture in the engine double. Do not also supply `assetVersion`. The bridge uses its own datatype library. For a standalone environment, call `Roblox.contentFacts.attach(environment, decodedCapture, library?)`. The optional library is a `Roblox.datatypes` library for that environment.

The consumer installs InsertService.LoadAssetVersion, AssetService.CreateMeshPartAsync and KeyframeSequenceProvider.GetKeyframeSequenceAsync fakes. Each load builds new instances and remaps references. Model loads go under InsertService. Mesh loads accept URI Content values and no options or an empty options table. Options that could change geometry fail. Animation loads accept `rbxassetid://` strings. GetKeyframes, GetPoses and GetSubPoses return captured children. Missing IDs and captured refusals raise errors. Partial reconstruction destroys its objects before it raises an error.

Captured bounds stay in the fact file. Model methods use the engine double's geometry rules over rebuilt parts. These methods do not simulate mesh collision or deformation. The capture keeps imported content outside a running hierarchy and never requires an imported module. It records no source. Rebuilt scripts are disabled. This format covers the listed fields. It is not a complete place serializer, an asset rights record or native playback proof.

## Consumer diagnostics

These functions report findings. The caller selects a ruleset and decides whether to fail.
The [lint policy](lint.md) describes adoption.

### `Consumer.generic`

Source: [src/consumer/init.luau](../src/consumer/init.luau).

`generic: Ruleset`

Returns: The frozen portable specification ruleset.

Failures: The value grants no host authority.

```luau
local findings = Consumer.scan("return {}", "case.verify.luau", Consumer.generic)
```

### `Consumer.roblox`

Source: [src/consumer/init.luau](../src/consumer/init.luau).

`roblox: Ruleset`

Returns: The frozen ruleset with Roblox host-global and external-mutation rules.

Failures: The value grants no permission for an external operation.

```luau
local findings = Consumer.scan('game:GetService("Players")', "case.verify.luau", Consumer.roblox)
assert(#findings > 0)
```

### `Consumer.scan`

Source: [src/consumer/init.luau](../src/consumer/init.luau).

`scan(contents: string, path: string, ruleset: Ruleset) -> { Finding }`

Returns: Ordered findings with code, source offset, reason and fix.

Failures: A malformed ruleset raises. Findings do not stop the process.

```luau
local findings = Consumer.scan("task.wait()", "case.verify.luau", Consumer.generic)
assert(#findings == 1)
```

### `Consumer.scanProductionPaths`

Source: [src/consumer/init.luau](../src/consumer/init.luau).

`scanProductionPaths(paths: { string }) -> { ProductionFinding }`

Returns: Findings for verification code in a production graph.

Failures: It expects a path array. It does not discover the graph itself.

```luau
local findings = Consumer.scanProductionPaths({ "src/check.verify.luau" })
assert(#findings == 1)
```

### `Consumer.scanTree`

Source: [src/consumer/init.luau](../src/consumer/init.luau).

`scanTree(root: string, options: TreeOptions) -> TreeReport`

Returns: Specification findings and production-path findings from supplied file operations.

Failures: An empty root, missing file operations or malformed ruleset raises. File errors propagate.

```luau
local findings = Consumer.scanTree(specRoot, treeOptions)
```

## Agent evaluation

Use explicit services to plan agent runs, retain their evidence and compare outcomes.
The [agent evaluation guide](agent-eval.md) owns the workflow.

### `AgentEval.SCHEMA_VERSION`

Source: [src/agent-eval/model.luau](../src/agent-eval/model.luau).

`SCHEMA_VERSION: number`

Returns: `1`, the evaluation suite schema version.

Failures: Reading the constant cannot fail.

```luau
assert(AgentEval.SCHEMA_VERSION == 1)
```

### `AgentEval.decodeSuite`

Source: [src/agent-eval/model.luau](../src/agent-eval/model.luau).

`decodeSuite(value: unknown, path: string, loader: Loader) -> Suite`

Returns: A validated suite with resolved task data and file manifests.

Failures: Invalid schema, budgets, arms, task references or loader reads raise.

```luau
local suite = AgentEval.decodeSuite(suiteData, suitePath, evalLoader)
```

### `AgentEval.plan`

Source: [src/agent-eval/model.luau](../src/agent-eval/model.luau).

`plan(suite: Suite, loader: Loader, selection: Selection?) -> { RunSpec }`

Returns: Deterministic selected task, arm, agent and seed combinations with input digests.

Failures: Invalid selection or missing files raise.

```luau
local runs = AgentEval.plan(suite, evalLoader)
```

### `AgentEval.load`

Source: [src/agent-eval/judging.luau](../src/agent-eval/judging.luau).

`load(evidence: string, files: Files, decode: (string) -> unknown) -> { RunResult }`

Returns: Validated saved runs in the evidence directory.

Failures: Missing files, invalid JSON or result schema errors raise.

```luau
local results = AgentEval.load(evidenceDirectory, evalFiles, Lute.parse)
```

### `AgentEval.adapters`

Source: [src/agent-eval/adapters.luau](../src/agent-eval/adapters.luau).

`parseStamped(text: string) -> { Line }`

Returns: Output lines with optional arrival timestamps. Plain lines keep an absent timestamp.

```luau
local lines = AgentEval.adapters.parseStamped("1.25\tready\nplain\n")
assert(lines[1].at == 1.25)
```

### `AgentEval.transcript`

Source: [src/agent-eval/init.luau](../src/agent-eval/init.luau).

`parseClaudeStream(lines, decode) -> Transcript`; `parseCodexStream(lines, decode) -> Transcript`; `total(usage: Usage) -> number`

Returns: Parsed events, usage, timings and failures, or the total token usage.

Failures: Malformed stream entries become parse failures where supported. Decoder errors follow the parser contract.

```luau
local transcript = AgentEval.transcript.parseClaudeStream({}, Lute.parse)
```

### `AgentEval.base64`

Source: [src/codec/base64.luau](../src/codec/base64.luau).

`encode(bytes: string) -> string`; `decode(text: string) -> string?`

Returns: The same codec as `Codec.base64`.

Failures: Invalid padded base64 returns nil.

```luau
assert(AgentEval.base64.decode("aGk=") == "hi")
```

### `AgentEval.random`

Source: [src/core/random.luau](../src/core/random.luau).

`hash(value: string) -> number`; `derive(seed: number, label: string) -> number`; `generator(seed: number) -> Generator`

Returns: Deterministic hashes, derived seeds or a stream with `next`, `integer` and `clone`.

Failures: Nonfinite or unsafe seeds and reversed integer ranges raise. This is not a cryptographic generator.

```luau
local random = AgentEval.random.generator(42)
local copy = random.clone()
assert(random.integer(1, 10) == copy.integer(1, 10))
```

### `AgentEval.stats`

Source: [src/agent-eval/stats.luau](../src/agent-eval/stats.luau).

`mean(values) -> number?`; `median(values) -> number?`; `percentile(values, rank) -> number?`; `bootstrap<T>(options: BootstrapOptions<T>) -> Interval`

Returns: Statistics or seeded confidence bounds. Empty inputs have no estimate.

Failures: Invalid percentile rank, confidence or resample count raises. Statistic callback errors propagate.

```luau
assert(AgentEval.stats.median({ 1, 3 }) == 2)
```

### `AgentEval.result`

Source: [src/agent-eval/result.luau](../src/agent-eval/result.luau).

`decode(value: unknown) -> RunResult`; `SCHEMA_VERSION: number`

Returns: A validated saved run with check, capture, timing and usage fields.

Failures: Invalid result fields, status or schema raise.

```luau
local result = AgentEval.result.decode(savedRun)
```

### `AgentEval.judge`

Source: [src/agent-eval/init.luau](../src/agent-eval/init.luau).

`compare(comparison, options) -> Judgment`; `parseVerdict(text, rubric, decode) -> (Verdict?, string?)`; `anthropic(options) -> Transport`; `claudeCli(options) -> Transport`; `codexCli(options) -> Transport`

`comparisons(suite, results) -> { Comparison }`; `run(options) -> { Judgment }`; `load(evidence, files, decode) -> { Judgment }`; `decodeLabels(value) -> { Label }`; `decodeRubric(value, label) -> Rubric?`; `calibrate(judgments, labels) -> Calibration`

Returns: Blinded comparisons, bounded transport bindings, saved judgments or calibration. `DEFAULT_MODEL`, `DEFAULT_CODEX_MODEL`, `DEFAULT_CODEX_EFFORT` and `DEFAULT_RUBRIC` supply defaults.

Failures: Invalid rubric and label input raises. Invalid verdict text returns nil and a reason. Transport refusal cannot establish a judgment.

```luau
local comparisons = AgentEval.judge.comparisons(suite, results)
```

### `AgentEval.lute`

Source: [src/agent-eval/lute.luau](../src/agent-eval/lute.luau).

`services(options?) -> Services`; `loader() -> Loader`; `encode(value) -> string`; `decode(text) -> unknown`; `absolute(path) -> string`; `sha256(bytes) -> string`; `files: Files`; `STAMP: string`

Returns: Lute host bindings for evaluation, filesystem access and serialization.

Failures: File, process and JSON failures follow the supplied services. These bindings grant no external authority.

```luau
local evalLoader = AgentEval.lute.loader()
local services = AgentEval.lute.services()
```

## Repository checks

The Lute-only `Checks` package returns findings without exiting.
[Repository checks](checks.md) owns configuration fields and contract falsifiers.
Paths are relative to the working directory unless that configuration states otherwise.

### `Checks.walk`

Source: [src/checks/walk.luau](../src/checks/walk.luau).

`paths(root, suffixes, into?) -> { string }`; `pathsSkipping(root, suffixes, skip) -> { string }`; `files(root, suffixes) -> { File }`; `filesSkipping(root, suffixes, skip) -> { File }`; `lineOf(source, offset) -> number`

Returns: Sorted paths, file contents or a one-based source line. Missing roots return no files.

Failures: Filesystem read errors propagate.

```luau
assert(Checks.walk.lineOf("first\nsecond", 7) == 2)
```

### `Checks.temporaryDirectory`

Source: [src/checks/temporary-directory.luau](../src/checks/temporary-directory.luau).

`root() -> string`; `run<T>(parent: string, prefix: string, body: (string) -> T) -> T`

Returns: The temporary root or the body result after removing its unique directory.

Failures: Invalid prefixes, allocation failures, body errors and cleanup failures raise. Cleanup also runs when the body raises.

```luau
local result = Checks.temporaryDirectory.run(Checks.temporaryDirectory.root(), "docs", function(path) return path ~= "" end)
assert(result)
```

### `Checks.denylist`

Source: [src/checks/denylist.luau](../src/checks/denylist.luau).

`scan(path: string, source: string, rules: { Rule }, allowedLiterals: Allowances?) -> { string }`

Returns: Findings for the caller rules and exact path allowances.

Failures: Invalid Luau patterns raise. Allowances preserve source line positions.

```luau
local findings = Checks.denylist.scan("sample", "blocked", { { pattern = "blocked", plain = true, why = "example rule" } })
assert(#findings == 1)
```

### `Checks.boundary`

Source: [src/checks/repository.luau](../src/checks/repository.luau).

`boundary(config: Config) -> { string }`

Returns: Source-boundary findings. An empty array passes. The check does not exit the process.

Failures: Invalid or missing discovery roots raise unless the configuration permits them.

```luau
local findings = Checks.boundary { root = "src/core", rules = {} }
```

### `Checks.leakage`

Source: [src/checks/repository.luau](../src/checks/repository.luau).

`leakage(config: Config) -> { string }`

Returns: Findings over Git-selected files. An empty array passes. The check does not exit the process.

Failures: Failed Git enumeration and unreadable files raise.

```luau
local findings = Checks.leakage { rules = {} }
```

### `Checks.noAny`

Source: [src/checks/repository.luau](../src/checks/repository.luau).

`noAny(config: Config) -> { string }`

Returns: Strict-type policy findings. An empty array passes. The check does not exit the process.

Failures: Malformed source fails closed. Git and file errors raise.

```luau
local findings = Checks.noAny { include = { "src/core" } }
```

### `Checks.specStyle`

Source: [src/checks/repository.luau](../src/checks/repository.luau).

`specStyle(config: Config) -> { string }`

Returns: Specification-style findings. An empty array passes. The check does not exit the process.

Failures: Git and file errors raise. Exclusions are exact paths.

```luau
local findings = Checks.specStyle { include = { "tests" } }
```

### `Checks.testManifest`

Source: [src/checks/manifest.luau](../src/checks/manifest.luau).

`testManifest(config: Config) -> { string }`

Returns: Manifest findings, or no findings after a successful write. An empty array passes. The check does not exit the process.

Failures: Discovery, load, write and formatter failures raise.

```luau
local findings = Checks.testManifest(manifestConfig)
```

### `Checks.publicSurface`

Source: [src/checks/surface.luau](../src/checks/surface.luau).

`publicSurface(config: Config) -> { string }`

Returns: Missing or stale API entries. An empty array passes. The check does not exit the process.

Failures: Unreadable documentation raises. Missing entries and failed package loads produce findings.

```luau
local findings = Checks.publicSurface(surfaceConfig)
```

### `Checks.comments`

Source: [src/checks/comments.luau](../src/checks/comments.luau).

`comments(config: Config) -> { string }`

Returns: Comment-policy findings, or no findings after a successful rewrite. An empty array passes. The check does not exit the process.

Failures: Parser, read and write errors raise.

```luau
local findings = Checks.comments { files = { "src/bdd.luau" }, allowed = { "^%-%-!" } }
```

### `Checks.provenance`

Source: [src/checks/provenance.luau](../src/checks/provenance.luau).

`provenance(config: Config) -> { string }`

Returns: License and source-provenance findings. An empty array passes. The check does not exit the process.

Failures: Unreadable required files and failed host operations cannot pass.

```luau
local findings = Checks.provenance(provenanceConfig)
```

### `Checks.cleanClone`

Source: [src/checks/clean-clone.luau](../src/checks/clean-clone.luau).

`cleanClone(config: Config) -> { string }`

Returns: Clean-HEAD and clone-command findings. An empty array passes. The check does not exit the process.

Failures: Dirty HEAD and command failures produce findings. Git or cleanup failures cannot pass.

```luau
local findings = Checks.cleanClone(cloneConfig)
```

### `Checks.lintRules`

Source: [src/checks/init.luau](../src/checks/init.luau).

`globalTableUsage: Rule`; `typeCheckInsideCall: Rule`; `badStringEscape: Rule`

Returns: Lute lint rules with `name` and `lint` fields. Configure their paths in a Lute lint configuration.

Failures: Lint findings use the Lute diagnostic route. Invalid host configuration can raise.

```luau
local rule = Checks.lintRules.badStringEscape
assert(type(rule.lint) == "function")
```

## Type imports

Types are declared beside their implementation. Root packages expose selected aliases.
For example, `Lute` exports `PlatformOptions`; `src/lute/studio.luau` declares `Options` and `HostOptions`.
Use a defining module only when its type is absent from the public root.
See the [terms](README.md#terms) for shared technical names.
