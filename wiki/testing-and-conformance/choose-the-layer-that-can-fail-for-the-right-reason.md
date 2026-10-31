[Wiki](../index.md) › [Testing and conformance](index.md)

# Choose the layer that can fail for the right reason

Verified: the layers are Rust unit and integration tests per crate (`cargo nextest run --workspace`); the frozen conformance corpus in `tests/conformance/fixtures` (run, check, test, parse phases, gated by `make conform`); `.ms` fixtures under `tests/e2e/testdata/` (`accept`, `reject`, `stdlib`, `projects`, `shutdown`) that seed the corpus; and documentation fences checked by `make docs-check`.

Apply when: deciding where a regression test belongs.
Evidence: [conformance corpus](../../tests/conformance/README.md), [development checks](../../documentation/contributing/development.md), [Makefile](../../Makefile).
Verify: the test fails on the unfixed code, then passes; `make verify` and the affected target (`make conform`) pass.
