# Structural gaps

Evidence for [`proposals/c-parity-structure.md`](../../../proposals/c-parity-structure.md): where ordinary Manuscript spends its time against C once single runtime calls are tuned. Two programs.

- `shapes.ms`: the same work in the shape lowering recognizes and in a neighboring shape (a binding, a helper argument, a combinator chain). Prints microseconds per case.
- `logstats_bytes.ms`: [`engineering/ms/logstats.ms`](../engineering/ms/logstats.ms) written as a byte scan with no `split`, the code a C programmer would write. It bounds what removing per-line lists and copies can gain.

```sh
ms build bench/perf/structural-gaps/shapes.ms -o /tmp/shapes && /tmp/shapes
MS=./target/release/ms BENCH_OUTPUT=/tmp/eng sh bench/perf/engineering/run.sh 1
ms build bench/perf/structural-gaps/logstats_bytes.ms -o /tmp/logstats_bytes
head -c 2000000 /tmp/eng/input/access.log > /tmp/small.log
valgrind --tool=callgrind /tmp/logstats_bytes < /tmp/small.log
```

Compare only runs from one machine. Callgrind sends allocations to glibc `malloc` ([wiki](../../../wiki/benchmarks-and-performance/callgrind-needs-a-smaller-allocator-reservation.md)), so allocator rows overstate the release cost; allocation counts are exact.

## 2026-11-12: Linux x86_64

`fff26e41`, Release LLVM `ms`, gcc 13.3 `-O2`, 4 vCPU Xeon 2.1 GHz shared VM.

### Shapes (min of 5, microseconds)

| work | recognized shape | us | neighboring shape | us | ratio |
| --- | --- | ---: | --- | ---: | ---: |
| sum a field of 200k map values | `for p in m.values():` | 1,134 | `vals := m.values()` then `total(vals)` | 11,024 | 9.7x |
| | | | `total(m.values())` | 4,510 | 4.0x |
| count a character in 860 KB | `for c in text.chars():` | 565 | `count_o(text.chars())` | 10,008 | 17.7x |
| first field of a 47-byte line, 1M times | `line.index_of(" ")` and `line.view(..)` | 20,411 | `f := line.split(" ")` then `f[5]` | 81,763 | 4.0x |
| filter, double, sum 2M `Int` | hand loop | 2,270 | `xs.filter(..).map(..).sum()` | 6,916 | 3.0x |
| sum a field of half of 200k records | hand loop | 1,421 | `for p in ps.filter(..):` | 2,352 | 1.7x |

### Engineering tasks on 2 MB of input (callgrind instructions, memcheck allocation counts)

| task | ms instructions | c instructions | ms / c | ms allocations | c allocations | generated code share of ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| grep (35,521 lines) | 23.3M | 13.5M | 1.73x | 84 | 4 | 3.1% |
| logstats (35,521 lines) | 112.5M | 37.0M | 3.04x | 152,022 | 9 | 8.1% |
| wordfreq (19,821 lines) | 113.6M | 66.3M | 1.71x | 3,874 | 8 | 69.1% |
| csvgroup (56,045 rows) | 248.6M | 57.4M | 4.33x | 303,035 | 9 | 17.4% |

Largest native rows: `ms_rt::string::find` 37.8% of `grep`; `msrt_string_split` 11.6%, `owned_copy` 10.4% and `find` 9.9% of `logstats`; `msrt_string_view` 20.7% of `wordfreq` (the rest of its `fields_by` is `.ms` source, 38.2%); `msrt_string_split` 7.4% of `csvgroup`.

"Generated code share" is the instructions spent in code compiled from `.ms` (the program and `@std` source); the rest is the native runtime, the allocator and libc. `logstats` allocates 4.3 times per line and `csvgroup` 5.4 times per row; C allocates the input buffer and the table.

### `logstats` three ways (same 2 MB)

| version | instructions | allocations | wall on 22 MB, min of 5 |
| --- | ---: | ---: | ---: |
| `engineering/ms/logstats.ms` (`line.split(" ")`, `f[3].clone()`) | 112.5M | 152,022 | 99 ms |
| `for part in line.split(" ")` with a field counter | 123.9M | 127,890 | not timed |
| `logstats_bytes.ms` (byte scan, `Bytes.view`) | 64.7M | 45,450 | 74 ms |
| `engineering/c/logstats.c` | 37.0M | 9 | 58 ms |

- The piece iterator is no cheaper than the list: `msrt_split_next` is 109 instructions per piece (284,173 calls) and the iterator and each kept key still allocate.
- The byte scan removes 42% of the instructions. What is left against C is the scan itself (about 20 instructions per input byte in the compiled loop against `memchr`) and one key copy per line: `Map.update` takes an owned key, so a key that is already present is still copied and freed.

### Other shapes (same build, one run, noisy)

