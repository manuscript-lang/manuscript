[Wiki](../index.md) › [Testing and conformance](index.md)

# Choose the layer that can fail for the right reason

Verified: the layers are Rust unit and integration tests per crate (`cargo nextest run --workspace`); the frozen conformance corpus in `tests/conformance/fixtures` (run, check, test, parse phases, gated by `make conform`); the former end-to-end fixtures, now corpus fixtures under `tests/conformance/fixtures/e2e/` (`accept` and `stdlib` as `test`, `reject` as `check`, multi-file `projects`), so `ms-conform` is the only runner for `.ms` behavior and a Rust test that only runs a program and compares output belongs there as a `run` fixture; and documentation fences checked by `make docs-check`.

Apply when: deciding where a regression test belongs.
Evidence: [conformance corpus](../../tests/conformance/README.md), [development checks](../../documentation/contributing/development.md), [Makefile](../../Makefile).
Verify: the test fails on the unfixed code, then passes; `make verify` and the affected target (`make conform`) pass.

Measured 2026-11-11 (coverage of the compiler crates, corpus versus Rust tests): only 11 of 228 Rust test modules reached nothing the corpus misses. The rest cover Rust-side surfaces (LSP, `--watch`, process and flag handling), so their cost is cut in the harness: LSP tests share one `ms_check::Session` per test thread (`support::session()`), which took `signature_help` from 105 CPU-s to 12, and the ownership-count gate's self-test runs in `make count-check`, where the stats runtime is already built, not in the unit suite.
