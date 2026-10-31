[Wiki](../index.md) › [Runtime](index.md)

# Cross-thread cancellation metadata must use atomic accesses

Verified: a volatile read of `Hdr.shield` raced with the owning task's writes through
`Cell<u32>`. Miri reports undefined behavior when `raise_main_cancel` runs concurrently
with `msrt_shield_enter` and `msrt_shield_exit`. The depth now uses `AtomicU32` for all
reads and writes; only the owner changes it, so relaxed loads/stores suffice.

Apply when: publishing task metadata to signal handlers or worker cancellation callers.
Evidence: [concurrent shield regression and ABI checks](../../crates/ms-rt/src/fault.rs).
Verify: `cargo +nightly miri test -p ms-rt concurrent_shield_updates_and_signal_reads` passes; ordinary shielded cancellation tests still pass. Volatile is not synchronization.
