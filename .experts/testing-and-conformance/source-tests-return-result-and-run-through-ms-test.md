[Wiki](../index.md) › [Testing and conformance](index.md)

# Source tests return Result and run through `ms test`

Decision: the user asked to replace panic assertions with the standard testing API, to use pipe chains where they clarify the flow, and to remove host-language orchestration of Manuscript conformance. Assertions return Result; helpers propagate errors, and task callers inspect returned Results after joining. Physical `.ms` tests use Result errors and run through `ms test`; keep deliberate fault/Never/nonexecution subjects as embedded source fixtures. Prove skipped callbacks with invocation assertions instead of panic sentinels.

Verified: runners that accepted `0 tests, 0 failed` and bypassed CLI argument handling hid breakage. Runner flags must not become test host arguments.

Apply when: adding source conformance cases, assertion helpers, or changing test entrypoints.
Evidence: [testing declarations](../../stdlib/test.ms), [core parity project](../../tests/e2e/testdata/projects/core_parity/conformance_test.ms).
Verify: `make conform`; source tests use `try`, pipeline calls do not discard Result errors, and invalid or incomplete reports fail.

---
Topics: [Testing](../topics/testing.md)
