# Studio tools for an agent run

An arm can declare `studio` instead of `mcp`:

```json
{
  "id": "native",
  "studio": {
    "build": ["rojo", "build", "default.project.json", "-o", "{evidence}/agent.rbxlx"],
    "place": "{evidence}/agent.rbxlx"
  }
}
```

The consumer owns the build command. Verify runs it in the run workspace before
the agent starts. `{workspace}` and `{evidence}` name only that run. A failed
build or launch prevents the agent from starting. A host without the optional
`Services.studio` binding refuses this setup.

The Lute binding launches a new Studio with the existing launcher. It identifies
one new Studio by its unique place name. It writes an MCP configuration outside
the workspace that starts `tools/scoped-studio-mcp.luau`. The proxy has one
immutable Studio id. Its listing returns only that Studio. It never forwards a
global listing. It injects the id when absent and refuses every other id before
calling the backend. Unknown methods, tools and argument fields are refused.
The agent gets play/stop, capture, execute, console output and input. `input`
runs the supplied native VirtualInput code on Client through `execute_luau`.
It takes `{ code, studio_id? }`. It does not emulate computer or browser input.
Capture results, including image content, pass through without text conversion.
Each proxy process claims a fresh transport directory. Restarting the same MCP
configuration keeps its Studio id and does not reuse old process or close files.
Each native request has a 60-second deadline, capped by the remaining run time.
An operator can set a finite positive `callSeconds` in the private scope file
before starting the proxy. The run's `seconds` limit still applies. Start long
work without waiting for completion and inspect its progress in later calls.
A request that returns no answer may have been applied. The proxy closes that
transport and reports the uncertainty without replaying the request. The next
explicit request opens a fresh transport to the same Studio. Late answers stay
with the old transport; they cannot satisfy the next request.

The runner closes the Studio before hidden checks. It also closes it when the
adapter raises. A cleanup failure fails the run. The proxy does not retry an
ambiguous execution. Each parallel run gets a different scope and Studio. The
build command must rebuild the place after source edits; the initial place is
the provisioned snapshot. Agents can use Edit execution to inspect and update
their Studio. A live source sync service is not provided.

For an agent that authors in Studio, set `studio.keep` to `true`. After the
bounded author process returns, Verify stops Play, closes its MCP session,
and leaves the owned Studio open. `studio-place.json` in the run directory
records the Studio id, local place path, and process id. The consumer must save
that place before closing Studio and evaluate the saved bytes. Keeping Studio
does not save the place or establish a submission. Hidden checks still run;
a missing saved submission must fail the consumer's checks. An adapter exception
still closes Studio, including when `keep` is set.

Use an agent setup that ignores user MCP configuration and disables unrelated
plugins, computer use and browser use. `studio` cannot be combined with another
MCP configuration. This scope restricts the supplied MCP tools. The workspace
is not an operating-system sandbox; an agent with arbitrary shell access can
start other processes. The consumer owns that broader permission boundary.

Token totals use the adapter's recorded usage for both shell and MCP tools.
There is no character estimate, free MCP allowance or extra charge for a tool
result already included in usage. A completed MCP item counts once as a tool
call even when the stream also includes started and updated events. Cached
input stays in the total. Missing usage remains missing.

Headless tests cover isolation, refusal without forwarding, image preservation,
closed scopes, adapter failure cleanup and token accounting. They do not prove
Studio launch, input delivery, captures or process cleanup on a native host.
Run the native gate on the reference Studio host before making those claims.
