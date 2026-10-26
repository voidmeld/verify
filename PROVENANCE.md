# Provenance and license

Verify, its adapters, tests, examples, tools and documentation are original work. Copyright © 2026 voidmeld.
Verify is licensed under the MIT License in [`LICENSE`](LICENSE). It is distributed from a public repository.

## Source and tools

- Do not commit, vendor, generate or run third-party source as a Verify dependency.
- Lute, Luau-LSP and StyLua are pinned development tools. Rokit fetches them. Verify does not distribute them.
- This repository contains no implementation from another test framework.
- Comparisons with other frameworks and their measurements stay outside this release tree.
- The public adapters in the [README](README.md#packages) belong to Verify.

## Generated fixtures

These files are generated. They are not authored.

| File | Source | Command |
| --- | --- | --- |
| `tests/fixtures/reflection-snapshot.json` | The reflection database of Lune 0.10.5 for the classes `Part`, `TextLabel`, `Frame`, `Model` and `Folder`. It is frozen. Verify no longer runs Lune. | None. Export the same classes from Studio to replace it. |
| `tests/fixtures/studio-reflection.json` | Roblox Studio through its official MCP: reflection, defaults of new instances, enums, brick colors and fonts. | `lute run tools/export-studio-reflection.luau tests/fixtures/studio-reflection.json --studio-name <place> --classes Folder,Model,Part,Frame,TextLabel,TextButton,ScrollingFrame,UICorner,UIListLayout,ScreenGui,GuiService --enums NormalId,Axis` |
| `src/lute/fixtures/text/*.json` | Native `TextService.GetTextBoundsAsync` measurements for the recorded font face and engine version. These facts contain no font source or outlines. | `lute run tools/capture-text-metrics.luau <out.json> <font-family> [weight] [style]` |
| `tests/fixtures/datatype-probes.json` | The results of the probes in `tests/fixtures/datatype-probes.luau`, run in Roblox Studio. | `lute run tools/export-studio-probes.luau tests/fixtures/datatype-probes.json --studio-name <place>` |

The Lune fixture does not change. The tests use it as a second, smaller database.
The Studio files record the engine version that wrote them. Regenerate them after a Roblox update and review the difference.

## Leakage checks

`tools/check-leakage.luau` scans tracked text for product asset, place and universe identifiers.
`tools/lib/denylist.luau` allows only exact literals in named files: URI constructors in the datatype implementation, synthetic IDs in tests and native conformance, and the engine-reported default font ID in the generated datatype probe fixture. The generated fixture's source and regeneration command are recorded above. Other literals in those files remain checked.
