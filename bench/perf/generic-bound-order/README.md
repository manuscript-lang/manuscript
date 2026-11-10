# Generic bound declaration order — 2026-11-10

Correctness issue [#3489](https://github.com/manuscript-lang/manuscript/issues/3489): register nominal parameter lists before resolving interface bounds. The source-level contract requires declaration-order independence. These measurements check the cost on source already accepted by the baseline; the new forward-reference behavior is covered separately by regression tests.

Base: `754aa75a3c5fb66a54c19047cf9f2bb45d1a9db4`. Candidate: the registration/bounds/default phase split in this change. Candidate `crates/ms-check/src/checker.rs` SHA-256: `0c0e912e57a12313b5d1d20a32b2f5bcf82d529b66c8bb7279576a88a02ea625`. Both variants use official Rust 1.99.1, Cargo release settings, and the repository frame-pointer configuration. The isolated warm harness depends only on the two existing local crates.

Linux-6.18.57-x86_64-with-glibc2.41; model name	: AMD EPYC 9V74 80-Core Processor; CPU 0 affinity. Shared cloud VM. No local build or test workload ran during measurement. These are Linux frontend measurements, not generated-program speed measurements.

## Method and results

Whole-process: 30 balanced alternating AB/BA pairs per case, shuffled case order with seed 3489, one warmup per binary/case. Includes parsing, process startup, and standard-library initialization. Every process must exit 0 with exactly empty JSON diagnostics and empty stderr. Twenty same-binary pairs measure noise.

Reused session: 20 balanced process pairs. Parse and initial library loading are outside the internal timer. Each process warms one check, then measures 100 checks for tiny/generic_1 and 10 for the other cases. Every iteration creates fresh module facts and runs normal checking, ownership analysis and result destruction, using one Session. Thus this measures the complete check path, not just the bounds pass; about 20 ms of common work remains per check. Each process validates the exact iteration count and empty diagnostics. The diagnostic hash is of that normalized empty-diagnostics result, not timing-bearing stdout. Five same-binary warm pairs are an additional anomaly check.

All values below are milliseconds per invocation/check. Ratio is the median of paired after/before ratios, which differs from the ratio of column medians.

| Case | Process before | Process after | Paired ratio | Warm before | Warm after | Paired ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| tiny | 53.380 | 54.220 | 1.013 | 19.852 | 19.957 | 0.998 |
| concrete_250 | 57.609 | 57.542 | 1.006 | 23.903 | 23.375 | 1.006 |
| generic_1 | 54.755 | 53.932 | 0.994 | 20.146 | 19.835 | 0.992 |
| nested_250 | 59.769 | 63.108 | 1.016 | 26.253 | 25.563 | 0.967 |
| defaults_100 | 55.643 | 57.562 | 1.018 | 21.786 | 22.350 | 1.015 |
| generic_250 | 59.706 | 61.603 | 1.033 | 25.857 | 25.129 | 0.981 |
| generic_500 | 68.375 | 67.888 | 1.006 | 30.882 | 32.503 | 1.022 |
| generic_1000 | 80.542 | 83.860 | 1.012 | 44.707 | 42.509 | 0.986 |

No consistent slowdown was detected. The warm 250/500/1,000 generic medians grow 1.29× and 1.31× when source size doubles; no worsening scaling appears over this range. Positive warm paired point estimates include +1.46% for defaults and +2.23% for 500 generic declarations. Independent review checked their sample variation: distribution-free median-ratio intervals from the 20 pairs include 1 (approximately 0.982–1.048 and 0.984–1.048). These data cannot exclude a few-percent slowdown, prove strict equivalence, or support a speedup claim. Whole-process same-binary paired ratios range from 0.979 to 1.030, illustrating startup noise. The five warm same-binary pairs range from 0.976 to 1.059; their small sample count makes them an anomaly check, not a tight equivalence bound.

Raw files retain every sample, full generated source, machine details, binary hashes, exact validation requirements, and summaries. No slower runs were discarded. The warm result hash label was corrected after measurement; timings were unchanged. Older suite baselines (for example [2026-10-28](../baseline-2026-10-28.md)) are historical context, not cross-machine comparisons.

## Reproduce

Use separate baseline and candidate checkouts. In each, build `cargo build --release --locked -p ms-check --bin ms-check-dev`. Copy this directory’s `Cargo.toml`, `Cargo.lock`, and `main.rs` into the same relative directory in the baseline checkout, then build both warm executables with `cargo build --release --locked --manifest-path bench/perf/generic-bound-order/Cargo.toml` from their repository roots.

```sh
python measure.py /path/before/target/release/ms-check-dev /path/after/target/release/ms-check-dev paired.json --pairs 30
python measure.py /path/before/target/release/ms-check-dev /path/after/target/release/ms-check-dev same.json --pairs 20 --same-binary
python measure.py /path/before/bench/perf/generic-bound-order/target/release/ms-generic-bound-order-perf /path/after/bench/perf/generic-bound-order/target/release/ms-generic-bound-order-perf warm.json --warm --pairs 20
python measure.py /path/before/bench/perf/generic-bound-order/target/release/ms-generic-bound-order-perf /path/after/bench/perf/generic-bound-order/target/release/ms-generic-bound-order-perf warm-same.json --warm --pairs 5 --same-binary
```

## Correctness and limits

Three new checker regressions fail on the unmodified baseline and pass with the fix: forward generic bounds across function/record/enum/interface declarations (including nested and recursive arguments), missing/excess arities in both orders, and both bundled-group module orders. Existing invalid bounds and defaults remain covered. The full checker run passed 136 unit and 91 integration tests before the group regression was added; the final focused group/bounds run passes all eight tests. `make check` (workspace Clippy with warnings denied, formatting, and 826 ABI symbols) and `make repo-check` pass.

The called e2e fixture fails baseline checking and passes candidate checking. Local native execution was blocked when the CLI tried to create `/home/agent/.cache/ms/native/28efe852593f5d1c-47328572` on a read-only filesystem; no cache redirect or permission change was attempted. Full workspace nextest, native conformance/e2e, and the complete verify-full gate require CI. No local native-execution or cross-platform result is claimed. The separate defaulted-bound defect is tracked in [#3494](https://github.com/manuscript-lang/manuscript/issues/3494).
