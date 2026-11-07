# Verify

A test library for Luau and Roblox.

Verify runs tests, called cases, and writes one report format wherever they run: in a plain
Lute process on your machine or in CI, in Roblox Studio, in a Roblox Player, or through
Open Cloud. It ships a simulated Roblox engine, so code that reads instances, datatypes,
UI layout or input can be tested without opening Studio, and a set of hosts and gates for
the checks that do need the real engine. A report records what ran, where, and what could
not run; a case that could not run is never counted as a pass.

Verify is not a test runner for your whole project and not a CI system. It does not find
your test files, decide who may run them, or publish results. Your repository supplies
those parts; Verify supplies the cases, the assertions, the simulated engine, the hosts and
the reports.

First, run one case with the [quickstart](docs/quickstart.md).

## What is inside

| Area | What it provides | Reference |
| --- | --- | --- |
| Cases and sessions | A harness that registers cases, runs them in isolation and produces a report; `describe` and `it` on top | [Cases and sessions](docs/api.md#cases-and-sessions) |
| Assertions and spies | `expect` with matchers for values, tables, errors and datatypes; spies that record calls | [Assertions and spies](docs/api.md#assertions-and-spies) |
| Reports | One report shape, validation, combining reports, moving them between hosts | [Reports and transport](docs/api.md#reports-and-transport) |
| Execution plans | Splitting cases across workers and hosts, with deadlines and capabilities | [Execution plans](docs/api.md#execution-plans) |
| Simulated engine | Instances, properties, signals, datatypes, reflection, UI layout and style, input and spatial queries, with no Roblox process | [Simulated environment](docs/api.md#simulated-environment) |
| Roblox hosts | Running cases in Studio, Player and Open Cloud, and capturing native models and meshes for the simulator | [Host adapters](docs/api.md#host-adapters) |
| Gates and evidence | Declarative gates with verdicts, and evidence that records its source, host and review | [Declarative gates](docs/api.md#declarative-gates), [Evidence provenance](docs/api.md#evidence-provenance) |
| Benchmarks | Benchmark cases, samples and paired comparisons for time and retained memory | [Benchmarks](docs/api.md#benchmarks) |
| Memory | Retained-heap measurement that is stable across garbage collector timing | [`Lute.memory`](docs/api.md#lutememory) |
| Repository checks | Reusable checks for a Luau repository: types, lint, public surface, leaked secrets, provenance | [Repository checks](docs/api.md#repository-checks) |

## Example

One case, run on Lute with no engine:

```luau
local Verify = require(path.to.verify.core)

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
```

The printed report names the case, where it ran and the outcome. The same case can run
in Studio through a Roblox host and produce the same report shape.
[examples/quickstart.luau](examples/quickstart.luau) is the complete program.

## How it fits together

| Root | Entry | Runs on | Use |
| --- | --- | --- | --- |
| `Core` | [`src/core`](src/core) | Any Luau | Cases, sessions, assertions, reports and plans |
| `Bdd` | [`src/bdd.luau`](src/bdd.luau) | Any Luau | `describe` and `it` registration over Core |
| `Roblox` | [`src/roblox`](src/roblox) | Any Luau | The simulated engine, datatypes, reflection, UI fakes and Roblox hosts |
| `Lute` | [`src/lute`](src/lute) | Lute | Loader, fixtures, memory measurement, platform runs, Studio, Player and Open Cloud |
| `Codec` | [`src/codec`](src/codec) | Any Luau | Base64, PNG metadata and XML parsing |
| `Gate` | [`src/gate`](src/gate) | Host side | Declarative gates and verdicts |
| `Evidence` | [`src/evidence`](src/evidence) | Host side | Evidence provenance, sinks and reviews |
| `Benchmark` | [`src/benchmark.luau`](src/benchmark.luau) | Host side | Benchmark cases, samples and comparisons |
| `Consumer` | [`src/consumer`](src/consumer) | Any Luau | Diagnostics for a consumer's specifications |
| `AgentEval` | [`src/agent-eval`](src/agent-eval) | Lute | Coding-agent evaluation |
| `Checks` | [`src/checks`](src/checks) | Lute | Repository checks |

Require one of these roots. Modules under `src` that the API reference does not list are
internal. Core has no engine dependency.

## Install

Verify is pinned by commit, not by version. Choose a commit of
`https://github.com/voidmeld/verify.git`, record its commit and tree hash in your
dependency lock, and require the roots you use. The
[consumer skill](.agents/skills/verify/SKILL.md) walks through adopting it in a repository.
To work on this repository, install the tools with `rokit install`.

## Documentation

| Task | Document |
| --- | --- |
| Run the first case | [Quickstart](docs/quickstart.md) |
| Find public functions, types and report fields | [API reference](docs/api.md) |
| Run cases and check this repository | [Run guide](docs/running.md) |
| Use plans, workers, gates and external hosts | [Execution](docs/execution.md) |
| Use Roblox hosts, simulation and benchmarks | [Experience verification](docs/experience.md) |
| Read shared technical names | [Terms](docs/README.md) |
| Read the lifecycle and evidence rules | [Verification laws](docs/laws.md) |
| Configure repository checks | [Repository checks](docs/checks.md) |
| Check consumer code | [Lint policy](docs/lint.md) |
| Evaluate coding agents | [Agent evaluation](docs/agent-eval.md) |
| Give an agent access to one Studio | [Studio tools for an agent run](docs/scoped-studio-mcp.md) |
| Add Verify to a repository | [Consumer skill](.agents/skills/verify/SKILL.md) |
| Change this repository | [Contributor guide](AGENTS.md) and [contributing](CONTRIBUTING.md) |

## Compatibility

The supported unit is an exact commit and tree; there is no semantic-version promise.
The API reference defines public behavior, and the [laws](docs/laws.md) define what a
report must contain. A contract changes together with its consumers. Your repository
decides which cases exist, who may run them, where reports go and what counts as a
release.

## License

Copyright (c) 2026 voidmeld. [MIT License](LICENSE). [Provenance](PROVENANCE.md) records
the source and license rules.
