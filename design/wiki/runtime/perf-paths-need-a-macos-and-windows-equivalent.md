[Wiki](../index.md) › [Runtime](index.md)

# Perf paths need a macOS and Windows equivalent

Rule (owner, 2026-11-12): fixes are cross-platform; measuring on Linux is fine. A Linux-only fast path (`madvise(MADV_HUGEPAGE)`, epoll tuning, `MADV_GUARD_INSTALL`) gets an equivalent for macOS and Windows or a note on why none exists, and the macOS and Windows CI is dispatched before the change is called fixed.

Verified failure (Rust era, 2026-11-12): the global allocator for the native standard modules was installed on Linux only, so macOS and Windows programs paid libc `malloc` on every native allocation; and a lock taken inside the allocator allocated on macOS (`pthread_mutex_t` boxed on first use), recursed, and died on the stack guard. Nothing an allocator reaches may allocate. The C runtime allocates through mimalloc (`src/base/alloc.c`) on every platform.

Apply when: adding a fast path that uses a Linux-only mechanism.
Evidence: [pr-checks-skip-windows](../repository/pr-checks-skip-windows-so-dispatch-the-full-matrix.md), `src/runtime/sys/{posix,windows}/`.
Verify: the dispatched Windows and macOS runs pass.
