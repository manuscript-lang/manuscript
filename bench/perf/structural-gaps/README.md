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

## 2026-11-12, self-recursive functions unrolled once

Same machine as the section above; before is the stack-check change, after adds the unrolling.

| program | before | after | C |
| --- | ---: | ---: | ---: |
| `recursion.ms` (`fib(32)`) instructions | 137.81M | 98.37M (-29%) | 72.4M |
| `recursion.ms` wall | 19 to 20 ms | 12 to 14 ms | |

- The MIR inliner copies the body of a small (at most 40 instructions) directly self-recursive function with at most two self calls into those calls once. A copy runs without a call, a frame-pointer setup or a recursion check; the calls inside it enter the function as before, so the check still runs once per physical frame. `fib` makes half the calls. The function is then marked `Never`, so the pass unrolls it once however often it runs.
- Fault reports are unchanged: the frame walk spends one step per logical frame, so the runaway-recursion report still ends at 999,996 repeats. Repeated frames are compared by text, since an inlined copy names its function by another table offset.

## 2026-11-12: borrowed key in `Map.update`, and a counted `split` that did not pay

`3d4d48b1`, same machine, `logstats` on 35,000 lines of the generated log (callgrind instructions, memcheck allocation counts) and on 22 MB (min of 25, ms).

- `add` and `add_default` already borrowed a cloned key (`borrowed_key_add`). `update` now does too: `m.update(f[3].clone(), ..)` on a `String`-keyed map reads `f[3]` in place and the runtime copies the key only when the entry is new. Keys of 22 bytes or fewer never allocated, so `logstats` (path keys) does not change: 152,022 allocations before and after, 104 against 105 ms. The change helps keys over 22 bytes (the byte-scan `logstats` copies one per line).
- Sizing the `split` list once for a one-byte separator (a `memchr` count pass, as the empty separator already does) cut `logstats` from 161,350 to 126,350 allocations (4.6 to 3.6 per line) and instructions from 127.8M to 120.3M, but wall time rose from 103 to 111 ms (min of 25, three runs agree). The extra pass over a 47-byte line costs more than the removed `realloc` saves with the release allocator, so it was not kept. Callgrind allocation rows overstate release cost (see above); judge allocation changes by wall time.
- The remaining `logstats` allocations are the copies of pieces over 22 bytes that `split` makes and the line itself: track 2 (lend), not stage 1.

## 2026-11-12: interface borrow in the frame

A borrowed value converted to an interface (`total(sq)` for `fn total(x: Shape)`) built a heap box of its leaves per call. When the `iface.borrow` result only reaches calls whose result is not a view of their arguments, and drops, the Cranelift lowering now keeps the leaves in a stack slot and tags the value as owning nothing (tag 2); any other use (return, branch argument, store, view-returning call) keeps the box. Probe (1,000 calls of `total(sq)` in a loop, `/tmp` build, callgrind instructions are for the whole process including startup, memcheck counts allocations): 1,013 to 13 allocations, 666,910 to 350,901 instructions (callgrind uses glibc `malloc`, so the instruction drop overstates release cost). Fixture: `e2e/stdlib/interface-borrow-in-frame`.

Closure captures: a closure passed to a call and not stored already allocates nothing (1,000 calls of `apply(fn x: x + k, i)`: 13 allocations in total). A closure stored in a list must escape the frame, so its environment stays on the heap; no change.

## 2026-11-12: nested element writes

Same machine; Release LLVM build; callgrind instruction totals. `grid.ms` is LCS over a 2001 x 2001 `List[List[Int]]`; `c/grid.c` is its C twin (`gcc -O2`).

| program | before | after | c |
| --- | ---: | ---: | ---: |
| `grid.ms` | 146.5M | 113.4M | 79.6M |

- `dp[i][j] = v` now lowers to `list.set` on the borrowed row `dp[i]`, written where it lies (`slot_list_set`, `crates/ms-lower/src/native/list.rs`). The row's `{ptr, len, cap}` are no longer taken out and stored back after every element write.
- List element loads and stores carry an alias region (`crates/ms-clif/src/lower.rs`): scalar elements and list or string headers are different regions. The LLVM emitter writes them as TBAA tags, so an `Int` store no longer forces reloading the previous row's header (about 4M instructions here). Only the LLVM backend gets them: a Cranelift alias region means disjoint from every other access, so tagging there dropped stores (`e2e/stdlib/queues` failed on macOS debug builds).
- Remaining gap: the bounds checks on `dp[i - 1]`, `dp[i]` and `a[i - 1]` and the current row's header load, which LLVM cannot hoist (they sit behind a data-dependent branch and a list buffer is not known to be dereferenceable). With every runtime check disabled the program is 91.3M, so a perfect range pass could close at most 22M of the 33.8M gap; it cannot prove the row-internal checks. Not pursued.
- Table build (`[0].repeated(m + 1)` per row) is 26.3M of the 113.4M. A doubling `splice` fill cut that to 20.5M instructions but not the wall time (19.4 ms for the table alone against 22.4 ms for `calloc` in C), so it was not shipped (#3645).
