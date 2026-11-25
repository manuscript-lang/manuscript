[Wiki](../index.md) › [Testing and conformance](index.md)

# The counting runtime is the stats preset

Verified (2026-11-23): leak, cancel and count gates run against `cmake --preset stats` (`MS_STATS=ON`), whose `ms` links a runtime that prints `ms-rt live blocks at exit`, `ms-rt counts` and, with `MS_PARK_COUNT`, `ms-rt parks` on standard error. `MS_CANCEL_AT_PARK=k` cancels the k-th park. `MS_STATS_TRACE=1` prints the allocation site of each live block; resolve the addresses with `addr2line -e <executable>` (copy the executable of `ms test` while it runs, it is deleted afterwards).

- A count that is not zero for `fn main() Int: return 0` is a runtime bug: process-lifetime tables (the capture table, retired pipe cells, the idle registry, the watcher thread) are released by the stats exit path, and a thread with no scheduler must not create one (`ms_token_free`).
- A leak the corpus shows is a compiler or native ownership bug, not counter noise; the sweep currently reports 0 leaking programs.
- `MS_ALLOC_LIBC=1` (stats runtime only) takes blocks from libc `malloc` instead of mimalloc, so valgrind sees a use after free, a double free or a read of uninitialized memory that mimalloc's pages hide. Build the program with `ms build`, then `MS_ALLOC_LIBC=1 valgrind -q <program>`. A program that stays on the main task runs clean; switching task stacks still floods valgrind (see the poisoned-slots page). The live-block count alone misses a stale read: a record that kept a pointer to a freed list printed an empty string and counted zero leaks (#6979).
- Counters live behind `#ifdef MS_STATS`; normal presets compile them away.

Apply when: adding process-global runtime state (free it in the stats exit path) or a runtime thread.
Evidence: [proposal](../../proposals/c-runtime-stats-variant.md), [stats.c](../../../src/runtime/core/stats.c), [leak-check](../../../tools/leak-check.ms).
Verify: `ms run tools/leak-check.ms` reports no leak a fix did not cause.
