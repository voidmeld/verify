# Contributing to Verify

Thank you for your interest in Verify. This guide explains how to set up a
checkout, how to check a change and how to send it.

## Setup

1. Install [Rokit](https://github.com/rojo-rbx/rokit).
2. Run `rokit install` in the repository root. This installs the pinned tools
   from `rokit.toml`: Lute, luau-lsp, StyLua and Rojo.
3. Run `lute setup` to install the Luau SDK type definitions.

## Rules

Read [AGENTS.md](AGENTS.md) before you change the repository. It states the
rules that every change must follow and the evidence that a change needs. The
[API reference](docs/api.md) states the public contracts.

## Check a change

- While you edit, run `lute run tools/gate.luau --tier fast`, or one
  specification with `lute run tools/gate.luau --only specs --file tests/name.verify.luau`.
- After you add or remove a specification, run
  `lute run tools/check-test-manifest.luau --write`.
- Commit the change. Then run `lute run tools/gate.luau` once on the clean
  commit. The full gate includes a fresh-clone check, so it must run on a
  committed tree. A change to a launcher or to the engine also needs
  `lute run tools/gate.luau --native`, which uses a Roblox Studio host.

[The repository gate](docs/running.md#repository-gate) describes each check and
its limits.

## Pull requests

- Open a pull request against `main`. Do not push to `main` directly.
- The required `Gate` check must pass before a pull request can merge.
- Describe what the change does, why, and the evidence: the specifications you
  added and the gate result.
- Keep one change in one pull request.

## License

Verify is licensed under the [MIT License](LICENSE). By contributing, you agree
that your contributions are licensed under the same license.
