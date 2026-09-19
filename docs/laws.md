# Verification laws

A claim consists of a named case, the observations it judges, and a receipt from its executor.
A recorded verdict is evidence of that execution, never authority to publish or proof of another
artifact.

| Law | Behavioral falsifier |
| --- | --- |
| Each harness/source owns its registry. Reset or reentry cannot erase queued work. | `tests/core.spec.luau`, `tests/foundation.spec.luau` |
| Setup, case, teardown and cleanup failures remain independently visible. Cleanup runs once, newest first. | `tests/core.spec.luau`, `tests/worker.spec.luau` |
| Missing capability is unsupported; deliberate omission is skipped. Neither passes. Empty, partial and focused runs cannot establish complete acceptance. | `tests/core.spec.luau`, `tests/execution.spec.luau`, `tests/foundation.spec.luau` |
| A plan accounts for every unit and attempt. Host failures, missing/duplicate results and disagreeing retries cannot become green. | `tests/execution.spec.luau`, `tests/pool.spec.luau` |
| Receipts retain source, executor, environment, failures and limitations. Malformed counts, schema drift, truncated/mixed/conflicting transport and duplicate cases fail closed. | `tests/core.spec.luau`, `tests/foundation.spec.luau`, `tests/adapters.spec.luau` |
| Sealing freezes observations; only the harness judges them. It does not authenticate the collector. | `tests/foundation.spec.luau`, `tests/tier-ladder.spec.luau` |
| Capture and transcript selection require the intended current source. Stale, absent, ambiguous, wrong-target and repeated evidence cannot silently qualify. | `tests/scenario-runner.spec.luau`, `tests/witness-host.spec.luau`, `tests/viewport-corners.spec.luau`, `tests/tier-ladder.spec.luau` |
| Host operations require caller-supplied capability and authority. A limitation never excuses an observed defect. | `tests/consumer.spec.luau`, `tests/tier-ladder.spec.luau` |

Core has no I/O, engine, ambient scheduler or credential dependency. Inject time when testing it.
Portable module graphs must resolve in the engine tree; `tests/requires.spec.luau` checks the actual
closure. Fake place/instance hosts test declared behavior and refusal paths, not engine truth.

The gate runs format, lint, types, behavioral tests and source-boundary checks on current bytes.
It does not execute Studio or Player, authenticate an image, establish audio/input quality, measure
production performance, or prove the caller's expected claims are complete. An adopter must bind
its real run, source/tree, destination and artifact bytes, then retain the current result in its own
operation record. Laws cannot substitute for those observations.
