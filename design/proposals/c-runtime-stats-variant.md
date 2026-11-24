# Stats variant of the C runtime (live blocks, parks, copies, poison slots)

## Summary

- Problem: leak-check, cancel-sweep, count-check, ownership-fuzz, `CONFORM_LEAKS` and `poison-check` need counters and hooks that only the Rust runtime has (`ms-rt` feature `stats`, `MS_POISON_SLOTS`). The C runtime has none, so these gates cannot run once Rust is gone.
- Change: a `stats` CMake preset that defines `MS_STATS` and compiles the counters into the C runtime, the same reports on standard error, and `MS_POISON_SLOTS` in the LLVM emitter. Ports of the five tools read the same lines.
- Decision requested: none. The coordinator asked for the checks to be ported, not dropped (2026-11-23).

## Status

Implemented 2026-11-23 against `977a3548`; the stats preset, counters, tools and poison fill landed together.

## Problem

- The tools parse lines the Rust runtime prints at exit: `ms-rt live blocks at exit: N`, `ms-rt parks: N`, `ms-rt counts: allocs=… alloc_bytes=… list_copies=… list_copy_bytes=… string_clones=… string_clone_bytes=…`, and the park hook `MS_CANCEL_AT_PARK=k` (`crates/ms-rt/src/task.rs` `sweep`, `start.rs` `report_leaks`).
- `tools/lib.ms` `use_stats_runtime` builds that runtime with cargo, so each tool starts a cargo build.
- The C runtime has live bytes (`ms_alloc_live_bytes`, `src/base/alloc.c`), thread-local allocation counts (`ms_alloc_counts`) and `MS_TASK_FLAG_BORN_SHIELDED` ("the sweep does not cancel its parks", `scheduler.h:34`), but no block count, park count, cancel hook or copy counters, and nothing frees at exit unless `MS_FREE_AT_EXIT` is set.
- `MS_POISON_SLOTS` has no equivalent in `src/compiler/emit`. The emitter shares stack storage between slots that are not live together (`emit_slot_pool`, `mir_cell_conflicts`), the case poisoning is for.

## Design

