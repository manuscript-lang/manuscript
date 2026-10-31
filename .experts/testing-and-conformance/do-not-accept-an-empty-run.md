[Wiki](../index.md) › [Testing and conformance](index.md)

# Do not accept an empty run

Verified: a runner that reports `0 tests, 0 failed` is a failure. Any new runner, shard script, or report parser needs a guard against empty inventories and a test that injects the empty case. `make conform` shards with `CONFORM_SHARD=i/n`; a single shard may legitimately select nothing only if the full inventory is nonempty.

Verified: an expected-failure regex matches the full `module::name` identity. A regex anchored at the bare test name can select nothing; accepting its nonzero exit as an expected failure hides an already passing test. The e2e runner validates selection with `--list --match` before accepting a failing execution.

Verified: merging a stale manifest can restore a fixed expected-failure entry while preserving its implementation fix. The corpus gate must use `--strict`, and quiet output must name unexpected passes so a green ordinary replay cannot conceal the restored marker. The [CLI regression](../../crates/ms-conform/tests/unexpected_pass.rs) checks both the identity and strict exit status.

Apply when: adding test entrypoints, sharding, or report parsers.
Evidence: [conformance runner](../../crates/ms-conform/src/runner.rs), [Makefile](../../Makefile).
Evidence: [e2e runner selection regression](../../crates/ms-repo-check/tests/e2e_runner.rs), [e2e runner](../../scripts/e2e.sh).
Verify: an injected discovery failure exits nonzero.

---
Topics: [Testing](../topics/testing.md)
