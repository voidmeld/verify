# Verify

Verify is a testing and verification library for Luau. It gives you one model for every check: the case.
A unit test, an engine check in Roblox Studio, a multiplayer scenario and a benchmark are all cases.
Each case uses the same context, the same assertions and the same result states. Each run produces the same structured report.

One model has these benefits:

- You learn one way to write a check. No host and no kind of check needs its own runner or its own assertion set.
- A case does not change when its host changes. The host supplies capabilities, and a case that needs a missing capability is reported as unsupported.
- One gate combines tests, commands, builds, benchmarks and native checks into one verdict.
- One report format records what passed, failed or could not run. A result that could not run never counts as a pass.

## Use cases

- Run cases on Lute, Lune, the simulator, Studio (launched or attached), a published Player or an Open Cloud task.
- Declare a gate over tests, commands, builds, benchmarks and native checks, with tiers, selection, deferrals and an acceptance verdict.
- Benchmark a workload with warmup, phases, sampling, baselines, stored-run comparison and stability checks.
- Seal and validate evidence: run, build, device and review provenance on a report.
- Simulate Roblox instances, input, multiplayer and UI with the simulator and the Lune fixture bridge.
- Split a test corpus across bounded worker processes and combine their reports.
- Check consumer specifications and production graphs with `verify-check`.

## Getting started

1. Install the pinned tools: `rokit install`.
2. Pin Verify. Use one exact commit of `https://github.com/voidmeld/verify.git`. Record its commit and tree hash in your repository. Require the public roots under its `src` directory.
3. Write a case and run it. This is the complete file [examples/quickstart.luau](examples/quickstart.luau):

```luau
--!strict

local process = require "@std/process"

local Verify = require "../src/core"

local harness = Verify.createHarness { now = os.clock }

harness:case("adds numbers", function(context)
	context:expect(2 + 2):toBe(4)
end)

local report = harness:run {
	executor = "quickstart",
	capabilities = {},
	environment = { revision = "working-tree" },
}
print(Verify.format(report))
if report.passed ~= report.total then
	process.exit(1)
end
```

Run it with `lute run examples/quickstart.luau`. The command prints one passing case.
To run cases on Studio, a Player or Open Cloud, follow the [run guide](docs/running.md).

## Documentation

| Document | Owns |
| --- | --- |
| [Run cases](docs/running.md) | Commands, hosts, evidence files and the repository gate. |
| [API](docs/api.md) | Public calls, types and report semantics. |
| [Execution](docs/execution.md) | Plans, workers, gates and external hosts. |
| [Experience verification](docs/experience.md) | One case model for Roblox hosts, benchmarks and simulation. |
| [Laws](docs/laws.md) | Lifecycle and evidence rules, with the tests that detect a violation. |
| [Consumer diagnostics](docs/lint.md) | Lint policy and `verify-check`. |
| [Consumer skill](.agents/skills/verify/SKILL.md) | How another repository adopts Verify. |
| [Contributor guide](AGENTS.md) | How to change and validate this repository. |

## Packages

| Public entry point | Use |
| --- | --- |
| [`src/core`](src/core) | Harness, assertions, sessions, plans, execution, typed operations, evidence types and reports. |
| [`src/gate`](src/gate) | Declarative gates: producers, deadlines, selection, acceptance and test sharding. Host side only. |
| [`src/benchmark.luau`](src/benchmark.luau) | Warmup, sampling, baseline and stability checks, reported as an ordinary case. Host side only. |
| [`src/evidence`](src/evidence) | Sealing and validating provenance on a report. Host side only. |
| [`src/bdd.luau`](src/bdd.luau) | BDD verbs, case metadata and report printing over the same harness. |
| [`src/lune`](src/lune) | The Lune host, Lune workers and the native-database fixture bridge. |
| [`src/runtime`](src/runtime) | Runtime-neutral worker, host, receipt and file logic. |
| [`src/lute`](src/lute) | The run command, evidence bundles, fixture mounting, bounded workers, Studio or Player launch and window capture. |
| [`src/roblox`](src/roblox) | Instance, input and multiplayer hosts, observation and report adapters, reflection, UI fakes and the simulator. |
| [`src/host`](src/host) | Deterministic execution host for failure injection. |
| [`src/consumer`](src/consumer) | Portable specification and production graph diagnostics. |

## Validate

Run `lute run tools/gate.luau`. The [run guide](docs/running.md#repository-gate) lists the options that narrow it.

## License

Copyright © 2026 voidmeld. [MIT License](LICENSE). [Provenance](PROVENANCE.md) states the source and tool boundaries.
