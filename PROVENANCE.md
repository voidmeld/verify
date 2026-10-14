# Provenance and license

Verify, its adapters, tests, examples, tools and documentation are original work. Copyright © 2026 voidmeld.
Verify is licensed under the MIT License in [`LICENSE`](LICENSE). It is distributed from a public repository.

## Source and tools

- Do not commit, vendor, generate or run third-party source as a Verify dependency.
- Lute, Lune, Luau-LSP and StyLua are pinned development tools. Rokit fetches them. Verify does not distribute them.
- This repository contains no implementation from another test framework.
- Comparisons with other frameworks and their measurements stay outside this release tree.
- The public adapters in the [README](README.md#packages) belong to Verify.

## Generated fixtures

These files are generated. They are not authored.

| File | Source | Command |
| --- | --- | --- |
| `tests/fixtures/reflection-snapshot.json` | The reflection database of the pinned Lune runtime, for the classes that the Lune tests name. | `lune run tools/export-reflection.luau tests/fixtures/reflection-snapshot.json --classes=Part,TextLabel,Frame,Model,Folder` |
| `tests/fixtures/studio-reflection.json` | Roblox Studio through its official MCP: reflection, defaults of new instances, enums, brick colors and fonts. | `lute run tools/export-studio-reflection.luau tests/fixtures/studio-reflection.json --studio-name <place> --classes Folder,Model,Part,Frame,TextLabel,TextButton,ScrollingFrame,UICorner,UIListLayout,ScreenGui,GuiService --enums NormalId,Axis` |
| `tests/fixtures/datatype-probes.json` | The results of the probes in `tests/fixtures/datatype-probes.luau`, run in Roblox Studio. | `lute run tools/export-studio-probes.luau tests/fixtures/datatype-probes.json --studio-name <place>` |

The Lune gate compares the Lune fixture with a fresh export, so that file cannot drift.
The Studio files record the engine version that wrote them. Regenerate them after a Roblox update and review the difference.
