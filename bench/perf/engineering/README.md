# Engineering tasks

Everyday programs an engineer writes in an afternoon, in Manuscript, C and Rust, on 15 to 40 MB of generated input: log statistics, CSV group-by, word frequency, sorting records, and substring search. Each program reads stdin and prints a small report; every sample's output must match the C version byte for byte. Rust uses `std` only (no crates), so its CSV parser is hand written; C uses an open-addressing table and `qsort`. Manuscript versions use the standard library idiomatically (`split`, `Map`, `sorted`, `@std/data/csv.ms`).

```sh
MS=./target/release/ms sh bench/perf/engineering/run.sh 5
```

`gen.ms` writes deterministic inputs (`ms run bench/perf/engineering/gen.ms -- <dir> [scale]`). Times are the minimum wall time in ms of N samples with the version order fixed; process start, stdin and stdout are included, compilation is not. Compare only runs from one machine, and add dated sections rather than editing old ones. `BENCH_OUTPUT=<dir>` keeps inputs, binaries and outputs.

## 2026-11-12 baseline

`0d723018`, Release LLVM `ms`, gcc 13.3 `-O2`, rustc 1.99.1 `-O`, 4 vCPU Xeon 2.1 GHz VM, min of 5.

| task | ms | c | rust | ms / c | ms / rust |
|---|---:|---:|---:|---:|---:|
| logstats (22 MB, 400k lines) | 116 | 64 | 97 | 1.81x | 1.20x |
| csvgroup (18 MB, 500k rows, `@std/data/csv.ms`) | 231 | 64 | 347 | 3.61x | 0.67x |
| wordfreq (40 MB, 4.8M words) | 622 | 229 | 225 | 2.72x | 2.76x |
| sortrecords (15 MB, 1M records) | 403 | 422 | 275 | 0.95x | 1.47x |
| grep (22 MB, substring per line) | 69 | 32 | 33 | 2.16x | 2.09x |

Largest gaps to close: wordfreq, grep, logstats.

## 2026-11-12, `fields_by` ASCII path and short-haystack search

Same machine and method (min of 7). `String.fields_by` on ASCII text copies each field once from the source instead of building it scalar by scalar (4.8M fields: 534 ms to about 225 ms); `find` scans haystacks of 32 to 127 bytes directly instead of building a `memmem` searcher per call (callgrind on 4 MB of log: 76.6M to 54.3M instructions); the two benchmarks that count keys use `Map.update` (one lookup).

| task | ms | c | rust | ms / c | ms / rust |
|---|---:|---:|---:|---:|---:|
| logstats | 103 | 59 | 93 | 1.75x | 1.11x |
| csvgroup | 202 | 61 | 348 | 3.31x | 0.58x |
| wordfreq | 381 | 224 | 237 | 1.70x | 1.61x |
| sortrecords | 386 | 371 | 269 | 1.04x | 1.43x |
| grep | 62 | 33 | 33 | 1.88x | 1.88x |

Remaining gap on `grep` and `logstats` is the input path (22 MB: `read_all` 14 ms, `decode_utf8` copy 18 ms, `split` 30 ms, against one read and one scan in C).

## 2026-11-12, JSON, dedupe and report tasks; `pad` without a temporary buffer

`jsonsum` (20 MB, 200k records): Manuscript parses into a typed `List[Rec]` with `parse[List[Rec]]`; C and Rust build a generic value tree with a hand-written recursive-descent parser (no serde or JSON library is available to `rustc` here), so the comparison is typed parse against tree parse, and a Rust program using serde derive would be faster than the Rust column. `dedupe` counts distinct lines and names in 1M records with maps. `report` formats 1M fixed-width lines (`pad_end`, `pad_start`, interpolation) into one buffer. `pad_start` and `pad_end` wrote into a `Vec`, then copied it into the string (a second allocation past 22 bytes); they now write into the final string directly (callgrind on 3 MB: 453M to 360M instructions; `report` 392 ms to about 270 ms).

Min of 7, same machine, all ten tasks:

| task | ms | c | rust | ms / c | ms / rust |
|---|---:|---:|---:|---:|---:|
| logstats | 111 | 62 | 100 | 1.79x | 1.11x |
| csvgroup | 210 | 63 | 351 | 3.33x | 0.60x |
| wordfreq | 388 | 229 | 232 | 1.69x | 1.67x |
| sortrecords | 407 | 399 | 275 | 1.02x | 1.48x |
| grep | 61 | 33 | 32 | 1.85x | 1.91x |
| treegrep | 38 | 29 | 26 | 1.31x | 1.46x |
| pargroup | 45 | 21 | 29 | 2.14x | 1.55x |
| jsonsum | 185 | 239 | 294 | 0.77x | 0.63x |
| dedupe | 334 | 319 | 374 | 1.05x | 0.89x |
| report | 225 | 184 | 174 | 1.22x | 1.29x |

## 2026-11-12: file reads in worker threads stay inline

`pargroup` (2,000 files, `map_concurrent` over 4 workers) sent every `read_file` on a worker thread to the blocking pool: `strace -c -f` showed 4,698 `futex` and 1,505 `epoll_wait` calls. `msrt_task_others_stalled` decided that a thread with other tasks must keep running them, but a worker thread's flow task only joins its root task (no token, descriptor or timer), so it was never counted as stalled. A task that is waiting only on a join now counts as stalled, so the read runs inline when nothing else on the thread could run. Min of 15 on the shared 4-CPU VM: 48 ms before, 37 ms after (C 20 ms); `futex` calls 4,698 to 13, `epoll_wait` 1,505 to 6. The rest of the gap to C is the per-line `split` and parse work, not the file calls.
