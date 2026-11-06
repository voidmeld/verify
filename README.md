# Verify

Verify is a test library for Luau. Each check is a case. Cases use one context and one report format. You can run cases on Lute, the simulator, Roblox Studio, Player or Open Cloud. A result that cannot run does not pass.

## First run

Follow the [quickstart](docs/quickstart.md) to install Verify, run a passing case and read its report.

## Documentation

Select a task. Each page contains the details for that task.

| Task | Document |
| --- | --- |
| Install Verify and run a first case | [Quickstart](docs/quickstart.md) |
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

The [API setup](docs/api.md#shared-setup) lists the public package roots.
For repository edits, start with [AGENTS.md](AGENTS.md), then follow [CONTRIBUTING.md](CONTRIBUTING.md).

Copyright (c) 2026 voidmeld.
