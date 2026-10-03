# Verify

A case states a claim. An authorized executor runs it and returns a versioned receipt. Verify
provides isolated lifecycle, deterministic execution plans, strict reports and the host adapters
needed to collect observations. Consumers own authorization, destinations and release decisions.

Start with [a working case](examples/basic.luau), [the API](docs/api.md), or
[execution](docs/execution.md). Contributors follow [AGENTS](AGENTS.md) and run:

```console
lute run tools/gate.luau
```

Run the working case with `lute run examples/basic.luau`. It prints one passing case, then a
combined report with two intentional shard failures: a missing worker report and a malformed payload.
The example exits successfully to demonstrate receipt formatting. Follow the
[caller verdict contract](docs/api.md#corecreateharness) when building a gate.

The main test corpus runs through Verify's public harness and Lute worker APIs. A small independent
bootstrap check verifies successful execution, reported failures, registration errors and refusal
of empty discovery, including the runner's process exit. Run the corpus with `lute run tools/test.luau`.

| Root | Responsibility |
| --- | --- |
| `src/core` | Harness, sessions, plans, execution, observations, reports and transport |
| `src/bdd.luau` | BDD verbs over the same harness |
| `src/lute` | Worker processes, JSON, corpus and optional viewport inspection |
| `src/roblox` | Injected capture, transcript, place boot, observation sink and tier judgments |
| `src/host` | Deterministic host for behavioral failure injection |
| `src/consumer` | Portable specification and production graph diagnostics |

[The laws](docs/laws.md) define what a receipt establishes and what it cannot. Pin source by tree
hash. Moving a dependency pin is a separate consumer change. This public MIT framework carries no
credentials or publication service.
