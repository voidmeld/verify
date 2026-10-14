---
name: verify
description: Author, run and read workloads that consume Verify. Use it when a consumer needs the verification model, plans, capabilities or reports.
---

# Verify consumer guide

This skill guides a consumer through authoring, running and reading Verify workloads.
Verify provides the lifecycle and the reports.
The consumer owns the work, locator resolution, host operations, external changes and credentials.
A capability describes what a host can observe. It grants no permission.
The [terms](../../../docs/README.md#terms) define each word that this guide uses.

## Start

1. Find the public root that you need. The [README](../../../README.md#packages) lists every root.
2. Find the committed manifest or plan and a nearby specification.
3. Read the gate instructions of the consumer and the relevant [documentation entry](../../../docs/README.md).
4. Run `lute run tools/verify-check.luau --ruleset <generic|roblox> <source-root>` when the consumer provides that command.

Follow these rules:

- Do not import internal modules.
- Do not infer undocumented APIs.
- Do not use suffix discovery as a gate.
- Do not call an unsupported or narrowed run a pass.

## Route by task

| Task | Document |
| --- | --- |
| Run cases | [Run cases](../../../docs/running.md). Use the shared command. Do not copy launcher or report glue into the consumer. |
| Write a case | [API](../../../docs/api.md) |
| Build a plan, host, worker, retry, fixture or selection policy | [Execution](../../../docs/execution.md) |
| Run the same case locally and in Roblox | [One case model](../../../docs/experience.md#one-case-model). Do not create a second case authoring model. |
| Test Roblox UI or engine code under Lute | [Reflection snapshots](../../../docs/api.md#reflection-snapshots) and [datatypes](../../../docs/api.md#datatypes). Export and commit a snapshot from Studio. Give code under test the datatype `typeof`. |
| Implement a host | [Host boundary](../../../docs/execution.md#host-boundary) |
| Seal or judge host observations | [Host observations](../../../docs/api.md#host-observations) and [evidence provenance](../../../docs/api.md#evidence-provenance) |
| Read a report or its claim | [API](../../../docs/api.md) and [laws](../../../docs/laws.md) |
| Evaluate coding agents or audit a Roblox interface | [Agent evaluation](../../../docs/agent-eval.md). Supply the tasks, arms, hidden checks and thresholds. Do not add a second runner or report. |

## Finish

1. Run focused checks for the assigned claim.
2. Run the complete gate of the consumer once on the final bytes. Do not repeat an unchanged gate.
3. Check provenance, source-loading failures, declared capabilities and limitations.
4. If a capability or a setup is missing, do not claim the affected result. Report the cause.
5. Report the exact checks and exit codes, the report path, the covered claims and the remaining gaps.

A passing count alone does not prove a complete claim.

## Evaluate agents

1. Write the suite file, one task directory for each task and the thresholds file. The [agent evaluation](../../../docs/agent-eval.md) document gives each schema.
2. Keep hidden checks in the task directory. Write screenshots to `{captures}/<device>/<screen>.png` and interface dumps from `Roblox.uiAudit.collect` to `{outputs}`.
3. Run `plan`, then `run`, `judge` and `report`. Commit the thresholds before the first `run`.
4. Report the verdict, the paired task count, the calibration and the limitations. A `PASS` covers the corpus, not every task.
