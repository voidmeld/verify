# Changelog

Verify follows [semantic versioning](https://semver.org). While the version is `0.x`, a minor
release may change a public contract.

## 0.1.1

- The package publishes the consumer skill (`.agents/skills/verify`).
- `gate --rerun` reads an earlier outcome that contains `build` or `benchmark` producers. The
  outcome parser accepted only `command`, `tests` and `native`, so such a gate could not rerun.

## 0.1.0

- First versioned release. Verify is a `lute pkg` package: `pkg.luau` declares the package, and
  consumers install it with `lute pkg install --vendor`.
- Requires Lute `1.0.1-nightly.20261120` or newer.
