# Formatter validation parse reuse — 2026-11-12

The final `format_lines` validation was parsed once to decide whether to print
`MS_FMT_DEBUG` output and then parsed again to propagate its error. Retain that
`Result` and use it for both purposes. Input/output validation, errors, debug
printing, formatting policy, and public APIs are unchanged.

Baseline: `37a14ba5797bed73a66d1350bee03d2238c63a20`. Candidate differs only in
`crates/ms-syntax/src/format.rs`: store `checked`, inspect `is_err()`, and use
`checked?`. This page describes the same-source before/after experiment, not a
comparison with old compiler/runtime suite results. The latest broad baseline is
[baseline-2026-10-28](../baseline-2026-10-28.md); it has no equivalent isolated
formatter case, so its times must not be compared with these measurements.

## Measurements

| Input | Baseline µs | Candidate µs | Change |
| --- | ---: | ---: | ---: |
| fn n=1 | 8.642 | 7.576 | -12.3% |
| fn n=64 | 378.346 | 339.892 | -10.2% |
| imports n=1 | 5.392 | 4.768 | -11.6% |
| imports n=4 | 23.589 | 20.642 | -12.5% |
| imports n=64 | 295.378 | 282.778 | -4.3% |
| same n=4 | 12.870 | 11.612 | -9.8% |
| same n=1000 | 2813.409 | 2518.463 | -10.5% |
| canonical n=1000 | 4972.669 | 4558.349 | -8.3% |

Each cell is the median of 36 samples: four sequential process rounds with
alternating baseline/candidate order, nine samples per case per process.
Each sample batches calls to target 3 ms, capped at 5,000 calls. Inputs are
constructed and validated outside timing; three warm-ups precede measurement.
Returned strings are consumed with `black_box`, including normal result disposal.
Raw samples and per-case output checksums are in `format-*-*.txt`.

Linux x86-64, kernel 6.18.57, AMD EPYC 9V74 virtual CPU, five visible CPUs,
shared unpinned VM. Rust 1.99.1 (58cf8f9c3), edition 2024, opt-level=3,
panic=abort. Only the dependency-free `ms-syntax` Rust crate and harness are
compiled: no Manuscript backend or runtime is invoked. No concurrent local
builds or benchmarks ran during these samples. Instruction/allocation/page-fault
counts were not measured. Absolute latency is noisy; earlier runs found smaller
percentage gains, so the robust claim is removing one redundant parse, not a
universal percentage speedup.

`fn` covers one and 64 functions. `imports` uses distinct module paths;
`same` uses one module; `canonical` formats already-formatted imports. Every
measured control improved in this run. This does not establish all-platform
or whole-tool performance.

## Correctness and reproduction

The harness strictly parses input and output and checks formatter idempotence;
checksums match baseline for every case. Existing syntax tests passed: 118
integration tests (including corpus, mutation, comments, Unicode/CRLF and edit
cases) and 19 unit tests. No new behavioral regression test is needed for
retaining an existing validation result; existing output/error contracts apply.
An independent reviewer approved the production diff. Full workspace tests and
Clippy remain PR CI gates rather than claims from this standalone harness.

Run `bash bench/perf/formatter-validation-2026-11-12/run.sh /tmp/new-results`
with an existing Rust 1.99.1 compiler on PATH, or set `RUSTC` to its path.
The output directory must not exist. This script installs nothing and compiles
only local source. The baseline commit must be available in the local clone.
