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

## 2026-11-12: stage 1, `decode_utf8` takes a dying `Bytes`

Same machine and `ms` build as above, before and after the change (`bytetake` pass, `msrt_bytes_decode_utf8_take`). Callgrind and memcheck on the 2 MB input, wall time is the minimum of 5 on the 22 MB input.

| task | instructions before | after | allocated bytes before | after | wall before | after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| grep | 23.28M | 22.76M | 6,299,139 | 4,202,043 | 56 ms | 39 ms |
| logstats | 112.45M | 111.83M | 15,248,255 | 13,151,115 | 98 ms | 88 ms |

The saved work is the 2 MB copy of the input and its page faults, which callgrind counts as few instructions, so the wall time is the measure. Allocation counts are unchanged (the buffer is reused, not removed).
