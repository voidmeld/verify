# Provenance and license

Verify, its adapters, tests, examples, tools and documentation are original work. Copyright © 2026 voidmeld.
Verify is licensed under the MIT License in [`LICENSE`](LICENSE). It is distributed from a public repository.

## Source and tools

- Do not commit, vendor, generate or run third-party source as a Verify dependency.
- Lute, Lune, Luau-LSP and StyLua are pinned development tools. Rokit fetches them. Verify does not distribute them.
- This repository contains no implementation from another test framework.
- Comparisons with other frameworks and their measurements stay outside this release tree.
- The public adapters in the [README](README.md#packages) belong to Verify.

## Generated fixture

`tests/fixtures/reflection-snapshot.json` is generated. It is not authored.
`tools/export-reflection.luau` exports it from the reflection database of the pinned Lune runtime.
It holds class names, property names, datatypes and defaults for the classes that the Lune tests name.
The Lune gate compares the committed file with a fresh export, so the file cannot drift.
