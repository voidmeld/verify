# Verify contributor guide

Verify is a testing library for Luau. It owns host-neutral cases, execution and reports.
Consumers own discovery, authorization, host operations, destinations and release acceptance.
First, select your task in the [README](README.md).
New consumers start with the [quickstart](docs/quickstart.md).
For public contracts, read only the task area in the [API reference](docs/api.md).
Before a repository edit, follow [CONTRIBUTING.md](CONTRIBUTING.md) for setup, validation and integration.

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

## Repository

Do not change verified bytes after the gate. Reuse evidence while its inputs stay unchanged.
Report the changed behavior, the validation and the limits.
A narrowed run is not the gate. A headless pass proves no engine, media, input or release claim.

Preserve the [MIT provenance](PROVENANCE.md). Keep history append-only unless the Owner authorizes a rewrite.
Consumers follow the [Verify skill](.agents/skills/verify/SKILL.md).

Every maintained Luau file requires `--!strict`, zero explicit `any` and zero type assertions
(`::`), including concrete casts. The required gate rejects violations without a baseline or exemptions.
