# Module-loader input tracking

`Loader::add_input` retains modules, symbolic links and embedded files for watch
and cache invalidation. This benchmark loads a broad graph of independent source
modules; every graph must retain dependency order, entry identity, all input
paths and no diagnostics. Preparation, assertions, graph destruction and checker
initialization are outside the reported loader interval. Process CPU and fault
columns in the CSV cover the entire child process, including assertions and
startup, and are supporting counters rather than loader-only timings.

Build the two revisions with the repository's pinned Rust toolchain:

```sh
cargo build --release --locked -p ms-driver --lib
rustc --edition=2024 -O -C panic=abort bench/perf/module-inputs/main.rs \
  -L dependency=target/release/deps \
  --extern ms_driver=target/release/libms_driver.rlib -o /tmp/loader-after
```

Build the same harness against an unmodified main checkout's release artifacts,
substituting its `target/release` paths and `/tmp/loader-before`. Run both binaries
against exactly the same prepared sources, with each input warmed once and nine
alternating sample pairs:

```sh
taskset -c 4 python3 bench/perf/module-inputs/run.py \
  /tmp/loader-before /tmp/loader-after /tmp/module-inputs.csv
```

Choose an available CPU on Linux. The paired driver uses Python's Unix
`resource` module for process counters; omit `taskset` on macOS. These are
frontend loader measurements, not generated-program or backend speed claims.
The latest repository baseline, [2026-10-28](../baseline-2026-10-28.md), covers
runtime suites and has no matching module-loader case; compare the two revisions
on one machine rather than comparing these timings with unrelated baseline
numbers.

## 2026-11-10

Baseline: main `3107528e8`. Candidate: that revision plus the `Loader::seen_inputs`
change in this PR. Linux x86_64, AMD EPYC 9V74 VM (five visible CPUs), Rust
1.99.1 release libraries, harness `rustc -O -C panic=abort`. Both binaries ran on
CPU 4, with local compilation paused for this paired trial and resumed afterward.
Warm file-cache loader medians from nine alternating sample pairs:

| Imported modules | Before, ms | After, ms | Before / after |
| ---: | ---: | ---: | ---: |
| 1 | 0.019144 | 0.019543 | 0.98x |
| 16 | 0.154288 | 0.153984 | 1.00x |
| 128 | 1.162942 | 1.163549 | 1.00x |
| 2,000 | 23.564955 | 20.084305 | 1.17x |
| 4,000 | 63.162776 | 44.908516 | 1.41x |
| 8,000 | 197.066213 | 90.358267 | 2.18x |
| 16,000 | 462.712721 | 185.002846 | 2.50x |

[Raw samples](samples-2026-11-10.csv) include process CPU and page-fault counters.
Every child had zero major faults. At 16,000 modules median process user CPU
fell from 375 to 108 ms; median minor faults rose from 13,943 to 14,199. The set
stores one additional path copy and a hash-table entry per unique input, so its
extra storage is proportional to total distinct path bytes. No meaningful
ordinary-graph slowdown appeared at 16 or 128 modules; the one-module case adds
about 0.4 microseconds. Instruction counters were unavailable in this image;
CPU time, page faults, source inspection and the paired wall-clock measurements
support this bounded loader-only claim.

The old membership check performs up to N(N-1)/2 path comparisons for N unique
inputs. The new per-load membership set keeps expected linear membership work
and retains the original first-seen output order. This is an existing scaling
defect, not a claim that a particular recent commit introduced it. No language,
diagnostic, module identity or generated-code behavior changes.
