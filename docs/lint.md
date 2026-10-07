# Lint policy

The gate runs `lute lint -c lint.config.luau` on each maintained Luau tree. It also runs `luau-lsp analyze`
in strict mode on every source, test, tool, example and lint configuration file.
The analyzer checks consumers against the installed SDK types. It ignores diagnostics inside external SDK and generated build directories.

Exported records and callbacks carry concrete types. Dynamic host members, arbitrary assertion values and
heterogeneous callback arguments stay explicit boundaries. A strict directive alone does not prove those values safe.

`tools/check-no-any.luau` parses every maintained Luau file. Each file must start with `--!strict`.
Explicit `any` types and `--!nonstrict` or `--!nocheck` directives fail the gate.
Use concrete types, correlated generics and validated `unknown` at external boundaries.
Do not hide weak typing behind aliases or unchecked casts.

The lint configuration keeps the Lute defect rules on. It turns off only `global_function_in_scope` and `unused_variable`.
At the pinned runtime, those two rules misreport forward-declared recursion and locals used as assignment-target bases.
`luau-lsp` keeps the real unused-local signal.

## Consumer specifications

`verify-check` checks consumer specifications. Choose a ruleset with `--ruleset`:

```console
lute run tools/verify-check.luau --ruleset generic path/to/specifications
lute run tools/verify-check.luau --ruleset roblox path/to/specifications
```

Both rulesets treat `*.verify.luau` as a portable specification. `*.lute.verify.luau` and `*.lune.verify.luau` are explicit host variants.
The generic ruleset rejects ambient scheduling and clocks in portable specifications.
It rejects unmeasured `--!native` annotations in every specification.
The `roblox` ruleset adds three rules. `*.roblox.verify.luau` is a host variant.
Portable specifications may not use the globals `game` and `workspace`.
No specification may call `PublishAsync`, `PostAsync`, `RequestAsync`, `CreateAssetAsync` or `SavePlaceAsync`.
A general-purpose linter cannot infer these architectural checks.

The tool calls `Consumer.scanTree(root, { ruleset, listDir, readFile })` ([public consumer root](../src/consumer/init.luau)).
A `Ruleset` is `{ name, hostVariantSuffixes, hostGlobals, externalMutationMembers }`. A call without one raises.
`scanTree` owns traversal, specification detection and exemption tracking.
It also runs `scanProductionPaths` over every discovered path, including files that are not specifications.
The same call detects `.verify.luau` files and Verify imports in a production source graph.
A consumer lint runner can reuse `Consumer.scan` and `scanProductionPaths`.
