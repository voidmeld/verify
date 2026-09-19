---
name: verify
description: Author, run, and read workloads that consume Verify; use when a consumer needs its verification model, plans, capabilities, or receipts.
---

# Verify consumer guide

This skill guides a consumer through authoring, running, and reading Verify workloads. Verify
provides lifecycle and receipts, and the consumer owns the work, locator resolution, host
operations, external changes, and credentials.
A capability describes what a host can observe. It does not grant permission.

## Start

1. Find the public root (`src/core`, `src/bdd.luau`, `src/lute`, `src/host`, `src/roblox`, or
   `src/consumer`), the committed manifest or plan, and a nearby specification.
2. Read the consumer's gate instructions and the relevant [documentation entry](../../../docs/README.md).
3. Run `lute run tools/verify-check.luau <source-root>` when the consumer provides that command.

Do not import internal modules or infer undocumented APIs. Do not use suffix discovery as a gate.
Do not call an unsupported or narrowed run a pass.

## Route by task

- Write a case: [API](../../../docs/api.md).
- Build a plan, host, pool, retry, fixture, or selection policy: [Execution](../../../docs/execution.md).
- Implement an executor: [Execution](../../../docs/execution.md#engine-and-external-execution).
- Seal or judge remote observations: [API](../../../docs/api.md#remote-observations).
- Read a receipt or its claim: [API](../../../docs/api.md) and [Laws](../../../docs/laws.md).

## Finish

Run the consumer's complete gate. A passing count alone does not prove a complete claim.
Check provenance, source-loading failures, declared capabilities, and stated limitations.
