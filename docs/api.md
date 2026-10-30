# API reference

### `Roblox.contentFacts`

`Roblox.contentFacts.requests(value)` checks a nonempty request array. Each request has a unique `key` and a `kind`. Use `{ kind = "model", key = "item", version = 123 }` for a pinned asset version. Use `{ kind = "mesh", key = "item", id = 123 }` for a mesh. Use `{ kind = "animation", key = "item", id = 123 }` for an animation or keyframe sequence. IDs must be positive safe integers. A model request cannot use an asset ID.

Run `lute run tools/capture-native-content.luau request.json facts.json` from the Verify checkout. The request file contains `{ "requests": [...] }`. It can also contain `"identity": { "placeId": 123, "universeId": 456 }`. The caller owns permission to use that identity and to load each asset. The command uses the text metrics place builder, Studio worker and report route. It starts a local server harness. It refuses an existing output file.

The command writes facts to `facts.json` and the native report to `facts.json.report.json`. It shares an attachment writer and disk reader with `tools/capture-text-metrics.luau`. The writer splits every attachment before it reaches the harness. Each part is less than 1 MiB and ends at a UTF-8 boundary. A manifest records the byte count and SHA-256 of each part and complete file. The reader refuses missing, duplicate, extra or mismatched parts. It verifies all files before it writes them to `facts.json.attachments`, then reads each file back and checks its bytes and SHA-256. The tools refuse existing output, report or attachment destinations. The capture route permits at most 4096 parts and 256 MiB in a report; it keeps the harness limit of 1 MiB per attachment. These limits do not change the defaults for other cases.

The command checks the schema, request list and optional place identity before it writes facts. It does not print the facts to the console. Keep the report, attachment directory and facts together. A load refusal is a recorded result. Inspect each row before you accept a capture.

`Roblox.contentFacts.validate(value)` checks a decoded capture and returns it. Use `Lute.fixture.host.decodeJson(text)` to decode a file into plain tables. Schema version 1 has `schemaVersion`, `engineVersion`, `placeId`, `placeVersion`, `gameId` and `rows`. Each row has `request`, `ok` and either `facts` or `refusal`. Successful facts are an array of nodes. A node has `className`, `name` and an optional `parent` index. The root has no parent. Each parent precedes its children. Reference indices point into the same array.

| Class | Captured fields |
| --- | --- |
| Model | `pivot`, `box`, `size`, optional `primaryPart` |
| BasePart | `cframe`, `pivotOffset`, `size`, `canCollide`, `canQuery`, `material`, `materialVariant` |
| MeshPart | `meshId`, `textureId`, `meshSize`, `collisionFidelity` |
| SurfaceAppearance | `colorMap`, `normalMap`, `metalnessMap`, `roughnessMap`, `alphaMode` |
| SpecialMesh | `meshId`, `textureId`, `scale`, `offset` |
| Attachment | `cframe` |
| Bone | `transform` in addition to attachment fields |
| Motor6D | `c0`, `c1`, `transform`, optional `part0`, `part1` |
| AnimationConstraint | `transform`, optional `attachment0`, `attachment1` |
| KeyframeSequence | `loop`, `priority` |
| Keyframe | `time` |
| Pose | `cframe`, `weight`, `easingStyle`, `easingDirection` |

Vectors have three finite components. Frames have the twelve components from `CFrame:GetComponents()`. Enum fields use member names. Map fields contain durable URI strings. An empty string means no map. Mesh capture uses Box collision fidelity. It records native Size and MeshSize. Its part frame and Size define its bounds. Model `box` and `size` record the native bounding box. Animation parent indices retain nested poses. The capture loads sequences through KeyframeSequenceProvider. It does not sample playback.

Pass `{ content = { facts = decodedCapture } }` to `Lute.fixture.bridge` to use the capture in the engine double. Do not also supply `assetVersion`. The bridge uses its own datatype library. For a standalone environment, call `Roblox.contentFacts.attach(environment, decodedCapture, library?)`. The optional library is a `Roblox.datatypes` library for that environment.

The consumer installs InsertService.LoadAssetVersion, AssetService.CreateMeshPartAsync and KeyframeSequenceProvider.GetKeyframeSequenceAsync fakes. Each load builds new instances and remaps references. Model loads go under InsertService. Mesh loads accept URI Content values and no options or an empty options table. Options that could change geometry fail. Animation loads accept `rbxassetid://` strings. GetKeyframes, GetPoses and GetSubPoses return captured children. Missing IDs and captured refusals raise errors. Partial reconstruction destroys its objects before it raises an error.

Captured bounds stay in the fact file. Model methods use the engine double's geometry rules over rebuilt parts. These methods do not simulate mesh collision or deformation. The capture keeps imported content outside a running hierarchy and never requires an imported module. It records no source. Rebuilt scripts are disabled. This format covers the listed fields. It is not a complete place serializer, an asset rights record or native playback proof.

Verify gives each case an isolated lifecycle and records the result in a report. The case context exposes its registered case ID as `context.id`. Start with cases and assertions. Use sessions, plans and host adapters when you coordinate several sources or collect observations on another host.

