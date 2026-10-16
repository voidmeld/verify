# Agent evaluation

The UI audit reports `text-overlap` when visible text bounds intersect unrelated
text or an action. It uses native text alignment and clips the bounds to the
visible region. A text child inside its own action is allowed. `action-covered`
reports an interactable action below an active full-screen backdrop. Disable
background actions while a modal is open. A saved dump checks geometry and
selection policy. Real input still needs a live host check.

An agent evaluation runs coding agents on a corpus of tasks and compares two or more arms.
An arm is one setup that the agents get, for example a set of files, instructions and tools.
Verify provisions each run, runs the agent with a deadline, records the transcript, runs hidden checks after the agent exits, audits the Roblox interface, judges screenshots and evaluates statistics against thresholds that you declare before the runs.
The consumer owns the tasks, the arms, the hidden checks, the credentials, the thresholds and the claim.

The package is [`src/agent-eval`](../src/agent-eval). It runs on Lute. The interface audit is in the engine-mountable package [`src/roblox`](../src/roblox).
The [example](../examples/agent-eval) is a complete corpus that runs with no network and no agent.

## Terms

| Term | Meaning |
| --- | --- |
| suite | The file that names the tasks, arms, agents, seeds, budgets and devices of one evaluation. |
| task | One unit of work: a brief, a starter workspace or an earlier task, and hidden checks. |
| arm | A named setup: overlay files, instructions, an MCP configuration and tool permissions. |
| agent | An adapter and a model, for example the Claude Code command line with one model. |
| run | One task, arm, agent and seed. Each run has its own workspace and evidence directory. |
| seed | The number of a repetition. It orders the runs and the judge. An agent command line accepts no sampling seed, so a seed does not make a run repeatable. |
| hidden check | A command, a Verify report or an interface audit that runs after the agent exits. |
| follow-up | A task that starts from the final workspace of an earlier task in the same arm, agent and seed. |
| judgment | A blind comparison of the screenshots of two arms for one task, device, agent and seed. |
| threshold | A rule that a bound of a confidence interval must pass. |

## Commands

```sh
lute run tools/agent-eval.luau plan   --suite eval.json
lute run tools/agent-eval.luau run    --suite eval.json [--parallel 2] [--task id] [--arm id] [--agent id] [--seed n] [--fresh]
lute run tools/agent-eval.luau judge  --suite eval.json [--transport api|cli] [--model id] [--effort level]
lute run tools/agent-eval.luau report --suite eval.json --thresholds thresholds.json [--labels labels.json] [--verify-report path --run id]
lute run tools/agent-eval.luau audit  dump.json [--out audit.json]
```

- `plan` lists the runs in order with their digests. It runs nothing.
- `run` executes the runs. It exits 1 when a run could not start, otherwise 0. A failed check does not change the exit code.
- `run --checks-only` repeats hidden checks and audits on completed saved workspaces. It calls no agent or Studio provisioning adapter. Agent metrics, transcripts, timestamps and build files stay as recorded. A missing saved result or workspace is an error. It archives the previous result, checks and captures under `rechecks/<clock>` before starting. The saved digest still identifies the original agent run.
- `judge` compares the screenshots. With `--transport api` it reads the key from `ANTHROPIC_API_KEY`. Only the command line reads this variable. The library takes the key as an argument.
- `report` writes `report.json` and `report.md`. It exits 0 for `PASS` and 1 for `FAIL`. `--verify-report` also writes the verdict as an ordinary Verify report in the `{ runId, report }` envelope, so a gate producer can require it.
- `audit` scores one interface dump.

`--evidence` sets the evidence directory. The default is `evidence` in the suite file, or `.verify/agent-eval/<suite id>`.
`--workspaces` sets the parent of the live workspaces. The default is `verify-agent-eval` in the system temporary directory.
`AgentEval.cli(args, context)` is the same command line for a consumer script.

## Suite file

