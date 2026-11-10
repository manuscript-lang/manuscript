# Arena benchmark

`ms run bench/perf/arena/main.ms` compares `@std/collections/arena.ms` with a recursive `enum Tree` (one allocation per node) and with `Map[Int, Rec]` (churn). See [proposals/arena.md](../../../proposals/arena.md).

## 2026-11-10

Revision `c6a7c5f3` plus the prototype, `ms run` (Cranelift), 4-core Linux container, three runs, ms.

| Benchmark | ms |
| --- | --- |
| tree_boxed_d16_x20 | 29 to 32 |
| tree_arena_d16_x20 | 80 to 91 |
| churn_map_2M_w1000 | 93 to 114 |
| churn_arena_2M_w1000 | 37 to 53 |

Drop (`ms run bench/perf/arena/drop.ms`, four runs, 20 trees of depth 16): boxed drop 19 to 29 ms, arena drop 1.2 to 5.5 ms; build while held: boxed 15 to 27 ms, arena 104 to 132 ms.
