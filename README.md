# Verify

A case states a claim. An authorized executor runs it and returns a versioned receipt. Verify
provides isolated lifecycle, deterministic execution plans, strict reports and the host adapters
needed to collect observations. Consumers own authorization, destinations and release decisions.

Start with [a working case](examples/basic.luau), [the API](docs/api.md), or
[execution](docs/execution.md). Contributors follow [AGENTS](AGENTS.md) and run:

```console
lute run tools/gate.luau
```

| Root | Responsibility |
| --- | --- |
| `src/core` | Harness, sessions, plans, execution, observations, reports and transport |
| `src/bdd.luau` | BDD verbs over the same harness |
| `src/lute` | Worker processes, pool, JSON, corpus and optional viewport inspection |
| `src/roblox` | Injected capture, transcript, place boot, observation sink and tier judgments |
| `src/host` | Deterministic host for behavioral failure injection |
| `src/consumer` | Portable specification and production graph diagnostics |

[The laws](docs/laws.md) define what a receipt establishes and what it cannot. Pin source by tree
hash; moving a dependency pin is a separate consumer change. This public MIT framework carries no
credentials or publication service.
