# Structural gaps

Evidence for [`proposals/c-parity-structure.md`](../../../proposals/c-parity-structure.md): where ordinary Manuscript spends its time against C once single runtime calls are tuned. Two programs.

- `shapes.ms`: the same work in the shape lowering recognizes and in a neighboring shape (a binding, a helper argument, a combinator chain). Prints microseconds per case.
- `logstats_bytes.ms`: [`suite/logstats/main.ms`](../suite/logstats/main.ms) written as a byte scan with no `split`, the code a C programmer would write. It bounds what removing per-line lists and copies can gain.

```sh
ms build bench/perf/structural-gaps/shapes.ms -o /tmp/shapes && /tmp/shapes
MS=./target/release/ms BENCH_OUTPUT=/tmp/eng sh bench/perf/suite/run.sh 1
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
| `suite/logstats/main.ms` (`line.split(" ")`, `f[3].clone()`) | 112.5M | 152,022 | 99 ms |
| `for part in line.split(" ")` with a field counter | 123.9M | 127,890 | not timed |
| `logstats_bytes.ms` (byte scan, `Bytes.view`) | 64.7M | 45,450 | 74 ms |
| `suite/logstats/main.c` | 37.0M | 9 | 58 ms |

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
- `suite/pargroup` (2,000 files, 4 workers): 53 to 79 ms against 21 to 37 ms. `strace -c -f`: 4,707 `futex`, 1,505 `epoll_wait` and 1,512 `write` calls where C makes none; each `read_file` inside a worker hands the read to a pool thread and waits to be woken.
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

## 2026-11-12, one stack check per recursive cycle

Same machine and Release LLVM build; callgrind instruction totals. `mutual.ms` is the call tree of `fib(32)` written as two functions (`count` calls `pair` calls `count`); the second program is mutual `is_even`/`is_odd` over 3,000 inputs plus a Collatz walk through two helpers (not committed).

| program | before | after |
| --- | ---: | ---: |
| `mutual.ms` | 130.76M | 103.24M (-21%) |
| even/odd and Collatz | 144.26M | 120.28M (-17%) |
| `recursion.ms` (`fib(32)`, one function) | 98.37M | unchanged |

- A function on a call cycle kept its recursion check. Now only the targets of the depth-first back edges keep it (`cycle_breakers`); every cycle closes with a back edge, so every cycle still passes a check and the stack is bounded as before, by one check per cycle plus the longest acyclic chain between checks. The graph still counts an indirect call as an edge to every closure and method, so this is conservative.
- The unchecked functions on a cycle then inline like any other function (`has_check`): every cycle through them still contains a checked function, and a checked function is never inlined. A function that becomes small and directly self-recursive by inlining its sibling is unrolled once as well.
- Before, LLVM happened to merge `count` into `pair` and unroll one level of that; after, MIR does the merge, so the result no longer depends on LLVM's choice.
- Runaway mutual recursion still reports the alternating `ping`/`pong` frames.

## 2026-11-12: borrowed key in `Map.update`, and a counted `split` that did not pay

`3d4d48b1`, same machine, `logstats` on 35,000 lines of the generated log (callgrind instructions, memcheck allocation counts) and on 22 MB (min of 25, ms).

- `add` and `add_default` already borrowed a cloned key (`borrowed_key_add`). `update` now does too: `m.update(f[3].clone(), ..)` on a `String`-keyed map reads `f[3]` in place and the runtime copies the key only when the entry is new. Keys of 22 bytes or fewer never allocated, so `logstats` (path keys) does not change: 152,022 allocations before and after, 104 against 105 ms. The change helps keys over 22 bytes (the byte-scan `logstats` copies one per line).
- Sizing the `split` list once for a one-byte separator (a `memchr` count pass, as the empty separator already does) cut `logstats` from 161,350 to 126,350 allocations (4.6 to 3.6 per line) and instructions from 127.8M to 120.3M, but wall time rose from 103 to 111 ms (min of 25, three runs agree). The extra pass over a 47-byte line costs more than the removed `realloc` saves with the release allocator, so it was not kept. Callgrind allocation rows overstate release cost (see above); judge allocation changes by wall time.
- The remaining `logstats` allocations are the copies of pieces over 22 bytes that `split` makes and the line itself: track 2 (lend), not stage 1.

## 2026-11-12: interface borrow in the frame

A borrowed value converted to an interface (`total(sq)` for `fn total(x: Shape)`) built a heap box of its leaves per call. When the `iface.borrow` result only reaches calls whose result is not a view of their arguments, and drops, the Cranelift lowering now keeps the leaves in a stack slot and tags the value as owning nothing (tag 2); any other use (return, branch argument, store, view-returning call) keeps the box. Probe (1,000 calls of `total(sq)` in a loop, `/tmp` build, callgrind instructions are for the whole process including startup, memcheck counts allocations): 1,013 to 13 allocations, 666,910 to 350,901 instructions (callgrind uses glibc `malloc`, so the instruction drop overstates release cost). Fixture: `e2e/stdlib/interface-borrow-in-frame`.

Closure captures: a closure passed to a call and not stored already allocates nothing (1,000 calls of `apply(fn x: x + k, i)`: 13 allocations in total). A closure stored in a list must escape the frame, so its environment stays on the heap; no change.

## 2026-11-12: stage 1, `decode_utf8` takes a dying `Bytes`

Same machine and `ms` build as above, before and after the change (`bytetake` pass, `msrt_bytes_decode_utf8_take`). Callgrind and memcheck on the 2 MB input, wall time is the minimum of 5 on the 22 MB input.

| task | instructions before | after | allocated bytes before | after | wall before | after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| grep | 23.28M | 22.76M | 6,299,139 | 4,202,043 | 56 ms | 39 ms |
| logstats | 112.45M | 111.83M | 15,248,255 | 13,151,115 | 98 ms | 88 ms |

The saved work is the 2 MB copy of the input and its page faults, which callgrind counts as few instructions, so the wall time is the measure. Allocation counts are unchanged (the buffer is reused, not removed).

## 2026-11-12: inlinable string scans (track 1, first step)

Same machine and build type as above (Release LLVM `ms`; callgrind instructions on the first 30,000 lines of each input, outputs compared byte for byte with the baseline build).

`String.index_of`, `starts_with`, `ends_with` and `view` moved into `ms-rt-hot`: a search in an ASCII text under 128 bytes and a view of an ASCII text inside its bounds are now code the caller inlines; other cases call the runtime as before (`msrt_string_index_of_long`, `msrt_string_view_slow`, the latter keeps the bounds fault). `split` scans a single-byte separator with one searcher and builds pieces of up to 15 bytes inline without a call.

| task | before | after | change |
| --- | ---: | ---: | ---: |
| logstats | 112.86M | 108.45M | -3.9% |
| wordfreq | 167.99M | 152.11M | -9.5% |
| csvgroup | 142.51M | 138.65M | -2.7% |
| grep | 19.73M | 19.70M | 0% |

The 40% ceiling on `logstats` is not reached by this step: what is left is `msrt_string_split` and its list and heap pieces (allocation, `memcpy`, `free`), which are the lending and allocation tracks. `grep` is one long-haystack `memmem` search; nothing inlines there.

### Step 2: `parse_int` and `scalar_at`

`String.parse_int` (all of it) and `scalar_at` on an ASCII text with the index inside it moved into `ms-rt-hot`; out-of-range, non-ASCII and long unflagged cases call `msrt_string_scalar_at_slow`.

| task | step 1 | step 2 | total change |
| --- | ---: | ---: | ---: |
| logstats | 108.45M | 106.95M | -5.2% |
| csvgroup | 138.65M | 136.54M | -4.2% |
| wordfreq | 152.11M | 152.11M | -9.5% |
| grep | 19.70M | 19.79M | +0.3% (layout noise; no call changed) |

### Step 3: `length` and a shared ASCII check

`String.length` and `scalar_length` moved into `ms-rt-hot` (non-ASCII and long unflagged text call `msrt_string_scalar_count_slow`). The ASCII test is one helper that reads the flag or the bits of an inline string, so the earlier steps stopped scanning bytes for short strings. `mixed.ms` case e (200,000-word scan with `==`, `starts_with`, `length`, 20 passes): 301.7M to 265.1M instructions (-12%). logstats 106.47M, wordfreq 149.62M, csvgroup 136.38M on the 30,000-line inputs.

### Step 4: `Set[Int]` without descriptor dispatch

`Set[Int]` `contains` is an inlined probe over the fixed 16-byte slots (`msrt_set_contains_w`, `ms-rt-hot`), and `add` is `msrt_set_add_copy_w` with the same layout; sets stamped with a module's key behaviour keep the general path. A contains-then-add loop over 2M random keys below 100,000 (`/tmp` program, callgrind instructions): 233.3M to 117.4M (-50%). New fixture `set-int-fixed-layout` covers repeats, extreme keys, growth, removal and reinsertion.

### Step 5: no `memmem` searcher for short text

`replace`, `split` and `count` with a multi-byte separator or pattern scan a text under 128 bytes directly (`Needle::for_text`) instead of building a `memmem` searcher per call. A 56-byte line with `replace("::", "--")`, `split("::")` and `contains("trace")`, 300,000 times: 1,014.4M to 877.0M instructions (-13.5%).
## 2026-11-12: nested element writes

Same machine; Release LLVM build; callgrind instruction totals. `grid.ms` is LCS over a 2001 x 2001 `List[List[Int]]`; `c/grid.c` is its C twin (`gcc -O2`).

| program | before | after | c |
| --- | ---: | ---: | ---: |
| `grid.ms` | 146.5M | 113.4M | 79.6M |

- `dp[i][j] = v` now lowers to `list.set` on the borrowed row `dp[i]`, written where it lies (`slot_list_set`, `crates/ms-lower/src/native/list.rs`). The row's `{ptr, len, cap}` are no longer taken out and stored back after every element write.
- List element loads and stores carry an alias region (`crates/ms-clif/src/lower.rs`): scalar elements and list or string headers are different regions. The LLVM emitter writes them as TBAA tags, so an `Int` store no longer forces reloading the previous row's header (about 4M instructions here). Only the LLVM backend gets them: a Cranelift alias region means disjoint from every other access, so tagging there dropped stores (`e2e/stdlib/queues` failed on macOS debug builds).
- Remaining gap: the bounds checks on `dp[i - 1]`, `dp[i]` and `a[i - 1]` and the current row's header load, which LLVM cannot hoist (they sit behind a data-dependent branch and a list buffer is not known to be dereferenceable). With every runtime check disabled the program is 91.3M, so a perfect range pass could close at most 22M of the 33.8M gap; it cannot prove the row-internal checks. Not pursued.
- Table build (`[0].repeated(m + 1)` per row) is 26.3M of the 113.4M. A doubling `splice` fill cut that to 20.5M instructions but not the wall time (19.4 ms for the table alone against 22.4 ms for `calloc` in C), so it was not shipped (#3645).

## 2026-11-12, third pass: character code and library containers

Same build and machine; callgrind instructions, C twins in `c/`.

| program | ms | c | ms / c |
| --- | ---: | ---: | ---: |
| `tokens.ms`: tokenizer over 680 KB with `text.get(i)` and `c == "+"` | 173.4M | 15.1M | 11.5x |
| `tokens_scalars.ms`: the same with `text.scalar_at(i)` and `c == 43` | 107.5M | 15.1M | 7.1x |
| `queues.ms`: grid BFS over `Deque[Int]`, then 2M `PriorityQueue[Int]` operations | 1,527M | 603M | 2.5x |

- `tokens`: `msrt_string_get` is 59% (about 62 instructions per call) and the compiled comparisons of one-character strings are 28% (72 instructions per input character; `c >= "0"` reaches `memcmp`). With code points, the compiled part falls to 20.9M, 1.4x C; the remaining 83.1M is the `msrt_string_scalar_at` call.
- `queues`, BFS half: about 380M against C's 78M. `Deque` keeps `slots: List[T?]`, 16 bytes a slot for an `Int`, and `pop_front` calls `msrt_list_replace` to put `none` back: 109M in `deque.ms` and 70M in the runtime call for 2.25M pushes and pops, about 80 instructions a pair against a handful for a ring of plain slots. The caller's own loop is 202M (bounds, overflow and division checks on `seen[p + 1]`, `dist[p]`, `p % w`).
- `queues`, heap half: about 1,070M against 524M, but not like for like: `PriorityQueue` keeps FIFO order among equal priorities with a second list.
- At or ahead of C: `sqrt` and `sin` loops (0.94x), division and modulo loops (0.97x), `sorted()` of 1M `Int` and 200k `String` against `qsort` (0.96x). A tree interpreter over a recursive `enum` is 1.42x in `eval` (stack check and checked arithmetic); small-record arithmetic, a generic `Comparable` scan and an `entries()` loop are 1.39x together.
- For the cost of the checks alone, the kernels page has C with Manuscript's checks against plain C: 1.07x (`nbody`) to 2.9x (`matmul`).

## 2026-11-12, fourth pass: types, methods, functions and interfaces

Same build and machine; callgrind instructions and min-of-3 wall time, C twins in `c/`. `abstractions.ms` runs six cases; each was measured alone.

| case | ms | c | wall ms / c |
| --- | ---: | ---: | --- |
| a: `Vec` methods returning records by value, 20M rounds | 1,400M | 1,420M | 134 / 147 ms |
| b: `List[Order]` with a nested record and a `List[Line]`, method `total()` | 278M | 294M | 41 / 55 ms |
| c: interface call over a `List[Shape]` of three types, 10M calls | 300M | 216M | 46 / 50 ms |
| d: function values from a list and a closure argument, 20M calls | 554M | 447M | 87 / 88 ms |
| e: generic `largest[T: Comparable]` on `List[Int]`, 20M elements | 240M | 100M | 17 to 30 / 9 ms |
| f: `var` method writing a nested record field, 30M calls | 390M | 600M | 125 / 132 ms |
| `records.ms`: field updates through `ps[i].x += ps[i].vx`, 20M | 538M | 471M | 80 / 60 ms |
| `intmap.ms`: `Map[Int, Int]` count and lookup, 4M operations | 379M | 136M | 69 / 73 ms |

- Records are flat words with no header, methods and generics are specialized and inlined, and a record result comes back in registers or a caller slot: a to f are at C except e.
- e: the generic is specialized and inlined. Two leftovers make it 12 instructions an element against 5: `xs[best]` keeps its upper check (`best` is always an index already proved), and `compare(a, b) > 0` stays a three-way select instead of `a > b`.
- c and d: 8 and 5 more instructions a call than a C function pointer (vtable load, receiver adjust), hidden by the call itself in wall time.
- `intmap`: 60 instructions a map operation in two opaque runtime calls against 17 for an open-addressing table in C; equal in wall time here because the division in the generator dominates. Covered by track 1 ("`Map` goes last").
- Also at or ahead of C: optional results `Int?` from a called function (560M against 1,170M for an out-parameter in C), building 300k interpolated lines and `join` (279M against 426M for `snprintf`).

## 2026-11-12, fifth pass: floats, sorting, trees, promises, string lists

Same build and machine; `mixed.ms` runs six cases, each measured alone (callgrind instructions, min-of-3 wall time). Case d has no C twin.

| case | ms | c | wall ms / c |
| --- | ---: | ---: | --- |
| a: `List[Float]` update and sum, 30M elements each | 125M | 155M | 34 / 33 ms |
| b: `sort` 200k records by a field with a closure, 5 times | 1,201M | 1,987M (`qsort`) | 104 / 250 ms |
| c: 200k inserts into a binary tree of `Node?` links through a `var` method | 1,808M | 117M | 112 / 73 ms |
| d: 100k promises of 200 loop steps each, `wait_all` in batches of 5,000 | 1,165M | | 146 ms |
| e: scan a `List[String]`: `w == "w42"`, `w.starts_with("w49")`, `w.length()`, 4M words | 485M | 225M | 68 / 29 ms |
| f: `filter`, `map` then `fold`, `contains`, `index_of` over 1M `Int`, 20 times | 767M | 514M | 145 / 114 ms |

- c: 4,329,208 allocations for 200,000 nodes. `self.left?.insert(key)` lowers to take the record, `opt.unbox` the child into a stack slot, call, `opt.some` (a new box) and put it back: one allocation, one free and a copy of the node at every level of every insert. It is the boxed-payload form of the `grid` row write-back above. Wall time hides most of it behind cache misses at this size.
- e: `starts_with` is 37 instructions a call, `length` 24 and `==` reaches `memcmp` through a call, all opaque to LLVM; the compiled loop is a quarter of the total.
- d: about 8,200 instructions and 9 allocations a promise beyond its own work (task record, stack switch, frame capture for fault reports, result cell). No C twin; a thread per task would be far slower, so this is a note, not a gap.
- a, b, f: at or ahead of C. The `Float` loops vectorize, since they carry no overflow check.

## 2026-11-12, sixth pass: keyed records, sets, enum trees, slices, text edits

Same build and machine; `keyed.ms` runs six cases, each measured alone, C twins in `c/keyed.c`.

| case | ms | c | wall ms / c |
| --- | ---: | ---: | --- |
| a: `Map[Int, Stat]`, `stats[k].count += 1`, `stats[k].sum += v`, max update, 2M rounds | 1,671M | 74M | 103 to 162 / 11 to 16 ms |
| a as one `stats.update(k, initial, fn ...)` (`keyed_update.ms`) | 305M | 74M | 32 / 11 to 16 ms |
| b: build and evaluate a recursive `enum` tree, 700k nodes | 570M | 224M | 70 / 42 ms |
| c: scan a `List[Int?]`, 30M elements | 377M | 346M | 46 / 44 ms |
| d: sum 20,000 windows through `xs.slice(a, b)` | 126M | 25M | 14 / 5 ms |
| e: `trim`, `replace`, `upper`, `contains` on 300k lines | 1,052M | 334M | 59 / 31 ms |
| f: `Set[Int]` `contains` then `add`, 3M rounds | 403M | 82M | 89 / 18 ms |

- a: each `stats[k].field += v` is three `msrt_map_get_ptr` calls (present check, read, write), so one loop pass makes a `contains` and nine lookups where C makes one. A lookup is about 95 instructions (76 in `value_ptr_k`, which derives the slot layout from the type descriptors on every call) against about 15 for an open-addressing probe in C. The single-lookup form is 5.5x fewer instructions and 3x faster.
- f: `ms_rt::map::contains_key` is 85 instructions a call and 63% of the program. Here the gap shows in wall time (5x), unlike the `intmap` case above where a division in the generator hid it.
- d: `slice` copies the window (the lend in track 2).
- e: `contains` and `replace` build a `memmem` searcher for the needle on every call (126 instructions before the scan starts), and `trim`, `replace` and `upper` each allocate a result.
- b: 1.42x in `evaluate` as noted above; the rest is allocator calls, which callgrind overstates because the runtime's allocator is replaced by glibc's under valgrind.
- c: at C.

## 2026-11-12, map entry reuse (sixth pass item a)

`simplify` now reuses the address a `msrt_map_get_ptr` probe returned for a later probe of the same map and key, while nothing between them calls out, drops, clones or allocates (`map_probes` in `crates/ms-mir/src/opt/simplify.rs`). The table follows a block into its only successor and is dropped at joins and loop headers.

| case a (`keyed.ms`, callgrind Ir) | before | after |
| --- | ---: | ---: |
| `contains` + `stats[k].count += 1`, `.sum += v`, max update, 2M rounds | 1,671M | 521M |

One probe remains per round besides the `contains` (the first statement's, after the join); the other eight are reused. A branch that folds the repeated null checks measured no change on the LLVM backend, which already merges them, so it was not kept.

| `containers.ms` case a (`Map[String, Stat]`, `contains` + two `stats[name].field += v`, 2M rounds) | wall | callgrind Ir |
| --- | ---: | ---: |
| with probe reuse | 87 to 105 ms | 778M |

The earlier run of this case was 281 to 349 ms with seven lookups a pass; C is 22 to 33 ms. What is left is two probes a round at about 95 to 125 instructions each, from `value_ptr_k` deriving the slot layout from the descriptors on every call; caching the layout in the map header is the next step. Linux, same build and machine as above.
## 2026-11-12, contains then update (stacked on map entry reuse)

`fuse_contains` in `simplify`: a join whose first probe reads a map that arrives as a block parameter takes the entry address from its predecessors instead, when one of them holds an earlier probe or `contains` of the same key (a `contains` becomes the equivalent probe); the other predecessor, normally the insert path, probes before it branches. The common present-key path then probes once per round.

| case | before | after |
| --- | ---: | ---: |
| `keyed.ms` case a, `Map[Int, Stat]` (callgrind Ir) | 521M | 281M |
| `containers.ms` case a, `Map[String, Stat]` (callgrind Ir) | 778M | 415M |

The Int case is now below the single `stats.update(...)` form (305M). A lookup is still about 80 instructions on a hit; its cost is spread over hashing, the string tag decode, the probe loop and the frame, not one hot spot, so no further single change is planned.

## 2026-11-12, word-map `get` and fixed key layouts

`m.get(k)` and `m[k]` called the general `msrt_map_get_ptr` even on `Map[Int, Int]`, where `contains` and `add` already used the inlinable `_w8` probes; they now use `word_map_symbol` too. The general probe also derived the slot layout from both descriptors on every call; for an `Int` or `String` key and a value aligned to at most a word it is now two additions.

| program (callgrind Ir, wall min of 3) | before | after |
| --- | ---: | ---: |
| `intmap.ms` (`Map[Int, Int]`, 2M counter updates, 2M `contains`) | 380.7M, 86 ms | 292.9M, 78 ms |
| `keyed.ms` case a (`Map[Int, Stat]`, with the join fusion above) | 281M | 262.7M |
| `containers.ms` case a (`Map[String, Stat]`, same) | 415M | 379.1M |

`msrt_map_add_w8` is 51 instructions a call (103M of `intmap`), the next cost there. Linux, same build and machine.

## 2026-11-12, equivalent C twins for `Map` and `Set`

The map and set C twins did less than `Map` promises: `keyed.c` cases a and f used a table presized for the key count (no growth), a sentinel (`-1` cannot be a key), no insertion order and no removal; `intmap.c` grew but had no order or removal. They now share `c/ordmap.h`: dense entries in insertion order, an index of tag-and-position words, growth (compacting first when over half the entries are holes), `remove`, any `long` key, one `_at` that inserts a zeroed value like `update`. Outputs match the old twins.

| program (callgrind Ir) | old C twin | equivalent C | ms |
| --- | ---: | ---: | ---: |
| `keyed.ms` case a (`Map[Int, Stat]`) | 98.4M | 163.0M | 262.7M |
| `keyed.ms` case f (`Set[Int]`) | 92.1M | 176.0M | 182.8M |
| `intmap.ms` | 136M | 257.4M | 292.9M |

Against the equivalent C the gaps are 1.6x, 1.04x and 1.14x in instructions; `Set[Int]` wall time is at C (58 to 84 ms against 77 ms, min of 5 on a noisy shared VM). Earlier "gap to C" figures for maps and sets in this file and in `proposals/c-parity-structure.md` compare against the old twins and overstate the gap. The `Map[String, Stat]` twin (`containers.c`) is not in the repository, so that row has no equivalent C yet.
## 2026-11-12: var calls through boxed optional fields

`tree.ms` is `mixed.ms` case c on its own: 200k inserts into a binary tree whose links are `Node?`, through `fn var Node.insert`. Same machine; callgrind instructions, allocations from memcheck, min-of-7 wall time.

| | before | after | c |
| --- | ---: | ---: | ---: |
| instructions | 1,808M | 99.5M (`d9f67581`) | 101.0M |
| allocations | 4,329,208 | 200,015 | 200,000 |
| wall | 132 ms | 70 ms | 72 ms |

- `self.left?.insert(key)` took the record, unboxed the child into a slot, called, boxed it again with a new allocation and refilled the field. The payload of a recursive `Optional` is already in memory, in the box, so a `var` call now gets the box's address (`opt.addr`, `alias_payload_addr` in `crates/ms-lower/src/alias.rs`) and changes the child where it lies. Only a boxed optional has such an address; an inline payload keeps the take and put-back.
- The remaining 34M instructions against C are not analysed.

## 2026-11-12: string edits take a dying receiver (track 2 take, text edits)

Case e of `keyed.ms` (`trim`, `replace`, `upper`, `contains` on 300k lines), before and after the `takes_self` twins for `trim`, `trim_start`, `trim_end`, `upper`, `lower` and `replace` (same machine; callgrind for instructions, minimum of 6 runs for wall time). Here `trim` already lends a view, so the owned copy made for `replace` and the `replace` result are the two receivers that die at a call.

| case | instructions before | after | wall before | after | C |
| --- | ---: | ---: | ---: | ---: | ---: |
| e: text edits, 300k lines | 954M | 554M | 39 ms | 28 ms | 334M, 31 ms |

Not done in this step: `sorted`, `reversed` and `filter` takes (no measured gap, and `sortgen` already copies the list itself), and lending `Map.values`, `keys`, `entries` and `List.slice`. A lent `values` or `keys` list still has to be a contiguous list, so only string payloads can be views (`msrt_map_values_view` exists); a lent `slice` needs a list view (a `cap == 0` list), which every list drop path in both backends must skip.

## 2026-11-12: string hot paths from the agent challenges (`scalar_values().all`, `slice`)

c03 `csv-group-sum` reference solution on 25,000 generated lines (callgrind, same machine; before is the build without these two changes and without the string-edit takes).

| change | c03 instructions |
| --- | ---: |
| before | 127.3M |
| `s.scalar_values().all/any/count(f)` with a reading lambda runs as one decoding loop (no list of scalars) | 110.9M |
| `slice` takes an ASCII path for strings of at most 256 bytes that carry no ASCII flag (a byte scan instead of walking scalars: 190 to about 120 instructions a call on 20-byte text) | 107.5M |

Reference Rust is 44.0M on this challenge at 400 KB per the heap-parity thread; what is left in c03 is malloc and free (about 35M under callgrind's glibc allocator), `split_view` at 106 instructions a piece, `Needle::find`, and the copy a no-match `replace` makes of a borrowed line.
- Re-measured at `d9f67581` against a standalone C twin (`gcc -O2`, `tree.c` with the same generator, depth and a free of the tree): 99.5M against 101.0M instructions, 70 against 72 ms. The C twin frees the tree (about 23M) and `tree.ms` does not. About 14M of the 99.5M is the `msrt_alloc`, `alloc_slow` and `alloc_large` layers, which appear only under callgrind (glibc replaces the release allocator). Generated code is within about 4M of C: the descent loop is 5 instructions a level as in C, `depth` is 6.1M against 2.9M (stack and overflow checks), and the tail of `insert` calls the drop glue on a child just tested to be none (about 8 instructions an insert). The earlier 151M and 117M figures (the latter was `mixed.ms` case c with its free) are superseded; there is no codegen gap left to close here.

## 2026-11-12: row building with `join`

`join.ms` builds 300k rows with `[...5 strings].join(",")`; `c/join.c` is the `snprintf` and `memcpy` twin (`gcc -O2`). Callgrind totals, same machine as above.

| version | instructions | allocations |
| --- | ---: | ---: |
| list of the five parts only (no `join`) | 187M | 300k |
| `join` before: byte builder grows 4, 8, 16, 32 | 719M | 1.22M |
| `join` after: a byte builder's first allocation is 32 bytes | 428M | 0.60M |
| C | 476M | |

`reserve` in `crates/ms-rt/src/vec.rs` gave every vector a first capacity of 4 elements, which for a `StringBuilder` is four bytes: a 25-byte row reallocated three times. Byte buffers now start at 32. The 5-part `join` still costs about 800 instructions a row of which most is allocator work under callgrind's glibc `malloc`.

## 2026-11-12, enum tree re-measured against a checked twin

Same machine and Release LLVM build as `main` at `6dd056b2`; callgrind instruction totals and wall time of five runs. `enum_tree.ms` is `keyed.ms` case b alone; `c/enum_tree.c` (`gcc -O2`) is its twin with the same generator, depth and tree free, and with trapping `+`, `*` and negation as Manuscript's `Int` has.

| | ms | c (checked) | c (unchecked) |
| --- | ---: | ---: | ---: |
| instructions | 565.6M | 360.7M | 357.6M |
| `evaluate` / `ev` | 220.3M | 156.7M | 153.6M |
| wall | 61 to 65 ms | 78 to 96 ms | 77 to 96 ms |

- The sixth-pass figures (570M against 224M, 70 against 42 ms) do not reproduce: the twin in `c/keyed.c` runs 357.6M instructions and 77 to 96 ms here. Against a like-for-like twin the Manuscript program is ahead in wall time.
- The instruction gap is the allocator layers (`alloc_large`, `alloc_slow`, `free_large`, `malloc_usable_size`, about 108M), which appear only under callgrind, and `evaluate` (63M more than `ev`): a stack check, a frame pointer and a tag range test per call. The tag test is two compares because the match default is a trap, not `unreachable`; making it unreachable saves about 2 of 28 instructions per call and turns a corrupted tag into undefined behavior, so it is not done. The stack check is item 7 above.
- No codegen gap is left to close for this shape.

## Short string literals as inline constants (2026-11-12)

A literal of 15 bytes or fewer lowered to a static string (a data symbol plus a tagged length). Comparing it with a short string built at run time (an inline string) crossed kinds, so `a == b` decoded both lengths with a three-way tag select before deciding. A literal of 15 bytes or fewer is now an inline string built from two constants, so a comparison with another short string decides from the second word (`string_eq_inline`, same-kind path) and a captured literal no longer loses the literal compare.

Release build at `b4d2b2ae` plus the change, callgrind instructions per element over 1,000 `String` elements (`strs.any(fn s: s == needle)`, `needle := "zzz"`, elements `"s{i}"`):

| case | before | after |
| --- | ---: | ---: |
| `strs.any(fn s: s == needle)` | 30.1 | 10.5 |
| `ps.all(fn p: p.name != needle)` | 30.1 | 10.5 |

`any`, `all` and `find_index` over `Int` lists already compile to a plain loop of 3 to 4 instructions per element (closure inlined, no allocation), at 1.27x scalar `gcc -O2` wall time on 6e9 element visits; no change there. `String.length()` (a scalar count, about 33 instructions on short strings) is unchanged. Fixture: `e2e/stdlib/inline-string-literal-compare`.
