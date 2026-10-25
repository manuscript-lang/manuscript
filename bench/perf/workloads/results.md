# Workload results

Ordinary agent-style programs (the reference solutions of the small agent challenges in `bench/agent/challenges`) on about 3 MB of stdin each, built with `ms build` (Release, LLVM), `go build` and `rustc -O`. Outputs are compared byte for byte; the time is the best wall time of 3 runs in milliseconds. Reproduce with `MS=./target/release/ms sh bench/perf/workloads/run.sh 3`; compare only runs from one machine.

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
