# Verification laws

A claim consists of a named case, the observations it judges, and a report from its host.
A recorded verdict provides evidence of that execution. It grants no publication authority and proves nothing about another artifact.

| Contract | Tests that can detect a violation |
| --- | --- |
| Each harness and each source owns its registry. A reset or a reentry cannot erase queued work. | [tests/core.spec.luau](../tests/core.spec.luau), [tests/foundation.spec.luau](../tests/foundation.spec.luau) |
| Setup, case, teardown and cleanup failures stay visible independently. Cleanup runs once, newest first. | [tests/core.spec.luau](../tests/core.spec.luau), [tests/worker.spec.luau](../tests/worker.spec.luau) |
| A missing capability is `unsupported`. A deliberate omission is `skipped`. Neither passes. An empty, partial or focused run cannot establish complete acceptance. | [tests/core.spec.luau](../tests/core.spec.luau), [tests/execution.spec.luau](../tests/execution.spec.luau), [tests/foundation.spec.luau](../tests/foundation.spec.luau) |
| A plan accounts for every unit and every attempt. A host failure, a missing result, a duplicate result or a disagreeing retry never passes. | [tests/execution.spec.luau](../tests/execution.spec.luau), [tests/worker.spec.luau](../tests/worker.spec.luau) |
| A gate accounts every declared producer and, with a declared census, every case. A selected run is never complete, even when it deselected cases, and it states its scope. An exit-zero producer needs a report from the current run. An unsupported host or an unpermitted deferral never passes. A benchmark keeps raw samples and reports an invalid run as such. | [tests/gate.spec.luau](../tests/gate.spec.luau), [tests/lute-gate.spec.luau](../tests/lute-gate.spec.luau), [tests/benchmark.spec.luau](../tests/benchmark.spec.luau) |
| A report retains its source, executor, environment, failures and limitations. Malformed counts, schema drift, duplicate cases and truncated, mixed or conflicting transport fail. | [tests/core.spec.luau](../tests/core.spec.luau), [tests/foundation.spec.luau](../tests/foundation.spec.luau), [tests/adapters.spec.luau](../tests/adapters.spec.luau) |
| Evidence is current, comes from the declared build and is intact when Verify hashes it again from the sink of the caller. It covers every required case, actor, checkpoint and device class. A required review names the exact artifacts that it judged. Metadata never proves quality or physical-device use. A sink outage never passes. | [tests/evidence-provenance.spec.luau](../tests/evidence-provenance.spec.luau) |
| A wait names the condition, how long it waited and the last observed state when it times out or is cancelled. Polling repeats no mutation. Only a host that can kill the work enforces a bound. | [tests/wait.spec.luau](../tests/wait.spec.luau), [tests/bounded.spec.luau](../tests/bounded.spec.luau) |
| Every host uses the ordinary case context and failure classifier. Typed host observations survive report transport. Capture metadata claims no judgment. | [tests/semantic-execution.spec.luau](../tests/semantic-execution.spec.luau), [tests/instance-host.spec.luau](../tests/instance-host.spec.luau) |
| A simulated engine member that is declared but not implemented raises `unsupported_method`, unless a function or an explicit fake supplies the answer. A schema is never a behavior. Destroyed instances lock, disconnect and are counted. Time is virtual. | [tests/environment.spec.luau](../tests/environment.spec.luau) |
| Hierarchy events keep the old state during removal and show the final ancestry afterward. Reflection validation rejects a write before mutation. Explicit fakes own UI behavior. | [tests/environment.spec.luau](../tests/environment.spec.luau) |

Core has no I/O, engine, ambient scheduler or credential dependency. Inject time when you test it.
Portable module graphs must resolve in the engine tree. [tests/requires.spec.luau](../tests/requires.spec.luau) checks the actual closure.
Fake place hosts and fake instance hosts test declared behavior and refusal paths. They do not test engine behavior.

The gate runs format, lint, types, behavioral tests and source-boundary checks on current bytes.
The portable gate does not run the reference Studio conformance cases. Add `--native` to run them.
Neither gate authenticates an image, establishes audio or input quality or measures production performance.
Neither gate proves that the expected claims of the consumer are complete.
The consumer must bind its real run, source tree, destination and artifact bytes.
The consumer must keep the current result in its own records. These laws do not replace those observations.
