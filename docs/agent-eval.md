# Agent evaluation

Verify reads saved coding-agent runs, decodes transcripts, plans suites and compares captured screenshots. Consumers own agent execution, hidden checks, credentials, evidence destinations and acceptance policy. The package is [`src/agent-eval`](../src/agent-eval).

## Saved runs

`AgentEval.decodeSuite(value, path, loader)` validates suite and task schemas. `AgentEval.plan(suite, loader)` produces the deterministic task, arm, agent and seed order. `AgentEval.lute.loader()` provides file, JSON and hashing helpers.

`AgentEval.load(evidence, files, decode)` reads `index.json` and decodes each referenced `result.json`. Missing files and malformed results raise. `AgentEval.result.decode(value)` validates one saved run. A saved run retains its identity, status, budgets, metrics, hidden check outcomes and captures. A completed agent alone does not establish a passed run.

`AgentEval.transcript.parseClaudeStream(lines, decode)` and `parseCodexStream(lines, decode)` decode timed output lines. Missing timing stays unavailable. `AgentEval.adapters.parseStamped(text)` reads optional timestamp prefixes. `AgentEval.lute.services(options?)` supplies bounded command execution, files, HTTP and timing; its stamped command path preserves arrival times even when the child times out. Consumers supply agent execution and Studio provisioning.

## Judging

`AgentEval.judge.comparisons(suite, results)` builds paired screenshot comparisons. `AgentEval.judge.run(options)` performs blind presentations and saves judgments. `AgentEval.judge.load(evidence, files, decode)` validates saved judgments. Model, transport and rubric identities bind cached judgments to their inputs.

`AgentEval.judge.codexCli(options)` builds a Codex judge transport with an explicit command executor, file binding, directory, encoder and decoder. `claudeCli` and `anthropic` supply the other retained transports. Callers own commands, credentials and authorization. The command executor receives a finite deadline. It must preserve that bound and command output.

`AgentEval.judge.decodeLabels`, `decodeRubric` and `calibrate` support independent human labels and calibration. A valid presentation alone is not position-controlled evidence. Keep both presentations and all failures.

## Statistics and interface audit

`AgentEval.stats` provides medians, means, percentiles and seeded bootstrap intervals. Consumers own thresholds and acceptance reports. Samples describe the measured corpus; they establish no population claim by themselves.

`Roblox.uiAudit.collect` observes an interface tree. `Roblox.uiAudit.decode` validates saved dumps and `analyze` computes rule findings. These observations do not prove rendering, input quality or visual judgment.

See the [API reference](api.md#agent-evaluation) for the remaining exports and the [verification laws](laws.md) for evidence limits.
