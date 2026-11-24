# Changelog

Verify follows [semantic versioning](https://semver.org). While the version is `0.x`, a minor
release may change a public contract.

## Unreleased

- Follow-up: `gate --rerun` must accept a producer of kind `build`. The gate-outcome parser
  rejects it today, so a consumer with build producers cannot rerun an earlier outcome; `--only`
  works.

## 0.1.0

- First versioned release. Verify is a `lute pkg` package: `pkg.luau` declares the package, and
  consumers install it with `lute pkg install --vendor`.
- Requires Lute `1.0.1-nightly.20261120` or newer.
