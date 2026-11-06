# Streams

ns per item for stream pipelines against the loops they replace: a list, a hand-written `Source` chain, `from_list | map` (one, three stages, and `collect`), and `lines` over 1 M 28-byte lines against a hand loop that allocates each line. Each case checks a sum; the timed region excludes building the input.

## Run

```sh
cargo xtask runtime && cargo build --release --locked -p ms-cli
target/release/ms build bench/perf/streams/main.ms -o /tmp/streams
/tmp/streams   # one line per case: name, ns per item, checksum
```

Build one executable per revision with that revision's `ms` and the same `main.ms`, then run them alternately and take medians.

## 2026-11-03: Linux x86_64

Intel Xeon @ 2.10 GHz, 4 vCPUs, release (LLVM). Medians of 7 alternating runs; all checksums equal. `6242dcc1` is main; `4df4796b` pulls stages with plain calls; `8991af6e` adds vtables LLVM can read.

| case | 6242dcc1 | 4df4796b | 8991af6e |
| --- | ---: | ---: | ---: |
| `for-list` | 1.6 | 1.7 | 1.9 |
| `source-list` | 4.1 | 4.4 | 2.0 |
| `source-map` | 9.9 | 9.7 | 2.7 |
| `stream-map` | 153.3 | 30.9 | 30.1 |
| `stream-map3` | 407.7 | 72.8 | 71.1 |
| `stream-collect` | 231.0 | 34.9 | 33.2 |
| `hand-lines` | 51.3 | 51.0 | 50.8 |
| `stream-lines` | 98.0 | 85.2 | 85.0 |

- Direct pull removes the promise per stage per item: `map` 5 times faster, three stages 5.6 times, `collect` 6.6 times.
- Readable vtables bring a `Source` chain to loop speed (`source-map` 9.9 to 2.7) but not `stream-map`: there the remaining cost is the one-item `List` that `Mapper.feed` returns per item, behind a source LLVM cannot trace through the `for` loop's holder.

## 2026-11-04: Linux x86_64, `Transform` writes to a `WriteStream`

Same machine and method. `c9446bfc` is main; the second column has `Transform.step(value, var out)` in place of `feed(value) List[B]`.

| case | c9446bfc | step |
| --- | ---: | ---: |
| `for-list` | 1.5 | 1.5 |
| `source-list` | 1.7 | 1.7 |
| `source-map` | 2.5 | 2.3 |
| `stream-map` | 27.5 | 28.4 |
| `stream-map3` | 62.7 | 64.4 |
| `stream-collect` | 27.8 | 27.9 |
| `hand-lines` | 43.2 | 43.3 |
| `stream-lines` | 78.6 | 70.5 |

- The per-item allocation is gone (callgrind on `stream-map`: 860 to 300 instructions per item, no `malloc`), but `map` time is unchanged: what remains is two interface calls per item, each returning a `Result` through memory.
- `lines` is 10% faster: it no longer builds a `List` per chunk, and `List.reverse` now swaps in place instead of copying every element.

## 2026-11-05: Linux x86_64, `filter`, `take`, `fold`

Same machine and method; `ms` built from the revision before and after adding the three steps. Medians of 7 alternating runs, all checksums equal. Existing cases are unchanged within noise (`stream-map` 23.0 to 22.3, `stream-map3` 45.1 to 45.4, `stream-collect` 20.9 to 22.2, `stream-lines` 66.4 to 67.2). New cases, ns per item:

| case | ns |
| --- | ---: |
| `for-filter` | 1.5 |
| `stream-filter` | 18.3 |
| `for-take` | 0.7 |
| `stream-take` (2.5 M items taken) | 21.5 |
| `stream-fold` | 7.8 |

Each stage costs about what `map` does (20 ns); `fold` is a plain consumer.

## 2026-11-06: Linux x86_64, one stream type, stages are `Source`s

Same machine class (Intel Xeon @ 2.10 GHz, 4 vCPUs, release/LLVM). Before: `a0dbdcb2` (main), the 2026-11-05 section plus a same-day run of `stream-map`, `stream-map3`, `stream-collect` and `stream-lines` on that revision (21.6, 40.3, 18.8, 57.7). After: this change, three runs of the same `main.ms` (its loops now use `for x in stream`); all checksums equal. ns per item:

| case | before | after |
| --- | ---: | ---: |
| `for-list` | 1.5 | 1.4 to 2.7 |
| `source-map` | 2.3 | 2.5 to 3.1 |
| `stream-map` | 21.6 to 22.3 | 10.2 to 11.7 |
| `stream-map3` | 40.3 to 45.4 | 16.0 to 20.7 |
| `stream-collect` | 18.8 to 22.2 | 8.2 to 10.2 |
| `stream-filter` | 18.3 | 8.3 to 10.5 |
| `stream-take` | 21.5 | 12.8 to 15.6 |
| `stream-fold` | 7.8 | 3.1 to 3.4 |
| `hand-lines` | 37 to 43 | 37 to 43 |
| `stream-lines` | 57.7 to 67.2 | 40.6 to 47.1 |

- Stages are about twice as fast and each added stage costs about 4 ns instead of 20. The stage records no longer pass through a runtime cell, and the loop calls `next` directly.
- A user-level prototype of the same shape measured 3.3 to 4.1 for one `map` and 9.5 to 11 for three. The stdlib stages are slower because each one pays a `ReadStream` wrapper call and a closure call on top of the `Source` call.
