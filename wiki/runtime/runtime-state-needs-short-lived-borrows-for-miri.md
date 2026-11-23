[Wiki](../index.md) › [Runtime](index.md)

# Runtime state is reached through short-lived borrows (Miri, Stacked Borrows)

Verified: the nightly Miri job found aliasing bugs where a `&mut` to per-isolate state stayed alive across a call that fetched the same state again (`alloc_slow` and `grow_resize` in the allocator, `msrt_promise_wait` in the promise table). Each fetch retags, so the older reference is invalid, and a `&mut` passed as an argument is protected for the whole callee. `grow_resize` runs in production, not only in tests.

Rules: do not keep a `&mut State` across a call that may reach the state again; read it again afterwards. `promise::table()` and `ends()` return an `Isolate<T>` handle (a raw pointer that makes one short reference per access), so a handle held across calls stays valid; a function that takes `&mut Table` must not call anything that fetches the table. Store function and data pointers in `AtomicPtr`, and copy slots that may hold pointers in pointer-typed words (`*mut u8`), not `u64`: an integer copy drops provenance. Keep Stacked Borrows on; Tree Borrows accepts more but was not chosen.

Miri has no `mmap` or inline assembly. Tests that need task stacks, context switches, real file descriptors or the memory copy bodies carry `cfg_attr(miri, ignore = "reason")`; exhaustive differential sweeps that take minutes interpreted do too, and the native run still covers them. The owner approved these 31 Miri-only ignores on 2026-11-15; no other test is gated without approval.

Verify: `MIRIFLAGS=-Zmiri-ignore-leaks cargo +nightly miri test -p ms-rt --lib` (about half an hour; run one test with `-- --exact name`). The nightly Miri job was retired with the C release; run it by hand on the Rust runtime history if needed.