- Building 1M closures that capture one `Int` into a `List[fn(Int) Int]`: 27.7 and 28.4 ms, about 28 ns each.
- Skeptical review rerun of the `split` row with a borrowed-parameter receiver and `f.get(5)`, 1M calls: `msrt_string_split_view` 69 to 70 ms, `msrt_string_split` 78 to 81 ms, `index_of` and `view` 19 to 20 ms. Lending the pieces is worth 12% to 15%; the list and the per-piece calls are the rest. The view entry is chosen only for a parameter receiver read through `get`, `length` or `is_empty` (`crates/ms-lower/src/native/method.rs:106`, `mutation.rs:214`); `f[5]` takes the copying entry.

## 2026-11-12, second pass: loops, calls, exit and file work

Same build and machine. `grid.ms`, `accumulate.ms`, `recursion.ms` and `teardown.ms` have C twins in `c/` (`gcc -O2`); instructions are callgrind totals, wall times are five runs.

| program | ms | c | note |
| --- | ---: | ---: | --- |
| `grid.ms`: LCS over a 2001 x 2001 `List[List[Int]]` | 146.5M | 79.6M | inner loop 30 instructions per cell against 12 |
| `accumulate.ms`: `cells[i].hits += 1`, `cells[i].sum += i`, `total += 1`, 400M updates | 583 to 696 ms | 166 to 291 ms | C with trapping adds (`accumulate_checked.c`): 525 to 645 ms |
| `recursion.ms`: `fib(32)` | 144.9M | 72.4M | 20.7 instructions per call against 10.3 |
| `teardown.ms`: build a 500k-entry `Map[String, Rec]`, print its length, exit | 168 to 218 ms | | build alone 139 to 187 ms; 25 to 33 ms is freeing at exit |

- `grid`: each cell reloads both row headers from the outer list, and after the element store writes the row's `{ptr, len, cap}` back (three stores a cell), because `dp[i][j] = v` takes the row out and puts it back and LLVM cannot tell that an `Int` store leaves a list header unchanged. A flat `List[Int]` with `i * w + j` is 132.8M: the bounds and overflow checks are most of the rest.
- `accumulate`: Manuscript matches C with trapping adds; unchecked C is 2.7x to 3.5x faster because the loop vectorizes. An overflow flag tested once per outer pass does not help (60.3M to 80.3M instructions against 64.3M trapping, 24.3M unchecked, on 4M updates).
- `recursion`: the stack check is 5 of the instructions per call and two dependent loads (`and`, load the limit's address, compare with the limit). `gcc` also turns the second call into a loop, which is half of the gap.
- `engineering/pargroup` (2,000 files, 4 workers): 53 to 79 ms against 21 to 37 ms. `strace -c -f`: 4,707 `futex`, 1,505 `epoll_wait` and 1,512 `write` calls where C makes none; each `read_file` inside a worker hands the read to a pool thread and waits to be woken.
- At or ahead of C, so not opportunities: `Result` and `?` on a hot path (12.5 instructions per call and check), interface dispatch over a `List[Shape]`, `print` of interpolated lines (0.67x `printf`), `String +=` (1.02x), `parse_int` (80 instructions against `strtoll` 145), process start (0.4 ms more).

## 2026-11-12, exit drops and the stack check

Same machine and `gcc -O2` twins as the second pass. Before is `main` at `f5b0b6b8`; after adds the two changes below. Instructions are callgrind totals; wall times are five runs of the built program.

| program | before | after |
| --- | ---: | ---: |
| `teardown.ms` instructions | 1,794.7M | 1,180.2M (-34%) |
| `teardown.ms` wall | 211 to 243 ms | 165 to 175 ms |
| `recursion.ms` (`fib(32)`) instructions | 144.86M | 137.81M (-4.9%) |
| `recursion.ms` wall | 19 to 21 ms | 19 to 20 ms |

- Exit drops (opportunity 4): `ms_mir::exit_drops` gates the drops on `main`'s return paths whose type is plain memory (strings, bytes, lists, maps, sets, big integers, optionals, records and alternatives of those) behind `msrt_exit_frees`. A closure, an interface value or a runtime handle is never gated, and the close call of a closeable owner is not a drop, so resources still close in the same order (`e2e/accept/main-exit-closes-resources`). The counting runtime of `make leak-check` and `MS_FREE_AT_EXIT=1` (valgrind) keep the frees: `make leak-check` still reports 0 of 382 leaking. A `main` that something calls again keeps every drop. The wall time drops by about 45 to 70 ms; the build itself is unchanged.
- Stack check (opportunity 7): the recursion limit of the running stack segment is copied into the region cell beside the task block's address (`STACK_LIMIT_CELL`), so the check is `mov`, `and`, `cmp` against memory, `ja` (4 instructions, one load) instead of the second dependent load through the block (5 instructions). The runtime keeps the cell current when a task is switched in, a segment is added or left, a fault shrinks the limit for cleanups, and a guard unwinds. 1.0 instruction per `fib` call (20.7 to 19.7); the wall time does not move beyond noise, because the removed load hit the cache and the check is not on the critical path of `fib`. Checking once per recursion cycle was not built: a self-recursive function is its own cycle, so `fib` would still check every call.
