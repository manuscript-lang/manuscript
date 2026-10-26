# Testing and conformance lessons

How behavior is proven in this repository. Test-API semantics (plans, fixtures, hooks) are in [runtime.md](runtime.md); CI mechanics are in [repository.md](repository.md).

### Choose the layer that can fail for the right reason

Verified: the layers are Rust unit and integration tests per crate (`cargo nextest run --workspace`); the frozen conformance corpus in `tests/conformance/fixtures` (run, check, test, parse phases, gated by `make conform`); `.ms` fixtures under `tests/e2e/testdata/` (`accept`, `reject`, `stdlib`, `projects`, `shutdown`) that seed the corpus; and documentation fences checked by `make docs-check`. A language change needs an accepting case and a rejecting case; a stdlib change needs its module fixture; a lifetime or cancellation change needs observable close/cancel/join cases.

Apply when: deciding where a regression test belongs.
Evidence: [conformance corpus](../tests/conformance/README.md), [development checks](../documentation/contributing/development.md), [Makefile](../Makefile).
Verify: the test fails on the unfixed code, then passes; `make verify` and the affected target (`make conform`) pass.

### C drivers must execute against the production runtime

Verified: the native C smoke harness compiled and linked with obsolete one-word string return/message declarations, then aborted at its first call. The adjacent benchmark also retained a six-word map after `MapVal` grew to seven words. Successful linking cannot check C declarations against Rust exports.

Apply when: changing runtime value layouts or exported signatures. Use the canonical [C string header](../crates/ms-rt-abi/include/ms_abi.h), audit the remaining declarations against `ms-rt-abi`, and keep the production archive driver in the regular test suite.
Evidence: [C driver regression](../crates/ms-native/tests/c_smoke.rs), [smoke checks](../crates/ms-rt/tests/e2e/run.sh).
Verify: `cargo nextest run -p ms-native --test c_smoke` exercises strings, faults, guard messages, joins, cancellation, argument lists, profiling, and the adjacent benchmark's results on Linux. Other native hosts retain their existing runtime and generated-program tests.

### Conformance expectations are frozen contracts

Decision: the corpus expectations were first recorded from the Go `ms` and are now the contract; the Go implementation is gone and is not needed to extend them. Known differences of the Rust `ms` are listed in `tests/conformance/expect-fail.txt` with a reason, and fixtures tagged `aliasing` are excluded because the value-semantics migration changes them on purpose. Remove an expect-fail entry when it is fixed; do not add one to hide a new regression.

Apply when: a conformance case fails, or a deliberate semantic change alters recorded output.
Evidence: [corpus README](../tests/conformance/README.md), [expected failures](../tests/conformance/expect-fail.txt), [runner](../crates/ms-conform/src/runner.rs).
Verify: `make conform` reports a nonempty plan with no unexpected failures or unexpected passes.

### Source tests return Result and run through `ms test`

Decision: the user asked to replace panic assertions with the standard testing API, to use pipe chains where they clarify the flow, and to remove host-language orchestration of Manuscript conformance. Assertions return Result; helpers propagate errors, and task callers inspect returned Results after joining. Physical `.ms` tests use Result errors and run through `ms test`; keep deliberate fault/Never/nonexecution subjects as embedded source fixtures. Prove skipped callbacks with invocation assertions instead of panic sentinels.

Verified: runners that accepted `0 tests, 0 failed` and bypassed CLI argument handling hid breakage. Runner flags must not become test host arguments.

Apply when: adding source conformance cases, assertion helpers, or changing test entrypoints.
Evidence: [testing declarations](../stdlib/testing.ms), [core parity project](../tests/e2e/testdata/projects/core_parity/conformance_test.ms).
Verify: `make conform`; source tests use `try`, pipeline calls do not discard Result errors, and invalid or incomplete reports fail.

### Fixtures follow current idiom, except where they test the old form

Decision: after sweeping renames (`to_string`, positional arguments, `--drop-labels`, `get(default)`, `TextError`, `write_bytes`, no `->`), fixtures are migrated to the new spelling; only rejected-variant fixtures keep removed syntax, and only to assert the diagnostic. A fixture that uses a removed name to pass is a stale test, not a compatibility contract. Accepted fixtures keep some/none `match` only when testing match semantics; nested `match` is guarded by `make repo-check`.

Apply when: a rename or removal lands, or a rebase brings in fixtures written before it.
Evidence: [nested-match check](../crates/ms-repo-check/src/nested.rs); `ms-repo-check` skips `tests/conformance/fixtures/` because those inputs are frozen.
Verify: `rg` for the old spelling finds only reject fixtures and intentionally scoped allowances.

### Do not accept an empty run

Verified: a runner that reports `0 tests, 0 failed` is a failure. Any new runner, shard script, or report parser needs a guard against empty inventories and a test that injects the empty case. `make conform` shards with `CONFORM_SHARD=i/n`; a single shard may legitimately select nothing only if the full inventory is nonempty.

Verified: an expected-failure regex matches the full `module::name` identity. A regex anchored at the bare test name can select nothing; accepting its nonzero exit as an expected failure hides an already passing test. The e2e runner validates selection with `--list --match` before accepting a failing execution.

Verified: merging a stale manifest can restore a fixed expected-failure entry while preserving its implementation fix. The corpus gate must use `--strict`, and quiet output must name unexpected passes so a green ordinary replay cannot conceal the restored marker. The [CLI regression](../crates/ms-conform/tests/unexpected_pass.rs) checks both the identity and strict exit status.

Apply when: adding test entrypoints, sharding, or report parsers.
Evidence: [conformance runner](../crates/ms-conform/src/runner.rs), [Makefile](../Makefile).
Evidence: [e2e runner selection regression](../crates/ms-repo-check/tests/e2e_runner.rs), [e2e runner](../scripts/e2e.sh).
Verify: an injected discovery failure exits nonzero.

### Fuzz regressions become observable tests

Verified: the conformance tool has generated-input fuzzing (`ms-conform fuzz-gen`, `fuzz`). A fuzz-found failure becomes an observable regression test before it is called resolved, with the minimized input kept in the test.

Apply when: fixing a crash found by fuzzing or adding timing-sensitive tests.
Evidence: [fuzz module](../crates/ms-conform/src/fuzz.rs), [corpus README](../tests/conformance/README.md).
Verify: the minimized input lives in a regression test.
