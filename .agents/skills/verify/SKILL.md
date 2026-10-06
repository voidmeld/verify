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
| Implement a host | [Host boundary](../../../docs/execution.md#host-boundary) |
| Seal or judge host observations | [Host observations](../../../docs/api.md#host-observations) and [evidence provenance](../../../docs/api.md#evidence-provenance) |
| Read a report or its claim | [API](../../../docs/api.md) and [laws](../../../docs/laws.md) |

## Finish

1. Run focused checks for the assigned claim.
2. Run the complete gate of the consumer once on the final bytes. Do not repeat an unchanged gate.
3. Check provenance, source-loading failures, declared capabilities and limitations.
4. If a capability or a setup is missing, do not claim the affected result. Report the cause.
5. Report the exact checks and exit codes, the report path, the covered claims and the remaining gaps.

A passing count alone does not prove a complete claim.
