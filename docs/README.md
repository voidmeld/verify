# Verify contracts

Read the documents in this order:

1. [Run cases](running.md): hosts, commands, evidence files, the repository gate and platform support.
2. [API](api.md): cases, assertions, reports, plans, evidence, the simulator and the fixture bridge.
3. [Execution](execution.md): plans, workers, gates, native hosts and report transport.
4. [Experience verification](experience.md): one case model for native actors, simulated networking and benchmarks.
5. [Laws](laws.md): lifecycle and evidence rules, with the tests that detect a violation.
6. [Consumer diagnostics](lint.md): lint policy and portable specification checks.
7. [Source rights](../PROVENANCE.md): original source, MIT grant and public distribution.

[AGENTS](../AGENTS.md) owns the contribution procedure.
The [consumer skill](../.agents/skills/verify/SKILL.md) owns the adoption procedure.
A document describes a contract. Only a run produces evidence.

## Choose an entry point

| Goal | Use |
| --- | --- |
| Write cases in one file and get a report | `Core.createHarness`, then `harness:run`. |
| Write cases with `describe` and `it`, or load cases from many source files | `Bdd.surface`. |
| Run named cases on the simulator, Studio, a Player or Open Cloud | `tools/run.luau`, or `Lute.platform.run` from code. |
| Run a whole corpus in worker processes | A `tests` producer of a gate. |
| Check a repository with tests, commands, builds and benchmarks | `Gate.define`, then `Lute.gate.run` or `Lune.gate.run`. |
| Measure a workload | `Benchmark.case` or `Benchmark.collection`. |

`Core.createSession`, workers and hosts are the lower layers that these entry points use. Call them directly only to build a custom host.

## Terms

Each document uses these terms with one meaning.

| Term | Meaning |
| --- | --- |
| consumer | A repository or program that uses Verify. It owns discovery, authorization, destinations and acceptance. |
| caller | The code that calls a Verify function. The caller is the consumer or a host adapter of the consumer. |
| case | One named check with an isolated lifecycle. |
| report | The structured record of a run. It states what passed, failed, was skipped or could not run. |
| host | A system that runs cases: the simulator, Lute, Lune, Studio, Player or Open Cloud. |
| capability | A statement of what a host can observe or do. It grants no permission. |
| actor | A named participant in a case, such as a client or the server. |
| checkpoint | A named point in a case where a host records an observation for an actor. |
| observation | A value that a host returns for an action, a query or a checkpoint. |
| capture | An image or other output that a host saves at a checkpoint. |
| artifact | A reference to a saved capture, with optional content hash and provenance. |
| evidence | The observations, artifacts and reviews that a report carries for a case. |
| plan | A finite set of units, declared capabilities and policy that Verify executes. |
| gate | A declared set of producers with an acceptance verdict. |
| producer | One unit of work in a gate: tests, a command, a build, a benchmark or a native check. |
| receipt | The run-bound file or envelope that a worker returns with its report. |
