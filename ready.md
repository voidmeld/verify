# Native font capture handoff

The live producer omitted `pixelScale` when constructing its validation model. It had already normalized the measured tables to raster pixels, so the model defaulted to scale 1 and returned raster widths instead of native widths. All four failed live reports recorded scale `0.6666666865348816` and 20,799 differences. For example, SourceSansPro Bold size-1 `Hello world` returned 7 instead of native `4.6666669845581055`.

The live model now receives the same measured `pixelScale` that the producer stores in its font facts and the Lute decoder loads. The inherited bold fix converts probes to raster pixels before subtraction, applies the width ceiling in raster units, then scales and converts to float32. Native line heights remain in their original units. Older font facts default to scale 1. The attachment manifest finishes before the zero-difference assertion so failures retain complete evidence.

Exact native equality and `check:expect(#differences):toBe(0)` remain unchanged. No tolerance or rounding of validation observations was added.

## Four passing native outputs

Old outputs were removed before these runs. Each command exited 0, wrote font facts and its report, and reassembled attachments with byte-count and SHA-256 validation. Every saved `differences.json` is `[]`. Engine: `0.744.0.7441077`; style: `Normal`; measured scale: `0.6666666865348816`.

All files below are under `C:/git/roa-worktrees/briefs/captures/`. Each output has a sibling `<output>.report.json` and `<output>.attachments/`.

| Output | Comparisons | Mismatches | Font facts SHA-256 |
| --- | ---: | ---: | --- |
| `font-SourceSansPro-Bold.json` | 20,800 | 0 | `e34e6ffa9bd87315b4377d9c02be4d361bfd3235c3d47f7bd0e2a2a3a764061d` |
| `font-SourceSansPro-SemiBold.json` | 20,800 | 0 | `4b6ef6b70673407fdda7b1faa3b7201682591a076c6920ace24108195f5eac6a` |
| `font-GothamSSm-Bold.json` | 20,800 | 0 | `d5e0e5c32530cb45270117ef75db7dd9b49ded7bc8cdbb3fdcd4b18b5171aaa2` |
| `font-GothamSSm-Medium.json` | 20,800 | 0 | `f95f597d178aecb41b24a2070c964ea85c079dff5924c6d09b7560aaf02fff21` |

Commands executed:

```powershell
lute run tools/capture-text-metrics.luau C:/git/roa-worktrees/briefs/captures/font-SourceSansPro-Bold.json rbxasset://fonts/families/SourceSansPro.json Bold Normal
lute run tools/capture-text-metrics.luau C:/git/roa-worktrees/briefs/captures/font-SourceSansPro-SemiBold.json rbxasset://fonts/families/SourceSansPro.json SemiBold Normal
lute run tools/capture-text-metrics.luau C:/git/roa-worktrees/briefs/captures/font-GothamSSm-Bold.json rbxasset://fonts/families/GothamSSm.json Bold Normal
lute run tools/capture-text-metrics.luau C:/git/roa-worktrees/briefs/captures/font-GothamSSm-Medium.json rbxasset://fonts/families/GothamSSm.json Medium Normal
```

## Checks and limits

- `lute run tools/check-test-manifest.luau --write`: exit 0.
- `lute run tools/gate.luau --file tests/text-metrics-scale.lute.verify.luau --file tests/capture-attachments.lute.verify.luau`: exit 0. Evidence: `.lute/tmp/verify-gate/gate-1793061019-979420-1/outcome.json`.
- `lute run tools/gate.luau --tier fast`: exit 1. All other selected producers passed; shared specs passed 1,179 of 1,180 cases. Evidence: `.lute/tmp/verify-gate/gate-1793062361-992842-1/outcome.json`.
- The sole fast-tier failure is the unchanged `tests/ui-style-selectors.lute.verify.luau::pseudo-instance selectors with hyphenated tags keep physical components independent`, at `chunk:15` (the nonzero property-transition refusal assertion). An isolated rerun reproduced the failure, exit 1: `.lute/tmp/verify-gate/gate-1793062537-222834-1/outcome.json`. No selector behavior was changed in this font fix.
- `git diff --check`: exit 0.

The native captures prove exact X widths for 208 strings at 100 sizes per face on this engine build. They do not establish arbitrary text, native wrapping/truncation, or release acceptance. The inherited 53-sample Bold fixture checks exact widths and retained heights; its scaled wrap/truncation tests check model units, not native wrapping. The repository fast tier remains failing on the selector case above.
