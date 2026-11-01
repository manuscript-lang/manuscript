[Wiki](../index.md) › [Runtime](index.md)

# Shared is changed only through a lock guard

Decision (Chinmay, 2026-10-25): a `Shared` payload is changed through `var guard = lock(box)` from `@std/concurrency/shared.ms` (written `with var guard = lock(box):` until the `with` statement was removed; scope-end drops replaced it, and `guard.close()` ends a critical section early), like Rust's `Arc<Mutex<T>>`; raw `take`/`put` were the manual lock that a cancellation left set (p13). `Shared`, `share`, `lock` and `SharedGuard` live in one module so `take`/`put`/`locked`/`id` are private free functions there, with no checker rule naming a caller file; do not reintroduce them as `Shared` methods (2026-11-01). The file is a mixed module: its source half (`lock`, `SharedGuard.close`) sees the native half's private declarations, and programs import `lock` by the file's path (`stdlib.rs` `import_source`).

Apply when: adding shared state to the stdlib, or touching scope-end cleanup, `Shared`, or cancellation cleanup.
Evidence: [lock proposal](../../proposals/shared-lock.md), [cancel regression](../../tests/e2e/testdata/accept/shared-lock-survives-cancellation.ms).
Verify: that fixture passes; without the slot in `crates/ms-lower/src/close.rs` `var-closes-final-value.ms` reports `[0]` for `[7]`.
