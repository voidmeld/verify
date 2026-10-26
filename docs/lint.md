# Lint policy

Run `lute lint -c lint.config.luau` on maintained Luau code. The gate also runs strict `luau-lsp analyze` on source, tests, tools, examples and lint configuration. The analyzer uses installed SDK types. It ignores diagnostics inside external SDK and generated build directories.

Give exported records and callbacks specific types. Use `unknown` for values that cross a dynamic boundary. Validate those values before use. A strict directive alone does not prove safety. Do not hide weak types behind aliases or casts that bypass validation.

`tools/check-no-any.luau` parses maintained Luau files. Each file must start with `--!strict`. Explicit `any`, `--!nonstrict` and `--!nocheck` fail the gate. Use specific types and generics that preserve the relationship between inputs and outputs.

The lint configuration enables Lute defect rules. It disables only `global_function_in_scope` and `unused_variable`. In the pinned runtime, these rules incorrectly report forward recursion and locals used as assignment bases. `luau-lsp` still reports unused locals.

## Consumer specifications

Select a ruleset:

```console
lute run tools/verify-check.luau --ruleset generic path/to/specifications
lute run tools/verify-check.luau --ruleset roblox path/to/specifications
```

Both rulesets treat `*.verify.luau` as portable specifications. `*.lute.verify.luau` is an explicit host variant. The generic ruleset rejects ambient scheduling and clocks in portable specifications. It rejects unmeasured `--!native` annotations in all specifications. The Roblox ruleset also recognizes `*.roblox.verify.luau` as a host variant. It rejects `game` and `workspace` in portable specifications. It rejects these calls in all specifications: `PublishAsync`, `PostAsync`, `RequestAsync`, `CreateAssetAsync` and `SavePlaceAsync`. A general linter cannot determine these architectural requirements.

The tool calls `Consumer.scanTree(root, { ruleset, listDir, readFile })` from the [consumer root](../src/consumer/init.luau). A `Ruleset` contains `{ name, hostVariantSuffixes, hostGlobals, externalMutationMembers }`. A call without a ruleset raises an error. `scanTree` traverses files, finds specifications and tracks exemptions. It also calls `scanProductionPaths` for all discovered paths, including files that are not specifications. This detects `.verify.luau` files and Verify imports in production source graphs. A consumer lint runner can call `Consumer.scan` and `scanProductionPaths` directly.
