# Verify contributor guide

Verify is a host-neutral Luau verification library: claims, execution and receipts. Consumers own
what to verify, discovery, authorization, actual host operations and release acceptance.

Read [README](README.md) and the applicable [contract](docs/README.md). Change the smallest useful
implementation and run `lute run tools/gate.luau` on final bytes. A focused run is never the gate.
Test real behavioral boundaries and their falsifiers; existing APIs and their own tests do not
justify retaining unused machinery. Check executable, dynamic, generated, CLI and documented
consumers before cutting a public surface.

[The laws](docs/laws.md) own lifecycle, evidence and authority. Source comments are prohibited;
Luau compiler/tool directives are allowed. Use `@self/child` inside directory modules and sibling
relative imports inside portable leaf modules. Core imports only core siblings and has no host
services. Do not add third-party source or dependency manifests. Preserve the MIT grant in
[provenance](PROVENANCE.md). Tracked framework files must contain no consumer
identity, product rules, credentials or milestone state.

Author and committer are `voidmeld <158495725+voidmeld@users.noreply.github.com>`; no AI attribution.
Keep history append-only except an explicitly authorized root reseal. Current Owner direction
controls scope, subject to the execution harness's permission boundaries. Resolve contradictions
at the owning law or implementation; do not create another historical exception ledger.

When consuming Verify, read [the consumer brief](.agents/skills/verify/SKILL.md). Completion reports
state changed behavior, exact validation and remaining limits. A passing headless gate establishes
no unobserved engine, image, audio, input or release result.

External end-user product names, adopter identities and competitive comparisons belong only in research repositories. Use neutral requirements and research links here. Required dependency, API, tool and license identifiers remain exact.
