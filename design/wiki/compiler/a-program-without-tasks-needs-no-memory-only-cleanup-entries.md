[Wiki](../index.md) › [Compiler and build](index.md)

# A program without tasks needs no memory-only cleanup entries

Verified (2026-11-23, callgrind, x86-64): every owned `var` of a droppable type (`var out = List[U](reserve: n)`) registered a `cleanup.push @close.drop.N` entry, and the runtime holds the slot's address, so a loop that pushed onto it reloaded and stored the list header on every push (about 16 instructions per element where Rust needs 5). A fault in a program that starts no task ends the process, so an entry that only frees memory never runs to any effect. `mir_shed` (run in `mir_pipeline_finish`, where `mir_unwind` handles the task case) removes the `close.drop.*` pushes, their `msrt_cleanup_discard`/`cancel` calls and the block parameters that carry the handles, only when every use of the handles is one of those; any other use keeps the function as it was. Entries that close a resource (a file, a user `close`) stay.

`xs.map(f).filter(g).sum()` chain: 664M to 540M instructions; `closures_20M` 47 to 39 ms.

Apply when: adding another way for a handle to be used (it keeps the function out of the pass), or a way for a program without tasks to survive a fault.
Evidence: `src/compiler/mir/mir_shed.c`, `bench/perf/kernels` `closures_20M`.
