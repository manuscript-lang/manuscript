[Wiki](../index.md) › Testing and conformance

# Testing and conformance

Test layers, conformance corpus, fuzzing, fixtures.

- [C drivers must execute against the production runtime](c-drivers-must-execute-against-the-production-runtime.md): the native C smoke harness compiled and linked with obsolete one-word string return/message declarations, then aborted at its first call.
- [Choose the layer that can fail for the right reason](choose-the-layer-that-can-fail-for-the-right-reason.md): the layers are Rust unit and integration tests per crate (`cargo nextest run --workspace`); the frozen conformance corpus in `tests/conforma…
- [Conformance expectations are frozen contracts](conformance-expectations-are-frozen-contracts.md): the corpus expectations were first recorded from the Go `ms` and are now the contract; the Go implementation is gone and is not needed to extend them.
- [Corpus time is standard-library loads per process](corpus-time-is-standard-library-loads-per-process.md): every `ms check` of a file that parses loads the standard library first, about 55 of its 60 ms.
- [Do not accept an empty run](do-not-accept-an-empty-run.md): a runner that reports `0 tests, 0 failed` is a failure.
- [Group e2e tests by the standard-library module they compile](group-e2e-tests-by-the-stdlib-module-they-compile.md): e2e compiles each fixture in Release, and LLVM spends about 6 s on a large module such as yaml once per fixture.
- [Fixtures follow current idiom, except where they test the old form](fixtures-follow-current-idiom-except-where-they-test-the-old.md): after sweeping renames (`to_string`, positional arguments, `--drop-labels`, `get(default)`, `write_bytes`, no `->`), fixtures a…
- [Fuzz regressions become observable tests](fuzz-regressions-become-observable-tests.md): the conformance tool has generated-input fuzzing (`ms-conform fuzz-gen`, `fuzz`).
- [One test binary per crate; e2e stays per fixture](one-test-binary-per-crate-and-why-e2e-stays-per-fixture.md): every crate links its integration tests once (`--test it <module>::`); one big `ms test a.ms b.ms` build is slower than per-fixture on 1 and 4 cores.
- [Source tests return Result and run through `ms test`](source-tests-return-result-and-run-through-ms-test.md): the user asked to replace panic assertions with the standard testing API, to use pipe chains where they clarify the flow, and to remove host…
- [Numeric tests use boundary values and an exact reference](numeric-tests-use-boundary-values-and-an-exact-reference.md): `@std/test/boundary.ms` lists extreme Int and Float inputs, and the numeric fixture compares the stdlib with BigInt/BigRat references.
- [Scaling gate compares growth ratios, not wall time](scaling-gate-compares-growth-ratios-not-wall-time.md): `make scaling-check` generates 1k/10k/100k inputs and fails when the 100k/10k ratio exceeds 30; passes use index-anchored side tables, not rescans.
- [The resource matrix generates every operation, call form and argument form](resource-matrix-generates-every-operation-and-call-form.md): `make resource-matrix` runs each accepted (operation, call form, argument form) against a made/closed oracle; passthrough is read from declarations.
- [The close matrix generates every resource shape and construct](close-matrix-generates-every-shape-and-construct.md): `make close-matrix` runs each accepted (resource shape, language construct) against the made/closed oracle; found two argument-conversion leaks.
- [Conformance is the golden suite](conformance-is-the-golden-suite.md): one runner, no duplicate Rust tests for behavior `.ms` fixtures already cover, regression test per fix.
