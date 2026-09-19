# Lint policy

The complete gate runs `lute lint -c lint.config.luau` on each maintained Luau tree. It also runs
`luau-lsp analyze` for type and scope-aware checks that pinned Lute does not perform correctly.
Verify does not use Selene.

The explicit configuration keeps Lute's defect rules on. It turns off only
`global_function_in_scope` and `unused_variable`. At the pinned runtime, those two rules misreport
forward-declared recursion and locals used as assignment-target bases. `luau-lsp` retains the real
unused-local signal.

`verify-check` is the consumer-semantic layer:

```console
lute run tools/verify-check.luau path/to/specifications
```

It recognizes `*.verify.luau` as portable specifications, with `*.lute.verify.luau` and
`*.roblox.verify.luau` as explicit host variants. It rejects ambient scheduling, clocks, and host
access in portable specifications. It rejects external mutation authority in every specification.
It rejects unmeasured `--!native` annotations. These are architectural checks a general-purpose
linter cannot infer.

The tool itself is a thin shell over `Consumer.scanTree(root, { listDir, readFile })`
(`src/consumer/init.luau`). The walk, the specification test, and the exemption bookkeeping belong
to `scanTree`, so a consumer building its own lint runner over `Consumer.scan`/`scanProductionPaths`
does not have to re-type them. `scanTree` also runs `scanProductionPaths` over every path it
discovers, specification or not. A tree that leaked a `.verify.luau` file, or Verify itself, into a
production source graph is caught by the same call.
