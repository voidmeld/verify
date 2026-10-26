# Terms

See the [Verify README](../README.md) to select a task.

| Term | Meaning |
| --- | --- |
| consumer | A repository or program that uses Verify. It owns discovery, authorization, destinations and acceptance. |
| caller | The code that calls a Verify function. The caller is the consumer or a host adapter of the consumer. |
| case | One named check with an isolated lifecycle. |
| report | The structured record of a run. It states what passed, failed, was skipped or could not run. |
| host | A system that runs cases: the simulator, Lute, Studio, Player or Open Cloud. |
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
| receipt | The run-bound envelope that a native host returns with its report. |
