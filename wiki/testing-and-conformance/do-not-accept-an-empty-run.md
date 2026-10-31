[Wiki](../index.md) › [Testing and conformance](index.md)

# Do not accept an empty run

Verified: a runner that reports `0 tests, 0 failed` is a failure. Any new runner, shard script, or report parser needs a guard against empty inventories and a test that injects the empty case. `make conform` shards with `CONFORM_SHARD=i/n`; a single shard may legitimately select nothing only if the full inventory is nonempty.

Apply when: adding test entrypoints, sharding, or report parsers.
Evidence: [conformance runner](../../crates/ms-conform/src/runner.rs), [Makefile](../../Makefile).
Evidence: [e2e runner selection regression](../../crates/ms-repo-check/tests/e2e_runner.rs), [e2e runner](../../scripts/e2e.sh).
Verify: an injected discovery failure exits nonzero.
