[Wiki](../index.md) › Testing and conformance

# Testing and conformance

Test layers, corpus, fuzzing, fixtures.

How behavior is proven in this repository. Test-API semantics (plans, fixtures, hooks) are in [runtime.md](../runtime/index.md); CI mechanics are in [repository.md](../repository/index.md).

## Pages

- [Choose the layer that can fail for the right reason](choose-the-layer-that-can-fail-for-the-right-reason.md): the layers are Rust unit and integration tests per crate (`cargo nextest run --workspace`); the frozen conformance corpus in `tests/conformance/fixtures` (run, check, test, parse phases, gated by `mak…
- [C drivers must execute against the production runtime](c-drivers-must-execute-against-the-production-runtime.md): the native C smoke harness compiled and linked with obsolete one-word string return/message declarations, then aborted at its first call.
- [Conformance expectations are frozen contracts](conformance-expectations-are-frozen-contracts.md): the corpus expectations were first recorded from the Go `ms` and are now the contract; the Go implementation is gone and is not needed to extend them.
- [Source tests return Result and run through `ms test`](source-tests-return-result-and-run-through-ms-test.md): the user asked to replace panic assertions with the standard testing API, to use pipe chains where they clarify the flow, and to remove host-language orchestration of Manuscript conformance.
- [Fixtures follow current idiom, except where they test the old form](fixtures-follow-current-idiom-except-where-they-test-the-old.md): after sweeping renames (`to_string`, positional arguments, `--drop-labels`, `get(default)`, `TextError`, `write_bytes`, no `->`), fixtures are migrated to the new spelling; only rejected-variant fixtu…
- [Do not accept an empty run](do-not-accept-an-empty-run.md): a runner that reports `0 tests, 0 failed` is a failure.
- [Fuzz regressions become observable tests](fuzz-regressions-become-observable-tests.md): the conformance tool has generated-input fuzzing (`ms-conform fuzz-gen`, `fuzz`).
