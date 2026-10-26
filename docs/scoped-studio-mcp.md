# Studio tools for an agent run

Set an arm's `studio` field instead of `mcp`:

```json
{
  "id": "native",
  "studio": {
    "build": ["rojo", "build", "default.project.json", "-o", "{evidence}/agent.rbxlx"],
    "place": "{evidence}/agent.rbxlx"
  }
}
```

The consumer owns the build command. Verify runs it in that run's workspace before the agent starts. `{workspace}` and `{evidence}` refer only to that run. Build or launch failure prevents agent startup. A host without the optional `Services.studio` binding rejects this setup.

The Lute binding launches a new Studio. It finds that Studio by its unique place name. It writes an MCP configuration outside the workspace for `tools/scoped-studio-mcp.luau`. The proxy keeps one fixed Studio ID. It lists only that Studio and never sends a global listing request. It inserts the ID when absent. It rejects other IDs, unknown methods, unknown tools and unknown argument fields before forwarding.

The agent gets play, stop, capture, execute, console output and input tools. `input` runs the given native VirtualInput code on Client through `execute_luau`. It accepts `{ code, studio_id? }`. It does not simulate computer or browser input. Captures pass through with image content. The proxy does not convert images to text.

Each proxy process creates a new transport directory. A restarted MCP configuration keeps its Studio ID. It does not reuse earlier process or close files. Native requests have a 60-second deadline, limited by the remaining run time. Before proxy startup, an operator can set a positive finite `callSeconds` in the private scope file. The run's `seconds` limit still applies. Start long work without waiting for completion. Check progress in later calls.

A request without an answer can still have taken effect. The proxy closes that transport and reports uncertain delivery. It does not repeat the request. The next explicit request opens a new transport to the same Studio. Late answers stay with the old transport. They cannot satisfy a new request.

The runner closes Studio before hidden checks. It also closes Studio after an adapter exception. Cleanup failure fails the run. Each parallel run has a separate scope and Studio. After source changes, the build command must rebuild the place. The initial place is a snapshot. Agents can inspect and change Studio through Edit execution. Verify provides no live source synchronization.

Set `studio.keep` to true for an agent that authors in Studio. After the bounded agent process returns, Verify stops Play and closes MCP. It leaves the owned Studio open. `studio-place.json` records the Studio ID, local place path and process ID. The consumer must save the place before closing Studio. Evaluate those saved bytes. Keeping Studio open does not save a submission. Hidden checks still run. Consumer checks must fail when a required saved submission is absent. An adapter exception still closes Studio, including with `keep`.

Use an agent setup that ignores user MCP configuration. Disable unrelated plugins, computer use and browser use. Do not combine `studio` with another MCP configuration. This scope restricts the given MCP tools. It is not an operating-system sandbox. An agent with arbitrary shell access can start other processes. The consumer controls that permission boundary.

Token totals use recorded adapter usage for shell and MCP tools. There is no character estimate, free MCP allowance or extra charge for results already included in usage. A completed MCP item counts once, even when the stream also contains start and update events. Cached input stays in the total. Missing usage stays missing.

Headless tests check isolation, refusal before forwarding, image preservation, closed scopes, exception cleanup and token accounting. They do not prove native Studio launch, input delivery, captures or process cleanup. Use the native gate on the reference Studio host for those claims.
