[Wiki](../index.md) › [Runtime](index.md)

# The runtime archive is pure C and carries its own 128-bit division

Verified 2026-11-21 (#5256): `cmake -P cmake/BuildRuntime.cmake` folds only the CMake C objects (ours, mimalloc, libuv and the other vendored libraries) into `libms_native.a`, with a musl twin on Linux and `--stats` for the counting runtime. No Rust crate is in the archive, so there is no Rust global allocator and no `compiler_builtins`; `ms-cli`'s build script rejects an archive older than `runtime/` or `cmake/`.

- The Rust staticlib used to supply `__udivti3`, `__umodti3`, `__divti3`, `__modti3`; the C sources divide `__int128` (decimals, big numbers, float formatting), and clang on musl also calls `__udivmodti4`. `runtime/core/int128.c` defines all four, weak. A link error naming one of them means a new 128-bit division needs no new code, only that file in the archive.
- `ms profile --allocs` uses the ordinary archive: the C profiler installs its own sampler. There is no allocs archive.
- `MS_SCHED_STRESS=1` is read by every runtime ([stress mode](scheduler-stress-mode-sends-every-promise-to-another-thread.md)); `make stress-sched` needs no separate build.
- Core C tests link `runtime/core` only, so anything the promise table calls (such as the kept test-capture fault record, `fault_kept.c`) must live in core, not entry.
- Out-parameters a helper writes only for `i < n` leave callers' locals uninitialized on some paths; gcc (`make c-test`) rejects it with `-Wmaybe-uninitialized` where clang does not. Write every slot (`mir_b_params`).
- A mimalloc block must be freed through the C heap: a second allocator for Rust crashed with "invalid page". Keep `msrt_heap_stats` (live bytes via `mi_stats_get`) as the leak measure; ASan tests need `MIMALLOC_PURGE_DELAY=-1`.
