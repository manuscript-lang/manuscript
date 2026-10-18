# Testing and conformance lessons

How behavior is proven in this repository. Test-API semantics (plans, fixtures, hooks) are in [runtime.md](runtime.md); CI mechanics are in [repository.md](repository.md).

### Choose the layer that can fail for the right reason

Verified: the layers are Go unit tests per package; `tests/e2e/testdata/accept` and `reject` (accepted fixtures run their `test` blocks, rejected cases assert diagnostics); `tests/e2e/testdata/stdlib` (one fixture per public module); `projects/` for multi-file modules; `shutdown/` for signals; and tutorial fences run by `make examples-check` / coverage. A language change needs an accept fixture and a reject fixture; a stdlib change needs its module fixture; a lifetime or concurrency change needs observable close/cancel/join cases under `-race`.

Apply when: deciding where a regression test belongs.
Evidence: [development checks](../documentation/contributing/development.md#conformance-and-coverage), [Makefile](../Makefile).
Verify: the test fails on the unfixed code, then passes; `make verify` and the affected target (`make conformance`, `make stdlib-test`, `make race`) pass.

### Source tests return Result and run through `ms test`

Decision: Manuscript conformance uses `ms test` with Result assertions; no panic sentinels, and no Go loops orchestrating `.ms` files. Details and the empty-report guard are in the first entry of [repository.md](repository.md).

Apply when: writing or migrating a `.ms` fixture.
Evidence: [dispatcher](../scripts/conformance.ms), commit c4c5d1bd.
Verify: `make conformance` reports a nonempty plan.

### Fixtures follow current idiom, except where they test the old form

Decision: after sweeping renames (`to_string`, positional arguments, `--drop-labels`, `get(default)`, `TextError`, `write_bytes`, no `->`), fixtures are migrated to the new spelling; only rejected-variant fixtures keep removed syntax, and only to assert the diagnostic. A fixture that uses a removed name to pass is a stale test, not a compatibility contract. Accepted fixtures keep some/none `match` only when testing match semantics; nested `match` is guarded by `make repo-check`.

Apply when: a rename or removal lands, or a rebase brings in fixtures written before it.
Evidence: commits 977c5fe7, 74af558c, 36a3ed43, [nested-match check](../scripts/repo-check/nested_match.go).
Verify: `rg` for the old spelling finds only reject fixtures and intentionally scoped allowances.

### Do not accept an empty run

Verified: a runner that reports `0 tests, 0 failed` is a failure. CI sharding and the conformance dispatcher both reject empty inventories. Any new runner or shard script needs the same guard and a test that injects the empty case.

Apply when: adding test entrypoints, sharding, or report parsers.
Evidence: [shard runner](../scripts/ci-test.sh), [its regressions](../scripts/repo-check/ci_test_test.go).
Verify: injected discovery failure exits nonzero.

### Fuzz and fixture-run time budgets are explicit

Verified: `make fuzz` runs parsing, editor recovery, and compilation for ten seconds each (`FUZZTIME` overrides). A fuzz-found failure becomes an observable regression test before it is called resolved. Race-checked packages run without coverage instrumentation because it makes timing tests flaky.

Apply when: fixing a crash found by fuzzing or adding timing-sensitive tests.
Evidence: [development checks](../documentation/contributing/development.md).
Verify: the minimized input lives in a regression test.
