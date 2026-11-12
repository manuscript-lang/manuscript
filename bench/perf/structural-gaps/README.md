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
