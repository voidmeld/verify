# Verify census

Status: proposal. Nothing is removed yet.

## Method

- Each tracked module under `src` was checked for a requirer: a `require` in
  `src`, `tests`, `tools` or `examples`, or a path that code loads at run
  time.
- The gate outcomes on this host were read: 1,351 outcomes under
  `.lute/tmp/verify-gate` in the main checkout and the worktrees. Most are
  the gate's own test fixtures. The 19 producers of `tools/gate.luau` were
  counted separately.

## Modules

| Module | Requirers | Recommendation |
| --- | --- | --- |
| `src/agent-eval/stamp.luau` | Run by path from `src/agent-eval/lute.luau` (the POSIX output pipe). | Keep. |
| `src/lute/tree-watchdog.luau` | Run by path from `src/lute/runtime.luau` (the Windows bounded runner). | Keep. |
| `src/roblox/reflection-capture.luau` | Read by path from `src/lute/studio-reflection.luau`. | Keep. |

Every module has a requirer.

## Gate producers

| Producer | Failures in the history | Class | Recommendation |
| --- | ---: | --- | --- |
| `specs` | 240 of 1,167 | behavior | Keep. |
| `types` | 10 of 65 | contract | Keep. |
| `format` | 1 of 54 | form | Keep. |
| `lint` | 0 of 55 | form | Keep. It is cheap. |
| `type-policy` | 0 of 50 | form | Merge into one `policy` producer with `test-bootstrap`, `boundary`, `dependencies`, `provenance` and `comments`. Each keeps its own finding text. |
| `test-bootstrap` | 0 of 47 | form | Merge into `policy`. |
| `boundary` | 0 of 47 | form | Merge into `policy`. |
| `dependencies` | 0 of 47 | form | Merge into `policy`. |
| `provenance` | 0 of 47 | form | Merge into `policy`. |
| `comments` | 0 of 47 | form | Merge into `policy`. |
| `consumer-diagnostics` | 0 of 47 | behavior | Keep. It runs the consumer rule set on the examples. |
| `example-experience`, `example-quickstart`, `example-evidence`, `example-benchmark`, `example-agent-eval` | 0 each | behavior | Merge the eight example producers into one `examples` producer that runs each example and reports each by name. |
| `example-attachments`, `example-multiplayer` | 1 each | behavior | Merge into `examples`. |
| `example-gate` | 2 of 47 | behavior | Merge into `examples`. |
| `native-conformance`, `native-multiplayer` | 0 of 1 each | behavior | Keep. They are the only engine evidence. |

The merges keep every comparison. They change 19 producers to 9: `specs`,
`types`, `format`, `lint`, `policy`, `consumer-diagnostics` and `examples`,
and the two native producers.