| Field | Required | Meaning |
| --- | --- | --- |
| `schemaVersion` | yes | `1`. |
| `id` | yes | An identifier. |
| `tasks` | yes | Task directories relative to the suite file. Each directory holds `task.json`. |
| `arms` | yes | Arms. Each arm has `id` and the arm setup fields below. |
| `agents` | yes | Agents: `{ id, adapter, model?, options? }`. |
| `seeds` | no | Whole numbers. The default is `[1]`. |
| `parallelism` | no | The number of runs at the same time. The default is 1. |
| `evidence` | no | The evidence directory relative to the suite file. |
| `budgets` | no | Default budgets for each task. |
| `devices` | no | Default devices for each task. |
| `judge` | no | `{ model?, seed? }` for the `judge` command. |

An identifier has 1 to 64 letters, digits, `.`, `_` or `-`, and starts with a letter or a digit.
An unknown field fails the load. Every error names the field.

## Task file

| Field | Required | Meaning |
| --- | --- | --- |
| `schemaVersion` | yes | `1`. |
| `id`, `title` | yes | The identifier and a title. |
| `tier` | no | A label for grouping. The default is `default`. |
| `brief` | yes | A Markdown file. It is the prompt of the agent. |
| `starter` | one of two | A directory that Verify copies into the workspace. |
| `from` | one of two | The identifier of an earlier task. The run starts from the final workspace of that task. |
| `arms` | no | Setup for each arm, keyed by arm identifier. It adds to the setup of the suite arm. |
| `checks` | no | Hidden checks, in order. |
| `devices` | no | Devices. They replace the devices of the suite. |
| `budgets` | no | Budgets. Each field replaces the field of the suite. |

An arm setup has these fields. Paths are relative to the file that declares them.

| Field | Meaning |
| --- | --- |
| `overlay` | Files and directories that Verify copies over the starter, in order. |
| `instructions` | A Markdown file. The Claude Code adapter appends it to the system prompt. The Codex adapter sends it as developer instructions. |
| `mcp` | An MCP configuration file. Verify replaces `{workspace}` and `{evidence}` in it. |
| `studio` | A build command and place for [Studio MCP scoped to one run](scoped-studio-mcp.md). Cannot be combined with `mcp`. |
| `allowedTools`, `disallowedTools` | Tool names that the adapter passes to the agent. |
| `env` | Environment variables for the agent process. |

A device is `{ id, width, height, scale?, input?, safeArea? }`. `input` lists `touch`, `gamepad`, `mouse` or `keyboard`.
Budgets are `{ maxTurns?, maxOutputTokens?, maxCostUsd?, wallSeconds }`. The default wall time is 1800 seconds.

## Hidden checks

A check is `{ id, kind, argv?, required?, after?, deadlineSeconds?, env?, perDevice?, scores?, dump?, audit?, report? }`.

