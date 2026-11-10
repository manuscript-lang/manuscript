# Optional sized literal context: frontend qualification

2026-11-10. Issue #3490. Base `ae87acedab5641ffac4179b17e3e0dc442fcca0e`; implementation `05ea47eff950766394807435593070551aacec74`. Source change is in `ms-check` argument checking; no native runtime or generated-code timing is claimed.

Rust 1.99.1 (`58cf8f9c3`, official pinned toolchain), release profile, repository frame-pointer flags. Linux x86_64 on AMD EPYC 9V74, four CPU equivalents and 16 GiB cgroup memory. Each child inherits affinity to CPU 0. The host is not exclusive. Times include process startup, parsing, fresh-session standard-library initialization, full frontend checking, and JSON output. Builds are excluded; filesystem caches are warm.

The runner performs three untimed checks per binary/input, then 31 paired samples, alternates base/head ordering, and shuffles workload order with seed 1729. Every sample must match its binary/input's exact exit status, stdout and stderr. All valid controls require the exact empty-diagnostics JSON. No samples or unfavorable runs were discarded.

| Input | Base median ms | Head median ms | Median paired head/base |
| --- | ---: | ---: | ---: |
| Small optional-argument function | 52.018 | 51.271 | 0.989 |
| Settings record and formatting | 51.044 | 50.940 | 0.984 |
| 200 ordinary arithmetic functions | 54.971 | 54.556 | 0.991 |
| 200 default-width optional expressions | 53.748 | 53.880 | 0.991 |
| 200 sized optional calls and callees | 57.655 | 57.890 | 0.998 |
| 200 affected sized optional expressions | 34.641 | 53.383 | 1.544 |

The valid controls show no measured slowdown in their paired medians; small differences are not evidence of a speedup. The affected row is **not an equivalent-success performance comparison**: base emits 200 errors and skips ownership analysis, whereas head accepts and performs the remaining frontend passes. Its additional work is expected from correcting rejection. Native execution and large-project steady-state latency are not established by these samples.

`raw-final.json` preserves every sample and binary hash. `raw-initial.json` preserves the earlier run on base `754aa75a3`, before restricting the extra literal-tree classification to explicitly sized payloads. That run showed roughly 0.8–1.8% increases on several valid controls, so it was not treated as clearance. The final guard avoids that extra scan for default `Int?`/`Float?`; both binaries were rebuilt from the same fresh base before the final run. Different absolute medians across runs reflect different machine load and standard-library snapshots; only within-run pairs are compared.

## Reproduce

Build `ms-check-dev` with the pinned toolchain at each revision in separate worktrees:

```sh
cargo build --release --locked -p ms-check --bin ms-check-dev
python3 bench/perf/optional-literal-context/run.py /path/to/base/target/release/ms-check-dev /path/to/head/target/release/ms-check-dev /tmp/optional-context-perf
```

The script writes all input programs, raw samples and a summary to the output directory. Run without other local builds/tests. Its affected input deliberately fails on base and succeeds on head; the remaining inputs must succeed on both. Regression fixtures independently pin kind, range, intermediate overflow, division by zero, named-value identity and one-layer wrapping.
