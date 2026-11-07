# Workload results

Ordinary agent-style programs (the reference solutions of the small agent challenges in `bench/agent/challenges`) on about 3 MB of stdin each, built with `ms build` (Release, LLVM), `go build` and `rustc -O`. Outputs are compared byte for byte; the time is the best wall time of 3 runs in milliseconds. Reproduce with `MS=./target/release/ms sh bench/perf/workloads/run.sh 3`; compare only runs from one machine.

The current runner checks every language's output in an untimed warm-up and every
timed trial, rotates version order, and rejects any nonzero producer status or
output mismatch before publishing a table. It uses a monotonic clock with
sub-millisecond precision. Times exclude compilation and validation but include
process startup, stdin and stdout. Go builds disable VCS stamping. With
`BENCH_OUTPUT=.artifacts/workloads`, each run retains its sources, binaries, inputs,
expected output and `samples.json` (raw nanoseconds and input/output/binary hashes).
A failed suite leaves no final `table.txt`; a pending table is incomplete evidence.
Run the regression tests with
`python3 -m unittest discover -s bench/perf/workloads -p test_measure.py`.
The [2026-10-29 validation controls](validation-2026-10-29.md) record the failure
reproductions, release settings and paired native samples. Historical results
below retain their original measurement method; this validation fix makes no
generated-program speedup claim.

## main at c1b81215 (2026-10-25)

linux/amd64, four cores, Go 1.24.7, rustc 1.99.1.

| program | Manuscript | Go | Rust | ms / Go | ms / Rust |
|---|---:|---:|---:|---:|---:|
| c03-csv-group-sum | 63 | 44 | 37 | 1.43x | 1.70x |
| c05-calculator | 46 | 48 | 98 | 0.96x | 0.47x |
| c09-ciphers | 63 | 61 | 33 | 1.03x | 1.91x |
| c13-inventory-orders | 118 | 248 | 143 | 0.48x | 0.83x |
| c14-dp-suite | 631 | 1431 | 645 | 0.44x | 0.98x |
| c16-maze-bfs | 31 | 39 | 32 | 0.79x | 0.97x |
| c18-cron-next-runs | 809 | 1052 | 807 | 0.77x | 1.00x |
| c25-log-analyzer | 28 | 60 | 21 | 0.47x | 1.33x |
| c36-bank-ledger | 97 | 109 | 63 | 0.89x | 1.54x |
| c44-unified-diff | 3 | 65 | 15 | 0.05x | 0.20x |

Manuscript is faster than Go on 8 of 10 programs and level on the ciphers; Go is clearly ahead only on the CSV grouping (1.43x). Against Rust it is level or ahead on 6 of 10; the four behind it are string-heavy (CSV splitting, per-character ciphers, log parsing and ledger formatting), where the remaining costs are `f"{int}"` formatting and scalar counting on short strings (see the data-types audit in the repository history for the callgrind breakdown).

## 2026-11-03, refcount removal

The reference solutions were ported from the removed `read_line`/`flush` API to `lines(stdin())` and `flush().wait()`. Min of two rounds of 5 on `d34af765` (refcounts, streams redesign) against `d6052382` (no refcounts): the ten programs read 0.94x to 1.09x with the Go and Rust columns moving as much, so no regression beyond noise. Table in [refcount-removal-2026-11-03.md](../refcount-removal-2026-11-03.md).

## 2026-11-07, suite rebuilt after the streams change

The ten reference solutions stopped building after [#2726](https://github.com/manuscript-lang/manuscript/pull/2726) (`input.read().wait()` is now `input.next()`, `flush()` returns its `Result`); they are ported again. Revision `4e8da342` plus the `String.from_scalars` change, Release LLVM build, min of 5, same shared 4 vCPU Xeon VM as above.

| program | ms ms | go ms | rust ms | ms/go | ms/rust |
|---|---:|---:|---:|---:|---:|
| c03-csv-group-sum | 71.8 | 45.1 | 33.8 | 1.59x | 2.12x |
| c05-calculator | 150.1 | 53.2 | 142.0 | 2.82x | 1.06x |
| c09-ciphers | 128.3 | 61.7 | 43.1 | 2.08x | 2.98x |
| c13-inventory-orders | 366.9 | 303.6 | 168.9 | 1.21x | 2.17x |
| c14-dp-suite | 768.4 | 1593.5 | 511.4 | 0.48x | 1.50x |
| c16-maze-bfs | 24.9 | 35.7 | 35.8 | 0.70x | 0.69x |
| c18-cron-next-runs | 1789.0 | 1188.3 | 831.5 | 1.51x | 2.15x |
| c25-log-analyzer | 23.8 | 48.4 | 24.1 | 0.49x | 0.99x |
| c36-bank-ledger | 85.8 | 126.4 | 70.0 | 0.68x | 1.23x |
| c44-unified-diff | 2.9 | 64.6 | 16.7 | 0.04x | 0.17x |

Worst gaps to work on next: c09 (3x Rust), c18, c03, c13 (2x Rust), c05 (2.8x Go).

`c09-ciphers` under callgrind (300 KB input, 43.7M instructions before): `String.from_scalars` took 3.8M, built a `Vec`, then copied it into the string. An all-ASCII list now narrows straight into the result (2.4M, whole program 41.4M, -5%; 100-scalar call 142 to 80 ns). Wall-clock moved 134 to 128 ms, inside the noise. The rest of the profile is spread thin: the compiled `transform` loop 25%, `owned_copy` 8%, `sub_scalars`, `replace`, `slice`, `realloc` 3-4% each.

Profiling note: callgrind cannot map the 256 GiB allocator reservation, so `ensure_region` fails and every allocation goes to glibc `malloc` (it made `c09` look malloc-bound at 68M instructions). Shrink `PAGES_SIZE` and `GROW_CHUNKS` in `crates/ms-rt/src/alloc.rs` locally for a profile run and do not commit the change.
