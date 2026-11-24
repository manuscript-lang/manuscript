[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Eager arena commit made a program's first large allocations slow

Verified (2026-11-23, linux/amd64 VM, mimalloc 3.6): the same 8000-insert, 8000-lookup `Map[Int, Int]` block took 1.8 ms the first time a process ran it and 0.22 ms the second time. Only `MIMALLOC_ARENA_EAGER_COMMIT=0` closed the gap (0.6 ms); arena reserve size, purge delay and large pages changed nothing. `bench/perf/programs`: `map_put_get_8k` 92 ns per op to 33 (Rust 33), `string_append_50k` 8.1 to 4.3. The build now defines `MI_DEFAULT_ARENA_EAGER_COMMIT=0` (`cmake/targets/third_party.cmake`).

A single-shot benchmark of an allocation-heavy loop measures the first-touch cost of the heap, so read it against a second run before blaming the loop's code. Instruction counts hid this: the two runs execute the same instructions.

Also found: `ms_map_insert` read both descriptors and computed the layout on every call (about 190 instructions per op with growth); an `Int` key with an eight-byte plain value now takes a constant-layout path (`insert_int_word`, 1517M to 1118M instructions for 500 rounds of the 16k-op block).

Apply when: a short benchmark of allocation or collection growth is several times slower than a long run of the same code.
Verify: `MIMALLOC_VERBOSE=1 ./program 2>&1 | grep arena_eager_commit` prints 0.