- Build: `cmake --preset stats` (RelWithDebInfo, frame pointers, `-DMS_STATS=1`) into `.artifacts/build/stats`. Its `ms` links the stats runtime through `MS_BUILD_RUNTIME`, so tools only change which `ms` they run (`MS_STATS_MS`, default that path). Normal presets never define `MS_STATS`; every hook below is `#ifdef MS_STATS` and compiles away.
- Live blocks (`base/alloc.c`): a striped atomic block count next to the byte count, `+1` per `ms_alloc`/`ms_realloc(NULL)`, `-1` per `ms_free`. `start.c` prints `ms-rt live blocks at exit: N` after `ms_stdout_release`. The stats variant makes `msrt_exit_frees` return 1, as the Rust one did, so tasks still parked are unwound.
- Runtime-owned blocks that outlive teardown (reactor, thread pool, stdout buffer) must be freed by teardown, not subtracted. Any block a trivial program leaves is a bug to fix in the stats variant's exit path; the acceptance test is `main` returning 0 prints 0.
- Counts line: `ms_alloc_counts` of the runtime thread, reset when `main` starts (`main_task`), plus `list_copies`, `list_copy_bytes`, `string_clones`, `string_clone_bytes` bumped in the list and string clone functions under `MS_STATS`.
- Parks: `ms_task_wait_fd_at` and `ms_token_park_at` call `ms_stats_park()` at their cancel check. `MS_CANCEL_AT_PARK=n` makes the n-th park return `MS_WAIT_CANCELLED`, sets the task's cancel flag so a swallowed cancel fails at the next park, and skips tasks with `MS_TASK_FLAG_BORN_SHIELDED` and parks inside a shield. A worker's idle park is marked internal and not counted. `MS_PARK_COUNT=1` prints `ms-rt parks: N`.
- Per-test counts: none. No tool needs one in the C test runner; tools run a test alone (`--test`), as cancel-sweep does. Park counts match the Rust placement: after a posted token value and `ready_now` return, at the cancel check.
- Poison: `mir_cell_conflicts(..., want_deaths, ...)` also returns the instructions after which a shareable object is not read again on any path out of its block (the backward walk it already makes). With `MS_POISON_SLOTS=1` (read in `src/cli/pipeline.c`, off by default, part of the build options) `emit_poison_fills` writes a volatile `0xDD` fill over that object's bytes of its shared cell. It covers cells; a slot that keeps its own `alloca` is not shared and is not filled. LLVM is the only backend in `src/compiler/emit`, so the Cranelift pass of the old target is gone. `tools/view-matrix.ms` reads the same option.
- `ms-rt live blocks by size` (a diagnostic) is dropped. `MS_HEAP_FACTS=off` has no C equivalent and is removed from `count-check.ms` unless LLVM elides counted allocations. Ownership-count headers are re-recorded against the C runtime. `tools/conform.ms` is deleted: `conform-run.ms` already exists and gains the `CONFORM_LEAKS` and poison options.
- The Rust-heap line (`ms-rt rust heap at exit`) has no C counterpart: all runtime memory goes through `ms_alloc`, so the live-block count covers it. `cancel-sweep` drops the `heap:` comparison.
- Tools: `use_stats_runtime` becomes "build the stats preset, return its `ms` path"; `tools/conform.ms` is replaced by `conform-run.ms` with `MS` set to the stats `ms` (`CONFORM_LEAKS=1`) or `MS_POISON_SLOTS=1`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `CMakePresets.json`, `cmake/targets/*.cmake` | `stats` preset, `MS_STATS` definition | `cmake --build --preset stats` |
| `src/base/alloc.[ch]` | block count | `core_alloc` unit with a leaked block |
| `src/runtime/entry/start.c` | exit report, counts reset at `main`, free at exit | hello program prints 0; a leaking program prints 1 |
| `src/runtime/core/{park,token}.c`, new `stats.[ch]` | park count and cancel hook | `tools/cancel-sweep.ms` on one stdlib fixture |
| `src/runtime/core/{list,string_*}.c` | copy counters | `tools/count-check.ms` over `tests/ownership-counts` |
| `src/compiler/mir/mir_slot_scope.c`, `src/compiler/emit/{emit_call,emit_func}.c`, `src/cli/pipeline.c` | cell deaths, poison fill, option | `tools/view-matrix.ms`, `make poison-check` |
| `tools/{lib,leak-check,cancel-sweep,count-check,ownership-fuzz,conform}.ms`, `Makefile` | run the stats `ms` | each tool on its corpus |

## Alternatives

- Do nothing: the gates stay on Rust and block deleting it. Rejected by the coordinator's direction.
- Always-on counters in the normal runtime: a block count and a park count cost an atomic add per allocation and park on every program. Rejected; the Rust runtime kept them out of release builds for the same reason.
- A second set of runtime archives selected with `MS_RUNTIME` (what `use_stats_runtime` does today with `MS_RT_LIB`): avoids rebuilding the compiler, but needs a variant of the 34 `ms_library` targets that depend on the changed files. The preset recompiles the compiler and third_party once per machine (ccache after that) and adds no CMake target logic. `src/base/alloc.c` is shared with the compiler, which then also counts blocks (one relaxed add per allocation, stats preset only).
- Valgrind or ASan leak checking: finds leaks in one process but cannot cancel at the n-th park or compare allocation counts to the expected headers.

## Stages

1. Block count, exit report, free at exit, `stats` preset: hello and a leaking program; `tools/leak-check.ms` on its corpus.
2. Parks and cancel hook: `tools/cancel-sweep.ms`.
3. Copy counters: `tools/count-check.ms`, `ownership-fuzz.ms`.
4. Poison fill and `make poison-check` on `conform`.
