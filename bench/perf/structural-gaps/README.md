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
