[Wiki](../index.md) › [Runtime](index.md)

# File fixtures own a separate lifetime from each test

Decision: the user chose an ordinary local `make_fixture()` convention and a concrete return type implementing TestHooks; tests use the implicit fixture binding, while hooks use self. No additional declaration or nesting is required. Omitted hooks are no-ops elaborated only for the canonical standard interface; written hooks retain ordinary signature checking and dispatch.

Apply when: changing fixture injection, runner hook ordering, or default hooks.
Evidence: [fixture lowering](../../crates/ms-lower/src/fixture.rs), [fixture fixture](../../tests/conformance/fixtures/e2e/stdlib/testing-fixture.ms), [testing declarations](../../stdlib/test/test.ms).
Verify: no setup for `--list`, one construction across repetitions, per-file isolation, ordinary interface calls to omitted hooks, and failure/cancellation cleanup with preserved machine outcomes.
