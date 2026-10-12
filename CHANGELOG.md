# Changelog

## Unreleased

- Group reusable Go packages under `pkg/`; Go callers must update the former root package imports to `github.com/manuscript-lang/manuscript/pkg/...`.
- Add read-only verification, pinned lint tools, environment diagnostics, and checked package/build boundaries.
- Publish documentation through GitHub Pages artifacts; generated HTML is no longer committed.
- Reuse the CLI across conformance tests, execute complete tutorial examples, and collect dependency-package coverage.
- Separate frontend facts from host runtime implementations and verify native signatures in integration tests.
- Validate compressed toolchain archives before cache publication, including interrupted downloads.
- Add repeatable dependency/pin maintenance, license inventories, and one shared release version.
