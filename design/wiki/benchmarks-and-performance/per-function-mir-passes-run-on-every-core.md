# Per-function MIR passes run on every core

Verified (2026-11-26): the optimizer ran one function after another, 2.7 s of a 6 s Debug build of a 123k-line project. `function_passes`, `simplify` and `unwind thread` (`src/compiler/opt/`) now go through `opt_parallel_funcs` (`opt_util.c`, on `base/parallel.h`, libuv threads). Debug build 6.0 to 5.5 s, Release `conform-run` 2.09 to 1.85 s on 4 cores.

The rule that makes it safe: a pass changes only its own function and adds to no module table. Each worker gets a copy of the module struct with an arena of its own (new operand arrays come from it), and the arenas are joined to the module's afterwards. After the loop the copy must equal the module apart from the arena, or the build stops with "a per-function pass changed the module": a pass that interns a type, name or string belongs in a serial step. A pass that reads other functions' bodies cannot use it (`inline`, `entry_ranges`, `fuse`).

Apply when: adding a per-function pass (use `opt_for_each_func`), or finding the optimizer serial in a profile. Next candidates: `copyelim`, `lastuse`, `strfuse`, `thread`; the `unwind thread` pass is quadratic in a huge function (analysis recomputed per threaded branch).
Evidence: `bench/perf/results.md#suite` (2026-11-26); the output of `ms emit --opt` is identical on one and four cores (`taskset -c 0`).
