[Wiki](../index.md) › [Testing and conformance](index.md)

# Choose the layer that can fail for the right reason

Verified: the layers are Rust unit and integration tests per crate (`cargo nextest run --workspace`); the frozen conformance corpus in `tests/conformance/fixtures` (run, check, test, parse phases, gated by `make conform`); `.ms` fixtures under `tests/e2e/testdata/` (`accept`, `reject`, `stdlib`, `projects`, `shutdown`) that seed the corpus; and documentation fences checked by `make docs-check`. A language change needs an accepting case and a rejecting case; a stdlib change needs its module fixture; a lifetime or cancellation change needs observable close/cancel/join cases.

Apply when: deciding where a regression test belongs.
Evidence: [conformance corpus](../../tests/conformance/README.md), [development checks](../../documentation/contributing/development.md), [Makefile](../../Makefile).
Verify: the test fails on the unfixed code, then passes; `make verify` and the affected target (`make conform`) pass.

Verified: putting assertion formatting and close work in a recursively called test destructor
can overflow a native host's test stack before reaching the intended deferred-drop state.
Keep that work in a non-inlined leaf helper; retain the full depth, pending-link assertions,
and exact destructor counts. The [channel lease regressions](../../crates/ms-rt/src/channel.rs)
cover both zero and nonzero pending links. Apply a controlled stack budget to the test
executable only, after building normally, so the experiment does not constrain rustc itself.

---
Topics: [Testing](../topics/testing.md)
