[Wiki](../index.md) › [Repository maintenance](index.md)

# Build steps use the active Cargo invocation's checkout

Verified: with a Cargo target directory shared between checkouts, Cargo reused an `xtask` executable whose compile-time `CARGO_MANIFEST_DIR` named the other checkout. `cargo xtask runtime` rebuilt that checkout's runtime, and the current CLI build then rejected its own stale archive. Cargo supplies the active package's manifest directory at execution time; use that runtime value for checkout-specific build inputs and outputs, with the compiled path only as a fallback for direct execution.


Apply when: a repository tool run by Cargo selects source or output paths, especially with shared build caches or worktrees.
Evidence: [runtime build step](../../crates/xtask/src/main.rs), [active-checkout regression](../../crates/xtask/tests/runtime_root.rs).
Verify: `cargo test -p xtask --test runtime_root`; an executable built elsewhere must pass the active checkout's manifest and runtime output directory to Cargo.
