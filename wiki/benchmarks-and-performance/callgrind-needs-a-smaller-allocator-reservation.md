[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Callgrind needs a smaller allocator reservation

Verified (2026-11-07, `c09-ciphers`): under `valgrind --tool=callgrind` the runtime allocator's 256 GiB page reservation plus 1 TiB grow region cannot be mapped, so `ensure_region` fails and every allocation uses glibc `malloc` and `malloc_usable_size`. The profile then shows 25% malloc/free and 68M instructions where the real run (14 `malloc` calls, counted with an `LD_PRELOAD` shim) needs 44M.

Apply when: profiling any compiled program with valgrind. Locally lower `PAGES_SIZE` (4 GiB) and `GROW_CHUNKS` (4) in `crates/ms-rt/src/alloc.rs`, rebuild with `make build`, rebuild the program, and revert before committing. Confirm with an `LD_PRELOAD` malloc counter that the program no longer reaches glibc.