| Kind | Runs | Passes when |
| --- | --- | --- |
| `command` | `argv` as a gate command producer. | The command exits 0. |
| `verify` | `argv` as a gate command producer that writes a Verify report to `{report}` for the run `{run}`. Write it with `Lute.gate.writeReport`. | The command exits 0 and the report of this run passes. `report` takes `{ cases?, minimum?, exact? }`. The default minimum is one case. |
| `audit` | The [interface audit](#interface-audit) on the dump file `dump`. `audit` holds the audit options and `minScore`. | A dump exists and its score is at least `minScore`. |

Verify runs the command checks through one [gate](execution.md#declarative-gates) per run, with the workspace as the working directory, after the agent process exits.
The check files stay in the task directory. Verify never copies them into the workspace.
`after` names earlier checks. A check after a check that did not pass is `blocked`.
`perDevice` runs the check once for each device as `<check id>.<device id>`.
`required = false` records the check but does not affect the pass.
With `scores = true`, the command writes a JSON object of numbers to `{scores}`. The result keeps them as `<check id>.<name>`.

Verify replaces these placeholders in `argv`, `env` and `dump`:

| Placeholder | Value |
| --- | --- |
| `{workspace}` | The live workspace of the run. |
| `{task}` | The task directory. |
| `{evidence}` | The evidence directory of the run. |
| `{outputs}` | `{evidence}/checks`, for files that checks write. |
| `{captures}` | `{evidence}/captures`. Write screenshots to `{captures}/<device>/<screen>.png`. |
| `{scores}` | The scores file of the check. |
| `{seed}` | The seed. |
| `{devices}` | The ids of the task devices, separated by commas. |
| `{device}`, `{width}`, `{height}`, `{scale}`, `{input}` | The device of a `perDevice` check. |

The gate replaces `{report}` and `{run}`. The run placeholders do not name the arm.

## Runs

The plan is deterministic. For each seed, then each task, then each agent, it adds one run for each arm.
The arm order rotates by one position for each seed, so no arm always runs first.
A follow-up comes after its earlier task.

A run has these steps:

1. Verify copies the starter, or the final workspace of the earlier task, into a new live workspace. Then it copies each overlay.
2. It writes `prompt.md` and `mcp.json` to the evidence directory, outside the workspace.
3. It starts the agent adapter with the wall-time budget as the deadline. The deadline uses the [bounded runner](running.md#platform-support).
4. It writes the time-stamped output to `transcript.jsonl` and the standard error to `agent.stderr.txt`.
5. It runs the hidden checks, then the audits. It hashes each screenshot in `{captures}`.
6. It moves the workspace to `workspace` in the evidence directory and writes `result.json`.

After each run Verify writes `index.json`. Before the runs it writes `plan.json`.
A run passes only when the agent completed, every required check passed and no budget was exceeded.
A run that hits `maxTurns` completes. A run that exceeds `wallSeconds`, `maxOutputTokens` or `maxCostUsd` fails and names the budget in `exceeded`.
A follow-up whose earlier run has no result or no workspace is `blocked`.
An unknown adapter is `unsupported`. An adapter that raises is `provision_failed`, and its result still exists.

Each run has a digest of its identity, the task file, the brief, the files of the starter and the overlays, the instructions, the MCP configuration, the agent and the digest of the earlier run.
On a new `run`, Verify reuses a result with the same digest and runs everything else again. `--fresh` runs everything.
`--parallel` runs that many runs at the same time. A follow-up waits for its earlier run.

The workspace is a directory, not a sandbox. An agent with full permissions can read any file that its user can read.
Put the live workspaces outside the corpus and the evidence directory. The default temporary directory does this.

## Agent adapters

An adapter is `{ id, run(request, services) -> outcome }`.
The request holds the workspace, the prompt file, the instructions, the MCP configuration, the tools, the model, the budgets and the agent options.

`AgentEval.adapters.claudeCode(decode)` (adapter name `claude-code`) runs this command in the workspace and sends the brief on standard input:

```sh
claude -p --output-format stream-json --verbose [--model id] [--max-turns n] [--max-budget-usd x] \
  --permission-mode bypassPermissions [--mcp-config file] --strict-mcp-config --no-session-persistence \
  [--setting-sources list] [--effort level] [--append-system-prompt text] [--allowedTools list] [--disallowedTools list]
```

The agent options are `command`, `permissionMode`, `strictMcpConfig` (default true), `persistSession` (default false), `settingSources`, `effort` and `arguments`.
`--strict-mcp-config` loads only the MCP servers of the arm.
The Lute binding records the arrival time of each output line.
On Windows it starts the agent through Windows PowerShell, which feeds the prompt file, reads the output lines and records the exit code. It needs no other shell.
On other systems it pipes the agent output through [`stamp.luau`](../src/agent-eval/stamp.luau) with `sh` and `cat`. The `shell` option of `AgentEval.lute.services` selects this pipe on Windows too.
A line keeps its arrival time even when the run reaches its deadline.

`AgentEval.transcript.parseClaudeStream(lines, decode)` reads the stream:

| Value | Source |
| --- | --- |
| Turns | `num_turns` of the `result` event, or the number of distinct top-level assistant messages. |
| Tokens | The sum of `modelUsage` of the `result` event, else its `usage`, else the usage of each distinct message. Blocks of one message count once. |
| Cost, durations | `total_cost_usd`, `duration_ms` and `duration_api_ms` of the `result` event. |
| Turn latency | For each top-level assistant message, the time from the previous line to its first line. |
| Turn interval | The time between the first lines of two top-level assistant messages. |
| Tool time | The union of the intervals from each `tool_use` to its `tool_result`. |
| Status | `success`, `error` (another `result` subtype) or `incomplete` (no `result` event). |

Messages with a `parent_tool_use_id` count as subagent messages, not as turns.
Without arrival times, the latencies are empty and the tool time is absent.

`AgentEval.adapters.codex(decode)` (adapter name `codex`) runs the Codex command line in the workspace and sends the brief on standard input:

```sh
codex exec --json --skip-git-repo-check -C workspace [-m id] [--sandbox mode] [--ephemeral] \
  [-c model_reasoning_effort="level"] [-c developer_instructions="text"] [-c mcp_servers.name.field=value]... \
  [-c override]... [arguments]... -
```

The agent options are `command`, `effort`, `sandbox`, `persistSession` (default false), `config` (a list of `key=value` overrides) and `arguments`.
The adapter writes each server of the `mcpServers` object of the arm MCP configuration as `mcp_servers.<name>` overrides: `command`, `args` and `env`, or `url`.
Codex cannot restrict tools, so an arm with `allowedTools` or `disallowedTools` fails to provision.
Codex takes no turn or cost limit. The adapter enforces only the wall-clock budget. The runner checks `maxOutputTokens` after the run.

`AgentEval.transcript.parseCodexStream(lines, decode)` reads the JSON events:

| Value | Source |
| --- | --- |
| Turns | The model steps: one for each tool item and one for each `turn.completed` event. Parallel tool calls of one model response count as more than one step. |
| Tokens | The sum of the `usage` of the `turn.completed` events. Input is `input_tokens` minus `cached_input_tokens` and `cache_write_input_tokens`. Cache reads are `cached_input_tokens`, cache writes are `cache_write_input_tokens` and output is `output_tokens`. |
| Tools | Each `command_execution`, `file_change`, `mcp_tool_call`, `web_search` and `todo_list` item counts once. A failed or declined item, or a command with a nonzero exit code, is a tool error. |
| Turn latency, interval | For each model step, the time from the previous line, and the time from the previous step. |
| Tool time | The union of the intervals from `item.started` to `item.completed` of the tool items. |
| Status | `error` after `turn.failed`, `success` after `turn.completed`, `error` when only an `error` event arrived, otherwise `incomplete`. |
| Result | The text of the last `agent_message` item, or the message of the failure. |

Codex reports no cost, so the cost is absent.

`AgentEval.adapters.command({ id, argv, parse?, stamp?, stdin?, decode })` runs another agent command line.
`argv` can use `{prompt_file}`, `{workspace}`, `{model}`, `{max_turns}`, `{mcp_config}`, `{seed}` and `{evidence}`.
`AgentEval.adapters.replay({ respond, parse?, decode })` writes files into the workspace and returns recorded lines. Tests use it.
The adapter name `fixture` reads a recorded stream and files from the agent options `stream` and `files`, which can use `{arm}`, `{task}` and `{seed}`.

## Interface audit

`Roblox.uiAudit.collect(options)` runs in the engine. It walks the visible `ScreenGui`, `SurfaceGui` and `BillboardGui` roots and returns a dump that `HttpService:JSONEncode` can encode.
By default the roots are the layer collectors in the `PlayerGui` of the local player, or in `StarterGui` when the player has none. `world = true` adds the `SurfaceGui` and `BillboardGui` instances in the workspace.
The options are `game`, `roots`, `world`, `device`, `scale`, `input`, `safeArea`, `safeAreaRoot`, `topbarSafeArea`, `topbarSafeAreaRoot`, `maxElements` (default 5000) and `stateStyled`.
`safeAreaRoot` is a `ScreenGui` with `ScreenInsets = DeviceSafeInsets`. Its rectangle becomes the safe area.
`topbarSafeAreaRoot` is a `ScreenGui` with `ScreenInsets = TopbarSafeInsets`. Its rectangle becomes the top-bar safe area: the free part of the top bar beside the core buttons. An element inside the safe area or inside the top-bar safe area is not outside the safe area.

The dump has `screen` (viewport size, scale, `GetGuiInset`, safe area, input), `roots` and `elements`.
An element records its class, path, parent, screen rectangle, rotation, visibility in the tree, the clip rectangle of its clipping ancestors, the viewport of its scrolling ancestors, `ZIndex`, selection properties, `NextSelection*` targets, background, image transparency, text properties and `TextBounds`, focus properties, `UIPadding` and layout padding.
Screen rectangles are `AbsolutePosition` plus the top-left inset of `GetGuiInset`.
The collector reads each property in a protected call, so a missing property reads as absent.

`Roblox.uiAudit.analyze(dump, options?)` returns a report with a score from 0 to 100. `decode(value)` validates a dump that crossed a wire.

| Rule | Severity | Finds |
| --- | --- | --- |
| `text-truncated` | high | `TextFits` is false, or the text bounds are larger than the element. Scaled text counts only when it does not fit. |
| `text-clipped` | high | An ancestor with `ClipsDescendants` cuts a text element. A scrolling frame does not count. |
| `contrast-low` | high | The text contrast is below 4.5:1, or 3:1 for large text, over both a black and a white world behind the backgrounds. |
| `offscreen` | high | A visible control or text extends past the screen. |
| `outside-safe-area` | medium | A visible control or text extends past the safe area. |
| `touch-target-small` | medium | A control is smaller than `minTouchTarget` (default 44) times the scale, on a touch device. |
| `interactive-overlap` | medium | Two controls in the same root partly overlap. A control that is the ancestor of the other, or whose rectangle holds the whole rectangle of the other (for example a full-screen scrim behind a dialog), does not count. |
| `gamepad-unreachable` | medium | A control is not selectable, or no selection path from the selected or top-left control reaches it. |
| `focus-hidden` | medium | On a gamepad device: a selectable control has an invisible `SelectionImageObject`. |
| `selection-link-broken` | low | `NextSelection*` names a control that is hidden or not selectable. |
| `press-feedback-missing` | low | With `pressFeedback = true` only: a button has no automatic color, hover image, pressed image or `stateStyled` state. |
| `type-scale` | low | Each distinct text size above `maxTypeSizes` (default 6). |
| `spacing-scale` | low | Each distinct spacing value above `maxSpacingValues` (default 8). Values are padding, layout padding and the gaps between adjacent siblings. |
| `instance-count` | low | More interface instances than `maxInstances` (default 3000). |

A violation subtracts its weight: 6 for high, 3 for medium and 1 for low. One rule subtracts at most `ruleCap` (default 20).
The score is 100 minus the penalties, and never below 0.
The selection path is an approximation. It follows explicit `NextSelection*` links and otherwise moves to the nearest control in the direction. A `SelectionGroup` with `SelectionBehavior*` set to `Stop` keeps the path inside the group in that direction.
A background with an image, or one that is transparent enough that black and white disagree, counts in `metrics.contrastUnknown` and is not a violation.
The audit reads properties. It does not see style rules, rendered pixels or animation. Validate the collector in Studio before you rely on it.

## Judge

`AgentEval.judge.run(options)` builds one comparison for each task, agent, seed, device and pair of arms.
A side holds the screenshots of one run for one device, sorted by screen name.
`AgentEval.judge.compare(comparison, options)` sends the brief, the device, the rubric and both screenshot sets to the transport twice, once in each order.
The images go as "the first interface" and "the second interface". The request names no arm, run or path of the evidence.
A seed that is derived from the suite seed and the comparison identifier selects the order of the two presentations.

The reply must be one JSON object, optionally in one code fence:

```json
{"criteria": {"hierarchy": "first", "clarity": "tie", "consistency": "second", "polish": "first", "fitness": "first", "device_fit": "first"},
 "overall": "first", "confidence": 0.7, "reasons": ["The primary action stands out."]}
```

An unknown field, a missing criterion, another value or a confidence outside 0 to 1 is invalid. Verify asks again up to `attempts` times (default 2).
Each presentation gives the first arm 1, 0.5 or 0. The score of the judgment is the mean of the presentations.
A judge that always prefers one position therefore gives 0.5. `consistent` states whether both orders agreed.
A judgment with one valid presentation states that position bias is not controlled.
When only one side has screenshots, the other side wins as a `forfeit`. When neither has screenshots, the judgment is `skipped`.
The rubric criteria are hierarchy, clarity, consistency, polish, fitness for the task and device fit. Pass `rubric` to replace them.

Two transports exist:

- `AgentEval.judge.anthropic({ request, apiKey, read, encode, decode, model?, maxTokens?, effort?, url?, deadlineSeconds?, maxImageBytes? })` posts to the Messages API with `anthropic-version: 2023-06-01`. Each image is a base64 content block. The default model is `claude-opus-5-5`. The transport refuses a file that is not PNG, JPEG, GIF or WebP, or that has more than 5 MiB. A `refusal` stop reason is an error. The judge sends no fallback model, so one model judges every comparison.
- `AgentEval.judge.claudeCli({ execute, files, directory, decode, model?, command?, deadlineSeconds? })` copies the images to neutral names in a new directory and runs `claude -p --output-format json --tools Read` there. The prompt names the files.

Verify keeps each judgment in `judgments/` with a key of the comparison, the image hashes, the rubric, the transport and the seed. A new `judge` reuses a judgment with the same key.
`judgments.json` holds every judgment of the last `judge` command with its seed and transport.

`AgentEval.judge.calibrate(judgments, labels)` compares the winners with human labels.
A labels file is `{ "schemaVersion": 1, "labels": [{ "comparison": "<judgment id>", "winner": "<arm id or tie>" }] }`.
The result holds the agreement, Cohen's kappa over the categories, the confusion counts and the labels or judgments that have no partner.

## Statistics and thresholds

The report pairs runs by task. For each agent, a task is paired when it has runs of the treatment arm and of the baseline arm.
A task value is the mean of its runs. The time to first pass of a task is the sum of the wall times of its runs in seed order, up to and including the first run that passed. A task with no pass contributes its total wall time.
Turn latency percentiles use the latencies of all runs of the sampled tasks.

| Metric | Statistic |
| --- | --- |
| `passRate`, `auditScore` | Difference of the treatment and baseline means. |
| `auditViolations` | Ratio of the treatment and baseline means. The value of a run is the mean number of audit violations in each audit of the run. A run with no audit has no value. |
| `judgeWinRate` | The mean treatment score of the judgments. |
| `inputTokens`, `cacheCreationTokens`, `cacheReadTokens`, `outputTokens`, `totalTokens`, `costUsd`, `turns`, `wallSeconds`, `timeToFirstPassSeconds` | Ratio of the treatment and baseline means. |
| `turnLatencyP50`, `turnLatencyP95` | Ratio of the treatment and baseline percentiles. |

The interval is a paired percentile bootstrap. It resamples tasks with replacement with a seeded generator.
Declare the thresholds before the runs:

```json
{
  "schemaVersion": 1,
  "treatment": "kit",
  "baseline": "plain",
  "confidence": 0.95,
  "resamples": 2000,
  "seed": 20261014,
  "minimumTasks": 10,
  "rules": [
    { "id": "judge-prefers-treatment", "metric": "judgeWinRate", "lower": 0.6 },
    { "id": "no-fewer-passes", "metric": "passRate", "lower": 0 },
    { "id": "fewer-tokens", "metric": "totalTokens", "upper": 0.8 },
    { "id": "faster-turns", "metric": "turnLatencyP50", "upper": 1 }
  ]
}
```

A rule has one of `lower`, `upper`, `atLeast` or `atMost`. A `lower` rule passes when the lower bound is above the value. An `upper` rule passes when the upper bound is below it.
An `atLeast` rule passes when the estimate is at least the value. An `atMost` rule passes when the estimate is at most the value.
To require an estimate and a bound for one metric, declare two rules.
A rule with `agent` applies to that agent. Otherwise it applies to each agent.
A rule fails when fewer than `minimumTasks` paired tasks carry its metric or the interval is undefined.
The verdict is `PASS` only when every rule passes.
`AgentEval.report.verdict(report)` turns each rule into one case, `<agent>:<rule>`, of an ordinary report.

## Limits

- A pass proves that the hidden checks accepted the final workspace. It proves nothing about tasks outside the corpus.
- The interval describes the sampled tasks. It does not make the corpus representative.
- A judge is a model. Calibrate it with human labels before you rely on its win rate.
- The tests use recorded streams and fake transports. They make no network call and start no agent.
- The Studio collector is tested with injected instances. It needs a live Studio check.
