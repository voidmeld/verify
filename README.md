# Verify

Verify is a test library for Luau. Each check is a case. Cases use one context and one report format. You can run cases on Lute, the simulator, Roblox Studio, Player or Open Cloud. A result that cannot run does not pass.

## First run

1. Install the tools: `rokit install`.
2. Run the [first case](examples/quickstart.luau): `lute run examples/quickstart.luau`.

The command prints one passing case. To use Verify in another repository, pin one exact commit of `https://github.com/voidmeld/verify.git`. Record its commit and tree hash. Follow the [consumer skill](.agents/skills/verify/SKILL.md).

## Documentation

Select a task. Each page contains the details for that task.

| Task | Document |
| --- | --- |
| Run cases and check this repository | [Run guide](docs/running.md) |
| Find public functions, types and report fields | [API reference](docs/api.md) |
| Use plans, workers, gates and external hosts | [Execution](docs/execution.md) |
| Use Roblox hosts, simulation and benchmarks | [Experience verification](docs/experience.md) |
| Read shared technical names | [Terms](docs/README.md) |
| Read the lifecycle and evidence rules | [Verification laws](docs/laws.md) |
| Configure repository checks | [Repository checks](docs/checks.md) |
| Check consumer code | [Lint policy](docs/lint.md) |
| Evaluate coding agents | [Agent evaluation](docs/agent-eval.md) |
| Give an agent access to one Studio | [Studio tools for an agent run](docs/scoped-studio-mcp.md) |
| Add Verify to a repository | [Consumer skill](.agents/skills/verify/SKILL.md) |
| Change Verify | [Contributor guide](AGENTS.md) |
| Read the source and license rules | [Provenance](PROVENANCE.md), [MIT License](LICENSE) |

The API reference defines public behavior. The laws define evidence requirements. Consumers control discovery, authorization, host operations, file destinations and release acceptance.

## Packages

Require one of these public roots. Do not require other modules under `src`. The [API reference](docs/api.md) lists each export.

| Root | Entry | Host | Use |
| --- | --- | --- | --- |
| `Core` | `src/core` | Any | Cases, sessions, assertions, reports and plans |
| `Bdd` | `src/bdd.luau` | Any | `describe` and `it` registration over Core |
| `Roblox` | `src/roblox` | Any | Engine double, datatypes, reflection, UI fakes and Roblox hosts |
| `Lute` | `src/lute` | Lute | Loader, fixtures, platform runs, Studio, Player and Open Cloud |
| `Codec` | `src/codec` | Any | Base64, PNG metadata and XML parsing |
| `Gate` | `src/gate` | Host side | Declarative gates and verdicts |
| `Evidence` | `src/evidence` | Host side | Evidence provenance, sinks and reviews |
| `Benchmark` | `src/benchmark.luau` | Host side | Benchmark cases, samples and comparisons |
| `Consumer` | `src/consumer` | Any | Consumer specification diagnostics |
| `AgentEval` | `src/agent-eval` | Lute | Coding-agent evaluation |
| `Checks` | `src/checks` | Lute | [Repository checks](docs/checks.md) |

## Check changes

Run `lute run tools/gate.luau --tier fast` to check a working tree. See the [repository gate](docs/running.md#repository-gate) for the full check and its limits.

Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup, checks and the pull request process.

Copyright (c) 2026 voidmeld.
