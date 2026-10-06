# Verify contributor guide

Verify is a testing library for Luau. It owns host-neutral cases, execution and reports.
Consumers own discovery, authorization, host operations, destinations and release acceptance.
The [README](README.md) maps the packages. Read only the applicable [contract](docs/README.md).

This file owns the contribution rules. The repository owner sets the scope of each change.
[Laws](docs/laws.md) own lifecycle and evidence. Each fact has one owning document.

## Rules

- Make the smallest useful change. Test real success and failure boundaries.
- Before you remove a surface, inspect its executable, dynamic, generated, CLI and documented consumers. Its tests and exports alone do not justify keeping it.
- Repair a current consumer before you add machinery.
- Use `@self/child` inside directory modules. Use sibling-relative imports in portable leaves.
- Core imports only core siblings. Core has no host services.
- Add no source comments except compiler and tool directives.
- Add no third-party source and no dependency manifests.
- Keep consumer identity, credentials, policy and milestones out of this repository. Keep comparisons with other frameworks out of this repository.

## Validate

- While you edit, run the narrowest check that can refute your change. Use [one documented command](docs/running.md#repository-gate) for one spec file, one case, one tier or a rerun of failures.
- On final bytes, run `lute run tools/gate.luau` once.
- For a launcher or engine change, run `lute run tools/gate.luau --native`. It needs the reference Studio host.
- A narrowed run is not the gate. A headless pass proves no engine, media, input or release claim.
- Reuse evidence while its inputs stay unchanged. Repeat a check only after a relevant change or an unresolved failure.
- Report the changed behavior, the validation and the limits.

## Repository

Preserve the [MIT provenance](PROVENANCE.md). Keep history append-only unless the Owner authorizes a rewrite.
Use author and committer `voidmeld <158495725+voidmeld@users.noreply.github.com>`. Add no attribution trailers.
Consumers follow the [Verify skill](.agents/skills/verify/SKILL.md).
