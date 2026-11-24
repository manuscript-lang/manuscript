[Wiki](../index.md) › [Testing and conformance](index.md)

# Choose the layer that can fail for the right reason

Verified: the layers are C unit and driver tests (`ctest --preset ci`), the conformance corpus in `tests/conformance/fixtures` (run, check, test and parse phases, gated by `make conform`), and the corpus fixtures under `tests/conformance/fixtures/e2e/` (`accept` and `stdlib` as `test`, `reject` as `check`, multi-file `projects`). `tools/conform-run.ms` is the only runner for `.ms` behavior, so a C test that only runs a program and compares its output belongs in the corpus instead.

Apply when: deciding where a regression test belongs.
Evidence: [conformance corpus](../../../tests/conformance/README.md), [development checks](../../../documentation/contributing/development.md), [Makefile](../../../Makefile).
Verify: the test fails on the unfixed code, then passes; `make verify` and the affected target (`make conform`) pass.
