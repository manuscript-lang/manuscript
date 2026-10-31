[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Compare instruction counts first; a low-IPC gap points at libc

Verified: wall-clock on a shared VM moves by 2x between runs, so compare `valgrind --tool=callgrind` instruction counts of one kernel built in Manuscript and Rust (`rustc -C opt-level=3 -C overflow-checks=on`) before chasing code generation. Most kernels executed fewer instructions than Rust. `text_1M` ran 0.77x Rust's instructions but 3x its time: the program spent its cycles in musl's `memcpy` (`rep movsq` startup on every short copy) and byte-at-a-time `memcmp`. `crates/ms-rt/src/mem.rs` now defines them, and `ms_rt::alloc::StdHeap` replaces musl's malloc for the Rust std natives. Low IPC with modest instruction counts means look at `objdump` of the hottest libc function.

Apply when: a Manuscript program is slower than Rust with similar or fewer instructions, or before replacing a libc routine.
Evidence: [mem routines](../../crates/ms-rt/src/mem.rs), [std heap](../../crates/ms-rt/src/alloc.rs).
Verify: callgrind totals and a wall-clock min of at least five runs before and after; the unit tests in `mem.rs`; no self-call in the disassembly of the replaced symbols.

---
Topics: [Performance](../topics/performance.md)
