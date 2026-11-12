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

Three probes remain per round (one per statement) where there were nine: each statement's block starts after a call or join in the lowered code, so the table restarts there. Linux, same build and machine as above.