| Task | Start here |
| --- | --- |
| Write and run a case | [Cases and sessions](#cases-and-sessions) |
| Compare values or record calls | [Assertions and spies](#assertions-and-spies) |
| Read, validate or combine results | [Reports and transport](#reports-and-transport) |
| Schedule work across hosts | [Execution plans](#execution-plans) |
| Judge observations that a host collected | [Host observations](#host-observations) |
| Prove that evidence is current, intact, reviewed and complete | [Evidence provenance](#evidence-provenance) |
| Plan captures or move reports from a native host | [Host adapters](#host-adapters) |
| Test engine-facing logic without Roblox | [Simulated environment](#simulated-environment) |
| Compose reflection, UI fakes and the engine seam | [Reflection and explicit UI fakes](#reflection-and-explicit-ui-fakes) |
| Score a Roblox interface or evaluate coding agents | [Agent evaluation](agent-eval.md) |

Examples use these package names. Replace the paths with the locations of your mounted packages:

```luau
local Core = require(path.to.verify.core)
local Bdd = require(path.to.verify.bdd)
```

The optional packages are:

- [`Lute`](../src/lute/init.luau) and [`Roblox`](../src/roblox/init.luau).
- [`Gate`](../src/gate/init.luau), [`Evidence`](../src/evidence/init.luau) and [`Benchmark`](../src/benchmark.luau). They run on the host side. A place mounts only core.
- [`Consumer`](../src/consumer/init.luau).

Each entry point exports its public functions and types. The [working example](../examples/basic.luau) is a case and report that you can run directly. The [laws](laws.md) define the lifecycle and evidence boundaries.

---

## Cases and sessions

### `Core.createHarness`

`createHarness({ now, source?, prefixIds? }) -> Harness`

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

The [one case model](experience.md#one-case-model) owns typed operations, host binding, deadlines and evidence. `Core.runCase({name, ...caseOptions}, host)` runs one ordinary case and returns the standard report. Use `Core.observationParity` to compare the action and query observations of two reports.

`Core.Resource<T>` types a resource for `context:own`. It is a cleanup function or a `T` with a `dispose` or `destroy` member. Declare the receiver of a disposal callback as the complete resource type.

Cleanup runs once, newest first. Setup, case, teardown and cleanup failures stay visible independently. A later failure does not erase an earlier one. Hooks and cleanup use the same invocation contract as the case. An artifact reference records a location. It does not save or authenticate bytes.

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

The surface contains `describe`, `it`, `itSkip`, `beforeEach`, `afterEach`, `expect`, `spy` and `skip`. Case and hook bodies receive `(own, context)`. `own` registers a cleanup function. Use `itSkip(name, reason, body?)` during registration and `skip(reason)` during a case or hook.

`it(name, { run, id?, requires?, tags?, limitations? })` passes the same case metadata as `harness:case`:

- `id` fixes the case identity.
- `requires` names capabilities. A missing capability makes the case `unsupported`.
- `tags` select cases.
- `limitations` appear in the report.

`Bdd.surface({executor, environment, capabilities, ambientSource, now?, selection?})` returns one session-backed surface. It holds the verbs above and these members: `load(source, register)`, `adoptReport`, `sourceReport`, `run`, `setSelection(selection?)`, `reset` and `useHarness`. `selection` and `setSelection` use the selection of the harness and the session. `load` opens the source and registers it. It adopts a registration error as a failed source report. `Bdd.formatResults(report, title?)`, `Bdd.formatFailures` and `Bdd.counts` print a report. A unit case, an engine-integration case and an end-to-end case use this one vocabulary. They differ in the capabilities that they require and the evidence that they attach, not in the runner.

### `Core.createSession`

`createSession(options) -> Session`

`Core.createSession` keeps the type of the factory surface in `verbs` and `current()`. It owns one registry per source. Use it when modules register their cases as they load. The options require `executor` and `environment`. Optional fields are `capabilities`, `now`, `surface`, `runtimeVerbs`, `prefixCaseIds` and `selection`. With solver v2, declare factory options as `Core.SessionProvidedOptions<YourSurface>` before you call the overloaded constructor.

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
| `verbs` | Route calls through the surface of the active source. |
| `adoptReport(source, report)` | Include an existing source report. |
| `sourceReport(id, source, status, detail)` | Construct a source-level failed or skipped report. |
| `setSelection(selection?)` | Set which cases to run. |
| `run()` / `reset()` | Execute the queued sources or reset the session state. |

Call session methods with `:`. A `surface` factory maps registration verbs to each harness. `runtimeVerbs` routes verbs such as `skip` while cases run. A reset or a reentry during a run fails and keeps the queued sources. The [worker examples](execution.md#lute-workers) show module-loading integration.

---

## Assertions and spies

### `Core.expect`

`expect(value) -> Expectation`

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

Inspect `calls`, `called()`, `lastArgs()` and `lastReturn()`. Use `reset()` to clear the recorded calls. Use `returnValue(value)` to give a fixed return and `implementation(fn)` to replace the callback.

---

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

| API | Use it to… |
| --- | --- |
| `Core.decode(value)` | Validate a foreign report and its schema. |
| `Core.merge(reports, executor, environment)` | Combine trusted reports. |
| `Core.compose(payloads, executor, environment)` | Account for every expected shard, including missing, invalid and duplicate outcomes. |
| `Core.syntheticReport(options)` | Record work that a host could not reach. |
| `Core.format(report)` | Produce readable output. Each case that carries measurements adds one line for each measurement: name, unit, sample count, `p50`, `p95`, declared extra percentiles and the evaluation reason. |

```luau
local combined = Core.compose({
    { id = "worker-1", report = report },
    { id = "worker-2", error = "worker exited before returning a report" },
}, "local-workers", { revision = "working-tree" })

print(Core.format(combined))
```

Give every launched shard, including errors. If you omit an unsuccessful worker from the input, the result cannot establish that all expected work passed.

### Move reports between hosts

| Surface | Transport |
| --- | --- |
| `Core.frame`, `extract`, `reassemble`, `receipt` | Tagged log lines. |
| `Core.segment`, `reassembleSegments` | Bounded payload arrays. |
| `Lute.encode`, `parse` | Any JSON value to text, and JSON text to a plain value. |
| `Lute.decode` | JSON text to a validated report. |

`Core.reassembleSegments(segments: { unknown })` validates decoded rows before using their segment fields. It also accepts arrays produced by `Core.segment`. Invalid fields, missing segments and digest disagreements return `nil` and a reason; reassembly never changes the given rows.

Missing, conflicting and mixed chunks fail. **JSON decoding is not report validation.** Validate each received report with `Core.decode`. The consumer binds executor identity and owns authenticity. [Report transport](execution.md#report-transport) describes the run-bound channel.

## Execution plans

A plan names a finite set of work and its requirements. The consumer provides discovery, the meaning of each locator and an authorized host.

| API | Responsibility |
| --- | --- |
| `Core.execute(plan, host, options?)` | Validate, select and batch the plan, then execute the batches with lifecycle, capability and failure accounting. |
| `Gate.define`, `run`, `format`, `testCases`, `rerun`, `explain`, `list` (package `src/gate`); `Lute.gate` (`run`, `last`, `cli`, `writeReport`) | Declare producers and execute them as one accounted plan with an acceptance verdict. See [declarative gates](execution.md#declarative-gates). |
| `Benchmark.case`, `run`, `collection`, `collect`, `store`, `storeReport`, `decode`, `compare`, `spread` (`src/benchmark.luau`) | Warm up, sample and check baselines and stability. Report the result as an ordinary case. Store, compare and summarize runs. See [benchmarks](experience.md#benchmarks). |
| `Lute.memory.measure`, `settle`, `create` | Estimate retained Luau heap in a separate lifecycle pass with bounded collection progress. See [retained heap estimates](execution.md#retained-heap-estimates-on-lute). |

[Execution](execution.md) describes fixtures, deadlines, retries and Lute workers. The [fake host](../tests/fake-host.luau) of the tests injects missing, duplicate, reordered, failed and cancelled deliveries without external effects.

---

## Mounted place sources

`Roblox.createPlaceCache(host)` shares source and compiled bytes. Each load uses its own environment. `Roblox.buildPlaceTree(engine, projectPath, dependencies)` mounts a project with the given engine and file host. `Roblox.createPlaceRuntime(engine, mounted, options)` runs source modules in separate client and server contexts. `Roblox.bootPlace(config, dependencies)` controls the bounded boot stages. These checks do not prove native rendering, input, asset access or release acceptance.

Project properties accept implicit Color3, Vector2, Vector3 and flat CFrame components. They also accept explicit datatype values. Primitive properties accept explicit type wrappers. `$attributes` sets attributes on the root, services and child instances. The environment validates each attribute value.

Project `emitLegacyScripts` defaults to true. Set it to false to mount client and server sources as Scripts with `RunContext`. An explicit `RunContext` property overrides this choice. Boot uses each script context and disabled state. Modern server Scripts run in Workspace, ServerScriptService, ReplicatedStorage, ReplicatedFirst and ServerStorage. Modern client Scripts run in Workspace, ReplicatedStorage, ReplicatedFirst and PlayerScripts. Legacy server Scripts run in Workspace and ServerScriptService. Legacy LocalScripts run in ReplicatedFirst and PlayerScripts. The shared Studio and simulator assertions check both modes, context overrides and disabled sources in the five services.

The place runtime accepts `debug.profilebegin`, `debug.profileend` and `debug.setmemorycategory`. These calls collect no performance or memory measurements. The debug table keeps the host inspection functions. It does not change the host table.

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

The simulator has no terrain voxel geometry. Use `environment.poke` to give a terrain proxy `CFrame`, `Size` and a uniform `Material`. Queries use that box in the Default collision group. Terrain without explicit bounds raises `unsupported_content`. Casts also require its material. `IgnoreWater` excludes terrain proxies with Water material. It does not exclude ordinary Parts with Water material. Mixed terrain materials and voxel changes need a query fake or native host. The simulator does not derive boxes from voxels. `Shapecast` cannot cast a Terrain source.

Nonzero `OverlapParams.Tolerance`, `RaycastParams.Margin` and `RaycastParams.SizeGradient` raise `unsupported`. Verify does not silently change the requested volume. Margin and SizeGradient accept validated values, then fail explicitly during a query. Spatial results prove only this geometry model. They do not prove native physics or floating-point parity. The query fails when it cannot resolve a box contact numerically.

AudioEmitter distance curves copy inputs, outputs and cloned state. Negative finite distances become zero. Finite volumes stay within `[0, 1]`. These rules match the native setters. Invalid keys or values fail before the curve changes. The simulator accepts at most 400 points. It does not simulate audibility or audio output.

`Model:ScaleTo` scales about the current pivot and keeps nested model factors and cloned scale state. Supported geometry includes part sizes and pivot offsets, attachment frames, joint C0/C1, mesh offsets and file-mesh scale. It includes sound rolloff distances and particle size, speed and acceleration. It also includes beam widths and curves, trail minimum and maximum length, and rope length and thickness. Supported Humanoid properties are hip height, speed, jump height and jump power. AnimationConstraint translation scales linearly and its maximum force and torque scale cubically; strength and damping remain unchanged. Motor6D/Bone animated transforms and light range remain unchanged. Edited properties become the new basis for later scaling; unchanged property sizes keep their original basis. Part positions use floating-point transformations. Constraints other than ropes and animation constraints refuse before geometry changes; constraint dynamics and other geometric properties require an explicit host or native execution.

Lute consumers use `Lute.fixture.host` for filesystem reads, compilation, environment-bound loading and JSON, and `Lute.fixture.files` for project traversal. Both tables are frozen; clone the host when injecting fixture sources. `Lute.FixturePlaceHost` is its exported type. Consumers keep project paths and game-specific setup rather than copying this platform wiring.

Project `$path` values resolve relative to the project file's directory. Absolute paths remain absolute. Project properties decode Rojo's tagged Color3, Vector3, CFrame and enum values through the engine's datatype library. Malformed components and unknown enum values fail before assignment.

The modeled `ContentProvider.PreloadAsync` accepts an empty request without callbacks. It rejects nonempty requests as `unsupported_place_asset`; it does not fetch assets or report a fabricated asset status.

`PlaceRuntimeEngine.environment` owns the simulated environment. The binding gives the runtime its DataModel, instance constructor, service lookup, datatypes and source diagnostics. Runtime and boot use public environment operations for properties, events and method doubles. The engine contract has no mutable `stateOf` or `serviceMethods` table.

Construct it with `Lute.fixture.bridge().placeEngine()`. Use `engine.environment.scheduler` for time, `environment.fire(instance, event, ...)` for events and `environment.fake` or `fakeOn` for explicit method doubles. BasePart position/CFrame writes remain coupled. The reflected environment models pivots, descendant placement and oriented model bounds; it does not simulate joints, collisions or physics. Set a model's primary part or world pivot when its orientation matters; an unset pivot uses the largest descendant part as its basis.

Runtime options are `{ aliases, cache, host, methodDoubles?, client?, beforeRender? }`. `methodDoubles` selects classes for the existing runtime method doubles. Omit it to use the standard simulation. Give an explicit list to restrict the methods. An empty list installs none. The runtime applies this selection to existing and new instances. Run `closeHandlers` when the host closes. This stops registration. Unselected media and physics methods get no behavior.

Runtime defaults preserve methods configured before runtime creation. `environment.hasFake(instance, member)` finds object overrides, inherited class fakes and class handlers. Closing removes only runtime overrides and listeners. It keeps caller methods.

`MemoryStoreService:GetHashMap()` gives cached handles with native structure when the game ID is positive. Reads, writes, expiry, contention and sharing across servers need explicit injected behavior. Handle creation proves none of these operations.

`Workspace:GetServerTimeNow()` follows the virtual scheduler clock, starting at simulated epoch zero. `UserInputService:GetLastInputType()` starts at `None` and follows dispatched input events; close handlers disconnect its listeners. These are controlled simulation inputs, not OS input or wall-clock synchronization. The mesh-part double keeps URI-backed `Content` and refuses empty or object-backed content; it performs no asset load and proves no asset access or appearance.

`bridge.placeEngine()` returns one cached engine for runtime and boot. The engine uses the bridge environment and reflection metadata. It owns a DataModel. Its service lookup creates only reflected services. Script construction restrictions still apply. The boot report keeps source diagnostics and observed roots. No separate diagnostic adapter is necessary.

The optional `client = { name, userId, viewport = { x, y } }` creates a Player, PlayerGui and camera. Viewport dimensions must be positive and finite. This sets `runtime.localPlayer` and `Players.LocalPlayer`. It does not start scripts or create a character. `runtime.step(seconds)` advances the scheduler and simulated RunService frame events. It calls `beforeRender()` before render events. Hosts can use `bridge.layout.step` there. Reader errors stop execution before render publication. These frames do not prove native rendering or physics. `StudioDeviceSimulatorService:SetDeviceAsync(id)` applies captured Studio facts for `iphone_14`, `xbox`, `hd_1080` and `generic_handheld_720`. `runtime.device()` returns current device facts. `runtime.screenArea(screenGui)` returns the device area for that ScreenGui and its `ScreenInsets`. `IgnoreGuiInset` selects `DeviceSafeInsets` or `CoreUISafeInsets`, as in Studio.

ModuleScript results are cached by instance and execution context. Relative requires use the mounted source tree. Runtime and compile failures stay in the cache. Another require raises the same failure.

## Host observations

Use typed operations, `context:perform`, `await`, `checkpoint`, `judge` and `measure` in the ordinary case. Evidence lives in `CaseResult.evidence` and uses the standard report transport. The [experience contract](experience.md) describes binding. The [execution contract](execution.md) describes hosts.

## Evidence provenance

Evidence travels on the report. An `Artifact` can carry `sha256`, `size` and a typed `provenance`. Provenance holds:

- The run, case, actor and checkpoint.
- The build (`commit`, `tree`, `clean`, `digest`).
- The executing host and its capabilities, taken from the case origin.
- The `device` class that the caller declares, and `capturedAt`.

A `Review` can carry `kind` (`visual` or `audio`) and `judged`, the content hashes that the reviewer saw. The report decoder keeps both. The report is the only record. No second record exists.

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

A sink is `{ put(content, meta) -> reference, get(reference) -> bytes, stat(reference) -> { size } }`. The caller provides it.

- `Lute.evidenceStore.localDirectory(path)` is the content-addressed reference sink.
- `Core.memorySink(hash)` is a portable sink.
- `Lute.evidenceStore.validate(report, { from, required })` fills in the store, hash and clock.

Validation needs only `get`, `stat`, a hasher and a clock. Pass `hash`, `read` and a sink to `Evidence` on another host:

```sh
lute run examples/evidence-provenance.luau
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

### Model files

`Lute.model` reads a Roblox XML model (`.rbxmx`) or place (`.rbxlx`) so that a case can assert on a built file.

- `read(text)` returns the root instances. Each instance is `{ className, name, path, properties, children }`.
  `name` is the `Name` property, or the class name when the file stores no name or an empty name, so that each path segment is not empty. `path` joins the names from the root with `/`.
  `properties[name]` is `{ type, value }`: the XML tag of the value, such as `string`, `ProtectedString` or `bool`, and its decoded text.
- `descendants(roots)` lists every instance in document order.
- `find(roots, path)` returns the first instance with that path, or `nil`.

`read` raises for invalid XML and for a document whose root is not `roblox`. It reads a binary file (`.rbxm`, `.rbxl`) as invalid. Build the XML format to assert on it. `Lute.place.build` merges into a base place with the same XML codec.

### Codecs

`src/codec` holds portable leaves that the hosts and the judge share. They need no host services.

- `codec/base64.luau`: `encode(bytes)` returns standard base64 with padding. `decode(text)` returns the bytes, or `nil` when the text is not padded base64. `AgentEval.base64` is the same module.
- `codec/xml.luau`: `parse(text)` returns the root element `{ tag, attributes, children, text, openEnd, closeStart }`. `text` is the decoded text before the first child element. `openEnd` is the offset of the `>` that ends the start tag. `closeStart` is the offset of the `<` that starts the end tag, or `nil` for a self-closing element. `children(element, tag)` and `first(element, tag)` select child elements.
- `codec/image.luau`: `mediaType(bytes)` returns `image/png`, `image/jpeg`, `image/gif`, `image/webp` or `nil` from the file signature. `pngSize(bytes)` returns the width and height from the PNG `IHDR` chunk, or `nil` when the bytes are not a PNG.

---

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
| A write that targets a rejected selection is ignored | `"raise"` is a test convenience. | `ui.selection = "ignore"` is engine-true. |
| A selection outside a `PlayerGui` is allowed | Engine-true. | `ui.requirePlayerGui = true` is a test convenience. |
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
- Inspection: `childrenOf`, `parentOf`, `propertyOf`, `attributeOf`, `isAlive`, `liveObjects` and `liveConnections`.
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

`Animator:LoadAnimation` returns a track. `Play`, `Stop` and `AdjustSpeed` change `IsPlaying` and `Speed` and fire `Stopped` and `Ended`. The simulator blends no frames. The package exports a `Datatype...` type for each datatype, and `DatatypeLibrary` and `DatatypeCatalog`. These types describe the values for the type checker. At run time each value is a userdata.

### Instance behavior

- Instances support `Parent`, `Name`, children events, find and ancestor lookups and `GetFullName`.
- `WaitForChild(name, timeout?)` returns an existing direct child without yielding. Otherwise it waits on the virtual scheduler until a child is added or renamed to `name`. A positive timeout returns nil when it expires; nil waits indefinitely. Nonpositive timeouts raise before the existing-child lookup. The simulator does not print the engine's infinite-yield warning.
- `Destroy` locks the parent, destroys the descendants and disconnects the signals of the instance.
- Attributes have change signals. Property change signals fire only on change.
- Signals start listeners in connect order on separate scheduler coroutines. A yielding listener does not suspend the emitter or other listeners. A connection that disconnects before its listener starts is skipped; a started listener may finish after disconnection.
- `signal:Wait()` yields through the existing scheduler until the next fire and returns its complete argument tuple. It ignores previous fires. Resumption and task cancellation release the wait listener.
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
- The order across events beyond these guarantees is not a contract.

### Held selection navigation

`GuiService:Select(parent)` chooses the eligible descendant with the lowest SelectionOrder inside the input host's PlayerGui. It excludes hidden, nonselectable, noninteractable and off-screen objects. Active does not affect eligibility. A parent with no eligible descendants leaves SelectedObject unchanged. A parent outside the PlayerGui raises an error.

The simulated input host repeats held arrow-key selection after 0.5 seconds, then at intervals of at least 0.12 seconds. Release stops the repeats. A repeat moves the current selection without another `InputBegan` event. A focused TextBox prevents selection movement. The shared Studio case checks the initial delay, repeat movement, release, key events and the end of a collection.

`UserInputService:GetGamepadState()` returns the 24 idle controls for each Gamepad1–Gamepad8 slot, including disconnected slots. Each InputObject identifies its slot and key, with End state and zero position. Other UserInputType values return an empty array. Each call returns a separate array. This initial-state model does not inject gamepad input.

### Input action state

`InputAction:Fire(value)` and `GetState()` share state with simulated keyboard dispatch. The value must match the action type: boolean, number, Vector2 or Vector3. Repeated values emit no event. Boolean transitions emit `Pressed` or `Released` before `StateChanged`. Other types emit only `StateChanged`.

An action must belong to a DataModel and be enabled. Its nearest InputContext must also be enabled. Disabling either resets the state. A parent change resets affected actions, and a type change publishes the new zero state. Clones start at zero. The shared Studio sequence checks these transitions, duplicate suppression and destruction. This model does not establish physical input delivery.

### Haptic requests without motor hardware

The default environment has no haptic motors. `HapticService:IsVibrationSupported()` and `IsMotorSupported()` return false. `HapticEffect:Play()` and `Stop()` accept requests but produce no motor output or `Ended` event. This matches the observed Studio host without haptic hardware. `SetWaveformKeys()` accepts FloatCurveKey arrays only when the effect type is Custom. Native request validation also accepts empty arrays, negative key times, repeated times and values outside 0–1. This model does not simulate waveform playback on supported hardware.

---

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
- `ui.selection` is `"raise"` (default) or `"ignore"`. See [rejected selection](#rejected-selection).
- `ui.requirePlayerGui = true` requires the target to descend from a `PlayerGui`.
- `GuiService.GetGuiInset` requires an explicit `ui.methods["GuiService.GetGuiInset"]` handler that returns both current inset vectors. There is no inferred inset or relationship to `TopbarInset`. A provider provides representative host state; it does not establish native inset or safe-area coverage.

The options `defaultProperty`, `computed`, `handlerErrors`, `undeclaredWrites` and `functionDoubles` pass to the environment. `Lute.fixture.bridge` accepts the same options.

The bridge returns `{ environment, engine, ui, layout, unavailable, faults, hasClass, observe, track, record, instanceHost, accounting, close }`.

`layout = { roots, viewport, origin?, screenArea?, read?, component?, vector?, measureBounds? }` enables simulated layout. `roots()` returns mounted roots. `viewport()` returns `{ X, Y }`. `screenArea(screenGui)` returns `{ x, y, width, height }` for each ScreenGui. Give `runtime.screenArea` to use the current device inset area. After mutations, call `bridge.layout.step()` before frame observations. It publishes geometry through the environment. It does not advance time or connect frame handlers.

Layout clamps `ScrollingFrame.CanvasPosition` when it owns the measured bounds. Poked `AbsoluteSize`, `AbsoluteWindowSize` or `AbsoluteCanvasSize` that differ from its last publication make those bounds stale. Before the first pass, nonzero bounds count as supplied geometry. If stale bounds would cause a clamp, layout raises `unsupported_ui_layout` before publishing geometry. The error names the instance and shows supplied and computed bounds. This includes poked bounds with an unmeasured zero canvas. Author `Size` and `CanvasSize`, or keep the poked frame outside layout roots.

`layout.objectsAtPosition(root, x, y)` queries published rectangles in GUI coordinates. It returns visible objects from front to back, including objects that cannot receive input. It supports Global and Sibling ordering, ancestor clipping and enabled ScreenGuis. Right and bottom edges are inclusive, as in the native fixture. Coordinates must be finite integers. Equal DisplayOrder values across ScreenGuis and unsupported geometry raise errors. The input backend separately checks input eligibility and routes presses and releases. The geometry query dispatches no events.

Layout supports UDim2 dimensions, anchors, scale, fixed padding, size constraints, single-line lists and wrapped lists. Lists support parent Fill, individual UIFlexItem modes, weighted growth and shrink, size limits, cross-axis flex and line alignment. Shrink weights include each item basis. Items at a size limit release remaining space to other flexible items. The same 58 flex configurations run in the simulator and Studio. Main-axis SpaceBetween, SpaceAround and SpaceEvenly support leading alignment when children do not overflow. Without flex, these modes distribute free space without list padding. AbsoluteContentSize still includes that padding. Both hosts run the same 24 spacing configurations. Intrinsic AutomaticSize supports fixed child bounds, simple lists and grids, including growth and shrink.

UIGridLayout supports both fill directions, start corners, sorting, alignment, cell padding and maximum cells per row or column. It publishes AbsoluteCellSize, AbsoluteCellCount and AbsoluteContentSize. A layout aspect constraint controls cell size with both aspect types and dominant axes. Cell dimensions use native float precision before the fit calculation. Both hosts run the same 37 configurations observed on native Studio. Individual cell size constraints or scales fail before geometry changes. Nonpositive sizes, negative padding and cells that depend on an automatic parent axis also fail before changes.

Wrapped lists form lines in either fill direction. Each line distributes its flexible items separately. Cross-axis flex distributes or stretches lines. Scaled padding uses the corresponding parent axis. Fixed-child lists support automatic sizing on either axis. They handle resize, visibility, sorting, removal and wrapping changes. Individual GUI aspect constraints support both aspect types, dominant axes, scaling, size limits and list flex. Both hosts run the same 1,164 wrapping and aspect configurations observed on native Studio. They also run reflow mutations.

Relative children under automatic parents support bounded measurement. Lists require the authored minimum to contain the children under both ancestor and final bounds. Free layouts measure natural child bounds first, then relative dimensions, then final padded bounds. Unpadded relative positions and anchors are supported when the final children fit. The same 444 configurations and a resize, minimum-size, visibility, insertion, removal and padding mutation sequence run under Studio and the double.

Unresolved relative growth and padded relative positions remain unsupported. Relative children under constrained automatic parents also remain unsupported. The same applies to relative intrinsic child sizes with their own automatic axis or aspect constraint. Unwrapped lists reject non-leading or overflowing distributed spacing. Table layouts, page layouts, rotation and LayerCollectors other than ScreenGui also fail. Aspect constraints on automatic-size GUI objects and individual grid cells fail. These cases raise `unsupported_ui_layout` before geometry publication. A `StyleLink` requires an effective-property `read(instance, property)` provider; the bridge provides its UI style reader by default. Supplied reader errors propagate. `vector(x, y)` selects the output datatype constructor. These mechanisms are simulated and do not establish native rendering or input coverage.

`Lute.fixture.bridge` installs captured text measurements by default. TextService.GetTextBoundsAsync and GetTextSize use font advances, pair adjustments and boundary corrections observed on native Studio. The facts record engine version and font face. They cover ASCII letters, digits, spaces and hard newlines at integer sizes 1-100. Committed families are Builder Sans, Nunito, Fondamento and Michroma. Each has Regular, Medium, SemiBold and Bold weights. Source Sans Pro Regular and Legacy Arial Regular are also included. All use Normal style. Word wrapping supports words that fit the available width. Unknown fonts, punctuation, other Unicode, rich text and words that need splitting raise `unsupported_text_metrics`. The simulator does not estimate those inputs. GetTextSize limits height to whole lines within frameSize.Y, with at least one line. Width includes all lines.

A given `ui.measureBounds` or `ui.measureText` replaces the default for that method. Set the field to false to leave the method unsupported. Portable Roblox.fixtureBridge and Roblox.reflectionSnapshot.bridge still need explicit measurement providers.

Layout uses measureBounds to publish TextBounds and TextFits and measure automatic text size. The bridge forwards its UI provider unless layout has its own. Line height and UI scale use line metrics observed on native Studio. These include Legacy Arial strut sizes. Rendered font sizes must be integers from 1 to 100. Text supports automatic axes and size constraints. Vertical lists with cross-axis Fill measure wrapped automatic height at the stretched width. Wrapped bounds limit visible height to complete lines and keep full wrapped width. TextFits is false when lines do not fit. Unsupported cases include unwrapped multiline text beyond the height and wrapped automatic width controlled by a list. Other flexed widths, TextScaled and TextTruncate also remain unsupported. Both hosts run 36 constraint, 180 clipping, 36 flex and 36 Legacy Arial configurations. Legacy Arial geometry allows 0.001 pixel error for native float rounding. Service bounds compare exactly. A native pass covers only the committed font faces and text grammar. It does not prove arbitrary text rendering.

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

#### Export from Studio

```sh
lute run tools/export-studio-reflection.luau <out.json> (--studio-id <id> | --studio-name <name>) [--classes A,B,...]... [--enums A,B,...]... [--services] [--mcp <StudioMCP>] [--framework <directory>]
```

The command uses an open Studio through the official Studio MCP. See [attached Studio](execution.md#attached-studio). Its `authorize` hook permits only the Studio listing and `execute_luau` in the `Edit` data model. The capture reads `ReflectionService`, `Enum`, `BrickColor` and `Font`, and it creates instances that it never parents. It lists classes with the current security capabilities and the `Plugin` capability, so the export includes plugin classes such as `PluginGui` and `DockWidgetPluginGui`. It reads the members of a plugin class with the same capabilities, and the members of every other class with the current capabilities only. It does not change, save or publish the place. The default transport of `Lute.studio.attach` must work on the host. See [platform support](running.md#platform-support).

- Without `--classes`, the command exports every class. With `--classes`, it exports the named classes and their superclasses.
- Without `--classes` and `--enums`, it exports every enum.
  Otherwise it exports the enums that the exported properties and defaults name, the enums in `--enums`, and the enums that the datatypes need.
  The datatypes need ContentSourceType, EasingDirection, EasingStyle, Font, FontStyle, FontWeight, KeyInterpolationMode and RaycastFilterType.
- Datatypes use the database names `Bool`, `Float32`, `Float64`, `Int32`, `Int64`, `String`, `CFrame`, `OptionalCFrame`, `Rect`, `Ref` and `Enum.<family>`. Other types keep the engine name.
- Scriptability comes from the read and write permits. A property that scripts can read but not write has the tag `ReadOnly`.
  A property with no permit has the scriptability `None` and the tag `NotScriptable`. A deprecated member has the tag `Deprecated`.
- A class without a `New` permit has the tag `NotCreatable`. A class with a `GetService` permit also has the tag `Service`.
- The defaults are the readable property values of `Instance.new(className)`, inherited properties included, for each creatable class.
  A service has no defaults. `--services` records the values of the open place instead. Those values describe that place, not the engine.
- A superclass that Studio does not list as a class, such as `Object` above `Instance`, is omitted.
- The full export of Studio 0.742 has 681 classes and 648 enums in about 600 KB.

From code, `Lute.fixture.exportStudio(execute, options?)` returns the snapshot. `execute(code)` runs the code in the `Edit` data model and returns its text, for example through `session.execute("Edit", code)`. `options` is `{ classes?, enums?, services?, batchSize?, framework? }`. `batchSize` (default 25) bounds the classes for each request. `framework` is the Verify checkout that holds `src/roblox/reflection-capture.luau`. `Lute.fixture.save(path, snapshot)` writes the file with sorted keys.


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

`tests/reflection-snapshot.lute.verify.luau` builds bridges from both fixture files. `tests/studio-reflection.lute.verify.luau` runs the generated Studio code against a fake engine. After a Roblox API update, regenerate a committed snapshot.

#### Run code under test with the library

`Lute.chunk.load(source, { name?, environment?, injectGlobals? })` compiles `source` and returns the chunk function. A global read looks in `environment` first and then in the Lute globals. `injectGlobals = false` uses `environment` alone. A global write stays in the chunk. `environment` does not change. `Lute.chunk.check(source, name?)` returns `true`, or `false` and the syntax error, and runs nothing. Put the library members and `typeof = types.typeof` in `environment`, so the code under test sees datatype globals with engine names.

#### Load a module tree under the library

`Lute.loader.new(options?)` returns `{ require(path) }`. It loads Roblox-targeted modules under Lute. `require(path)` takes a path relative to the working directory, with or without `.luau`. A directory path loads its `init.luau`.

Each module runs in its own environment:

- `typeof` is the datatype `typeof`, so a datatype value reports its engine name.
- `warn(...)` prints the arguments with the prefix `[warn]`.
- `getfenv(0)` returns the environment of the module. `getfenv(f)` returns the environment of a function that a module returned.
- `require` resolves `./` and `../` paths, `@self/` children and the aliases in `options.aliases`. `@std/` and `@lute/` load from the runtime.
- Each name in `options.globals` is a global, for example `game`, `Instance` or `Enum` from an engine fixture. A name in `options.globals` replaces `typeof` and `warn`.
- `options.transform(path, source)` returns the source to load for a file. Use it to change one module in a test.
- `options.files = { exists(path), readFile(path) }` provides the module files. Without this option, the loader uses the host filesystem. Use an in-memory file table when module loads must complete without filesystem waits. Both functions receive normalized paths relative to the working directory.
- `require` also takes a reference from `loader.reference(path)`. A reference gives a child reference for each indexed name, so `require(game.ReplicatedStorage.shared.rules)` loads `<path>/rules` when `game.ReplicatedStorage.shared` is `loader.reference("<path>")`. The loader reads `options.globals` on each access, so a global can hold references that the loader makes.

The loader loads each file once and keeps the resolved paths. A require cycle, a missing module and an unknown alias raise with the module named. A file under a prefix in `options.hostPaths` loads with `options.requireHost(module)` instead, as an ordinary host module. `module` is the path without `.luau` or `/init.luau`.

```luau
local loader = Lute.loader.new {
	aliases = { repo = "" },
	hostPaths = { "tools/vendor/" },
	requireHost = function(module: string): unknown
		return (require :: (string) -> unknown)("../../" .. module)
	end,
}
local Package = loader.require "src"
```

#### Studio probes

`Lute.fixture.probeStudio(execute, probes)` runs each `{ name, source, tolerance? }` probe in Studio and returns `{ engineVersion, results }`. `Lute.fixture.probeLocal(environment, probes)` runs the same probes with `Lute.chunk.load`. Each result is `ok: ` and the `tostring` of the returned value, or `error: ` and the message without its location. Record the Studio results in a file. Compare the local results with that file in a test. A probe proves only the expression that it runs.

### UI fakes

`Roblox.uiFakes.classes` declares optional UI methods. Give it as a class overlay. Pass `uiFakes.validateProperty` as the property validator to reject the selection of hidden or unselectable controls. `Instance:GetStyled(property)` resolves the nearest linked StyleSheet. It supports class, tag, name and compound selectors, child (`>`) and descendant (`>>`) combinators. It also supports comma-separated alternatives, rule priorities and attribute tokens. For example, `.Container > Frame#Card.Hot` requires the parent tag, child class, child name and child tag. Relevant branches must use supported syntax. A nondefault raw property overrides the style. Writing the default or resetting it exposes the style again. Empty links do not replace an ancestor scope.

`ScrollingFrame:GetScrollVelocity()` returns `Vector2.zero`. Canvas writes and virtual time create no momentum. `ResetScrollVelocity()` keeps the canvas position. The double does not simulate inertial scrolling, release velocity or deceleration.

`Instance:GetStyled(property, "::ClassName")` reads a phantom `UIPadding`, `UICorner`, `UIStroke` or `UIGradient`. Missing phantoms raise. These components do not appear in the physical hierarchy, change resource counts or fire child events. A physical component has its own styled properties and takes precedence for layout. The shared fixtures check this distinction with physical and phantom padding, raw overrides, default values, token changes and removal.

`Instance:GetStyledPropertyChangedSignal(property)` observes the underlying style value and linked scope. Raw writes do not fire this signal. Style changes can fire it while a raw override masks the returned value. Call `controller.step()` to refresh observations; fixture layout does this before layout. `controller.styled(object, property)` exposes the effective read. `controller.component(object, className, property)` reads a physical component first, then a supported phantom, or returns nil when neither exists. Supply this as `layout.component` beside `layout.read` for phantom padding geometry. The fixture bridge provides both readers when it provides styled reads. Closing the controller disconnects its observations.

`Instance.StyledPropertiesChanged` fires on a GuiObject at `controller.step()` when a rule value it read through `GetStyled` changes and the GuiObject has a listener. It compares the rule value, so a transition fires the event once, not on each interpolation frame. Non-GuiObject instances such as UIPadding do not fire it yet.

Style transitions accept `TweenInfo` values or attribute tokens through `SetPropertyTransition`, `SetPropertyTransitions` and `SetDefaultPropertyTransition`. The `"*"` entry is the default. An explicit property entry overrides the default in its rule. Transition settings cascade separately from property targets, as in [StyleRule](https://create.roblox.com/docs/reference/engine/classes/StyleRule).

The first styled read sets the initial value. Later target changes interpolate on `environment.now`. `GetStyled`, `controller.styled` and phantom reads return the current value. Raw property reads keep their default or explicit value. Retargeting starts from the current value. `DelayTime` holds the value before interpolation. `RepeatCount` and `Reverses` are ignored, as `StyleRule` specifies. `controller.step()` publishes intermediate values; fixture layout calls it before layout.

The double interpolates numbers, `Color3`, `UDim`, `UDim2`, `Vector2`, `Vector2int16`, `Vector3`, `Rect` and `CFrame`. Booleans and enum items switch at eased progress 0.5. Other types snap. All easing styles and directions are supported. Removing a rule, tag or sheet uses the transition left in the cascade, or snaps when none is left. Invalid transitions and unresolved tokens raise `unsupported_ui_style`. Retargeting, discrete switching and removal timing are model choices until native conformance covers them.

Relevant nested rules, state selectors and query selectors raise `unsupported_ui_style`. Implicit space combinators, named or nested phantoms and derived sheets also raise this error. The same applies to multiple links at one scope, equal-priority conflicts, other selector arguments and nonzero transitions. Unsupported selectors do not block properties that their rules cannot affect. This is bounded model coverage. Shared Studio Client and double assertions check hierarchy selectors, name/tag/parent mutations, compound selectors and phantom modifiers. Native conformance does not prove rendering.


#### Rejected selection

When the real engine gets `GuiService.SelectedObject = target` for a hidden, disabled or unselectable control, it ignores the write. The default `ui.selection = "raise"` raises instead, so a test finds the mistake. `ui = { selection = "ignore" }` is the engine-true mode. It drops the write with no error, no signal and no change. `controller.rejectedSelections()` lists each `{ target, reason }` in order. A hidden ancestor, a disabled `ScreenGui` and `Selectable == false` reject. A value that is not a `GuiObject` still raises in both modes.

`ui.requirePlayerGui = true` makes a target outside a `PlayerGui` raise in both modes. It is an opt-in test convenience.

A `validateProperty` function that returns `false` vetoes the write or `poke` silently, with no change and no signal. Any other return value accepts it. This applies to `Parent` too.

`uiFakes.attach(environment, { measureText?, measureBounds?, methods? })` installs fakes for these behaviors:

- Focus.
- Style maps.
- Video state.
- Path-point storage.
- Instant page navigation.

Measurement providers are required for measurement claims. Keep the controller and call `close()` to release focus resources. The simulator does not simulate curve evaluation, rendered text, animated navigation, playback quality or style rendering. A declared method that is unsupported needs an explicit injected implementation. `attach` registers `environment.onClone`. `Clone()` then copies style, transition, derive and path state, and remaps in-tree derive references. Focus is never copied. `environment.observe` and `pendingFailures` expose operation observation and unfired fault injection.

### Engine seam

`Roblox.environmentEngine(environment, library?)` exposes the environment as a structural scene engine. The engine has creation, heartbeat, clock, datatype constructors, destruction and property observation. Objects and signals keep their identity. The default uses Verify datatypes. Give the typed factory library when you use native datatypes. This adapter adds no renderer and no native engine claim.

---

## Consumer diagnostics

`Consumer.scan(contents, path, ruleset)`, `scanTree` and `scanProductionPaths` inspect portable specifications and production graphs. Choose a ruleset: `Consumer.generic` or `Consumer.roblox`. [Consumer diagnostics](lint.md) describes the rules and their limits.

## Shape predicates

`Core.shape` exposes predicates over unknown values without coercion:

- `finite(value)` accepts numbers other than NaN and infinities.
- `finiteNonnegative(value)` also requires a value at least zero.
- `nonnegativeInteger(value)` also requires a whole number.
- `denseRows(value, count)` requires a metatable-free array of the exact length. It permits userdata marker keys used by JSON encoders.

Consumers keep their field sets, identifiers and acceptance policy.

## Named case collections

`Core.runCases(cases, options, now, ids?)` executes ordinary named cases with exact selection. The [run guide](running.md) describes selection, entry modules and host execution.

`Core.waitUntil(spec, ops)` polls to a limit. It returns the terminal reason, last observation and elapsed time. `Core.awaitValue(predicate, seconds, poll, ops)` waits for a value other than nil. The value can be false. It returns nil on timeout or cancellation. Probe failures raise errors. Set the optional final `truthy` argument to true to ignore false as well as nil. The caller gives the clock, sleep function and optional cancellation function.

## Package export index

Each heading names one runtime export. Table exports group the operations described in the relevant contract. Type-only exports remain declared in each entry point.

### `AgentEval.SCHEMA_VERSION`

Schema version accepted by the evaluation suite decoder.

### `AgentEval.adapters`

Adapters that bind declared evaluation services to a run.

### `AgentEval.base64`

Base64 encoding and decoding for evaluation payloads.

### `AgentEval.cli`

Command line entry point for evaluation runs.

### `AgentEval.decodeSuite`

Validate an unknown evaluation suite before planning it.

### `AgentEval.judge`

Judge backends, rubric defaults, verdict decoding and calibration.

### `AgentEval.load`

Load an evaluation suite from its source.

### `AgentEval.lute`

Lute operations used by the evaluation runner.

### `AgentEval.plan`

Build an evaluation plan from a decoded suite.

### `AgentEval.random`

Seeded random values for reproducible evaluation inputs.

### `AgentEval.report`

Decode thresholds, build reports and determine verdicts.

### `AgentEval.result`

Evaluation result constructors and validation.

### `AgentEval.run`

Execute an evaluation plan with explicit services.

### `AgentEval.scopedMcp`

MCP service scoped to the evaluation's authorized operations.

### `AgentEval.stats`

Statistical comparisons used by evaluation reports.

### `AgentEval.transcript`

Decode and inspect agent transcripts.

### `Bdd.counts`

Summarize result counts by status.

### `Bdd.formatFailures`

Format failed results and their details.

### `Bdd.formatResults`

Format all case results and summary counts.

### `Bdd.surface`

Build the BDD registration surface over a harness.

### `Benchmark.case`

Construct a named benchmark case.

### `Benchmark.check`

Validate benchmark results against limits.

### `Benchmark.checkCollection`

Validate a collection of benchmark reports.

### `Benchmark.collect`

Collect benchmark measurements using the given host.

### `Benchmark.collection`

Construct a benchmark collection.

### `Benchmark.compare`

Compare benchmark measurements.

### `Benchmark.decode`

Decode an unknown benchmark report.

### `Benchmark.limits`

Benchmark limit constructors and validation.

### `Benchmark.run`

Run benchmark cases with the given timing options.

### `Benchmark.spread`

Calculate measurement spread.

### `Benchmark.store`

Benchmark report persistence operations.

### `Benchmark.storeReport`

Store a benchmark report through the given store.

### `Consumer.generic`

Generic consumer diagnostic ruleset.

### `Consumer.roblox`

Roblox consumer diagnostic ruleset.

### `Consumer.scan`

Scan a source string with the selected diagnostic rules.

### `Consumer.scanProductionPaths`

Check production paths for test framework leakage.

### `Consumer.scanTree`

Scan a tree using caller-given file operations.

### `Core.SCHEMA_VERSION`

Current report schema version.

### `Core.awaitValue`

Wait for a given reader to return the required value within a bound.

### `Core.bindOperation`

Bind an operation descriptor to an implementation.

### `Core.compose`

Compose reports with validated provenance.

### `Core.decode`

Decode unknown data as a validated report.

### `Core.execute`

Execute an explicit plan with given executors.

### `Core.extract`

Extract framed report records from host output.

### `Core.float32`

Round a number to its float32 representation for comparisons.

### `Core.format`

Format a report for human inspection.

### `Core.frame`

Frame a report for transport through host output.

### `Core.memorySink`

Create an in-memory evidence sink.

### `Core.merge`

Merge compatible report results.

### `Core.observationParity`

Compare observations across reports.

### `Core.operation`

Construct an operation descriptor.

### `Core.performance`

Performance observation and budget helpers.

### `Core.progress`

Progress event validation and construction.

### `Core.reassemble`

Reassemble transported report records.

### `Core.reassembleSegments`

Reassemble segmented reports.

### `Core.receipt`

Create a transport receipt.

### `Core.runCase`

Run one named case with explicit options and clock.

### `Core.runCases`

Run a validated named case collection with explicit selection.

### `Core.segment`

Split a report into transport segments.

### `Core.shape`

Predicates for finite numbers, nonnegative numbers, integers and dense rows.

### `Core.syntheticReport`

Construct a report for an execution-level result.

### `Core.waitUntil`

Wait for a predicate with explicit clock and timing bounds.

### `Evidence.bindReview`

Bind a review to the exact sealed evidence it judges.

### `Evidence.expand`

Expand evidence requirements for validation.

### `Evidence.explain`

Explain evidence validation findings.

### `Evidence.seal`

Seal evidence content with its provenance and digest.

### `Evidence.validate`

Validate evidence integrity, freshness, reviews and coverage.

### `Gate.SCHEMA_VERSION`

Current gate schema version.

### `Gate.define`

Validate a producer draft and define the gate.

### `Gate.explain`

Explain producer selection and outcome.

### `Gate.format`

Format a gate outcome.

### `Gate.list`

List the gate's producers.

### `Gate.rerun`

Select previously unsuccessful producers for another run.

### `Gate.run`

Run selected producers through explicit execution operations.

### `Gate.testCases`

Expose gate producers as named cases.

### `Lute.attachments`

Attachment sinks for writing case artifacts.

### `Lute.chunk`

Chunked source loading helpers.

### `Lute.corpus`

Deterministic source discovery, queries and lock parsing.

### `Lute.decode`

Decode a worker wire record.

### `Lute.decodeBatch`

Decode a batch of worker results.

### `Lute.encode`

Encode a worker wire record.

### `Lute.evidence`

Host evidence collection and validation helpers.

### `Lute.evidenceStore`

Filesystem evidence sealing and validation.

### `Lute.fixture`

Create simulated host fixtures and run exported probes.

`bridge(snapshot?, options?)` accepts `content` providers in addition to the reflection and UI options:

- `content.assetVersion(versionId)` returns a live, archivable Model template created in this bridge's environment, or nil for unavailable content. `InsertService:LoadAssetVersion` validates the version ID, clones the template on each call and parents the result to InsertService. Missing providers, unavailable versions and invalid templates raise. The provider owns fixture acquisition and version mapping; the double performs no network fetch and invents no geometry.
- `content.terrainMaterialColor(material)` provides a captured Color3 for an unset terrain material. `Terrain:SetMaterialColor` stores per-terrain overrides and `GetMaterialColor` returns them before consulting the provider. Air, Water, other enum families and invalid colors raise. An unset material without a provider raises rather than inventing a default palette.

`placeEngine().record` keeps diagnostics and sends virtual timestamps and message types to LogService history and MessageOut. History returns independent tables. It keeps the newest 512 entries in order. ClearOutput clears history but keeps diagnostics. Structured Logger context is outside this simulation.

Sound Play, Pause, Resume and Stop update playback state and emit the corresponding events. Virtual time advances TimePosition at PlaybackSpeed. A positive TimeLength permits completion and loops. The simulator does not load sound media, find durations or prove audible playback.

`TweenService:Create(instance, tweenInfo, goals)` returns a Tween with `Instance`, `TweenInfo` and `PlaybackState`. Play, Pause and Cancel follow the engine states Begin, Delayed, Playing, Paused, Cancelled and Completed. Virtual time advances a playing tween. When `DelayTime` plus `Time` elapses, the tween writes each goal value once and fires `Completed` with `Enum.PlaybackState.Completed`. A tween that is within 1e-6 seconds of its end is complete. The tween writes no intermediate values, because the engine interpolates natively. Cancel resets progress, writes no goal and fires `Completed` with `Enum.PlaybackState.Cancelled`. Destroying a playing tween stops it. `RepeatCount` other than 0 and `Reverses` raise. The simulator does not prove easing curves or rendered motion.

TextChatService.OnIncomingMessage uses write-only callback storage. A host can inspect and invoke it through propertyOf. This does not prove filtered chat delivery.

Font faces without captured facts still raise errors. Give measured `ui.measureBounds`, `ui.truncateBounds` and `ui.measureText` adapters for the required operations. You can also capture facts with the [native text tool](running.md#capture-native-text-metrics). Verify never substitutes an unrelated face.

Truncation compares the rendered prefix and ellipsis with the available width, including fractional widths. An exact fit is accepted. The combined raster width is converted to a float32 result once. The shared Studio case checks widths on both sides of these boundaries.

### `Lute.gate`

Run the gate command line with bounded producer processes.

### `Lute.host`

Create a Lute worker host.

### `Lute.loader`

Load a mounted module tree into an explicit environment.

### `Lute.memory`

Collect heap observations through an explicit memory host.

### `Lute.model`

Read and write model source representations.

### `Lute.openCloud`

Submit, observe and reconcile authorized Open Cloud execution.

### `Lute.parse`

Parse worker wire output.

### `Lute.place`

Build or bundle mounted source trees into XML fixtures.

### `Lute.platform`

Dispatch a case entry to the selected simulator or native host.

### `Lute.player`

Run cases through a caller-selected Player backend.

### `Lute.selfRegisteringWorker`

Run worker modules that register their own cases.

### `Lute.studio`

Launch or attach Studio execution sessions.

### `Lute.typePolicy`

Find explicit `any` annotations (`explicitAny`) and files that weaken strict typing (`nonStrict`). Consumers use it for type budgets.

### `Lute.worker`

Run the worker protocol over registered sources.

### `Roblox.assertInstance`

Assert that a value is a simulated instance.

### `Roblox.bootPlace`

Boot a place using explicit engine operations and mounted sources.

### `Roblox.buildPlaceTree`

Build the simulated instance tree for a mounted place.

### `Roblox.createPlaceCache`

Create a cache for mounted place sources.

### `Roblox.createPlaceRuntime`

Create a place runtime with explicit engine bindings.

### `Roblox.datatypes`

Simulated Roblox datatype constructors and catalog.

### `Roblox.environmentEngine`

Adapt a simulated environment to the place engine contract.

### `Roblox.experienceHost`

Coordinate experience observations through explicit host operations.

### `Roblox.fixtureBridge`

Bridge reflection facts and behavior adapters into a fixture.

### `Roblox.inputHost`

Host adapter for explicit input observations.

### `Roblox.instanceHost`

Host adapter for instance observations.

### `Roblox.isInstance`

Test whether a value is a simulated instance.

### `Roblox.multiplayer`

Coordinate declared multiplayer roles and observations.

### `Roblox.network`

Network observation and validation helpers.

### `Roblox.performance`

Roblox performance observation helpers.

### `Roblox.playerHost`

Host adapter for player observations.

### `Roblox.progressChannel`

Transport progress events between host contexts.

### `Roblox.reflection`

Decode and query reflection facts.

### `Roblox.reflectionSnapshot`

Build and inspect frozen reflection snapshots.

### `Roblox.reportChannel`

Transport reports between host contexts.

### `Roblox.testEnvironment`

Create an isolated simulated environment.

### `Roblox.typeName`

Return a simulated value's Roblox type name.

### `Roblox.uiAudit`

Collect, decode and analyze UI facts with explicit rules.

### `Roblox.uiFakes`

Explicit UI behavior doubles used with reflection facts.

## Repository checks

The Lute-only `src/checks` package returns findings without exiting. Configuration, behavior and contract falsifiers are defined in [repository checks](checks.md).

### `Checks.walk`

Sorted file traversal, subtree exclusion and source line lookup.

### `Checks.temporaryDirectory`

Unique scoped temporary directories with cleanup on return or error.

### `Checks.denylist`

Parameterized rule scanning with exact path exemptions and literal allowances.

### `Checks.boundary`

Check source roots against configured host/domain rules.

### `Checks.leakage`

Check Git-selected repository files against configured leakage rules.

### `Checks.noAny`

Require strict maintained Luau and reject explicit dynamic type escapes.

### `Checks.specStyle`

Reject colon case registration, context expectations and dotted `Test.it`, `Test.expect` or `Test.describe` calls in `*.verify.luau` files, so specs declare `describe`, `it` and `expect` once. Takes the same selection as `Checks.noAny`; `exclude` names files whose subject is the raw harness API.

### `Checks.testManifest`

Compare or write a manifest against configured corpus discovery.

### `Checks.publicSurface`

Compare caller-loaded public exports with configured API documentation.

### `Checks.comments`

Check or rewrite prohibited source/config comments with explicit allowances.

### `Checks.provenance`

Validate license text, dependency provenance and configured source/notice policy.

### `Checks.cleanClone`

Require clean HEAD and run a configured gate in a disposable exact-HEAD clone.

### `Checks.lintRules`

Lute rules for shared globals, misplaced type comparisons and invalid string escapes.

See the [terms](README.md#terms) for shared technical names.

## Type imports

Types are defined beside their implementation. For example, `src/lute/studio` exports `Options` and `HostOptions`. `src/roblox/fixture-bridge` exports `Options`. Root packages expose selected aliases. Use the defining module for other types.
