# Guru Regular Normal

Cause: all 98 mismatches among 20,800 native comparisons were width underestimates in one string containing `W.n`. Sizes 1 and 3 matched. Guru substitutes period-prefixed ligatures, including `.n`; the capture vocabulary omitted them. Separate `W.` and `.n` pair adjustments could not retain kerning through the substituted glyph.

Fix: capture all 20 period-prefixed ligature sequences as whole tokens. The existing longest-match model then uses their native advances, pair adjustments and boundary corrections. Add the successful output as `src/lute/fixtures/text/Guru-Regular-Normal.json`, with the same schema as the other faces. Exact equality remains required; no tolerance was added.

Validation: native capture on Studio 0.744.0.7441077 passed all 20,800 comparisons with zero mismatches. The focused text-metrics specification failed with the original facts and passed with the new facts. Native conformance now also exercises period ligatures, leading punctuation, spaces, repeated ligatures and three-character substitutions. Coverage is limited to the captured text grammar and sizes 1 through 100.

PR: https://github.com/voidmeld/verify/pull/18

Additional native limits: `lute run tools/gate.luau --native` passed all 24 portable producers but failed the unchanged UI-layout suite (7 cases) and multiplayer (timeout with CoreScript chat errors). A direct text-metrics conformance run reported failures across all 23 faces. Guru had zero width differences and 90 multiline height-rounding differences. These broader native checks do not pass; the successful 20,800-comparison capture establishes the requested width claim only.
